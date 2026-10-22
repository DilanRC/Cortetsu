use cortetsu_rescue::{Roots, current, hash_path, plan_rollback, previous};
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);
struct Fixture {
    root: PathBuf,
}
impl Fixture {
    fn new() -> Self {
        let id = NEXT.fetch_add(1, Ordering::SeqCst);
        let root =
            std::env::temp_dir().join(format!("cortetsu-rescue-{}-{id}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        Self { root }
    }
    fn roots(&self) -> Roots {
        Roots {
            data: self.root.join("data"),
            runtime: self.root.join("runtime"),
        }
    }
    fn populate(&self) {
        let roots = self.roots();
        let shell = roots.data.join("builds/shell-1");
        let dot = roots.data.join("dotfiles/builds/dot-1");
        let system = roots.data.join("system/builds/system-1");
        for dir in [&shell, &dot, &system, &roots.runtime] {
            fs::create_dir_all(dir).unwrap();
        }
        fs::write(shell.join("shell.qml"), "// hello\n").unwrap();
        fs::write(shell.join("BUILD_ID"), "shell-1\n").unwrap();
        fs::write(shell.join("BUILD.json"), r#"{"schema":1}"#).unwrap();
        let file = dot.join("home/.config/example.toml");
        fs::create_dir_all(file.parent().unwrap()).unwrap();
        fs::write(&file, "name = 'x'\n").unwrap();
        let digest = hash_path(&file).unwrap();
        assert_eq!(
            digest,
            "03fb99e89899aa6c11d9c199e450e3bcc37c52a1df2b86deebce77cea3b18e82"
        );
        fs::write(dot.join("MANIFEST.json"),format!(r#"{{"schema":1,"entries":[{{"target":".config/example.toml","sha256":"{digest}"}}]}}"#)).unwrap();
        fs::write(system.join("SYSTEM.json"),format!(r#"{{"schema":1,"shellGeneration":"{}","dotfilesGeneration":"{}","repositoryRevision":"test"}}"#,shell.display(),dot.display())).unwrap();
        use std::os::unix::fs::symlink;
        fs::create_dir_all(roots.data.join("system")).unwrap();
        fs::create_dir_all(roots.data.join("dotfiles")).unwrap();
        symlink(&shell, roots.runtime.join("current")).unwrap();
        symlink(&dot, roots.data.join("dotfiles/current")).unwrap();
        symlink(&system, roots.data.join("system/current")).unwrap();
        symlink(&system, roots.data.join("system/previous")).unwrap();
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

#[test]
fn verifies_existing_python_schema_1() {
    let fixture = Fixture::new();
    fixture.populate();
    let status = current(&fixture.roots()).unwrap();
    assert_eq!(status.revision.as_deref(), Some("test"));
    assert!(plan_rollback(&fixture.roots()).is_err()); // no fake previous generation
}

#[test]
fn refuses_digest_mismatch_and_traversal() {
    let f = Fixture::new();
    f.populate();
    let file = f
        .roots()
        .data
        .join("dotfiles/builds/dot-1/home/.config/example.toml");
    fs::write(&file, "tampered\n").unwrap();
    assert!(current(&f.roots()).is_err());
    f.populate_fresh_manifests_for_test();
}

impl Fixture {
    fn populate_fresh_manifests_for_test(&self) {
        let roots = self.roots();
        let dot = roots.data.join("dotfiles/builds/dot-1");
        fs::write(dot.join("MANIFEST.json"),r#"{"schema":1,"entries":[{"target":"../evil","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}"#).unwrap();
        assert!(current(&roots).is_err());
    }
}

#[test]
fn rejects_system_pointer_escape() {
    let f = Fixture::new();
    f.populate();
    let roots = f.roots();
    fs::remove_file(roots.data.join("system/current")).unwrap();
    std::os::unix::fs::symlink(&f.root, roots.data.join("system/current")).unwrap();
    assert!(current(&roots).is_err());
}

impl Fixture {
    fn add_second_generation(&self) {
        let roots = self.roots();
        let shell = roots.data.join("builds/shell-2");
        let dot = roots.data.join("dotfiles/builds/dot-2");
        let system = roots.data.join("system/builds/system-2");
        for dir in [&shell, &dot, &system] {
            fs::create_dir_all(dir).unwrap();
        }
        fs::write(shell.join("shell.qml"), "// older shell\n").unwrap();
        fs::write(shell.join("BUILD_ID"), "shell-2\n").unwrap();
        fs::write(shell.join("BUILD.json"), r#"{"schema":1}"#).unwrap();
        let file = dot.join("home/.config/example.toml");
        fs::create_dir_all(file.parent().unwrap()).unwrap();
        fs::write(&file, "name = 'older'\n").unwrap();
        let digest = hash_path(&file).unwrap();
        fs::write(dot.join("MANIFEST.json"), format!(r#"{{"schema":1,"entries":[{{"target":".config/example.toml","sha256":"{digest}"}}]}}"#)).unwrap();
        fs::write(system.join("SYSTEM.json"), format!(r#"{{"schema":1,"shellGeneration":"{}","dotfilesGeneration":"{}","repositoryRevision":"older"}}"#, shell.display(), dot.display())).unwrap();
        use std::os::unix::fs::symlink;
        let old_previous = roots.data.join("system/previous");
        fs::remove_file(&old_previous).unwrap();
        symlink(&system, &old_previous).unwrap();
        symlink(&shell, roots.runtime.join("previous")).unwrap();
        symlink(&dot, roots.data.join("dotfiles/previous")).unwrap();
    }
}

#[test]
fn two_generation_rollback_is_offline_reversible_and_explicit() {
    use cortetsu_rescue::transaction::{capture_pointers, rollback_pointers};
    let f = Fixture::new();
    f.populate();
    f.add_second_generation();
    let roots = f.roots();
    let before = capture_pointers(&roots).unwrap();
    assert_eq!(previous(&roots).unwrap().revision.as_deref(), Some("older"));
    assert!(rollback_pointers(&roots, false).is_err());
    assert_eq!(capture_pointers(&roots).unwrap(), before);
    let receipt = rollback_pointers(&roots, true).unwrap();
    assert_eq!(receipt.result, "ROLLBACK_POINTERS_ONLY");
    assert_eq!(current(&roots).unwrap().revision.as_deref(), Some("older"));
    assert_eq!(previous(&roots).unwrap().revision.as_deref(), Some("test"));
    rollback_pointers(&roots, true).unwrap();
    assert_eq!(capture_pointers(&roots).unwrap(), before);
}

#[test]
fn preflight_aborts_without_modifying_links_if_previous_is_tampered() {
    use cortetsu_rescue::transaction::{capture_pointers, rollback_pointers};
    let f = Fixture::new();
    f.populate();
    f.add_second_generation();
    let roots = f.roots();
    let before = capture_pointers(&roots).unwrap();
    fs::write(
        roots
            .data
            .join("dotfiles/builds/dot-2/home/.config/example.toml"),
        "bad",
    )
    .unwrap();
    assert!(rollback_pointers(&roots, true).is_err());
    // The captured symlinks remain unchanged despite target integrity failure.
    assert_eq!(
        fs::read_link(roots.data.join("system/current")).unwrap(),
        before.system_current
    );
    assert_eq!(
        fs::read_link(roots.runtime.join("current")).unwrap(),
        before.shell_current
    );
}

#[test]
fn exec_v1_shared_fixture_verifies_a_real_generation() {
    let f = Fixture::new();
    f.populate();
    let fixture = include_bytes!("../../contracts/exec/v1/fixtures/system-verify.json");
    let reply = cortetsu_rescue::exec_read::handle(fixture, &f.roots());
    assert_eq!(reply["verified"], true);
    assert_eq!(reply["outcome"], "read");
    assert_eq!(reply["body"]["revision"], "test");
}

#[test]
fn sigkill_between_pointer_moves_recovers_from_durable_journal() {
    use cortetsu_rescue::transaction::capture_pointers;
    use std::process::{Command, Stdio};
    use std::thread;
    use std::time::{Duration, Instant};

    let f = Fixture::new();
    f.populate();
    f.add_second_generation();
    let roots = f.roots();
    let before = capture_pointers(&roots).unwrap();
    let child_path = env!("CARGO_BIN_EXE_cortetsu-rescue");
    let mut child = Command::new(child_path)
        .arg("rollback")
        .arg("--acknowledge-unmanaged-helpers")
        .env("CORTETSU_DATA_ROOT", &roots.data)
        .env("CORTETSU_RUNTIME_ROOT", &roots.runtime)
        .env("CORTETSU_RESCUE_TEST_PAUSE_AFTER", "3")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let start = Instant::now();
    let reached = loop {
        let shell_current = fs::read_link(roots.runtime.join("current")).unwrap();
        let journal = roots.data.join("system/rescue-transaction-v1.json");
        if journal.exists() && shell_current == roots.data.join("builds/shell-2") {
            break true;
        }
        if start.elapsed() > Duration::from_secs(10) {
            break false;
        }
        thread::sleep(Duration::from_millis(15));
    };
    child.kill().unwrap();
    child.wait().unwrap();
    assert!(
        reached,
        "transaction never reached the fault injection point"
    );
    assert!(
        roots
            .data
            .join("system/rescue-transaction-v1.json")
            .exists()
    );
    let output = Command::new(child_path)
        .arg("recover")
        .env("CORTETSU_DATA_ROOT", &roots.data)
        .env("CORTETSU_RUNTIME_ROOT", &roots.runtime)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(capture_pointers(&roots).unwrap(), before);
}
