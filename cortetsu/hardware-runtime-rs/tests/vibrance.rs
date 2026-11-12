// Per-output saturation through the generated Hyprland screen shader.
mod common;
use common::*;
use serde_json::{Value, json};
use std::{fs, path::Path, process::Command};
use tempfile::TempDir;

fn fake_vibrance_hyprctl(t: &TempDir) {
    // Remembers the shader path set through eval, as Hyprland does.
    exe(
        &t.path().join("bin/hyprctl"),
        "#!/bin/sh\nstate=\"$HOME/shader-path\"\ncase \"$1\" in\n-j) echo '[{\"id\":0,\"name\":\"eDP-1\"},{\"id\":3,\"name\":\"DP-1\"}]';;\ngetoption) printf 'str: %s\\nset: true\\n' \"$(cat \"$state\" 2>/dev/null)\";;\neval) printf '%s' \"$2\" | sed -n 's/.*screen_shader=\"\\([^\"]*\\)\".*/\\1/p' > \"$state\"; echo \"$2\" >> \"$HOME/evals\"; echo ok;;\n*) exit 77;;\nesac\n",
    );
}
#[test]
fn vibrance_shader_keeps_one_strength_per_output_and_compiles() {
    let t = setup();
    fake_vibrance_hyprctl(&t);
    let set = output(run(&t, &["cortetsu-display-vibrance", "set", "DP-1", "40"]));
    assert_eq!(set["value"], 40);
    let shader = fs::read_to_string(set["shader"].as_str().unwrap()).unwrap();
    assert!(
        shader.contains("if (wl_output == 3) return 0.40;"),
        "{shader}"
    );
    assert!(
        shader.contains("if (wl_output == 0) return 0.16;"),
        "eDP-1 keeps the old default"
    );
    let stable = t.path().join(".local/state/cortetsu/screen-shader.glsl");
    assert_eq!(
        fs::read_to_string(&stable).unwrap(),
        shader,
        "a Hyprland reload reads the same shader"
    );
    // The fixed strength of the previous static shader stays the default.
    let status = output(run(&t, &["cortetsu-display-vibrance", "status"]));
    assert_eq!(status["active"], true);
    assert_eq!(
        status["outputs"],
        json!([{"id":0,"value":16,"name":"eDP-1"},{"id":3,"value":40,"name":"DP-1"}])
    );
    if let Ok(glslang) = which_glslang() {
        let checked = Command::new(glslang)
            .args(["-S", "frag"])
            .arg(&stable)
            .output()
            .unwrap();
        assert!(
            checked.status.success(),
            "{}",
            String::from_utf8_lossy(&checked.stdout)
        );
    }
    // Same content: no second eval, and only the live hashed file remains.
    output(run(&t, &["cortetsu-display-vibrance", "apply"]));
    assert_eq!(
        fs::read_to_string(t.path().join("evals"))
            .unwrap()
            .lines()
            .count(),
        1
    );
    let hashed = fs::read_dir(t.path().join(".local/state/cortetsu"))
        .unwrap()
        .filter(|e| {
            e.as_ref()
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with("screen-shader-")
        })
        .count();
    assert_eq!(hashed, 1);
}
fn which_glslang() -> Result<String, ()> {
    ["/usr/bin/glslangValidator"]
        .iter()
        .find(|p| Path::new(p).exists())
        .map(|p| p.to_string())
        .ok_or(())
}
#[test]
fn vibrance_rejects_bad_values_and_keeps_the_profile_when_hyprland_refuses() {
    let t = setup();
    fake_vibrance_hyprctl(&t);
    let bad = run(&t, &["cortetsu-display-vibrance", "set", "DP-1", "101"]);
    assert!(!bad.status.success());
    let unknown = run(&t, &["cortetsu-display-vibrance", "set", "HDMI-A-1", "10"]);
    assert!(!unknown.status.success());
    output(run(&t, &["cortetsu-display-vibrance", "set", "DP-1", "30"]));
    let stable = t.path().join(".local/state/cortetsu/screen-shader.glsl");
    let accepted = fs::read(&stable).unwrap();
    exe(
        &t.path().join("bin/hyprctl"),
        "#!/bin/sh\ncase \"$1\" in -j) echo '[{\"id\":3,\"name\":\"DP-1\"}]';; getoption) echo 'str: /elsewhere';; *) echo 'lua error' ; exit 1;; esac\n",
    );
    let refused = run(&t, &["cortetsu-display-vibrance", "set", "DP-1", "80"]);
    assert!(!refused.status.success());
    let profile: Value = serde_json::from_slice(
        &fs::read(t.path().join(".local/state/cortetsu/vibrance.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(
        profile["profile"]["DP-1"], 30,
        "a refused change is not saved"
    );
    assert_eq!(
        fs::read(&stable).unwrap(),
        accepted,
        "the next Hyprland reload reads the shader it last accepted"
    );
    // Monitors that cannot be read are not "no monitors": apply must not
    // write a shader that puts every output back on the default.
    exe(
        &t.path().join("bin/hyprctl"),
        "#!/bin/sh\ncase \"$1\" in -j) exit 1;; getoption) echo 'str: /elsewhere';; *) echo ok;; esac\n",
    );
    let unread = run(&t, &["cortetsu-display-vibrance", "apply"]);
    assert!(!unread.status.success());
    assert_eq!(fs::read(&stable).unwrap(), accepted);
}

