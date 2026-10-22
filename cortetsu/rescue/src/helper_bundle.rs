//! Immutable helper staging. The installation transaction owns activation.
use super::{Result, Roots, invalid};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const LIMIT_COUNT: usize = 128;
const LIMIT_HELPER_SIZE: u64 = 32 * 1024 * 1024;
const LIMIT_TOTAL_BYTES: u64 = 128 * 1024 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BundleManifest {
    schema: u32,
    build_id: String,
    helpers: Vec<HelperEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct HelperEntry {
    name: String,
    bytes: u64,
    sha256: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct BundleReport {
    pub build_id: String,
    pub helpers: usize,
    pub bytes: u64,
    pub directory: String,
    pub activated: bool,
}

fn safe_filename(name: &str) -> bool {
    (name == "cortetsu" || name.starts_with("cortetsu-"))
        && name.len() <= 120
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

fn safe_build_id(id: &str) -> bool {
    id.starts_with("helpers-")
        && id.len() <= 120
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

fn helpers_root(roots: &Roots) -> PathBuf {
    roots.data.join("helpers/builds")
}

fn reject_non_regular(path: &Path) -> Result<fs::Metadata> {
    let metadata = fs::symlink_metadata(path).map_err(|_| invalid("cannot stat helper"))?;
    if !metadata.is_file()
        || metadata.file_type().is_symlink()
        || metadata.len() > LIMIT_HELPER_SIZE
    {
        return Err(invalid("unsafe or oversized helper source"));
    }
    Ok(metadata)
}

fn sync_dir(dir: &Path) -> Result<()> {
    File::open(dir)
        .and_then(|fd| fd.sync_all())
        .map_err(|_| invalid("cannot sync bundle directory"))
}

fn hex_hash(bytes: &[u8]) -> String {
    let mut digest = Sha256::new();
    digest.update(bytes);
    digest
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn inspect_bundle(path: &Path, expected: &str) -> Result<BundleReport> {
    let metadata = fs::symlink_metadata(path).map_err(|_| invalid("helper bundle missing"))?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(invalid("helper bundle is not a directory"));
    }
    let manifest_file = path.join("HELPERS.json");
    reject_non_regular(&manifest_file)?;
    let raw = fs::read(&manifest_file).map_err(|_| invalid("unreadable helper manifest"))?;
    if raw.len() > 1024 * 1024 {
        return Err(invalid("helper manifest too large"));
    }
    let manifest: BundleManifest =
        serde_json::from_slice(&raw).map_err(|_| invalid("invalid helper manifest"))?;
    if manifest.schema != 1
        || manifest.build_id != expected
        || manifest.helpers.is_empty()
        || manifest.helpers.len() > LIMIT_COUNT
    {
        return Err(invalid("unsupported or empty helper manifest"));
    }
    let mut names = std::collections::HashSet::new();
    let mut total = 0u64;
    for item in &manifest.helpers {
        if !safe_filename(&item.name)
            || !names.insert(item.name.clone())
            || item.sha256.len() != 64
            || !item.sha256.bytes().all(|b| b.is_ascii_hexdigit())
            || item.bytes > LIMIT_HELPER_SIZE
        {
            return Err(invalid("invalid helper entry"));
        }
        let file = path.join(&item.name);
        let meta = reject_non_regular(&file)?;
        if meta.len() != item.bytes || meta.permissions().mode() & 0o111 == 0 {
            return Err(invalid("helper file metadata mismatch"));
        }
        let bytes = fs::read(&file).map_err(|_| invalid("cannot read helper"))?;
        if hex_hash(&bytes) != item.sha256 {
            return Err(invalid("helper sha256 mismatch"));
        }
        total = total
            .checked_add(item.bytes)
            .ok_or_else(|| invalid("helper bundle overflow"))?;
        if total > LIMIT_TOTAL_BYTES {
            return Err(invalid("helper bundle exceeds size limit"));
        }
    }
    let names_on_disk: std::collections::HashSet<_> = fs::read_dir(path)
        .map_err(|_| invalid("cannot list helper bundle"))?
        .map(|entry| {
            entry
                .map(|item| item.file_name().to_string_lossy().into_owned())
                .map_err(|_| invalid("invalid helper directory"))
        })
        .collect::<Result<_>>()?;
    if names_on_disk.len() != manifest.helpers.len() + 1 || !names_on_disk.contains("HELPERS.json")
    {
        return Err(invalid("unexpected helper bundle entries"));
    }
    Ok(BundleReport {
        build_id: expected.into(),
        helpers: manifest.helpers.len(),
        bytes: total,
        directory: path.to_string_lossy().into_owned(),
        activated: false,
    })
}

pub fn verify(roots: &Roots, id: &str) -> Result<BundleReport> {
    if !safe_build_id(id) {
        return Err(invalid("invalid helper build id"));
    }
    let root = helpers_root(roots);
    let path = root.join(id);
    // Do not follow a symlink on the build directory itself.
    if fs::symlink_metadata(&root)
        .map_err(|_| invalid("helpers root missing"))?
        .file_type()
        .is_symlink()
    {
        return Err(invalid("unsafe helpers root"));
    }
    inspect_bundle(&path, id)
}

fn lock_install(roots: &Roots) -> Result<File> {
    fs::create_dir_all(&roots.data).map_err(|_| invalid("cannot create data root"))?;
    let path = roots.data.join("install.lock");
    if let Ok(meta) = fs::symlink_metadata(&path)
        && (!meta.is_file() || meta.file_type().is_symlink())
    {
        return Err(invalid("unsafe install lock"));
    }
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(path)
        .map_err(|_| invalid("cannot open install lock"))?;
    file.try_lock_exclusive()
        .map_err(|_| invalid("Cortetsu install busy"))?;
    Ok(file)
}

/// Snapshot only files whose basename belongs to the Cortetsu helper
/// namespace. No destination in ~/.local/bin is opened or replaced.
pub fn stage(roots: &Roots, source: &Path) -> Result<BundleReport> {
    if !source.is_absolute() {
        return Err(invalid("helper source must be absolute"));
    }
    let _lock = lock_install(roots)?;
    let source = fs::canonicalize(source).map_err(|_| invalid("helper source missing"))?;
    if !source.is_dir() {
        return Err(invalid("helper source must be a directory"));
    }
    let mut entries = Vec::<(String, PathBuf)>::new();
    for entry in fs::read_dir(&source).map_err(|_| invalid("cannot list helper sources"))? {
        let entry = entry.map_err(|_| invalid("cannot list helper sources"))?;
        let name = entry
            .file_name()
            .to_str()
            .ok_or_else(|| invalid("non-utf8 filename"))?
            .to_owned();
        if !safe_filename(&name) {
            continue;
        }
        reject_non_regular(&entry.path())?;
        entries.push((name, entry.path()));
    }
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    if entries.is_empty() || entries.len() > LIMIT_COUNT {
        return Err(invalid("unsupported number of helpers"));
    }
    let root = helpers_root(roots);
    fs::create_dir_all(&root).map_err(|_| invalid("cannot create helpers root"))?;
    if fs::symlink_metadata(&root)
        .map_err(|_| invalid("helpers root missing"))?
        .file_type()
        .is_symlink()
    {
        return Err(invalid("unsafe helpers root"));
    }
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| invalid("invalid system clock"))?
        .as_nanos();
    let id = format!("helpers-{nanos:x}-{}", std::process::id());
    let staging = root.join(format!(".{id}.staging"));
    let finished = root.join(&id);
    fs::create_dir(&staging).map_err(|_| invalid("cannot create helpers staging"))?;
    let result = (|| {
        let mut records = Vec::<HelperEntry>::new();
        let mut total = 0u64;
        for (name, src) in entries {
            let metadata = reject_non_regular(&src)?;
            total = total
                .checked_add(metadata.len())
                .ok_or_else(|| invalid("bundle size overflow"))?;
            if total > LIMIT_TOTAL_BYTES {
                return Err(invalid("bundle too large"));
            }
            let bytes = fs::read(&src).map_err(|_| invalid("cannot copy helper"))?;
            // Reject changes while copying rather than recording a false digest.
            if bytes.len() as u64 != metadata.len() {
                return Err(invalid("source modified during staging"));
            }
            let dest = staging.join(&name);
            let mut f = OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o700)
                .open(dest)
                .map_err(|_| invalid("cannot stage helper"))?;
            f.write_all(&bytes)
                .and_then(|_| f.sync_all())
                .map_err(|_| invalid("cannot save helper"))?;
            records.push(HelperEntry {
                name,
                bytes: metadata.len(),
                sha256: hex_hash(&bytes),
            });
        }
        let manifest = BundleManifest {
            schema: 1,
            build_id: id.clone(),
            helpers: records,
        };
        let serialized = serde_json::to_vec_pretty(&manifest)
            .map_err(|_| invalid("cannot serialize helper manifest"))?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(staging.join("HELPERS.json"))
            .map_err(|_| invalid("cannot stage manifest"))?;
        file.write_all(&serialized)
            .and_then(|_| file.sync_all())
            .map_err(|_| invalid("cannot sync helper manifest"))?;
        sync_dir(&staging)?;
        inspect_bundle(&staging, &id)?;
        fs::rename(&staging, &finished).map_err(|_| invalid("cannot publish helper bundle"))?;
        sync_dir(&root)?;
        inspect_bundle(&finished, &id)
    })();
    if result.is_err() {
        let _ = fs::remove_dir_all(&staging);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    struct Fixture {
        home: PathBuf,
        roots: Roots,
    }
    impl Fixture {
        fn new() -> Self {
            let home = std::env::temp_dir().join(format!(
                "cortetsu-bundle-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&home).unwrap();
            let roots = Roots {
                data: home.join("data"),
                runtime: home.join("runtime"),
            };
            Self { home, roots }
        }
        fn source(&self) -> PathBuf {
            let path = self.home.join("repo");
            fs::create_dir_all(&path).unwrap();
            fs::write(path.join("cortetsu-pomodoro"), "#!/bin/sh\necho ok\n").unwrap();
            path
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.home);
        }
    }
    #[test]
    fn stages_verifiable_bundles_without_touching_user_binaries() {
        let fixture = Fixture::new();
        let src = fixture.source();
        let report = stage(&fixture.roots, &src).unwrap();
        assert_eq!(report.helpers, 1);
        assert!(!report.activated);
        assert_eq!(verify(&fixture.roots, &report.build_id).unwrap().bytes, 18);
        assert!(!fixture.home.join(".local/bin").exists());
        fs::write(
            Path::new(&report.directory).join("cortetsu-pomodoro"),
            "TAMPERED",
        )
        .unwrap();
        assert!(verify(&fixture.roots, &report.build_id).is_err());
    }
    #[test]
    fn refuses_symlink_and_non_managed_sources() {
        let fixture = Fixture::new();
        let src = fixture.source();
        std::os::unix::fs::symlink("/etc/passwd", src.join("cortetsu-danger")).unwrap();
        assert!(stage(&fixture.roots, &src).is_err());
        assert!(verify(&fixture.roots, "../../outside").is_err());
    }
    #[test]
    fn refuses_parallel_install_lock() {
        let fixture = Fixture::new();
        let src = fixture.source();
        fs::create_dir_all(&fixture.roots.data).unwrap();
        let file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(false)
            .open(fixture.roots.data.join("install.lock"))
            .unwrap();
        file.lock_exclusive().unwrap();
        assert!(stage(&fixture.roots, &src).is_err());
        fs2::FileExt::unlock(&file).unwrap();
    }
    #[test]
    fn includes_stable_cli_in_generation() {
        let fixture = Fixture::new();
        let src = fixture.source();
        fs::write(src.join("cortetsu"), "#!/bin/sh\nexit 0\n").unwrap();
        let bundle = stage(&fixture.roots, &src).unwrap();
        assert_eq!(bundle.helpers, 2);
        assert!(Path::new(&bundle.directory).join("cortetsu").is_file());
    }
}
