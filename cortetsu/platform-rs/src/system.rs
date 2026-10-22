use crate::{dotfiles, util::*};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::{Path, PathBuf},
};
pub fn managed(path: &Path, root: &Path) -> Result<PathBuf> {
    if !path.is_absolute() || path.is_symlink() || !path.is_dir() {
        return fail("invalid generation path");
    }
    let canon = fs::canonicalize(path)?;
    if canon.parent() != Some(fs::canonicalize(root)?.as_path()) {
        return fail("generation escapes managed builds");
    }
    Ok(canon)
}
pub fn validate_shell(path: &Path) -> Result<Value> {
    for p in ["shell.qml", "BUILD_ID", "BUILD.json"] {
        if !path.join(p).is_file() {
            return fail(format!("generación shell inválida, falta {p}"));
        }
    }
    let v = json(&path.join("BUILD.json"))?;
    if v["schema"] != 1 {
        return fail("unsupported shell schema");
    }
    Ok(v)
}
pub fn validate_system(path: &Path) -> Result<Value> {
    let r = roots()?;
    cortetsu_rescue::verify_generation(&r, path)?;
    let v = json(&path.join("SYSTEM.json"))?;
    let shell = Path::new(v["shellGeneration"].as_str().ok_or("missing shell")?);
    if json(&shell.join("BUILD.json"))?["runtimeManifestSha256"].is_string() {
        crate::runtime::validate(shell, true)?;
    }
    Ok(v)
}
pub fn verify() -> Result<PathBuf> {
    let r = roots()?;
    let snapshot = cortetsu_rescue::current(&r)?;
    let current = PathBuf::from(snapshot.system);
    validate_system(&current)?;
    Ok(current)
}
fn promotion_journal(root: &Path) -> Result<Option<Value>> {
    let path = root.join("promotion-journal.json");
    match fs::symlink_metadata(&path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e.into()),
        Ok(m) if !m.is_file() || m.file_type().is_symlink() => {
            return fail("system promotion journal must be a regular file");
        }
        _ => {}
    }
    let v = json(&path)?;
    if v["schema"] != 1
        || !matches!(
            v["phase"].as_str(),
            Some("PREPARED" | "COMMITTED" | "RECOVERED")
        )
    {
        return fail("invalid system promotion journal");
    }
    Ok(Some(v))
}
fn reject_pending_promotion(root: &Path) -> Result<()> {
    if promotion_journal(root)?.is_some_and(|v| v["phase"] == "PREPARED") {
        return fail("system promotion is pending; run cortetsu recover");
    }
    Ok(())
}
fn pointer(path: &Path) -> Result<Option<PathBuf>> {
    match fs::symlink_metadata(path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
        Ok(m) if !m.file_type().is_symlink() => fail("system pointer is not a symlink"),
        Ok(_) => Ok(Some(fs::canonicalize(path)?)),
    }
}
pub fn recover() -> Result<()> {
    let r = roots()?;
    let root = r.data.join("system");
    let _lock = lock(&root.join("system.lock"), false)?;
    crate::install::check_mutation()?;
    let Some(mut journal) = promotion_journal(&root)? else {
        return Ok(());
    };
    if journal["phase"] != "PREPARED" {
        return Ok(());
    }
    // A standalone promotion seals already-selected components. Complete it
    // only when those exact selections still exist; whole-install recovery
    // restores its own snapshots before this operation is attempted.
    let target = managed(
        Path::new(
            journal["target"]
                .as_str()
                .ok_or("missing promotion target")?,
        ),
        &root.join("builds"),
    )?;
    let meta = validate_system(&target)?;
    let before = match &journal["beforeCurrent"] {
        Value::Null => None,
        Value::String(p) => Some(managed(Path::new(p), &root.join("builds"))?),
        _ => return fail("invalid prior system pointer"),
    };
    let before_previous = match &journal["beforePrevious"] {
        Value::Null => None,
        Value::String(p) => Some(managed(Path::new(p), &root.join("builds"))?),
        _ => return fail("invalid prior system previous pointer"),
    };
    let current = pointer(&root.join("current"))?;
    if current != before && current.as_ref() != Some(&target) {
        return fail("system current changed since prepared promotion");
    }
    let previous = pointer(&root.join("previous"))?;
    if previous != before_previous && previous != before {
        return fail("system previous changed since prepared promotion");
    }
    for (key, link) in [
        ("shellGeneration", r.runtime.join("current")),
        ("dotfilesGeneration", r.data.join("dotfiles/current")),
        ("helpersGeneration", r.data.join("helpers/current")),
    ] {
        let expected = meta[key].as_str().map(PathBuf::from);
        if pointer(&link)? != expected {
            return fail(format!("{key} changed since prepared promotion"));
        }
    }
    for name in strings(&meta["managedLaunchers"]) {
        if fs::read_link(home()?.join(".local/bin").join(&name))?
            != r.data.join("helpers/current").join(name)
        {
            return fail("managed launcher changed since prepared promotion");
        }
    }
    if let Some(old) = &before
        && validate_system(old).is_ok()
    {
        atomic_link(old, &root.join("previous"))?;
    }
    atomic_link(&target, &root.join("current"))?;
    verify()?;
    journal["phase"] = json!("COMMITTED");
    write_json(&root.join("promotion-journal.json"), &journal)?;
    println!("RECOVERED system={}", target.display());
    Ok(())
}
pub fn promote(a: &Args) -> Result<()> {
    let r = roots()?;
    let root = r.data.join("system");
    let _lock = lock(&root.join("system.lock"), false)?;
    crate::install::check_mutation()?;
    reject_pending_promotion(&root)?;
    let shell =
        resolve_link(&r.runtime.join("current")).ok_or("no existe shell current administrado")?;
    let dots = resolve_link(&r.data.join("dotfiles/current"))
        .ok_or("no existe dotfiles current administrado")?;
    managed(&shell, &r.data.join("builds"))?;
    managed(&dots, &r.data.join("dotfiles/builds"))?;
    validate_shell(&shell)?;
    dotfiles::validate_generation(&dots)?;
    let helpers = a
        .get("helpers")
        .map(PathBuf::from)
        .or_else(|| resolve_link(&r.data.join("helpers/current")));
    let id = unique();
    let build = root.join("builds").join(&id);
    fs::create_dir_all(&build)?;
    let mut payload = json!({"schema":if helpers.is_some(){2}else{1},"buildId":id,"builtAt":timestamp(),"repositoryRevision":revision(&a.repo()?),"shellGeneration":shell,"dotfilesGeneration":dots});
    let shell_meta = json(&shell.join("BUILD.json"))?;
    if shell_meta["runtimeManifestSha256"].is_string() {
        payload["nativeRuntime"] = json!(true);
        payload["shellManifestSha256"] = json!(format!(
            "{:x}",
            Sha256::digest(fs::read(shell.join("BUILD.json"))?)
        ));
        payload["dotfilesManifestSha256"] = json!(format!(
            "{:x}",
            Sha256::digest(fs::read(dots.join("MANIFEST.json"))?)
        ));
    }
    if let Some(h) = &helpers {
        managed(h, &r.data.join("helpers/builds"))?;
        cortetsu_rescue::helper_bundle::verify(
            &r,
            h.file_name()
                .and_then(|x| x.to_str())
                .ok_or("bad helper id")?,
        )?;
        payload["helpersGeneration"] = json!(h);
        payload["helpersManifestSha256"] = json!(format!(
            "{:x}",
            Sha256::digest(fs::read(h.join("HELPERS.json"))?)
        ));
        let hm = json(&h.join("HELPERS.json"))?;
        let names = a
            .get("launchers")
            .map(|s| {
                s.split(',')
                    .filter(|x| !x.is_empty())
                    .map(str::to_owned)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_else(|| {
                if hm["launcherNames"].is_array() {
                    strings(&hm["launcherNames"])
                } else {
                    hm["helpers"]
                        .as_array()
                        .map(|items| {
                            items
                                .iter()
                                .filter_map(|x| x["name"].as_str().map(str::to_owned))
                                .collect()
                        })
                        .unwrap_or_default()
                }
            });
        payload["managedLaunchers"] = json!(names);
    }
    write_json(&build.join("SYSTEM.json"), &payload)?;
    validate_system(&build)?;
    let cur = root.join("current");
    let prev = root.join("previous");
    let old = resolve_link(&cur);
    let old_prev = resolve_link(&prev);
    for p in [&cur, &prev] {
        if p.exists() && !p.is_symlink() {
            return fail("system pointer is not symlink");
        }
    }
    let valid_old = old.as_ref().is_some_and(|p| validate_system(p).is_ok());
    if let Some(h) = helpers
        && resolve_link(&r.data.join("helpers/current")).as_ref() != Some(&h)
    {
        return fail(
            "helpers must be transactionally activated by installer before system promotion",
        );
    }
    let journal = root.join("promotion-journal.json");
    let mut journal_meta = json!({"schema":1,"phase":"PREPARED","beforeCurrent":old,"beforePrevious":old_prev,"target":build});
    write_json(&journal, &journal_meta)?;
    let result = (|| {
        if valid_old {
            atomic_link(old.as_ref().unwrap(), &prev)?;
        }
        atomic_link(&build, &cur)?;
        verify()?;
        journal_meta["phase"] = json!("COMMITTED");
        write_json(&journal, &journal_meta)?;
        Ok(())
    })();
    if let Err(e) = result {
        restore_link(&cur, &old)?;
        restore_link(&prev, &old_prev)?;
        journal_meta["phase"] = json!("RECOVERED");
        write_json(&journal, &journal_meta)?;
        return Err(e);
    }
    println!("PROMOTED system={}", build.display());
    if let Some(p) = old {
        println!("PREVIOUS system={}", p.display());
    }
    Ok(())
}
pub fn run(a: &Args) -> Result<i32> {
    a.check(&["repo", "keep", "helpers", "launchers"])?;
    match a.action("status").as_str() {
        "promote" => promote(a)?,
        "recover" => recover()?,
        "verify" => println!("PASS: system generation {}", verify()?.display()),
        "status" => {
            println!("System generations:");
            for label in ["current", "previous"] {
                if let Some(p) = resolve_link(&data_root()?.join("system").join(label)) {
                    println!("  {label}={}", p.display());
                    match validate_system(&p) {
                        Ok(v) => {
                            for (key, name) in [
                                ("shellGeneration", "shell"),
                                ("dotfilesGeneration", "dotfiles"),
                                ("helpersGeneration", "helpers"),
                                ("repositoryRevision", "revision"),
                            ] {
                                if let Some(s) = v[key].as_str() {
                                    println!("  {label}_{name}={s}");
                                }
                            }
                        }
                        Err(e) => println!("  {label}_metadata=invalid ({e})"),
                    }
                } else {
                    println!("  {label}=missing");
                }
            }
        }
        "rollback" => {
            crate::install::check_mutation()?;
            let r = roots()?;
            reject_pending_promotion(&r.data.join("system"))?;
            verify()?;
            let (now, _) = cortetsu_rescue::plan_rollback(&r)?;
            if now.helpers.is_none() {
                return fail(
                    "native rollback of schema1 requires explicit legacy recovery; use cortetsu-rescue rollback-pointers --acknowledge-unmanaged-helpers",
                );
            }
            let status = cortetsu_rescue::transaction::rollback_pointers(&r, true)?;
            verify()?;
            println!("ROLLED BACK system {}", serde_json::to_string(&status)?);
        }
        "gc" => println!(
            "GC system: sin borrados; la recolección es coordinada y explícita.\nRevisa el plan con: cortetsu gc --keep {}",
            a.get("keep").unwrap_or("3")
        ),
        _ => return fail("unknown system action"),
    };
    Ok(0)
}
