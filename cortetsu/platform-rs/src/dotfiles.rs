use crate::util::*;
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};
#[derive(Clone)]
pub struct Entry {
    pub source: String,
    pub target: String,
    pub tags: Vec<String>,
}
pub fn load_profile(repo: &Path, name: &str, seen: &mut BTreeSet<String>) -> Result<Value> {
    safe_relative(name)?;
    if name.contains('/') || !seen.insert(name.to_owned()) {
        return fail(format!("ciclo de perfiles detectado: {name}"));
    }
    let raw = toml_json(&repo.join("profiles").join(format!("{name}.toml")))?;
    if raw["schema"] != 1 {
        return fail("schema de perfil no soportado");
    }
    let mut tags = Vec::new();
    let mut groups = Vec::new();
    for parent in strings(&raw["inherits"]) {
        let p = load_profile(repo, &parent, &mut seen.clone())?;
        tags.extend(strings(&p["enabled_tags"]));
        groups.extend(strings(&p["package_groups"]));
    }
    tags.extend(strings(&raw["enabled_tags"]));
    groups.extend(strings(&raw["package_groups"]));
    fn dedupe(v: &mut Vec<String>) {
        let mut seen = BTreeSet::new();
        v.retain(|x| seen.insert(x.clone()));
    }
    dedupe(&mut tags);
    dedupe(&mut groups);
    Ok(
        json!({"name":raw["name"].as_str().unwrap_or(name),"enabled_tags":tags,"package_groups":groups}),
    )
}
pub fn manifest(repo: &Path, profile: Option<&str>) -> Result<(Value, Vec<Entry>)> {
    let raw = toml_json(&repo.join("dotfiles/manifest.toml"))?;
    if raw["schema"] != 1 {
        return fail("schema de dotfiles no soportado");
    }
    let env_profile = std::env::var("CORTETSU_PROFILE").ok();
    let name = profile
        .or(env_profile.as_deref())
        .or(raw["defaults"]["profile"].as_str())
        .unwrap_or("personal");
    let p = load_profile(repo, name, &mut BTreeSet::new())?;
    let enabled: BTreeSet<_> = strings(&p["enabled_tags"]).into_iter().collect();
    let mut entries = Vec::new();
    let mut targets = BTreeSet::new();
    for item in raw["entry"].as_array().ok_or("missing manifest entries")? {
        let source = item["source"].as_str().ok_or("missing source")?;
        let target = item["target"].as_str().ok_or("missing target")?;
        safe_relative(source)?;
        safe_relative(target)?;
        let tags = strings(&item["tags"]);
        if !tags.is_empty() && !tags.iter().any(|x| enabled.contains(x)) {
            continue;
        }
        if !targets.insert(target.to_owned()) {
            return fail(format!("target duplicado: {target}"));
        }
        if !repo.join(source).exists() {
            return fail(format!("source inexistente: {source}"));
        }
        entries.push(Entry {
            source: source.into(),
            target: target.into(),
            tags,
        });
    }
    if entries.is_empty() {
        return fail("el perfil no selecciona ningún dotfile");
    }
    Ok((p, entries))
}
pub fn validate_generation(path: &Path) -> Result<Value> {
    let v = json(&path.join("MANIFEST.json"))?;
    if v["schema"] != 1 {
        return fail("schema de generación no soportado");
    }
    if v["entries"].as_array().is_none_or(Vec::is_empty) {
        return fail("empty dotfiles generation");
    }
    let mut targets = BTreeSet::new();
    for entry in v["entries"]
        .as_array()
        .ok_or("missing generation entries")?
    {
        let t = entry["target"].as_str().ok_or("missing target")?;
        if !targets.insert(t) {
            return fail("duplicate manifest target");
        }
        let file = path.join("home").join(safe_relative(t)?);
        let expected = entry["sha256"].as_str().ok_or("missing digest")?;
        if cortetsu_rescue::hash_path(&file)? != expected {
            return fail(format!("hash inválido en generación: {}", file.display()));
        }
    }
    Ok(v)
}
pub fn build(repo: &Path, profile: Option<&str>) -> Result<PathBuf> {
    let (p, entries) = manifest(repo, profile)?;
    let root = data_root()?.join("dotfiles/builds");
    fs::create_dir_all(&root)?;
    let id = format!(
        "{}-{}",
        unique(),
        &revision(repo)[..revision(repo).len().min(8)]
    );
    let stage = root.join(format!(".staging-{id}"));
    let final_path = root.join(&id);
    fs::create_dir(&stage)?;
    let result = (|| {
        let mut records = Vec::new();
        for e in entries {
            let dest = stage.join("home").join(safe_relative(&e.target)?);
            copy_path(&repo.join(&e.source), &dest)?;
            records.push(json!({"source":e.source,"target":e.target,"tags":e.tags,"sha256":cortetsu_rescue::hash_path(&dest)?}));
        }
        write_json(
            &stage.join("MANIFEST.json"),
            &json!({"schema":1,"buildId":id,"builtAt":timestamp(),"repositoryRevision":revision(repo),"profile":p["name"],"entries":records}),
        )?;
        validate_generation(&stage)?;
        fs::rename(&stage, &final_path)?;
        Ok(final_path)
    })();
    if result.is_err() {
        let _ = fs::remove_dir_all(stage);
    }
    result
}
fn loader(stable: &Path) -> Result<String> {
    Ok(format!(
        "-- Cortetsu stable loader; the target is promoted atomically.\ndofile({})\n",
        serde_json::to_string(&stable.to_string_lossy())?
    ))
}
pub fn points_to_stable(path: &Path, stable: &Path) -> bool {
    if path.file_name().is_some_and(|x| x == "hyprland.lua") {
        return !path.is_symlink() && fs::read_to_string(path).ok() == loader(stable).ok();
    }
    fs::read_link(path).is_ok_and(|p| {
        if p.is_absolute() {
            p == stable
        } else {
            path.parent().is_some_and(|parent| parent.join(p) == stable)
        }
    })
}
pub fn verify(repo: &Path, profile: Option<&str>) -> Result<PathBuf> {
    crate::install::check_mutation()?;
    let (p, entries) = manifest(repo, profile)?;
    let root = data_root()?;
    let current = resolve_link(&root.join("dotfiles/current"))
        .ok_or("no existe generación de dotfiles current")?;
    let v = validate_generation(&current)?;
    if v["profile"] != p["name"] {
        return fail("perfil promovido no coincide");
    }
    for e in entries {
        let target = home()?.join(&e.target);
        if !points_to_stable(&target, &root.join("dotfiles/current/home").join(&e.target))
            || !target.exists()
        {
            return fail(format!(
                "target no administrado o roto: {}",
                target.display()
            ));
        }
    }
    Ok(current)
}
fn recover_apply_locked() -> Result<()> {
    let root = data_root()?;
    let path = root.join("dotfiles/apply-journal.json");
    if !path.exists() {
        return Ok(());
    }
    if path.is_symlink() {
        return fail("dotfiles apply journal is a symlink");
    }
    let mut v = json(&path)?;
    if v["schema"] != 1
        || v["home"].as_str() != home()?.to_str()
        || v["data"].as_str() != root.to_str()
    {
        return fail("dotfiles journal root mismatch");
    }
    match v["phase"].as_str() {
        Some("COMMITTED" | "RECOVERED") => return Ok(()),
        Some("PREPARED" | "RECOVERING") => {}
        _ => return fail("invalid dotfiles journal phase"),
    }
    crate::install::verify_snapshots_at(&v, &root.join("dotfiles/backups"))?;
    v["phase"] = json!("RECOVERING");
    write_json(&path, &v)?;
    crate::install::restore_snapshots(&v)?;
    v["phase"] = json!("RECOVERED");
    write_json(&path, &v)?;
    println!(
        "RECOVERED dotfiles={}",
        v["id"].as_str().unwrap_or_default()
    );
    Ok(())
}
pub fn apply(repo: &Path, profile: Option<&str>) -> Result<()> {
    let _lock = lock(&data_root()?.join("dotfiles/dotfiles.lock"), false)?;
    crate::install::check_mutation()?;
    recover_apply_locked()?;
    let (p, entries) = manifest(repo, profile)?;
    let root = data_root()?;
    let current = root.join("dotfiles/current");
    let previous = root.join("dotfiles/previous");
    let old_current = resolve_link(&current);
    for pointer in [&current, &previous] {
        if pointer.exists() && !pointer.is_symlink() {
            return fail("generation pointer is not a symlink");
        }
    }
    let generation = build(repo, profile)?;
    let invalid = old_current
        .as_ref()
        .is_some_and(|g| validate_generation(g).is_err());
    let id = unique();
    let backup_root = root.join("dotfiles/backups").join(&id);
    let mut backups = BTreeMap::new();
    for e in &entries {
        let target = home()?.join(&e.target);
        let stable = root.join("dotfiles/current/home").join(&e.target);
        if points_to_stable(&target, &stable) {
            continue;
        }
        if target.is_dir() && !target.is_symlink() {
            return fail(format!(
                "no se adopta un directorio completo automáticamente: {}",
                target.display()
            ));
        }
        let backup = if fs::symlink_metadata(&target).is_ok() {
            let b = backup_root.join("home").join(&e.target);
            copy_path(&target, &b)?;
            Some(b)
        } else {
            None
        };
        backups.insert(target, backup);
    }
    let mut targets = vec![current.clone(), previous.clone()];
    targets.extend(backups.keys().cloned());
    fs::create_dir_all(&backup_root)?;
    let mut snapshots = Vec::new();
    for (i, target) in targets.iter().enumerate() {
        snapshots.push(crate::install::snapshot(
            target,
            &backup_root.join(format!("snapshot-{i}")),
        )?);
    }
    let journal_path = root.join("dotfiles/apply-journal.json");
    let mut journal = json!({"schema":1,"id":id,"phase":"PREPARED","home":home()?,"data":root,"backupRoot":backup_root,"snapshots":snapshots,"generation":generation});
    write_json(&journal_path, &journal)?;
    let outcome = (|| {
        if let Some(ref old) = old_current
            && !invalid
        {
            atomic_link(old, &previous)?;
        }
        atomic_link(&generation, &current)?;
        for e in &entries {
            let target = home()?.join(&e.target);
            let stable = root.join("dotfiles/current/home").join(&e.target);
            if points_to_stable(&target, &stable) {
                continue;
            }
            if e.target == ".config/hypr/hyprland.lua" {
                atomic_write(&target, loader(&stable)?, 0o644)?;
            } else {
                atomic_link(&stable, &target)?;
            }
        }
        verify(repo, profile)?;
        Ok(())
    })();
    if let Err(e) = outcome {
        recover_apply_locked()?;
        return Err(e);
    }
    journal["phase"] = json!("COMMITTED");
    write_json(&journal_path, &journal)?;
    if invalid && let Some(old) = &old_current {
        let dest = root.join("dotfiles/invalid").join(format!(
            "{}-{}",
            old.file_name()
                .ok_or("missing generation name")?
                .to_string_lossy(),
            unique()
        ));
        fs::create_dir_all(dest.parent().unwrap())?;
        fs::rename(old, &dest)?;
        println!("QUARANTINED invalid={}", dest.display());
    }
    println!(
        "PROMOTED dotfiles={}\nPROFILE profile={}",
        generation.display(),
        p["name"].as_str().unwrap_or("unknown")
    );
    if let Some(old) = old_current {
        println!("PREVIOUS dotfiles={}", old.display());
    }
    if backup_root.exists() {
        println!("BACKUP unmanaged={}", backup_root.display());
    }
    Ok(())
}
pub fn run(a: &Args) -> Result<i32> {
    a.check(&["repo", "profile", "keep"])?;
    let repo = a.repo()?;
    let profile = a.get("profile");
    match a.action("status").as_str() {
        "plan" => {
            let (p, entries) = manifest(&repo, profile)?;
            println!(
                "Cortetsu dotfiles plan · profile={}",
                p["name"].as_str().unwrap_or("unknown")
            );
            for e in entries {
                let target = home()?.join(&e.target);
                let stable = data_root()?.join("dotfiles/current/home").join(&e.target);
                let action = if points_to_stable(&target, &stable) {
                    "managed"
                } else if fs::symlink_metadata(&target).is_ok() {
                    "backup+adopt"
                } else {
                    "create"
                };
                println!("  {action:12} {} <- {}", e.target, e.source);
            }
        }
        "apply" => apply(&repo, profile)?,
        "recover" => {
            let _lock = lock(&data_root()?.join("dotfiles/dotfiles.lock"), false)?;
            crate::install::check_mutation()?;
            recover_apply_locked()?;
        }
        "verify" => println!(
            "PASS: dotfiles generation {}",
            verify(&repo, profile)?.display()
        ),
        "status" => {
            let (p, entries) = manifest(&repo, profile)?;
            let root = data_root()?;
            let managed = entries
                .iter()
                .filter(|e| {
                    home().is_ok_and(|h| {
                        points_to_stable(
                            &h.join(&e.target),
                            &root.join("dotfiles/current/home").join(&e.target),
                        )
                    })
                })
                .count();
            println!(
                "Dotfiles generations:\n  profile={}\n  current={}\n  previous={}\n  managed_targets={}/{}",
                p["name"].as_str().unwrap_or("unknown"),
                resolve_link(&root.join("dotfiles/current"))
                    .map_or("missing".into(), |p| p.display().to_string()),
                resolve_link(&root.join("dotfiles/previous"))
                    .map_or("missing".into(), |p| p.display().to_string()),
                managed,
                entries.len()
            );
        }
        "rollback" => {
            manifest(&repo, profile)?;
            let root = data_root()?.join("dotfiles");
            let _lock = lock(&root.join("dotfiles.lock"), false)?;
            crate::install::check_mutation()?;
            let current = resolve_link(&root.join("current")).ok_or("rollback requiere current")?;
            let previous =
                resolve_link(&root.join("previous")).ok_or("rollback requiere previous")?;
            validate_generation(&current)?;
            validate_generation(&previous)?;
            atomic_link(&previous, &root.join("current"))?;
            if let Err(e) = atomic_link(&current, &root.join("previous"))
                .and_then(|_| verify(&repo, profile).map(|_| ()))
            {
                atomic_link(&current, &root.join("current"))?;
                atomic_link(&previous, &root.join("previous"))?;
                return Err(e);
            }
            println!(
                "ROLLED BACK dotfiles current={} previous={}",
                previous.display(),
                current.display()
            );
        }
        "gc" => println!(
            "GC dotfiles: sin borrados; la recolección es coordinada y explícita.\nRevisa el plan con: cortetsu gc --keep {}",
            a.get("keep").unwrap_or("3")
        ),
        _ => return fail("unknown dotfiles action"),
    };
    Ok(0)
}
