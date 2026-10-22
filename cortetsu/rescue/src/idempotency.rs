//! Durable *inert* idempotency ledger for typed future Rust operations.
//! This module never invokes or authorizes an operation. A VERIFIED journal
//! entry still requires live resource readback before returning any success.
//! It does not rely on the coordinator or QML for crash recovery.
use super::{Result, invalid};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

const MAX_RECORD: usize = 4096;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Phase {
    Prepared,
    Verified,
    RecoveryRequired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Record {
    schema: u32,
    idempotency_key: String,
    fingerprint_sha256: String,
    resource: String,
    expected_revision: u64,
    observed_revision: Option<u64>,
    phase: Phase,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Begin {
    New,
    RecoveryRequired,
    ReadbackRequired,
    Conflict,
}

pub struct Ledger {
    root: PathBuf,
}

fn uuid(s: &str) -> bool {
    s.len() == 36
        && s.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        })
}
fn safe_resource(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 128
        && s.bytes().enumerate().all(|(i, b)| {
            b.is_ascii_alphanumeric()
                || (i != 0 && (b == b'.' || b == b'_' || b == b'-' || b == b':'))
        })
}
fn fingerprint(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit())
}

impl Ledger {
    /// Use a pre-created, caller-owned 0700 directory. Never create or
    /// follow an untrusted storage root, including in a recovery path.
    pub fn open(root: &Path) -> Result<Self> {
        if !root.is_absolute() {
            return Err(invalid("ledger root must be absolute"));
        }
        let m = fs::symlink_metadata(root).map_err(|_| invalid("ledger root missing"))?;
        let self_uid = fs::metadata("/proc/self")
            .map_err(|_| invalid("cannot determine local uid"))?
            .uid();
        if !m.is_dir()
            || m.file_type().is_symlink()
            || m.permissions().mode() & 0o777 != 0o700
            || m.uid() != self_uid
        {
            return Err(invalid("ledger root must be private"));
        }
        Ok(Self { root: root.into() })
    }
    fn path(&self, key: &str) -> PathBuf {
        self.root.join(format!("{key}.json"))
    }
    fn lock(&self) -> Result<File> {
        let path = self.root.join(".idempotency.lock");
        if let Ok(meta) = fs::symlink_metadata(&path)
            && (meta.file_type().is_symlink() || !meta.is_file())
        {
            return Err(invalid("unsafe ledger lock"));
        }
        let file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(path)
            .map_err(|_| invalid("cannot open ledger lock"))?;
        file.lock_exclusive()
            .map_err(|_| invalid("cannot lock ledger"))?;
        Ok(file)
    }
    fn load(&self, key: &str) -> Result<Option<Record>> {
        let path = self.path(key);
        let metadata = match fs::symlink_metadata(&path) {
            Ok(m) => m,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(_) => return Err(invalid("cannot stat ledger record")),
        };
        if !metadata.is_file()
            || metadata.file_type().is_symlink()
            || metadata.len() as usize > MAX_RECORD
            || metadata.permissions().mode() & 0o077 != 0
        {
            return Err(invalid("unsafe ledger record"));
        }
        let raw = fs::read(&path).map_err(|_| invalid("cannot read ledger record"))?;
        let entry: Record =
            serde_json::from_slice(&raw).map_err(|_| invalid("invalid ledger record"))?;
        if entry.schema != 1
            || entry.idempotency_key != key
            || !uuid(&entry.idempotency_key)
            || !fingerprint(&entry.fingerprint_sha256)
            || !safe_resource(&entry.resource)
            || entry.expected_revision > 9007199254740991
            || (entry.phase == Phase::Verified
                && entry
                    .observed_revision
                    .is_none_or(|n| n <= entry.expected_revision))
            || (entry.phase == Phase::Prepared && entry.observed_revision.is_some())
        {
            return Err(invalid("invalid ledger identity"));
        }
        Ok(Some(entry))
    }
    fn store(&self, entry: &Record) -> Result<()> {
        let path = self.path(&entry.idempotency_key);
        match fs::symlink_metadata(&path) {
            Ok(_) => {
                let _ = self.load(&entry.idempotency_key)?;
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Err(invalid("cannot inspect ledger record")),
        }
        let temp = self.root.join(format!(
            ".{}.{}.tmp",
            entry.idempotency_key,
            std::process::id()
        ));
        let bytes = serde_json::to_vec(entry).map_err(|_| invalid("cannot encode journal"))?;
        if bytes.len() > MAX_RECORD {
            return Err(invalid("ledger record too large"));
        }
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temp)
            .map_err(|_| invalid("cannot stage ledger record"))?;
        let result = (|| {
            f.write_all(&bytes)
                .and_then(|_| f.sync_all())
                .map_err(|_| invalid("cannot sync ledger record"))?;
            fs::rename(&temp, &path).map_err(|_| invalid("cannot publish ledger record"))?;
            File::open(&self.root)
                .and_then(|dir| dir.sync_all())
                .map_err(|_| invalid("cannot sync ledger directory"))
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        result
    }
    pub fn begin(
        &self,
        key: &str,
        fingerprint_sha256: &str,
        resource: &str,
        expected_revision: u64,
    ) -> Result<Begin> {
        if !uuid(key)
            || !fingerprint(fingerprint_sha256)
            || !safe_resource(resource)
            || expected_revision > 9007199254740991
        {
            return Err(invalid("invalid idempotency key, fingerprint or resource"));
        }
        let _lock = self.lock()?;
        if let Some(previous) = self.load(key)? {
            if previous.fingerprint_sha256 != fingerprint_sha256
                || previous.resource != resource
                || previous.expected_revision != expected_revision
            {
                return Ok(Begin::Conflict);
            }
            return Ok(if previous.phase == Phase::Verified {
                Begin::ReadbackRequired
            } else {
                Begin::RecoveryRequired
            });
        }
        self.store(&Record {
            schema: 1,
            idempotency_key: key.into(),
            fingerprint_sha256: fingerprint_sha256.into(),
            resource: resource.into(),
            expected_revision,
            observed_revision: None,
            phase: Phase::Prepared,
        })?;
        Ok(Begin::New)
    }
    /// The resource owner must independently read back an authoritative
    /// monotonically increasing revision. We do not accept "process exited 0".
    pub fn finish_with_readback(
        &self,
        key: &str,
        fingerprint_sha256: &str,
        mut readback: impl FnMut() -> Result<u64>,
    ) -> Result<()> {
        if !uuid(key) || !fingerprint(fingerprint_sha256) {
            return Err(invalid("invalid ledger request"));
        }
        let _lock = self.lock()?;
        let mut entry = self
            .load(key)?
            .ok_or_else(|| invalid("unknown idempotency key"))?;
        if entry.fingerprint_sha256 != fingerprint_sha256 || entry.phase != Phase::Prepared {
            return Err(invalid("operation does not own a prepared journal"));
        }
        let observed = readback()?;
        if observed <= entry.expected_revision {
            return Err(invalid("no authoritative state revision advance"));
        }
        entry.observed_revision = Some(observed);
        entry.phase = Phase::Verified;
        self.store(&entry)
    }
    pub fn state(&self, key: &str) -> Result<Option<(Phase, Option<u64>)>> {
        if !uuid(key) {
            return Err(invalid("invalid journal key"));
        }
        let _lock = self.lock()?;
        Ok(self.load(key)?.map(|r| (r.phase, r.observed_revision)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "cortetsu-idempotency-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).unwrap();
            fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
            Self(path)
        }
    }
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    const KEY: &str = "00000000-0000-0000-0000-000000000001";
    const HASH: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    #[test]
    fn durable_prepared_replay_is_never_autoexecuted() {
        let t = Temp::new();
        let l = Ledger::open(&t.0).unwrap();
        assert_eq!(
            l.begin(KEY, HASH, "notifications.dnd", 5).unwrap(),
            Begin::New
        );
        assert_eq!(
            l.begin(KEY, HASH, "notifications.dnd", 5).unwrap(),
            Begin::RecoveryRequired
        );
        assert_eq!(
            l.begin(KEY, HASH, "notifications.dnd", 6).unwrap(),
            Begin::Conflict
        );
        assert!(l.finish_with_readback(KEY, HASH, || Ok(5)).is_err());
        assert_eq!(l.state(KEY).unwrap(), Some((Phase::Prepared, None)));
        l.finish_with_readback(KEY, HASH, || Ok(6)).unwrap();
        assert_eq!(l.state(KEY).unwrap(), Some((Phase::Verified, Some(6))));
        assert_eq!(
            l.begin(KEY, HASH, "notifications.dnd", 5).unwrap(),
            Begin::ReadbackRequired
        );
    }
    #[test]
    fn refuses_unsafe_and_corrupted_state() {
        let t = Temp::new();
        let l = Ledger::open(&t.0).unwrap();
        assert!(l.begin("../x", HASH, "notifications.dnd", 0).is_err());
        assert!(l.begin(KEY, HASH, "../escape", 0).is_err());
        fs::write(t.0.join(format!("{KEY}.json")), "{invalid").unwrap();
        assert!(l.begin(KEY, HASH, "notifications.dnd", 0).is_err());
        fs::remove_file(t.0.join(format!("{KEY}.json"))).unwrap();
        std::os::unix::fs::symlink("/etc/passwd", t.0.join(format!("{KEY}.json"))).unwrap();
        assert!(l.begin(KEY, HASH, "notifications.dnd", 0).is_err());
        let outside = Temp::new();
        fs::set_permissions(&outside.0, fs::Permissions::from_mode(0o755)).unwrap();
        assert!(Ledger::open(&outside.0).is_err());
    }
}
