use crate::{dotfiles, migrations, util::*};
use serde_json::{Value, json};
use std::process::{Command, Stdio};
fn check(
    name: impl Into<String>,
    status: &str,
    detail: impl Into<String>,
    required: bool,
) -> Value {
    json!({"name":name.into(),"status":status,"detail":detail.into(),"required":required})
}
pub fn run(a: &Args) -> Result<i32> {
    a.check(&["repo", "profile", "json"])?;
    let repo = a.repo()?;
    let (profile, _) = dotfiles::manifest(&repo, a.get("profile"))?;
    let packages = toml_json(&repo.join("packages/arch.toml"))?;
    let mut checks = Vec::new();
    for group in strings(&profile["package_groups"]) {
        let g = &packages["group"][&group];
        if !g.is_object() {
            checks.push(check(
                format!("package-group:{group}"),
                "error",
                "grupo inexistente",
                true,
            ));
            continue;
        }
        let required = g["required"] == true;
        for command in strings(&g["commands"]) {
            let found = which(&command);
            checks.push(check(
                format!("cmd:{command}"),
                if found.is_some() {
                    "ok"
                } else if required {
                    "error"
                } else {
                    "warn"
                },
                found.map_or("missing".into(), |p| p.display().to_string()),
                required,
            ));
        }
        if which("pacman").is_some() {
            for package in strings(&g["packages"]) {
                let installed = Command::new("pacman")
                    .args(["-Q", &package])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status()?
                    .success();
                checks.push(check(
                    format!("pkg:{package}"),
                    if installed {
                        "ok"
                    } else if required {
                        "error"
                    } else {
                        "warn"
                    },
                    if installed { "installed" } else { "missing" },
                    required,
                ));
            }
        }
    }
    let runtime = runtime_root()?.join("current/shell.qml");
    checks.push(check(
        "runtime",
        if runtime.is_file() { "ok" } else { "error" },
        runtime.display().to_string(),
        true,
    ));
    match dotfiles::verify(&repo, a.get("profile")) {
        Ok(_) => checks.push(check(
            "dotfiles",
            "ok",
            "immutable generation verified",
            true,
        )),
        Err(e) => checks.push(check("dotfiles", "error", e.to_string(), true)),
    }
    if which("systemctl").is_some() {
        let status = Command::new("systemctl")
            .args(["--user", "show-environment"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()?
            .success();
        checks.push(check(
            "systemd-user",
            if status { "ok" } else { "warn" },
            if status {
                "available"
            } else {
                "user manager unavailable"
            },
            false,
        ));
        let enabled = Command::new("systemctl")
            .args(["--user", "is-enabled", "cortetsu-shell.service"])
            .stderr(Stdio::null())
            .output()?;
        checks.push(check(
            "shell-supervision",
            if enabled.status.success() {
                "ok"
            } else {
                "warn"
            },
            String::from_utf8_lossy(&enabled.stdout).trim().to_owned(),
            false,
        ));
    }
    let service = config_home()?.join("systemd/user/cortetsu-shell.service");
    checks.push(check(
        "shell-service",
        if service.exists() { "ok" } else { "warn" },
        service.display().to_string(),
        false,
    ));
    let legacy = migrations::lifecycle_scan(&home()?);
    checks.push(if legacy.is_empty() {
        check(
            "shell-lifecycle",
            "ok",
            "systemd --user is the only process owner",
            true,
        )
    } else {
        check(
            "shell-lifecycle",
            "error",
            format!(
                "legacy direct launch/kill references: {}",
                legacy
                    .iter()
                    .filter_map(|x| x["path"].as_str())
                    .collect::<Vec<_>>()
                    .join("; ")
            ),
            true,
        )
    });
    let ui = repo.join("dotfiles/home/.config/cortetsu/ui.toml");
    checks.push(match toml_json(&ui) {
        Ok(v) if v["schema"] == 1 && v["palette"].is_object() => check(
            "theme-ownership",
            "ok",
            "Cortetsu owns terminal/Hyprland/GTK/Qt theme surfaces",
            true,
        ),
        _ => check(
            "theme-ownership",
            "error",
            "Cortetsu ui.toml has an invalid schema",
            true,
        ),
    });
    let secret = which("secret-tool");
    checks.push(check(
        "secret-service",
        if secret.is_some() { "ok" } else { "warn" },
        secret.map_or("secret-tool missing".into(), |p| p.display().to_string()),
        false,
    ));
    if let Ok(o) = Command::new("git")
        .arg("-C")
        .arg(&repo)
        .args(["status", "--porcelain"])
        .output()
        && o.status.success()
    {
        checks.push(check(
            "git-worktree",
            if o.stdout.is_empty() { "ok" } else { "warn" },
            if o.stdout.is_empty() {
                "clean"
            } else {
                "dirty"
            },
            false,
        ));
    }
    let failed = checks
        .iter()
        .any(|c| c["status"] == "error" && c["required"] == true);
    if a.has("json") {
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({"schema":1,"checks":checks}))?
        );
    } else {
        println!("Cortetsu doctor");
        for c in checks {
            println!(
                "{:4} {}: {}",
                match c["status"].as_str() {
                    Some("ok") => "PASS",
                    Some("warn") => "WARN",
                    _ => "FAIL",
                },
                c["name"].as_str().unwrap_or_default(),
                c["detail"].as_str().unwrap_or_default()
            );
        }
    }
    Ok(if failed { 1 } else { 0 })
}
