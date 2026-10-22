//! Schema-2 helper generations are verified and rolled back with the other layers.
//! All paths live in a disposable fixture, never in the installed user home.
use cortetsu_rescue::helper_bundle;
use cortetsu_rescue::transaction::{capture_pointers, rollback_pointers};
use cortetsu_rescue::{Roots, current, hash_path, plan_rollback};
use std::fs;
use std::os::unix::fs::symlink;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
static NEXT: AtomicU64 = AtomicU64::new(0);

struct Fixture {
    path: PathBuf,
    roots: Roots,
    bundles: [PathBuf; 2],
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "cortetsu-schema2-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
        ));
        let roots = Roots {
            data: path.join("data"),
            runtime: path.join("runtime"),
        };
        let mut bundles = Vec::new();
        for i in 1..=2 {
            let source = path.join(format!("source-{i}"));
            fs::create_dir_all(&source).unwrap();
            fs::write(
                source.join("cortetsu-pomodoro"),
                format!("#!/bin/sh\necho {i}\n"),
            )
            .unwrap();
            let bundle = helper_bundle::stage(&roots, &source).unwrap();
            bundles.push(PathBuf::from(bundle.directory));
            let shell = roots.data.join(format!("builds/shell-{i}"));
            let dots = roots.data.join(format!("dotfiles/builds/dots-{i}"));
            let system = roots.data.join(format!("system/builds/system-{i}"));
            fs::create_dir_all(&shell).unwrap();
            fs::create_dir_all(dots.join("home")).unwrap();
            fs::create_dir_all(&system).unwrap();
            fs::write(shell.join("shell.qml"), "// test").unwrap();
            fs::write(shell.join("BUILD_ID"), format!("shell-{i}")).unwrap();
            fs::write(shell.join("BUILD.json"), r#"{"schema":1}"#).unwrap();
            fs::write(dots.join("home/example.txt"), format!("sample {i}")).unwrap();
            let digest = hash_path(&dots.join("home/example.txt")).unwrap();
            fs::write(
                dots.join("MANIFEST.json"),
                format!(
                    r#"{{"schema":1,"entries":[{{"target":"example.txt","sha256":"{digest}"}}]}}"#,
                ),
            )
            .unwrap();
            fs::write(system.join("SYSTEM.json"), format!(
                r#"{{"schema":2,"shellGeneration":"{}","dotfilesGeneration":"{}","helpersGeneration":"{}"}}"#,
                shell.display(), dots.display(), bundles.last().unwrap().display(),
            )).unwrap();
        }
        fs::create_dir_all(&roots.runtime).unwrap();
        for (group, current_target, previous_target) in [
            (
                roots.data.join("system"),
                roots.data.join("system/builds/system-1"),
                roots.data.join("system/builds/system-2"),
            ),
            (
                roots.runtime.clone(),
                roots.data.join("builds/shell-1"),
                roots.data.join("builds/shell-2"),
            ),
            (
                roots.data.join("dotfiles"),
                roots.data.join("dotfiles/builds/dots-1"),
                roots.data.join("dotfiles/builds/dots-2"),
            ),
            (
                roots.data.join("helpers"),
                bundles[0].clone(),
                bundles[1].clone(),
            ),
        ] {
            symlink(current_target, group.join("current")).unwrap();
            symlink(previous_target, group.join("previous")).unwrap();
        }
        Self {
            path,
            roots,
            bundles: bundles.try_into().unwrap(),
        }
    }
}

#[test]
fn complete_schema2_rollback_includes_helpers_and_returns() {
    let f = Fixture::new();
    assert_eq!(
        current(&f.roots).unwrap().helpers.as_deref(),
        Some(f.bundles[0].to_str().unwrap())
    );
    assert!(plan_rollback(&f.roots).is_ok());
    let original = capture_pointers(&f.roots).unwrap();
    assert_eq!(
        original.helpers_previous.as_deref(),
        Some(f.bundles[1].as_path())
    );
    assert!(rollback_pointers(&f.roots, false).is_err());
    let result = rollback_pointers(&f.roots, true).unwrap();
    assert_eq!(result.result, "ROLLBACK_POINTERS_ONLY");
    assert_eq!(
        current(&f.roots).unwrap().helpers.as_deref(),
        Some(f.bundles[1].to_str().unwrap())
    );
    rollback_pointers(&f.roots, true).unwrap();
    assert_eq!(capture_pointers(&f.roots).unwrap(), original);
}

#[test]
fn refuses_corrupt_bundle_and_partial_schema2_manifest() {
    let f = Fixture::new();
    let before = capture_pointers(&f.roots).unwrap();
    fs::write(f.bundles[1].join("cortetsu-pomodoro"), "modified").unwrap();
    assert!(plan_rollback(&f.roots).is_err());
    assert!(rollback_pointers(&f.roots, true).is_err());
    assert_eq!(
        fs::read_link(f.roots.data.join("helpers/current")).unwrap(),
        f.bundles[0]
    );
    // A malformed or downgraded schema-2 manifest must not be accepted.
    fs::write(
        f.roots.data.join("system/builds/system-1/SYSTEM.json"),
        format!(
            r#"{{"schema":2,"shellGeneration":"{}","dotfilesGeneration":"{}"}}"#,
            before.shell_current.display(),
            before.dotfiles_current.display()
        ),
    )
    .unwrap();
    assert!(current(&f.roots).is_err());
}
