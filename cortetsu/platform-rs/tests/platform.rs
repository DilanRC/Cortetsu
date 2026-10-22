use serde_json::Value;
use std::{
    fs,
    path::PathBuf,
    process::{Command, Output},
    sync::atomic::{AtomicUsize, Ordering},
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
struct Sandbox(PathBuf);
impl Sandbox {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "cortetsu-platform-test-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&p).unwrap();
        Self(p)
    }
    fn put(&self, p: &str, s: &str) {
        let d = self.0.join(p);
        fs::create_dir_all(d.parent().unwrap()).unwrap();
        fs::write(d, s).unwrap()
    }
    fn run(&self, args: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_cortetsu-platform"))
            .args(args)
            .env("HOME", self.0.join("home"))
            .env("XDG_CONFIG_HOME", self.0.join("home/.config"))
            .env("XDG_DATA_HOME", self.0.join("home/.local/share"))
            .env("XDG_STATE_HOME", self.0.join("home/.local/state"))
            .env("CORTETSU_DATA_ROOT", self.0.join("data"))
            .env("CORTETSU_RUNTIME_ROOT", self.0.join("runtime"))
            .current_dir(&self.0)
            .output()
            .unwrap()
    }
    fn repo(&self) -> String {
        self.0.join("repo").to_string_lossy().into_owned()
    }
}
impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn ok(out: Output) -> String {
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap()
}
fn fixture(s: &Sandbox) {
    s.put(
        "repo/profiles/personal.toml",
        "schema = 1\nname = 'personal'\nenabled_tags = ['test']\npackage_groups = []\n",
    );
    s.put("repo/dotfiles/manifest.toml","schema = 1\n[defaults]\nprofile = 'personal'\n[[entry]]\nsource = 'source/config'\ntarget = '.config/demo'\ntags = ['test']\n");
    s.put("repo/source/config", "first\n");
    s.put("home/.config/demo", "unmanaged\n");
}
#[test]
fn dotfiles_roundtrip_preserves_backup_and_detects_drift() {
    let s = Sandbox::new();
    fixture(&s);
    let repo = s.repo();
    ok(s.run(&["dotfiles", "apply", "--repo", &repo]));
    assert_eq!(
        fs::read_to_string(s.0.join("home/.config/demo")).unwrap(),
        "first\n"
    );
    let backups: Vec<_> = walkdir::WalkDir::new(s.0.join("data/dotfiles/backups"))
        .into_iter()
        .filter_map(Result::ok)
        .filter(|e| e.path().ends_with("demo"))
        .collect();
    assert_eq!(backups.len(), 1);
    assert_eq!(
        fs::read_to_string(backups[0].path()).unwrap(),
        "unmanaged\n"
    );
    s.put("repo/source/config", "second\n");
    ok(s.run(&["dotfiles", "apply", "--repo", &repo]));
    ok(s.run(&["dotfiles", "rollback", "--repo", &repo]));
    assert_eq!(
        fs::read_to_string(s.0.join("home/.config/demo")).unwrap(),
        "first\n"
    );
    let current = fs::canonicalize(s.0.join("data/dotfiles/current")).unwrap();
    fs::write(current.join("home/.config/demo"), "tampered").unwrap();
    assert!(
        !s.run(&["dotfiles", "verify", "--repo", &repo])
            .status
            .success()
    );
}
#[test]
fn rejects_dotfile_escape_without_touching_home() {
    let s = Sandbox::new();
    fixture(&s);
    s.put(
        "repo/dotfiles/manifest.toml",
        "schema = 1\n[[entry]]\nsource='source/config'\ntarget='../escape'\n",
    );
    assert!(
        !s.run(&["dotfiles", "apply", "--repo", &s.repo()])
            .status
            .success()
    );
    assert!(!s.0.join("escape").exists());
}
#[test]
fn stable_hyprland_loader_is_regular_file() {
    let s = Sandbox::new();
    fixture(&s);
    s.put(
        "repo/dotfiles/manifest.toml",
        "schema = 1\n[[entry]]\nsource='source/config'\ntarget='.config/hypr/hyprland.lua'\n",
    );
    ok(s.run(&["dotfiles", "apply", "--repo", &s.repo()]));
    let p = s.0.join("home/.config/hypr/hyprland.lua");
    assert!(!p.is_symlink());
    assert!(fs::read_to_string(p).unwrap().contains("dofile("));
}
#[test]
fn normalize_shell_is_idempotent_and_fail_closed() {
    let s = Sandbox::new();
    s.put(
        "stage/shell.qml",
        "ShellRoot {\n    settings.watchFiles: true\n    Background {}\n    Shortcuts {}\n}\n",
    );
    let root = s.0.join("stage");
    let args = ["normalize-shell-24", root.to_str().unwrap()];
    ok(s.run(&args));
    let first = fs::read(root.join("shell.qml")).unwrap();
    ok(s.run(&args));
    assert_eq!(first, fs::read(root.join("shell.qml")).unwrap());
    assert!(String::from_utf8(first).unwrap().contains("BottomHub {}"));
    s.put("stage/shell.qml", "ShellRoot {}\n");
    assert!(!s.run(&args).status.success());
}
#[test]
fn preferences_migration_preserves_existing_values_and_copies_state() {
    let s = Sandbox::new();
    s.put(
        "home/.config/caelestia/shell.json",
        r#"{"launcher":{"favouriteApps":["a",1]},"services":{"maxVolume":1.4}}"#,
    );
    s.put(
        "home/.config/cortetsu/preferences.json",
        r#"{"favouriteApps":["mine"],"custom":true}"#,
    );
    s.put("home/.local/state/caelestia/notifs.json", "[]");
    ok(s.run(&["migrate_config"]));
    let p: Value = serde_json::from_str(
        &fs::read_to_string(s.0.join("home/.config/cortetsu/preferences.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(p["favouriteApps"], serde_json::json!(["mine"]));
    assert_eq!(p["maxVolume"], 1.4);
    assert_eq!(p["custom"], true);
    assert!(s.0.join("home/.local/state/cortetsu/notifs.json").exists());
}
#[test]
fn lifecycle_migration_is_backed_up_and_does_not_signal() {
    let s = Sandbox::new();
    s.put(
        "home/.config/hypr/hyprland/execs.lua",
        "caelestia shell -d\n",
    );
    ok(s.run(&["shell_lifecycle", "migrate"]));
    let text = fs::read_to_string(s.0.join("home/.config/hypr/hyprland/execs.lua")).unwrap();
    assert!(text.contains("systemctl --user start cortetsu-shell.service"));
    ok(s.run(&["shell_lifecycle", "verify"]));
}
#[test]
fn sensitive_import_is_blocked() {
    let s = Sandbox::new();
    fixture(&s);
    s.put("home/.config/fish/config.fish", "set -g EDITOR vim\n");
    s.put("home/.config/fish/secret.fish", "api_key = abc\n");
    let out = s.run(&["import_fish", "apply", "--repo", &s.repo()]);
    assert!(!out.status.success());
    assert!(!s.0.join("repo/dotfiles/imported/fish").exists());
}
#[test]
fn fish_import_apply_creates_valid_manifest() {
    let s = Sandbox::new();
    fixture(&s);
    s.put(
        "repo/dotfiles/imported/fish/home/.config/fish/obsolete.fish",
        "stale\n",
    );
    s.put("home/.config/fish/config.fish", "set -g EDITOR vim\n");
    for args in [
        &["init", "-q"][..],
        &["add", "."][..],
        &[
            "-c",
            "user.email=x@y",
            "-c",
            "user.name=Test",
            "commit",
            "-qm",
            "fixture",
        ][..],
    ] {
        assert!(
            Command::new("git")
                .current_dir(s.0.join("repo"))
                .args(args)
                .status()
                .unwrap()
                .success()
        );
    }
    ok(s.run(&["import_fish", "apply", "--repo", &s.repo()]));
    assert!(
        !s.0.join("repo/dotfiles/imported/fish/home/.config/fish/obsolete.fish")
            .exists()
    );
    assert_eq!(
        fs::read_to_string(s.0.join("repo/dotfiles/imported/fish/home/.config/fish/config.fish"))
            .unwrap(),
        "set -g EDITOR vim\n"
    );
    let _: toml::Value = fs::read_to_string(s.0.join("repo/dotfiles/manifest.toml"))
        .unwrap()
        .parse()
        .unwrap();
}

#[test]
fn native_theme_matches_committed_outputs() {
    let repo = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap();
    let s = Sandbox::new();
    ok(s.run(&["theme", "check", "--repo", repo.to_str().unwrap()]));
}
#[test]
fn theme_adoption_preserves_kde_preferences_and_rejects_external_symlinks() {
    let s = Sandbox::new();
    s.put(
        "home/.config/kdeglobals",
        "[General]\nColorScheme=Other\nfont=Custom\n\n[Other]\nColorScheme=Ignore\n",
    );
    s.put(
        "home/.config/caelestia/cli.json",
        r#"{"theme":{"enableQt":true},"unrelated":true}"#,
    );
    ok(s.run(&["theme", "adopt"]));
    assert_eq!(
        fs::read_to_string(s.0.join("home/.config/kdeglobals")).unwrap(),
        "[General]\nColorScheme=Cortetsu\nfont=Custom\n\n[Other]\nColorScheme=Ignore\n"
    );
    let cli: Value =
        serde_json::from_slice(&fs::read(s.0.join("home/.config/caelestia/cli.json")).unwrap())
            .unwrap();
    assert_eq!(cli["unrelated"], true);
    assert_eq!(cli["theme"]["enableQt"], false);
    fs::remove_file(s.0.join("home/.config/kdeglobals")).unwrap();
    s.put("outside", "[General]\nColorScheme=External\n");
    std::os::unix::fs::symlink(s.0.join("outside"), s.0.join("home/.config/kdeglobals")).unwrap();
    let before = fs::read(s.0.join("home/.config/caelestia/cli.json")).unwrap();
    assert!(!s.run(&["theme", "adopt"]).status.success());
    assert_eq!(
        before,
        fs::read(s.0.join("home/.config/caelestia/cli.json")).unwrap()
    );
    assert_eq!(
        fs::read_to_string(s.0.join("outside")).unwrap(),
        "[General]\nColorScheme=External\n"
    );
}
fn link(from: &std::path::Path, to: &std::path::Path) {
    fs::create_dir_all(to.parent().unwrap()).unwrap();
    if to.is_symlink() {
        fs::remove_file(to).unwrap();
    }
    std::os::unix::fs::symlink(from, to).unwrap();
}
fn generation(s: &Sandbox, n: u32) {
    use sha2::{Digest, Sha256};
    use std::os::unix::fs::PermissionsExt;
    let shell = format!("data/builds/shell-{n}");
    s.put(&format!("{shell}/shell.qml"), "//fixture\n");
    s.put(&format!("{shell}/BUILD_ID"), &format!("shell-{n}"));
    s.put(
        &format!("{shell}/BUILD.json"),
        r#"{"schema":1,"sourceProject":"Cortetsu","repositoryRevision":"test"}"#,
    );
    let helper = format!("data/helpers/builds/helpers-{n}");
    let body = format!("#!/bin/sh\nprintf '%s\\n' {n}\n");
    s.put(&format!("{helper}/cortetsu-demo"), &body);
    fs::set_permissions(
        s.0.join(&helper).join("cortetsu-demo"),
        fs::Permissions::from_mode(0o755),
    )
    .unwrap();
    s.put(&format!("{helper}/HELPERS.json"),&serde_json::json!({"schema":1,"build_id":format!("helpers-{n}"),"helpers":[{"name":"cortetsu-demo","bytes":body.len(),"sha256":format!("{:x}",Sha256::digest(body.as_bytes()))}],"launcherNames":["cortetsu-demo"]}).to_string());
    for (source, target) in [
        (&shell, "runtime/current"),
        (&helper, "data/helpers/current"),
    ] {
        let old = fs::canonicalize(s.0.join(target)).ok();
        if let Some(old) = old {
            link(&old, &s.0.join(target.replace("current", "previous")));
        }
        link(&s.0.join(source), &s.0.join(target));
    }
    link(
        &s.0.join("data/helpers/current/cortetsu-demo"),
        &s.0.join("home/.local/bin/cortetsu-demo"),
    );
    s.put("repo/source/config", &format!("generation {n}\n"));
    ok(s.run(&["dotfiles", "apply", "--repo", &s.repo()]));
    ok(s.run(&["system", "promote", "--repo", &s.repo()]));
}
#[test]
fn schema2_promotes_rolls_back_all_components_and_checks_launchers() {
    let s = Sandbox::new();
    fixture(&s);
    generation(&s, 1);
    generation(&s, 2);
    ok(s.run(&["system", "verify"]));
    ok(s.run(&["system", "rollback"]));
    assert_eq!(
        fs::canonicalize(s.0.join("runtime/current")).unwrap(),
        s.0.join("data/builds/shell-1")
    );
    assert_eq!(
        fs::canonicalize(s.0.join("data/helpers/current")).unwrap(),
        s.0.join("data/helpers/builds/helpers-1")
    );
    assert_eq!(
        fs::read_to_string(s.0.join("home/.config/demo")).unwrap(),
        "generation 1\n"
    );
    fs::remove_file(s.0.join("home/.local/bin/cortetsu-demo")).unwrap();
    s.put("home/.local/bin/cortetsu-demo", "replaced\n");
    assert!(!s.run(&["system", "verify"]).status.success());
}
#[test]
fn gc_preserves_helper_references_and_requires_current_plan() {
    let s = Sandbox::new();
    fixture(&s);
    generation(&s, 1);
    generation(&s, 2);
    generation(&s, 3);
    let plan = ok(s.run(&["generation_gc", "--keep", "0", "--repo", &s.repo()]));
    assert!(plan.contains("HELPERS:"));
    assert!(plan.contains("DELETE helpers-1"));
    let id = plan
        .lines()
        .find_map(|l| l.strip_prefix("PLAN_ID "))
        .unwrap();
    assert!(
        !s.run(&[
            "generation_gc",
            "--apply",
            "--keep",
            "0",
            "--plan-id",
            "stale",
            "--repo",
            &s.repo()
        ])
        .status
        .success()
    );
    assert!(s.0.join("data/helpers/builds/helpers-1").exists());
    ok(s.run(&[
        "generation_gc",
        "--apply",
        "--archive",
        "--keep",
        "0",
        "--plan-id",
        id,
        "--repo",
        &s.repo(),
    ]));
    assert!(!s.0.join("data/helpers/builds/helpers-1").exists());
    assert!(s.0.join("data/helpers/builds/helpers-2").exists());
    assert!(s.0.join("data/helpers/builds/helpers-3").exists());
    ok(s.run(&["system", "verify"]));
}
#[test]
fn build_metadata_and_status_are_native() {
    let s = Sandbox::new();
    let path = s.0.join("BUILD.json");
    ok(s.run(&[
        "build-metadata",
        path.to_str().unwrap(),
        "sample-id",
        "abcdef",
    ]));
    let v: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(v["schema"], 1);
    assert_eq!(v["sourceProject"], "Cortetsu");
    assert_eq!(v["repositoryRevision"], "abcdef");
    assert_eq!(
        ok(s.run(&["metadata", path.to_str().unwrap(), "buildId"])).trim(),
        "sample-id"
    );
}
fn locked(s: &Sandbox, token: Option<&str>, args: &[&str]) -> Output {
    fs::create_dir_all(s.0.join("data")).unwrap();
    let mut cmd = Command::new("flock");
    cmd.arg("-n")
        .arg(s.0.join("data/install.lock"))
        .arg(env!("CARGO_BIN_EXE_cortetsu-platform"))
        .args(args)
        .env("HOME", s.0.join("home"))
        .env("XDG_CONFIG_HOME", s.0.join("home/.config"))
        .env("XDG_DATA_HOME", s.0.join("home/.local/share"))
        .env("CORTETSU_DATA_ROOT", s.0.join("data"))
        .env("CORTETSU_RUNTIME_ROOT", s.0.join("runtime"))
        .current_dir(&s.0);
    if let Some(token) = token {
        cmd.env("CORTETSU_INSTALL_TRANSACTION", token);
    }
    cmd.output().unwrap()
}
#[test]
fn interrupted_install_restores_all_pointers_and_user_files() {
    let s = Sandbox::new();
    fixture(&s);
    generation(&s, 1);
    let original = fs::canonicalize(s.0.join("data/system/current")).unwrap();
    let helpers = s.0.join("data/helpers/builds/helpers-1");
    let shell = s.0.join("data/builds/shell-1");
    let repo = s.repo();
    let args = [
        "install-transaction",
        "begin",
        "--repo",
        &repo,
        "--helpers",
        helpers.to_str().unwrap(),
        "--shell",
        shell.to_str().unwrap(),
    ];
    let token = ok(locked(&s, None, &args)).trim().to_owned();
    assert!(
        !s.run(&["dotfiles", "apply", "--repo", &s.repo()])
            .status
            .success(),
        "unrelated mutation must not race install"
    );
    ok(locked(
        &s,
        Some(&token),
        &["install-transaction", "activate"],
    ));
    fs::remove_file(s.0.join("home/.config/demo")).unwrap();
    s.put("home/.config/demo", "partial install");
    fs::remove_file(s.0.join("data/system/current")).unwrap();
    ok(locked(&s, None, &["install-transaction", "recover"]));
    assert_eq!(
        fs::canonicalize(s.0.join("data/system/current")).unwrap(),
        original
    );
    assert_eq!(
        fs::read_to_string(s.0.join("home/.config/demo")).unwrap(),
        "generation 1\n"
    );
    ok(s.run(&["system", "verify"]));
    ok(locked(&s, None, &["install-transaction", "recover"]));
}
#[test]
fn install_journal_refuses_corrupt_backups_before_mutating() {
    let s = Sandbox::new();
    fixture(&s);
    generation(&s, 1);
    let h = s.0.join("data/helpers/builds/helpers-1");
    let shell = s.0.join("data/builds/shell-1");
    let token = ok(locked(
        &s,
        None,
        &[
            "install-transaction",
            "begin",
            "--repo",
            &s.repo(),
            "--helpers",
            h.to_str().unwrap(),
            "--shell",
            shell.to_str().unwrap(),
        ],
    ));
    let journal: Value =
        serde_json::from_slice(&fs::read(s.0.join("data/install-journal.json")).unwrap()).unwrap();
    let snapshot = journal["snapshots"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["kind"] == "symlink")
        .unwrap();
    let before = fs::read_link(snapshot["target"].as_str().unwrap()).unwrap();
    let p = std::path::Path::new(snapshot["backup"].as_str().unwrap());
    fs::remove_file(p).unwrap();
    std::os::unix::fs::symlink("/tampered", p).unwrap();
    assert!(
        !locked(&s, Some(token.trim()), &["install-transaction", "recover"])
            .status
            .success()
    );
    assert_eq!(
        fs::read_link(snapshot["target"].as_str().unwrap()).unwrap(),
        before
    );
}
#[test]
fn legacy_schema1_upgrade_creates_immutable_helper_aware_rollback_checkpoint() {
    use std::os::unix::fs::PermissionsExt;
    let s = Sandbox::new();
    fixture(&s);
    generation(&s, 1);
    let original = fs::canonicalize(s.0.join("data/system/current")).unwrap();
    let mut manifest: Value =
        serde_json::from_slice(&fs::read(original.join("SYSTEM.json")).unwrap()).unwrap();
    manifest["schema"] = serde_json::json!(1);
    for k in [
        "helpersGeneration",
        "helpersManifestSha256",
        "managedLaunchers",
    ] {
        manifest.as_object_mut().unwrap().remove(k);
    }
    let original_bytes = serde_json::to_vec_pretty(&manifest).unwrap();
    fs::write(original.join("SYSTEM.json"), &original_bytes).unwrap();
    fs::remove_file(s.0.join("data/helpers/current")).unwrap();
    fs::remove_file(s.0.join("home/.local/bin/cortetsu-demo")).unwrap();
    s.put("home/.local/bin/cortetsu-demo", "#!/bin/sh\necho legacy\n");
    fs::set_permissions(
        s.0.join("home/.local/bin/cortetsu-demo"),
        fs::Permissions::from_mode(0o755),
    )
    .unwrap();
    let helper = s.0.join("data/helpers/builds/helpers-1");
    let shell = s.0.join("data/builds/shell-1");
    let token = ok(locked(
        &s,
        None,
        &[
            "install-transaction",
            "begin",
            "--repo",
            &s.repo(),
            "--helpers",
            helper.to_str().unwrap(),
            "--shell",
            shell.to_str().unwrap(),
        ],
    ))
    .trim()
    .to_owned();
    ok(locked(
        &s,
        Some(&token),
        &["install-transaction", "activate"],
    ));
    ok(locked(
        &s,
        Some(&token),
        &["dotfiles", "apply", "--repo", &s.repo()],
    ));
    ok(locked(
        &s,
        Some(&token),
        &["system", "promote", "--repo", &s.repo()],
    ));
    ok(locked(&s, Some(&token), &["install-transaction", "commit"]));
    assert_eq!(
        fs::read(original.join("SYSTEM.json")).unwrap(),
        original_bytes
    );
    ok(s.run(&["system", "rollback"]));
    assert_eq!(
        fs::read_to_string(s.0.join("home/.local/bin/cortetsu-demo")).unwrap(),
        "#!/bin/sh\necho legacy\n"
    );
    ok(s.run(&["system", "verify"]));
}
#[test]
fn repository_runtime_can_be_composed_sealed_and_detects_drift() {
    let s = Sandbox::new();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let runtime = s.0.join("data/builds/staged");
    fs::create_dir_all(&runtime).unwrap();
    let cp = |from: &std::path::Path, to: &std::path::Path| {
        fs::create_dir_all(to).unwrap();
        assert!(
            Command::new("cp")
                .arg("-a")
                .arg(from.join("."))
                .arg(to)
                .status()
                .unwrap()
                .success()
        );
    };
    cp(&root.join("cortetsu/base"), &runtime);
    for dir in [
        "modules",
        "components",
        "utils",
        "services",
        "theme",
        "data",
    ] {
        cp(&root.join("cortetsu").join(dir), &runtime.join(dir));
    }
    fs::copy(root.join("cortetsu/shell.qml"), runtime.join("shell.qml")).unwrap();
    fs::create_dir_all(runtime.join("base/modules/bar")).unwrap();
    fs::copy(
        root.join("cortetsu/base/modules/bar/SystemTrayIdentity.js"),
        runtime.join("base/modules/bar/SystemTrayIdentity.js"),
    )
    .unwrap();
    for (src, dest) in [
        ("runtime-provenance.json", "provenance.json"),
        ("composition.json", "composition.json"),
        ("wall-utility.json", "wall-utility.json"),
    ] {
        fs::copy(
            root.join("cortetsu/contracts").join(src),
            runtime.join(dest),
        )
        .unwrap();
    }
    ok(s.run(&["compose-panels", runtime.to_str().unwrap()]));
    fs::write(runtime.join("BUILD_ID"), "staged").unwrap();
    ok(s.run(&[
        "build-metadata",
        runtime.join("BUILD.json").to_str().unwrap(),
        "staged",
        "test",
    ]));
    ok(s.run(&["seal-runtime", runtime.to_str().unwrap()]));
    ok(s.run(&["validate-runtime", runtime.to_str().unwrap()]));
    fs::write(runtime.join("components/CortetsuButton.qml"), "tamper").unwrap();
    assert!(
        !s.run(&["validate-runtime", runtime.to_str().unwrap()])
            .status
            .success()
    );
}
#[test]
fn interrupted_install_refuses_redirected_parent_before_recovery() {
    let s = Sandbox::new();
    fixture(&s);
    generation(&s, 1);
    let helper = s.0.join("data/helpers/builds/helpers-1");
    let shell = s.0.join("data/builds/shell-1");
    ok(locked(
        &s,
        None,
        &[
            "install-transaction",
            "begin",
            "--repo",
            &s.repo(),
            "--helpers",
            helper.to_str().unwrap(),
            "--shell",
            shell.to_str().unwrap(),
        ],
    ));
    fs::rename(s.0.join("home/.config"), s.0.join("home/config-before")).unwrap();
    s.put("outside/demo", "untouched");
    std::os::unix::fs::symlink(s.0.join("outside"), s.0.join("home/.config")).unwrap();
    assert!(
        !locked(&s, None, &["install-transaction", "recover"])
            .status
            .success()
    );
    assert_eq!(
        fs::read_to_string(s.0.join("outside/demo")).unwrap(),
        "untouched"
    );
}
#[test]
fn standalone_dotfiles_apply_has_a_recoverable_durable_journal() {
    let s = Sandbox::new();
    fixture(&s);
    ok(s.run(&["dotfiles", "apply", "--repo", &s.repo()]));
    let path = s.0.join("data/dotfiles/apply-journal.json");
    let mut journal: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    journal["phase"] = serde_json::json!("PREPARED");
    fs::write(&path, journal.to_string()).unwrap();
    ok(s.run(&["dotfiles", "recover", "--repo", &s.repo()]));
    assert_eq!(
        fs::read_to_string(s.0.join("home/.config/demo")).unwrap(),
        "unmanaged\n"
    );
    assert!(!s.0.join("data/dotfiles/current").is_symlink());
    ok(s.run(&["dotfiles", "recover", "--repo", &s.repo()]));
}
#[test]
fn standalone_system_promotion_recovers_its_prepared_target() {
    let s = Sandbox::new();
    fixture(&s);
    generation(&s, 1);
    let old = fs::canonicalize(s.0.join("data/system/current")).unwrap();
    generation(&s, 2);
    let target = fs::canonicalize(s.0.join("data/system/current")).unwrap();
    let path = s.0.join("data/system/promotion-journal.json");
    let mut v: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    v["phase"] = serde_json::json!("PREPARED");
    v["target"] = serde_json::json!(target);
    v["beforeCurrent"] = serde_json::json!(old);
    fs::write(path, v.to_string()).unwrap();
    link(&old, &s.0.join("data/system/current"));
    ok(s.run(&["system", "recover"]));
    assert_eq!(
        fs::canonicalize(s.0.join("data/system/current")).unwrap(),
        target
    );
    ok(s.run(&["system", "verify"]));
}
