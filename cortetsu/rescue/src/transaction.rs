//! Opt-in offline transaction recovery for Cortetsu generation pointers.
//!
//! This deliberately operates only on the six managed generation symlinks.
//! The preexisting helper binaries under ~/.local/bin are *not* part of schema 1;
//! a rollback is therefore refused unless the operator acknowledges that
//! helper versions need separate verified recovery. Never invoke automatically.
use super::{
    CheckError, Result, Roots, current, invalid, managed_generation, managed_link, plan_rollback,
    verify_dotfiles, verify_shell,
};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, symlink};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const JOURNAL_NAME: &str = "rescue-transaction-v1.json";
const JOURNAL_SCHEMA: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Pointers {
    pub system_current: PathBuf,
    pub system_previous: PathBuf,
    pub shell_current: PathBuf,
    pub shell_previous: Option<PathBuf>,
    pub dotfiles_current: PathBuf,
    pub dotfiles_previous: Option<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Phase {
    Prepared,
    Applying,
    Verifying,
    Committed,
    RecoveryRequired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Journal {
    pub schema: u32,
    pub id: String,
    pub phase: Phase,
    pub before: Pointers,
    pub target: Pointers,
}

#[derive(Debug, Clone, Serialize)]
pub struct RecoveryStatus {
    pub transaction_id: String,
    pub recovered: bool,
    pub result: String,
}

impl Roots {
    fn roles(&self) -> [(PathBuf, PathBuf); 6] {
        [
            (
                self.system_root().join("current"),
                self.system_root().join("builds"),
            ),
            (
                self.system_root().join("previous"),
                self.system_root().join("builds"),
            ),
            (self.runtime.join("current"), self.data.join("builds")),
            (self.runtime.join("previous"), self.data.join("builds")),
            (
                self.dot_root().join("current"),
                self.dot_root().join("builds"),
            ),
            (
                self.dot_root().join("previous"),
                self.dot_root().join("builds"),
            ),
        ]
    }
}

fn existing_pointer(path: &Path, builds: &Path) -> Result<Option<PathBuf>> {
    match fs::symlink_metadata(path) {
        Ok(_) => managed_link(path, builds).map(Some),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err(invalid("generation pointer cannot be inspected")),
    }
}

pub fn capture_pointers(roots: &Roots) -> Result<Pointers> {
    // Verify both full generations before trying to capture any target.
    plan_rollback(roots)?;
    let roles = roots.roles();
    let mut values = Vec::with_capacity(6);
    for (link, builds) in &roles {
        values.push(existing_pointer(link, builds)?);
    }
    let required = |index: usize| {
        values[index]
            .clone()
            .ok_or_else(|| invalid("missing required generation link"))
    };
    Ok(Pointers {
        system_current: required(0)?,
        system_previous: required(1)?,
        shell_current: required(2)?,
        shell_previous: values[3].clone(),
        dotfiles_current: required(4)?,
        dotfiles_previous: values[5].clone(),
    })
}

impl Pointers {
    fn members(&self) -> [Option<&Path>; 6] {
        [
            Some(&self.system_current),
            Some(&self.system_previous),
            Some(&self.shell_current),
            self.shell_previous.as_deref(),
            Some(&self.dotfiles_current),
            self.dotfiles_previous.as_deref(),
        ]
    }

    fn validate(&self, roots: &Roots) -> Result<()> {
        for ((_, builds), member) in roots.roles().iter().zip(self.members()) {
            if let Some(path) = member {
                // Canonical path equality stops a journal from directing a
                // recovery outside its generation directory.
                let candidate = managed_generation(&path.to_string_lossy(), builds)?;
                if candidate != path {
                    return Err(invalid("noncanonical path in transaction journal"));
                }
            }
        }
        Ok(())
    }
}

fn planned(roots: &Roots) -> Result<(Pointers, Pointers)> {
    let (active, previous) = plan_rollback(roots)?;
    let before = capture_pointers(roots)?;
    let target = Pointers {
        system_current: before.system_previous.clone(),
        system_previous: before.system_current.clone(),
        shell_current: PathBuf::from(&previous.shell),
        shell_previous: Some(PathBuf::from(&active.shell)),
        dotfiles_current: PathBuf::from(&previous.dotfiles),
        dotfiles_previous: Some(PathBuf::from(&active.dotfiles)),
    };
    before.validate(roots)?;
    target.validate(roots)?;
    verify_shell(&target.shell_current)?;
    verify_dotfiles(&target.dotfiles_current)?;
    Ok((before, target))
}

fn journal_path(roots: &Roots) -> PathBuf {
    roots.system_root().join(JOURNAL_NAME)
}

fn reject_symlink(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(meta) if meta.file_type().is_symlink() || !meta.is_file() => {
            Err(invalid("transaction journal is not a regular file"))
        }
        Ok(_) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(invalid("cannot inspect transaction journal")),
    }
}

fn sync_dir(dir: &Path) -> Result<()> {
    File::open(dir)
        .and_then(|file| file.sync_all())
        .map_err(|_| invalid("cannot sync transaction directory"))
}

fn store(roots: &Roots, journal: &Journal) -> Result<()> {
    let path = journal_path(roots);
    reject_symlink(&path)?;
    let parent = path
        .parent()
        .ok_or_else(|| invalid("invalid journal directory"))?;
    let tmp = parent.join(format!(".{JOURNAL_NAME}.{}.tmp", std::process::id()));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&tmp)
        .map_err(|_| invalid("cannot create transaction journal"))?;
    let result = (|| {
        let bytes = serde_json::to_vec_pretty(journal)
            .map_err(|_| invalid("cannot serialize transaction journal"))?;
        if bytes.len() > 64 * 1024 {
            return Err(invalid("transaction journal exceeds maximum size"));
        }
        file.write_all(&bytes)
            .and_then(|()| file.sync_all())
            .map_err(|_| invalid("cannot persist transaction journal"))?;
        fs::rename(&tmp, &path).map_err(|_| invalid("cannot install transaction journal"))?;
        sync_dir(parent)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

fn load(roots: &Roots) -> Result<Option<Journal>> {
    let path = journal_path(roots);
    reject_symlink(&path)?;
    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(invalid("cannot read transaction journal")),
    };
    if bytes.len() > 64 * 1024 {
        return Err(invalid("transaction journal exceeds maximum size"));
    }
    let journal: Journal =
        serde_json::from_slice(&bytes).map_err(|_| invalid("invalid transaction journal"))?;
    if journal.schema != JOURNAL_SCHEMA {
        return Err(invalid("unsupported transaction journal schema"));
    }
    journal.before.validate(roots)?;
    journal.target.validate(roots)?;
    Ok(Some(journal))
}

fn remove_journal(roots: &Roots) -> Result<()> {
    let file = journal_path(roots);
    reject_symlink(&file)?;
    fs::remove_file(&file).map_err(|_| invalid("cannot clear transaction journal"))?;
    sync_dir(&roots.system_root())
}

fn locks(roots: &Roots) -> Result<(File, File)> {
    fs::create_dir_all(&roots.data).map_err(|_| invalid("cannot create data root"))?;
    // Same order as scripts/install-cortetsu.sh: installation lock first,
    // system mutation lock second. Refuse rather than blocking when installing.
    let install_path = roots.data.join("install.lock");
    reject_symlink(&install_path)?;
    let install = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(&install_path)
        .map_err(|_| invalid("cannot open install lock"))?;
    install
        .try_lock_exclusive()
        .map_err(|_| invalid("installation already running"))?;
    let dir = roots.system_root();
    fs::create_dir_all(&dir).map_err(|_| invalid("cannot create system root"))?;
    let path = dir.join("system.lock");
    reject_symlink(&path)?;
    let system = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(&path)
        .map_err(|_| invalid("cannot open system lock"))?;
    system
        .lock_exclusive()
        .map_err(|_| invalid("cannot acquire system lock"))?;
    Ok((install, system))
}

fn atomic_pointer(link: &Path, target: Option<&Path>, builds: &Path, step: usize) -> Result<()> {
    // Refuse to replace arbitrary user data if the pointer has been changed.
    existing_pointer(link, builds)?;
    match target {
        Some(target) => {
            managed_generation(&target.to_string_lossy(), builds)?;
            let parent = link
                .parent()
                .ok_or_else(|| invalid("invalid pointer parent"))?;
            let temp = parent.join(format!(".rescue-{}.{}.tmp", std::process::id(), step));
            symlink(target, &temp).map_err(|_| invalid("cannot stage generation pointer"))?;
            let changed =
                fs::rename(&temp, link).map_err(|_| invalid("cannot publish generation pointer"));
            if changed.is_err() {
                let _ = fs::remove_file(&temp);
                return changed;
            }
            sync_dir(parent)
        }
        None => {
            if fs::symlink_metadata(link).is_ok() {
                fs::remove_file(link).map_err(|_| invalid("cannot remove optional pointer"))?;
                sync_dir(
                    link.parent()
                        .ok_or_else(|| invalid("invalid pointer parent"))?,
                )?;
            }
            Ok(())
        }
    }
}

fn apply(
    roots: &Roots,
    pointers: &Pointers,
    mut hook: impl FnMut(usize) -> Result<()>,
) -> Result<()> {
    pointers.validate(roots)?;
    let roles = roots.roles();
    let members = pointers.members();
    // Previous pointers before current; system/current is the commit marker.
    for (step, i) in [3, 2, 5, 4, 1, 0].into_iter().enumerate() {
        atomic_pointer(&roles[i].0, members[i], &roles[i].1, step)?;
        hook(step + 1)?;
    }
    Ok(())
}

fn verify_target(roots: &Roots, expected: &Pointers) -> Result<()> {
    current(roots)?;
    for ((link, builds), target) in roots.roles().iter().zip(expected.members()) {
        let actual = existing_pointer(link, builds)?;
        if actual.as_deref() != target {
            return Err(invalid("transaction pointer readback mismatch"));
        }
    }
    Ok(())
}

fn restore(roots: &Roots, journal: &mut Journal) -> Result<()> {
    if let Err(e) = apply(roots, &journal.before, |_| Ok(()))
        .and_then(|()| verify_target(roots, &journal.before))
    {
        journal.phase = Phase::RecoveryRequired;
        let _ = store(roots, journal);
        return Err(CheckError(format!("RECOVERY_REQUIRED: {e}")));
    }
    remove_journal(roots)
}

fn execute(
    roots: &Roots,
    mut after_step: impl FnMut(usize) -> Result<()>,
) -> Result<RecoveryStatus> {
    let _guards = locks(roots)?;
    if load(roots)?.is_some() {
        return Err(invalid("pending transaction: run recover before rollback"));
    }
    let (before, target) = planned(roots)?;
    let id = format!(
        "{}-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| invalid("invalid system clock"))?
            .as_nanos(),
        std::process::id()
    );
    let mut journal = Journal {
        schema: JOURNAL_SCHEMA,
        id: id.clone(),
        phase: Phase::Prepared,
        before,
        target,
    };
    store(roots, &journal)?;
    journal.phase = Phase::Applying;
    store(roots, &journal)?;
    if let Err(err) = apply(roots, &journal.target, &mut after_step) {
        restore(roots, &mut journal)?;
        return Err(err);
    }
    journal.phase = Phase::Verifying;
    store(roots, &journal)?;
    if let Err(err) = verify_target(roots, &journal.target) {
        restore(roots, &mut journal)?;
        return Err(err);
    }
    journal.phase = Phase::Committed;
    store(roots, &journal)?;
    remove_journal(roots)?;
    Ok(RecoveryStatus {
        transaction_id: id,
        recovered: false,
        result: "ROLLBACK_POINTERS_ONLY".into(),
    })
}

pub fn rollback_pointers(
    roots: &Roots,
    acknowledge_unmanaged_helpers: bool,
) -> Result<RecoveryStatus> {
    if !acknowledge_unmanaged_helpers {
        return Err(invalid(
            "rollback refused: schema 1 cannot restore ~/.local/bin helpers; explicit acknowledgement required",
        ));
    }
    execute(roots, |step| {
        // Instrumentation available only in debug CI test builds. Release
        // binaries never read the fault injection environment variable.
        #[cfg(debug_assertions)]
        if std::env::var("CORTETSU_RESCUE_TEST_PAUSE_AFTER")
            .ok()
            .and_then(|v| v.parse::<usize>().ok())
            == Some(step)
        {
            std::thread::sleep(std::time::Duration::from_secs(30));
        }
        let _ = step;
        Ok(())
    })
}

pub fn recover(roots: &Roots) -> Result<RecoveryStatus> {
    let _guards = locks(roots)?;
    let mut journal = load(roots)?.ok_or_else(|| invalid("no pending recovery journal"))?;
    if journal.phase == Phase::Committed && verify_target(roots, &journal.target).is_ok() {
        remove_journal(roots)?;
        return Ok(RecoveryStatus {
            transaction_id: journal.id,
            recovered: true,
            result: "ALREADY_COMMITTED".into(),
        });
    }
    let id = journal.id.clone();
    restore(roots, &mut journal)?;
    Ok(RecoveryStatus {
        transaction_id: id,
        recovered: true,
        result: "RESTORED_BEFORE".into(),
    })
}

#[cfg(test)]
mod tests {
    use super::super::hash_path;
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT: AtomicU64 = AtomicU64::new(0);

    struct Fixture {
        dir: PathBuf,
        roots: Roots,
    }

    impl Fixture {
        fn new() -> Self {
            let dir = std::env::temp_dir().join(format!(
                "cortetsu-txn-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::SeqCst)
            ));
            let roots = Roots {
                data: dir.join("data"),
                runtime: dir.join("runtime"),
            };
            for name in ["1", "2"] {
                let shell = roots.data.join("builds").join(format!("shell-{name}"));
                let dots = roots
                    .data
                    .join("dotfiles/builds")
                    .join(format!("dots-{name}"));
                let system = roots
                    .data
                    .join("system/builds")
                    .join(format!("system-{name}"));
                fs::create_dir_all(&shell).unwrap();
                fs::create_dir_all(&dots).unwrap();
                fs::create_dir_all(&system).unwrap();
                fs::write(shell.join("shell.qml"), "// test").unwrap();
                fs::write(shell.join("BUILD_ID"), name).unwrap();
                fs::write(shell.join("BUILD.json"), r#"{"schema":1}"#).unwrap();
                let file = dots.join("home/example.toml");
                fs::create_dir_all(file.parent().unwrap()).unwrap();
                fs::write(&file, format!("name = '{name}'")).unwrap();
                fs::write(
                    dots.join("MANIFEST.json"),
                    format!(
                        r#"{{"schema":1,"entries":[{{"target":"example.toml","sha256":"{}"}}]}}"#,
                        hash_path(&file).unwrap()
                    ),
                )
                .unwrap();
                fs::write(
                    system.join("SYSTEM.json"),
                    format!(
                        r#"{{"schema":1,"shellGeneration":"{}","dotfilesGeneration":"{}"}}"#,
                        shell.display(),
                        dots.display()
                    ),
                )
                .unwrap();
            }
            fs::create_dir_all(&roots.runtime).unwrap();
            symlink(
                roots.data.join("builds/shell-1"),
                roots.runtime.join("current"),
            )
            .unwrap();
            symlink(
                roots.data.join("builds/shell-2"),
                roots.runtime.join("previous"),
            )
            .unwrap();
            symlink(
                roots.data.join("dotfiles/builds/dots-1"),
                roots.data.join("dotfiles/current"),
            )
            .unwrap();
            symlink(
                roots.data.join("dotfiles/builds/dots-2"),
                roots.data.join("dotfiles/previous"),
            )
            .unwrap();
            symlink(
                roots.data.join("system/builds/system-1"),
                roots.data.join("system/current"),
            )
            .unwrap();
            symlink(
                roots.data.join("system/builds/system-2"),
                roots.data.join("system/previous"),
            )
            .unwrap();
            Self { dir, roots }
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.dir);
        }
    }

    #[test]
    fn interrupted_transaction_restores_before_snapshot() {
        let f = Fixture::new();
        let before = capture_pointers(&f.roots).unwrap();
        let crashed = std::panic::catch_unwind(|| {
            let _ = execute(&f.roots, |step| {
                if step == 3 {
                    panic!("simulated SIGKILL after 3 pointers");
                }
                Ok(())
            });
        });
        assert!(crashed.is_err());
        assert!(journal_path(&f.roots).exists());
        assert!(execute(&f.roots, |_| Ok(())).is_err());
        let result = recover(&f.roots).unwrap();
        assert_eq!(result.result, "RESTORED_BEFORE");
        assert_eq!(capture_pointers(&f.roots).unwrap(), before);
        assert!(!journal_path(&f.roots).exists());
    }

    #[test]
    fn rejects_corrupted_journal_before_any_link_change() {
        let f = Fixture::new();
        let before = capture_pointers(&f.roots).unwrap();
        fs::write(journal_path(&f.roots), r#"{"schema":2,"phase":"APPLYING"}"#).unwrap();
        assert!(recover(&f.roots).is_err());
        assert_eq!(capture_pointers(&f.roots).unwrap(), before);
    }

    #[test]
    fn refuses_rollback_while_installer_holds_install_lock() {
        let f = Fixture::new();
        let before = capture_pointers(&f.roots).unwrap();
        let lock = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(false)
            .open(f.roots.data.join("install.lock"))
            .unwrap();
        lock.lock_exclusive().unwrap();
        assert!(rollback_pointers(&f.roots, true).is_err());
        assert_eq!(capture_pointers(&f.roots).unwrap(), before);
        fs2::FileExt::unlock(&lock).unwrap();
    }

    #[test]
    fn phase_roundtrip() {
        let raw = serde_json::to_vec(&Phase::RecoveryRequired).unwrap();
        assert_eq!(
            serde_json::from_slice::<Phase>(&raw).unwrap(),
            Phase::RecoveryRequired
        );
    }
}
