//! Whole-install undo journal. The Bash installer holds install.lock throughout
//! these operations. Backups are durable before the first active pointer moves.
use crate::{dotfiles, system, util::*};
use fs2::FileExt;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File, OpenOptions},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};
fn journal_path() -> Result<PathBuf> {
    Ok(data_root()?.join("install-journal.json"))
}
fn pending(v: &Value) -> bool {
    matches!(
        v["phase"].as_str(),
        Some("PREPARED" | "ACTIVE" | "RECOVERING")
    )
}
pub fn check_mutation() -> Result<()> {
    let path = journal_path()?;
    if !path.exists() {
        return Ok(());
    }
    let v = load()?;
    if pending(&v)
        && std::env::var("CORTETSU_INSTALL_TRANSACTION")
            .ok()
            .as_deref()
            != v["id"].as_str()
    {
        return fail(
            "installation transaction is pending; use cortetsu recover under the installation lock",
        );
    }
    Ok(())
}
fn require_install_lock() -> Result<()> {
    let p = data_root()?.join("install.lock");
    if p.is_symlink() {
        return fail("unsafe install lock");
    }
    let f = OpenOptions::new().read(true).write(true).open(&p)?;
    match f.try_lock_exclusive() {
        Ok(()) => {
            FileExt::unlock(&f)?;
            fail("install-transaction requires the caller to hold install.lock with flock")
        }
        Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => Ok(()),
        Err(e) => Err(e.into()),
    }
}
fn fingerprint(path: &Path) -> Result<String> {
    let m = fs::symlink_metadata(path)?;
    let mut h = Sha256::new();
    if m.file_type().is_symlink() {
        h.update(b"link\0");
        h.update(fs::read_link(path)?.as_os_str().as_encoded_bytes());
    } else if m.is_file() {
        h.update(b"file\0");
        h.update(m.permissions().mode().to_le_bytes());
        h.update(fs::read(path)?);
    } else {
        return fail("install snapshots support files and symlinks only");
    }
    Ok(format!("{:x}", h.finalize()))
}
pub(crate) fn snapshot(target: &Path, backup: &Path) -> Result<Value> {
    let mut anchor = target.parent().ok_or("snapshot parent")?;
    while !anchor.exists() && !anchor.is_symlink() {
        anchor = anchor.parent().ok_or("snapshot anchor")?;
    }
    if !anchor.is_dir() {
        return fail("snapshot parent is not a directory");
    }
    let resolved = fs::canonicalize(anchor)?;
    let mut result = match fs::symlink_metadata(target) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            Ok::<Value, Box<dyn std::error::Error>>(json!({"target":target,"kind":"absent"}))
        }
        Err(e) => Err(e.into()),
        Ok(m) => {
            if !m.is_file() && !m.file_type().is_symlink() {
                return fail(format!(
                    "refusing to snapshot non-file install target {}",
                    target.display()
                ));
            }
            copy_path(target, backup)?;
            if m.is_file() {
                File::open(backup)?.sync_all()?;
            }
            File::open(backup.parent().ok_or("backup parent")?)?.sync_all()?;
            Ok(
                json!({"target":target,"kind":if m.file_type().is_symlink(){"symlink"}else{"file"},"backup":backup,"sha256":fingerprint(backup)?}),
            )
        }
    }?;
    result["parentAnchor"] = json!(anchor);
    result["parentResolved"] = json!(resolved);
    Ok(result)
}
fn helper_names(path: &Path) -> Result<Vec<String>> {
    let r = roots()?;
    system::managed(path, &r.data.join("helpers/builds"))?;
    let id = path
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or("helper id")?;
    cortetsu_rescue::helper_bundle::verify(&r, id)?;
    json(&path.join("HELPERS.json"))?["helpers"]
        .as_array()
        .ok_or("helpers list")?
        .iter()
        .map(|x| {
            x["name"]
                .as_str()
                .map(str::to_owned)
                .ok_or_else(|| "helper name".into())
        })
        .collect()
}
fn valid_name(name: &str) -> bool {
    (name == "cortetsu" || name.starts_with("cortetsu-"))
        && name.len() <= 120
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}
fn legacy_checkpoint(bundle: &Path) -> Result<Option<(PathBuf, PathBuf, Vec<String>)>> {
    let r = roots()?;
    let Some(old) = resolve_link(&r.data.join("system/current")) else {
        return Ok(None);
    };
    let mut manifest = system::validate_system(&old)?;
    if manifest["schema"] == 2 {
        system::verify()?;
        return Ok(None);
    }
    system::verify()?;
    let bin = home()?.join(".local/bin");
    let mut sources = BTreeMap::<String, PathBuf>::new();
    if bin.is_dir() {
        for entry in fs::read_dir(&bin)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if valid_name(&name) && entry.path().is_file() {
                sources.insert(name, fs::canonicalize(entry.path())?);
            }
        }
    }
    if sources.is_empty() {
        return fail(
            "schema1 upgrade needs the installed legacy helpers to make a complete rollback checkpoint",
        );
    }
    // Management commands stay independent of the updated source checkout.
    for name in ["cortetsu", "cortetsu-platform", "cortetsu-rescue"] {
        if bundle.join(name).is_file() {
            sources.insert(name.into(), bundle.join(name));
        }
    }
    if sources.len() > 128 {
        return fail("legacy helpers exceed bundle limit");
    }
    let id = format!("helpers-legacy-{}", unique());
    let final_dir = r.data.join("helpers/builds").join(&id);
    let stage = r.data.join("helpers/builds").join(format!(".stage-{id}"));
    fs::create_dir_all(&stage)?;
    let operation = (|| {
        let mut helpers = Vec::new();
        let mut total = 0u64;
        for (name, path) in &sources {
            let m = fs::metadata(path)?;
            total = total.checked_add(m.len()).ok_or("legacy size overflow")?;
            if !m.is_file() || m.len() > 32 * 1024 * 1024 || total > 128 * 1024 * 1024 {
                return fail("legacy helper is unsafe or oversized");
            }
            let bytes = fs::read(path)?;
            atomic_write(&stage.join(name), &bytes, 0o755)?;
            helpers.push(json!({"name":name,"bytes":bytes.len(),"sha256":format!("{:x}",Sha256::digest(&bytes))}));
        }
        write_json(
            &stage.join("HELPERS.json"),
            &json!({"schema":1,"build_id":id,"helpers":helpers,"legacyRollbackOnly":true}),
        )?;
        fs::rename(&stage, &final_dir)?;
        File::open(final_dir.parent().ok_or("helper parent")?)?.sync_all()?;
        helper_names(&final_dir)?;
        let checkpoint_id = format!("legacy-checkpoint-{}", unique());
        let checkpoint = r.data.join("system/builds").join(&checkpoint_id);
        fs::create_dir_all(&checkpoint)?;
        let names = sources.keys().cloned().collect::<Vec<_>>();
        manifest["schema"] = json!(2);
        manifest["buildId"] = json!(checkpoint_id);
        manifest["builtAt"] = json!(timestamp());
        manifest["legacySourceSystem"] = json!(old);
        manifest["helpersGeneration"] = json!(final_dir);
        manifest["helpersManifestSha256"] = json!(format!(
            "{:x}",
            Sha256::digest(fs::read(final_dir.join("HELPERS.json"))?)
        ));
        manifest["managedLaunchers"] = json!(names);
        write_json(&checkpoint.join("SYSTEM.json"), &manifest)?;
        system::validate_system(&checkpoint)?;
        Ok(Some((checkpoint, final_dir, names)))
    })();
    if operation.is_err() {
        let _ = fs::remove_dir_all(stage);
    }
    operation
}
fn begin(a: &Args) -> Result<()> {
    let path = journal_path()?;
    if path.exists() && pending(&load()?) {
        return fail("recover pending install before beginning another");
    }
    let r = roots()?;
    let h = home()?;
    let cfg = config_home()?;
    let repo = fs::canonicalize(a.repo()?)?;
    let bundle = PathBuf::from(a.get("helpers").ok_or("--helpers required")?);
    let shell = PathBuf::from(a.get("shell").ok_or("--shell required")?);
    let names = helper_names(&bundle)?;
    system::managed(&shell, &r.data.join("builds"))?;
    system::validate_shell(&shell)?;
    let _system = lock(&r.data.join("system/system.lock"), false)?;
    let _dotfiles = lock(&r.data.join("dotfiles/dotfiles.lock"), false)?;
    let legacy = legacy_checkpoint(&bundle)?;
    let mut launchers = names.clone();
    if let Some((_, _, old_names)) = &legacy {
        launchers.extend(old_names.clone());
    }
    launchers.sort();
    launchers.dedup();
    let mut targets = BTreeSet::new();
    for root in [
        &r.runtime,
        &r.data.join("dotfiles"),
        &r.data.join("system"),
        &r.data.join("helpers"),
    ] {
        targets.insert(root.join("current"));
        targets.insert(root.join("previous"));
    }
    targets.insert(r.runtime.join("legacy-previous"));
    targets.insert(r.data.join("repository"));
    targets.insert(r.data.join("system/promotion-journal.json"));
    targets.insert(r.data.join("dotfiles/apply-journal.json"));
    for name in &launchers {
        if !valid_name(name) {
            return fail("invalid launcher");
        };
        targets.insert(h.join(".local/bin").join(name));
    }
    for e in dotfiles::manifest(&repo, None)?.1 {
        targets.insert(h.join(e.target));
    }
    for rel in [
        "caelestia/cli.json",
        "kdeglobals",
        "hypr/hyprland/execs.lua",
        "hypr/hyprland/keybinds.lua",
        "kitty/caelestia-theme.conf",
        "caelestia/templates/kitty-cortetsu.conf",
    ] {
        targets.insert(cfg.join(rel));
    }
    targets.insert(h.join(".local/state/caelestia/theme/kitty-cortetsu.conf"));
    let id = unique();
    let backups = r.data.join("install-backups").join(&id);
    fs::create_dir_all(&backups)?;
    fs::set_permissions(&backups, fs::Permissions::from_mode(0o700))?;
    let mut snapshots = Vec::new();
    for (i, target) in targets.iter().enumerate() {
        snapshots.push(snapshot(target, &backups.join(format!("file-{i}")))?);
    }
    let mut v = json!({"schema":1,"id":id,"phase":"PREPARED","createdAt":timestamp(),"home":h,"data":r.data,"runtime":r.runtime,"config":cfg,"repo":repo,"helpers":bundle,"shell":shell,"launchers":names,"allLaunchers":launchers,"snapshots":snapshots,"backupRoot":backups});
    if let Some((checkpoint, helpers, names)) = legacy {
        v["legacyCheckpoint"] = json!(checkpoint);
        v["legacyHelpers"] = json!(helpers);
        v["legacyLaunchers"] = json!(names);
    }
    write_json(&path, &v)?;
    println!("{id}");
    Ok(())
}
fn load() -> Result<Value> {
    let path = journal_path()?;
    if path.is_symlink() || !path.is_file() {
        return fail("install journal must be a regular file");
    }
    let v = json(&path)?;
    if !matches!(
        v["phase"].as_str(),
        Some("PREPARED" | "ACTIVE" | "RECOVERING" | "RECOVERED" | "COMMITTED")
    ) {
        return fail("invalid install journal phase");
    }
    let r = roots()?;
    if v["schema"] != 1
        || v["home"].as_str() != home()?.to_str()
        || v["data"].as_str() != r.data.to_str()
        || v["runtime"].as_str() != r.runtime.to_str()
        || v["config"].as_str() != config_home()?.to_str()
    {
        return fail("install journal root mismatch");
    }
    Ok(v)
}
fn require_token(v: &Value) -> Result<()> {
    if std::env::var("CORTETSU_INSTALL_TRANSACTION")
        .ok()
        .as_deref()
        != v["id"].as_str()
    {
        return fail("install transaction token mismatch");
    };
    Ok(())
}
fn activate() -> Result<()> {
    let mut v = load()?;
    require_token(&v)?;
    if v["phase"] != "PREPARED" {
        return fail("install activation requires PREPARED journal");
    }
    let r = roots()?;
    let bundle = PathBuf::from(v["helpers"].as_str().ok_or("helpers")?);
    helper_names(&bundle)?;
    let shell = PathBuf::from(v["shell"].as_str().ok_or("shell")?);
    system::validate_shell(&shell)?;
    // Persist intent before any mutation; recovery is valid after every rename.
    v["phase"] = json!("ACTIVE");
    write_json(&journal_path()?, &v)?;
    if let Some(checkpoint) = v["legacyCheckpoint"].as_str() {
        atomic_link(Path::new(checkpoint), &r.data.join("system/current"))?;
    }
    let old_helpers = v["legacyHelpers"]
        .as_str()
        .map(PathBuf::from)
        .or_else(|| resolve_link(&r.data.join("helpers/current")));
    if let Some(old) = old_helpers {
        atomic_link(&old, &r.data.join("helpers/previous"))?;
    }
    atomic_link(&bundle, &r.data.join("helpers/current"))?;
    if let Some(old) = resolve_link(&r.runtime.join("current")) {
        if system::validate_shell(&old).is_ok() {
            atomic_link(&old, &r.runtime.join("previous"))?;
        } else if old.join("shell.qml").is_file() {
            atomic_link(&old, &r.runtime.join("legacy-previous"))?;
            remove_path(&r.runtime.join("previous"))?;
        }
    }
    atomic_link(&shell, &r.runtime.join("current"))?;
    for name in strings(&v["allLaunchers"]) {
        atomic_link(
            &r.data.join("helpers/current").join(&name),
            &home()?.join(".local/bin").join(name),
        )?;
    }
    atomic_link(
        Path::new(v["repo"].as_str().ok_or("repo")?),
        &r.data.join("repository"),
    )?;
    println!("ACTIVATED install={}", v["id"].as_str().unwrap_or_default());
    Ok(())
}
pub(crate) fn verify_snapshots_at(v: &Value, backup_root: &Path) -> Result<()> {
    let r = roots()?;
    let h = home()?;
    let cfg = config_home()?;
    let id = v["id"].as_str().ok_or("journal id")?;
    safe_relative(id)?;
    let expected = backup_root.join(id);
    if Path::new(v["backupRoot"].as_str().ok_or("backupRoot")?) != expected {
        return fail("invalid backup root");
    }
    let mut seen = BTreeSet::new();
    for item in v["snapshots"].as_array().ok_or("journal snapshots")? {
        let target = Path::new(item["target"].as_str().ok_or("snapshot target")?);
        if !target.is_absolute()
            || target
                .components()
                .any(|c| matches!(c, std::path::Component::ParentDir))
            || ![&h, &cfg, &r.data, &r.runtime]
                .iter()
                .any(|root| target.starts_with(root) && target != root.as_path())
            || !seen.insert(target)
        {
            return fail("unsafe snapshot target");
        }
        if target.is_dir() && !target.is_symlink() {
            return fail("recovery refuses an unexpected directory target");
        }
        let anchor = Path::new(
            item["parentAnchor"]
                .as_str()
                .ok_or("missing parent anchor")?,
        );
        let resolved = Path::new(
            item["parentResolved"]
                .as_str()
                .ok_or("missing parent identity")?,
        );
        if !target.starts_with(anchor) || fs::canonicalize(anchor)? != resolved {
            return fail("snapshot parent directory changed");
        }
        let mut parent = target.parent().ok_or("target parent")?;
        while parent != anchor {
            if parent.is_symlink() {
                return fail("new symlink in recovery target ancestry");
            }
            parent = parent.parent().ok_or("invalid snapshot ancestry")?;
        }
        match item["kind"].as_str() {
            Some("absent") => {}
            Some("file" | "symlink") => {
                let backup = Path::new(item["backup"].as_str().ok_or("backup path")?);
                if backup.parent() != Some(expected.as_path())
                    || fingerprint(backup)? != item["sha256"].as_str().ok_or("backup digest")?
                {
                    return fail("install backup integrity check failed");
                }
            }
            _ => return fail("invalid snapshot kind"),
        }
    }
    Ok(())
}
pub(crate) fn restore_snapshots(v: &Value) -> Result<()> {
    for item in v["snapshots"].as_array().ok_or("snapshots")?.iter().rev() {
        let target = Path::new(item["target"].as_str().ok_or("target")?);
        if target.is_dir() && !target.is_symlink() {
            return fail(format!(
                "recovery refuses unexpected directory {}",
                target.display()
            ));
        }
        match item["kind"].as_str() {
            Some("absent") => remove_path(target)?,
            Some("symlink") => atomic_link(
                &fs::read_link(item["backup"].as_str().ok_or("backup")?)?,
                target,
            )?,
            Some("file") => {
                let b = Path::new(item["backup"].as_str().ok_or("backup")?);
                atomic_write(target, fs::read(b)?, fs::metadata(b)?.permissions().mode())?
            }
            _ => return fail("snapshot kind"),
        }
    }
    Ok(())
}
fn recover() -> Result<()> {
    if !journal_path()?.exists() {
        println!("NO_PENDING_INSTALL");
        return Ok(());
    }
    let mut v = load()?;
    if !pending(&v) {
        println!("NO_PENDING_INSTALL");
        return Ok(());
    }
    verify_snapshots_at(&v, &data_root()?.join("install-backups"))?;
    v["phase"] = json!("RECOVERING");
    write_json(&journal_path()?, &v)?;
    restore_snapshots(&v)?;
    v["phase"] = json!("RECOVERED");
    v["recoveredAt"] = json!(timestamp());
    write_json(&journal_path()?, &v)?;
    println!("RECOVERED install={}", v["id"].as_str().unwrap_or_default());
    Ok(())
}
fn commit() -> Result<()> {
    let mut v = load()?;
    require_token(&v)?;
    if v["phase"] != "ACTIVE" {
        return fail("install commit requires ACTIVE journal");
    }
    let current = system::verify()?;
    let system = json(&current.join("SYSTEM.json"))?;
    if system["schema"] != 2
        || system["helpersGeneration"] != v["helpers"]
        || system["shellGeneration"] != v["shell"]
    {
        return fail("promoted system differs from prepared install");
    }
    dotfiles::verify(Path::new(v["repo"].as_str().ok_or("repo")?), None)?;
    v["phase"] = json!("COMMITTED");
    v["committedAt"] = json!(timestamp());
    v["system"] = json!(current);
    write_json(&journal_path()?, &v)?;
    println!("COMMITTED install={}", v["id"].as_str().unwrap_or_default());
    Ok(())
}
pub fn run(a: &Args) -> Result<i32> {
    a.check(&["repo", "helpers", "shell"])?;
    require_install_lock()?;
    let _lock = lock(&data_root()?.join("install-transaction.lock"), true)?;
    match a.action("status").as_str() {
        "begin" => begin(a)?,
        "activate" => activate()?,
        "commit" => commit()?,
        "recover" => recover()?,
        "status" => {
            if journal_path()?.exists() {
                println!("{}", json(&journal_path()?)?)
            } else {
                println!("NO_PENDING_INSTALL")
            }
        }
        _ => return fail("unknown install-transaction action"),
    };
    Ok(0)
}
