use crate::{dotfiles, system, util::*};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    process::Command,
};
#[derive(Clone)]
struct Layer {
    root: PathBuf,
    all: Vec<PathBuf>,
    protected: BTreeMap<PathBuf, BTreeSet<String>>,
    sizes: BTreeMap<PathBuf, u64>,
}
impl Layer {
    fn deletions(&self) -> Vec<PathBuf> {
        self.all
            .iter()
            .filter(|p| !self.protected.contains_key(*p))
            .cloned()
            .collect()
    }
    fn protect(&mut self, p: PathBuf, why: &str) -> Result<()> {
        if !self.all.contains(&p) {
            return fail(format!("unknown retained generation: {}", p.display()));
        }
        self.protected.entry(p).or_default().insert(why.into());
        Ok(())
    }
}
struct Plan {
    layers: BTreeMap<String, Layer>,
    keep: usize,
    pins: BTreeMap<String, Vec<String>>,
    links: BTreeMap<String, String>,
    id: String,
}
fn size(path: &Path) -> Result<u64> {
    let mut bytes = 0;
    for e in walkdir::WalkDir::new(path).follow_links(false).into_iter() {
        let e = e?;
        let m = fs::symlink_metadata(e.path())?;
        if m.is_file() {
            bytes += if m.blocks() > 0 {
                m.blocks() * 512
            } else {
                m.len()
            };
        }
    }
    Ok(bytes)
}
fn generations(root: &Path) -> Result<Vec<PathBuf>> {
    if !root.exists() {
        return Ok(Vec::new());
    }
    let mut paths = Vec::new();
    for e in fs::read_dir(root)? {
        let p = e?.path();
        if p.is_symlink()
            || !p.is_dir()
            || p.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .starts_with('.')
            || fs::canonicalize(&p)? != p
        {
            return fail(format!(
                "entradas inválidas en generaciones: {}",
                p.display()
            ));
        }
        paths.push(p);
    }
    paths.sort();
    paths.reverse();
    Ok(paths)
}
fn pins(root: &Path, layer: &str) -> Result<Vec<String>> {
    let p = root.join("pins").join(format!("{layer}.txt"));
    if !p.exists() {
        return Ok(Vec::new());
    }
    if p.is_symlink() || !p.is_file() {
        return fail("invalid pin manifest");
    }
    let mut out = Vec::new();
    for line in fs::read_to_string(p)?.lines() {
        let v = line.split('#').next().unwrap_or_default().trim();
        if v.is_empty() {
            continue;
        }
        if !v
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
            || !v.as_bytes()[0].is_ascii_alphanumeric()
        {
            return fail("invalid pin name");
        }
        if !out.contains(&v.to_owned()) {
            out.push(v.to_owned());
        }
    }
    Ok(out)
}
fn pointer(link: &Path, root: &Path) -> Result<Option<PathBuf>> {
    if fs::symlink_metadata(link).is_err() {
        return Ok(None);
    }
    let target = resolve_link(link).ok_or("invalid generation pointer")?;
    Ok(Some(system::managed(&target, root)?))
}
fn build(keep: usize) -> Result<Plan> {
    let data = fs::canonicalize(data_root()?)?;
    let runtime = runtime_root()?;
    let mut layers: BTreeMap<String, Layer> = BTreeMap::new();
    let mut all_pins = BTreeMap::new();
    let mut links = BTreeMap::new();
    for (name, root, pointer_root) in [
        ("system", data.join("system/builds"), data.join("system")),
        ("shell", data.join("builds"), runtime),
        (
            "dotfiles",
            data.join("dotfiles/builds"),
            data.join("dotfiles"),
        ),
        ("helpers", data.join("helpers/builds"), data.join("helpers")),
    ] {
        let all = generations(&root)?;
        if name == "helpers" && all.is_empty() {
            continue;
        }
        let values = pins(&data, name)?;
        let mut layer = Layer {
            root: root.clone(),
            sizes: BTreeMap::new(),
            all,
            protected: BTreeMap::new(),
        };
        for p in &layer.all {
            layer.sizes.insert(p.clone(), size(p)?);
        }
        for label in ["current", "previous"] {
            let link = pointer_root.join(label);
            if let Some(p) = pointer(&link, &root)? {
                links.insert(format!("{name}_{label}"), p.display().to_string());
                layer.protect(p, label)?;
            } else if label == "current" {
                return fail(format!("missing {name} current"));
            }
        }
        for value in &values {
            layer.protect(root.join(value), "pinned")?;
        }
        all_pins.insert(name.into(), values);
        layers.insert(name.into(), layer);
    }
    let sys = layers.get_mut("system").ok_or("missing system layer")?;
    let mut count = 0;
    for p in sys.all.clone() {
        if !sys.protected.contains_key(&p) && count < keep {
            sys.protect(p, "additional")?;
            count += 1;
        }
    }
    // Checkpoints keep their immutable schema1 proof as well as the component
    // generations; otherwise GC could make an otherwise healthy rollback fail.
    let mut pending = sys.protected.keys().cloned().collect::<Vec<_>>();
    let mut checked = BTreeSet::new();
    while let Some(p) = pending.pop() {
        if !checked.insert(p.clone()) {
            continue;
        }
        let v = system::validate_system(&p)?;
        if let Some(source) = v["legacySourceSystem"].as_str() {
            let original = PathBuf::from(source);
            sys.protect(original.clone(), "legacy-checkpoint-proof")?;
            pending.push(original);
        }
    }
    let kept = sys.protected.keys().cloned().collect::<Vec<_>>();
    for p in kept {
        let v = system::validate_system(&p)?;
        for (key, layer_name) in [
            ("shellGeneration", "shell"),
            ("dotfilesGeneration", "dotfiles"),
            ("helpersGeneration", "helpers"),
        ] {
            if let Some(s) = v[key].as_str() {
                layers
                    .get_mut(layer_name)
                    .ok_or("missing referenced layer")?
                    .protect(PathBuf::from(s), "referenced")?;
            }
        }
    }
    system::verify()?;
    for (name, layer) in &layers {
        for p in layer.protected.keys() {
            match name.as_str() {
                "shell" => {
                    system::validate_shell(p)?;
                }
                "dotfiles" => {
                    dotfiles::validate_generation(p)?;
                }
                "helpers" => {
                    cortetsu_rescue::helper_bundle::verify(
                        &roots()?,
                        p.file_name()
                            .and_then(|x| x.to_str())
                            .ok_or("invalid helper name")?,
                    )?;
                }
                _ => {}
            }
        }
    }
    let mut digest_layers = serde_json::Map::new();
    for (name, l) in &layers {
        digest_layers.insert(
            name.clone(),
            json!({"delete":l.deletions(),"protected":l.protected,"sizes":l.sizes}),
        );
    }
    let bytes = serde_json::to_vec(
        &json!({"keep":keep,"pins":all_pins,"symlinks":links,"layers":digest_layers}),
    )?;
    let id = format!("{:x}", Sha256::digest(bytes))[..16].to_owned();
    Ok(Plan {
        layers,
        keep,
        pins: all_pins,
        links,
        id,
    })
}
fn human(bytes: u64) -> String {
    let mut v = bytes as f64;
    for unit in ["B", "KiB", "MiB", "GiB"] {
        if v < 1024.0 || unit == "GiB" {
            return format!("{v:.2} {unit}");
        }
        v /= 1024.0;
    }
    unreachable!()
}
fn render(p: &Plan, apply: bool) -> String {
    let mut lines=vec!["Cortetsu generation GC".into(),format!("MODE={}",if apply{"APPLY"}else{"DRY-RUN"}),format!("KEEP_ADDITIONAL={}",p.keep),"RETENTION current+previous always; additional=newest system generations; referenced=components of retained system generations; pinned=pins/<layer>.txt".into()];
    let mut total = 0;
    let mut reclaim = 0;
    for name in ["system", "shell", "dotfiles", "helpers"] {
        let Some(l) = p.layers.get(name) else {
            continue;
        };
        let del = l.deletions();
        let bytes = del.iter().map(|x| l.sizes[x]).sum::<u64>();
        total += del.len();
        reclaim += bytes;
        lines.push(format!("\n{}:\n  generations={}\n  protected={}\n  delete={}\n  total_size={}\n  estimated_reclaim={}",name.to_uppercase(),l.all.len(),l.protected.len(),del.len(),human(l.sizes.values().sum()),human(bytes)));
        for (path, why) in l.protected.iter().rev() {
            lines.push(format!(
                "  KEEP   {} [{}]",
                path.file_name().unwrap_or_default().to_string_lossy(),
                why.iter().cloned().collect::<Vec<_>>().join(",")
            ));
        }
        for d in del {
            lines.push(format!(
                "  DELETE {} ({})",
                d.file_name().unwrap_or_default().to_string_lossy(),
                human(l.sizes[&d])
            ));
        }
    }
    lines.push(format!(
        "\nINVALID: none\nTOTAL_DELETE={total}\nTOTAL_RECLAIM={}\nPLAN_ID {}",
        human(reclaim),
        p.id
    ));
    if !apply {
        lines.push(if total>0{format!("Nada se borró. Para aplicar exactamente este plan: cortetsu gc --apply --keep {} --plan-id {} [--archive]",p.keep,p.id)}else{"Nada que recolectar.".into()});
    }
    lines.join("\n")
}
fn backup(p: &Plan, repo: &Path, out: &str) -> Result<PathBuf> {
    let dest = data_root()?.join("gc-backups").join(unique());
    fs::create_dir_all(&dest)?;
    atomic_write(&dest.join("dry-run.txt"), format!("{out}\n"), 0o600)?;
    let mut deletes = serde_json::Map::new();
    let mut protected = serde_json::Map::new();
    for (name, l) in &p.layers {
        deletes.insert(name.clone(), json!(l.deletions()));
        protected.insert(name.clone(), json!(l.protected.keys().collect::<Vec<_>>()));
        for path in l.protected.keys() {
            let root = dest
                .join("metadata")
                .join(name)
                .join(path.file_name().ok_or("no generation name")?);
            for file in [
                "BUILD_ID",
                "BUILD.json",
                "MANIFEST.json",
                "SYSTEM.json",
                "HELPERS.json",
            ] {
                let source = path.join(file);
                if source.is_file() {
                    copy_path(&source, &root.join(file))?;
                }
            }
        }
    }
    write_json(
        &dest.join("plan.json"),
        &json!({"schema":2,"createdAt":timestamp(),"repositoryRevision":revision(repo),"keepAdditional":p.keep,"delete":deletes,"protected":protected,"symlinks":p.links,"pins":p.pins,"planId":p.id}),
    )?;
    write_json(&dest.join("symlinks.json"), &json!(p.links))?;
    Ok(dest)
}
fn archive(p: &Plan, dest: &Path) -> Result<usize> {
    let mut count = 0;
    for (name, l) in &p.layers {
        for path in l.deletions() {
            let n = path.file_name().ok_or("no generation name")?;
            let out = dest
                .join("archives")
                .join(name)
                .join(format!("{}.tar.gz", n.to_string_lossy()));
            fs::create_dir_all(out.parent().unwrap())?;
            let status = Command::new("tar")
                .arg("-czf")
                .arg(&out)
                .arg("-C")
                .arg(&l.root)
                .arg("--")
                .arg(n)
                .status()?;
            if !status.success() {
                return fail("archive failed; no generations deleted");
            }
            let list = Command::new("tar").arg("-tzf").arg(&out).output()?;
            if !list.status.success() {
                return fail("archive cannot be verified");
            }
            let actual: BTreeSet<_> = String::from_utf8(list.stdout)?
                .lines()
                .map(|x| x.trim_end_matches('/').to_owned())
                .collect();
            let expected: Result<BTreeSet<String>> = walkdir::WalkDir::new(&path)
                .follow_links(false)
                .into_iter()
                .map(|e| {
                    let e = e?;
                    Ok(e.path()
                        .strip_prefix(&l.root)?
                        .to_string_lossy()
                        .into_owned())
                })
                .collect();
            if actual != expected? {
                return fail("archivo incompleto; no se borró nada");
            }
            count += 1;
        }
    }
    Ok(count)
}
pub fn run(a: &Args) -> Result<i32> {
    a.check(&["repo", "keep", "dry-run", "apply", "plan-id", "archive"])?;
    let keep = a.get("keep").unwrap_or("5").parse::<usize>()?;
    let apply = a.has("apply");
    if (a.has("archive") || a.has("plan-id")) && !apply {
        return fail("--plan-id y --archive sólo con --apply");
    }
    if a.has("dry-run") && apply {
        return fail("--apply and --dry-run are mutually exclusive");
    }
    if !apply {
        println!("{}", render(&build(keep)?, false));
        return Ok(0);
    }
    let expected = a.get("plan-id").ok_or("--apply exige --plan-id")?;
    let data = data_root()?;
    let mut locks = Vec::new();
    for rel in [
        "install.lock",
        "build.lock",
        "system/system.lock",
        "dotfiles/dotfiles.lock",
        "gc.lock",
        "helpers/helpers.lock",
    ] {
        locks.push(lock(&data.join(rel), true)?);
    }
    crate::install::check_mutation()?;
    let p = build(keep)?;
    if p.id != expected {
        return fail(format!(
            "el plan cambió desde su aprobación (aprobado={expected} actual={})",
            p.id
        ));
    }
    if p.layers.values().all(|l| l.deletions().is_empty()) {
        println!("{}\nGC_APPLIED deleted=0", render(&p, true));
        return Ok(0);
    }
    if a.has("archive") {
        let required = p
            .layers
            .values()
            .flat_map(|l| l.deletions().iter().map(|x| l.sizes[x]).collect::<Vec<_>>())
            .sum::<u64>()
            + 16 * 1024 * 1024;
        if fs2::available_space(&data)? < required {
            return fail("espacio insuficiente para archivo completo; no se borró nada");
        }
    }
    let output = render(&p, true);
    let b = backup(&p, &a.repo()?, &output)?;
    let archives = if a.has("archive") {
        archive(&p, &b)?
    } else {
        0
    };
    if build(keep)?.id != p.id {
        return fail("generation state changed during backup; no deletions");
    }
    for name in ["system", "dotfiles", "shell", "helpers"] {
        let Some(l) = p.layers.get(name) else {
            continue;
        };
        for path in l.deletions() {
            system::managed(&path, &l.root)?;
            fs::remove_dir_all(path)?;
        }
    }
    build(keep)?;
    println!("{output}\nBACKUP_METADATA {}", b.display());
    if a.has("archive") {
        println!(
            "BACKUP_ARCHIVES verified={archives} dir={}",
            b.join("archives").display()
        );
    } else {
        println!("BACKUP_ARCHIVES none (solo metadatos)");
    }
    println!("GC_APPLIED verified=plan-and-links");
    drop(locks);
    Ok(0)
}
