use cortetsu_rescue::{Roots, hash_path, helper_bundle};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
fn sha(bytes: impl AsRef<[u8]>) -> String {
    format!("{:x}", Sha256::digest(bytes.as_ref()))
}
struct Fixture {
    home: PathBuf,
    roots: Roots,
    shell: PathBuf,
    system: PathBuf,
    helpers: PathBuf,
}
impl Fixture {
    fn new() -> Self {
        let home = std::env::temp_dir().join(format!(
            "cortetsu-native-rescue-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let roots = Roots {
            data: home.join("data"),
            runtime: home.join("runtime"),
        };
        let shell = roots.data.join("builds/shell-native");
        let dots = roots.data.join("dotfiles/builds/dots-native");
        let system = roots.data.join("system/builds/system-native");
        for p in [
            &shell,
            &dots.join("home"),
            &system,
            &home.join("source"),
            &home.join(".local/bin"),
        ] {
            fs::create_dir_all(p).unwrap();
        }
        fs::write(shell.join("shell.qml"), "// shell\n").unwrap();
        fs::write(shell.join("BUILD_ID"), "shell-native").unwrap();
        let files = json!({"schema":1,"files":{"shell.qml":sha("// shell\n"),"BUILD_ID":sha("shell-native")}});
        fs::write(shell.join("FILES.json"), files.to_string()).unwrap();
        let build = json!({"schema":1,"buildId":"shell-native","sourceProject":"Cortetsu","repositoryRevision":"fixture","runtimeManifestSha256":sha(files.to_string())});
        fs::write(shell.join("BUILD.json"), build.to_string()).unwrap();
        fs::write(dots.join("home/demo"), "dotfile").unwrap();
        let dotmanifest = json!({"schema":1,"entries":[{"target":"demo","sha256":hash_path(&dots.join("home/demo")).unwrap()}]});
        fs::write(dots.join("MANIFEST.json"), dotmanifest.to_string()).unwrap();
        fs::write(
            home.join("source/cortetsu-demo"),
            "#!/bin/sh\necho fixture\n",
        )
        .unwrap();
        let helpers = PathBuf::from(
            helper_bundle::stage(&roots, &home.join("source"))
                .unwrap()
                .directory,
        );
        let manifest = json!({"schema":2,"nativeRuntime":true,"shellGeneration":shell,"dotfilesGeneration":dots,"helpersGeneration":helpers,"helpersManifestSha256":sha(fs::read(helpers.join("HELPERS.json")).unwrap()),"shellManifestSha256":sha(build.to_string()),"dotfilesManifestSha256":sha(dotmanifest.to_string()),"managedLaunchers":["cortetsu-demo"]});
        fs::write(system.join("SYSTEM.json"), manifest.to_string()).unwrap();
        for (from, to) in [
            (&shell, roots.runtime.join("current")),
            (&dots, roots.data.join("dotfiles/current")),
            (&system, roots.data.join("system/current")),
            (&helpers, roots.data.join("helpers/current")),
            (
                &roots.data.join("helpers/current/cortetsu-demo"),
                home.join(".local/bin/cortetsu-demo"),
            ),
        ] {
            fs::create_dir_all(to.parent().unwrap()).unwrap();
            std::os::unix::fs::symlink(from, to).unwrap();
        }
        Self {
            home,
            roots,
            shell,
            system,
            helpers,
        }
    }
    fn verify(&self) -> Output {
        Command::new(env!("CARGO_BIN_EXE_cortetsu-rescue"))
            .arg("verify")
            .env("HOME", &self.home)
            .env("CORTETSU_DATA_ROOT", &self.roots.data)
            .env("CORTETSU_RUNTIME_ROOT", &self.roots.runtime)
            .output()
            .unwrap()
    }
    fn mutate_system(&self, f: impl FnOnce(&mut Value)) {
        let p = self.system.join("SYSTEM.json");
        let mut v: Value = serde_json::from_slice(&fs::read(&p).unwrap()).unwrap();
        f(&mut v);
        fs::write(p, v.to_string()).unwrap();
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.home);
    }
}
#[test]
fn native_generation_verifies_and_detects_shell_file_drift() {
    let f = Fixture::new();
    let out = f.verify();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    fs::write(f.shell.join("shell.qml"), "modified").unwrap();
    assert!(!f.verify().status.success());
}
#[test]
fn helper_manifest_digest_is_verified_even_when_bundle_entries_are_valid() {
    let f = Fixture::new();
    let p = f.helpers.join("HELPERS.json");
    let mut bytes = fs::read(&p).unwrap();
    bytes.push(b'\n');
    fs::write(p, bytes).unwrap();
    assert!(!f.verify().status.success());
}
#[test]
fn managed_launcher_replacement_is_detected() {
    let f = Fixture::new();
    let p = f.home.join(".local/bin/cortetsu-demo");
    fs::remove_file(&p).unwrap();
    fs::write(p, "stale launcher").unwrap();
    assert!(!f.verify().status.success());
}
#[test]
fn native_marker_cannot_downgrade_to_unsealed_or_forged_legacy_shell() {
    let f = Fixture::new();
    let p = f.shell.join("BUILD.json");
    let mut build: Value = serde_json::from_slice(&fs::read(&p).unwrap()).unwrap();
    build
        .as_object_mut()
        .unwrap()
        .remove("runtimeManifestSha256");
    fs::write(&p, build.to_string()).unwrap();
    f.mutate_system(|v| {
        v["shellManifestSha256"] = json!(sha(build.to_string()));
    });
    assert!(!f.verify().status.success());
    f.mutate_system(|v| {
        v["legacySourceSystem"] = json!(Path::new("/outside/forged"));
    });
    assert!(!f.verify().status.success());
}
