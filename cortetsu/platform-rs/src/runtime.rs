use crate::{system, util::*};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};
fn digest(bytes: impl AsRef<[u8]>) -> String {
    format!("{:x}", Sha256::digest(bytes.as_ref()))
}
fn inventory(root: &Path) -> Result<BTreeMap<String, String>> {
    let mut result = BTreeMap::new();
    for entry in walkdir::WalkDir::new(root).follow_links(false).min_depth(1) {
        let entry = entry?;
        if entry.file_type().is_dir() {
            continue;
        }
        let rel = entry
            .path()
            .strip_prefix(root)?
            .to_str()
            .ok_or("non-utf8 runtime file")?;
        if ["BUILD.json", "FILES.json"].contains(&rel) {
            continue;
        }
        if entry.file_type().is_symlink() {
            let target = fs::canonicalize(entry.path())?;
            if !target.starts_with(fs::canonicalize(root)?) {
                return fail("runtime symlink escapes generation");
            }
        }
        if !entry.path().is_file() {
            return fail("runtime contains non-file");
        }
        result.insert(rel.to_owned(), digest(fs::read(entry.path())?));
    }
    Ok(result)
}
pub fn validate(path: &Path, historical: bool) -> Result<()> {
    system::validate_shell(path)?;
    let required: Vec<String> =
        serde_json::from_str(include_str!("../templates/runtime-required.json"))?;
    for rel in required {
        if !path.join(&rel).is_file() {
            return fail(format!("runtime missing {rel}"));
        }
    }
    let build = json(&path.join("BUILD.json"))?;
    if build["sourceProject"] != "Cortetsu"
        || build["repositoryRevision"]
            .as_str()
            .is_none_or(str::is_empty)
    {
        return fail("invalid runtime build provenance");
    }
    let provenance = json(&path.join("provenance.json"))?;
    if provenance["schema"] != 1 || provenance["project"] != "Cortetsu" {
        return fail("invalid runtime provenance");
    }
    if json(&path.join("composition.json"))?["schema"] != 2 {
        return fail("unsupported runtime composition");
    }
    let wall = json(&path.join("wall-utility.json"))?;
    let expected: Value = serde_json::from_str(include_str!("../templates/wall-utility.json"))?;
    if historical {
        for k in ["schema", "id", "product", "direction", "states"] {
            if wall[k] != expected[k] {
                return fail(format!("incompatible historical wallpaper contract: {k}"));
            }
        }
    } else if wall != expected {
        return fail("runtime wallpaper contract mismatch");
    }
    if let Some(hash) = build["runtimeManifestSha256"].as_str() {
        let bytes = fs::read(path.join("FILES.json"))?;
        if digest(&bytes) != hash {
            return fail("runtime file manifest digest mismatch");
        }
        let manifest: Value = serde_json::from_slice(&bytes)?;
        if manifest["schema"] != 1 || manifest["files"] != serde_json::to_value(inventory(path)?)? {
            return fail("runtime file integrity mismatch");
        }
    } else if !historical {
        return fail("native runtime requires a sealed file manifest");
    }
    Ok(())
}
fn source_contract(path: &Path) -> Result<()> {
    // Runtime gates own input/ownership invariants; wider product design checks
    // remain in developer regression suites and actual Qt Quick tests.
    for folder in ["modules", "components"] {
        for entry in walkdir::WalkDir::new(path.join(folder)).follow_links(false) {
            let entry = entry?;
            if !entry.file_type().is_file() || entry.path().extension().is_none_or(|e| e != "qml") {
                continue;
            }
            let body = fs::read_to_string(entry.path())?;
            if body.contains("sh -c") || body.contains("import Caelestia") {
                return fail(format!(
                    "runtime ownership violation: {}",
                    entry.path().display()
                ));
            }
        }
    }
    for rel in [
        "CortetsuButton.qml",
        "CortetsuToggle.qml",
        "CortetsuSlider.qml",
        "CortetsuChoiceCard.qml",
        "CortetsuListRow.qml",
    ] {
        let body = fs::read_to_string(path.join("components").join(rel))?;
        if !body.contains("focus: false") || !body.contains("activeFocusOnTab") {
            return fail(format!("keyboard focus contract violated: {rel}"));
        }
    }
    for rel in ["EnergyPage.qml", "PowerPage.qml", "PowerAutomationPage.qml"] {
        let body = fs::read_to_string(path.join("modules/hardware").join(rel))?;
        if !body.contains("running: root.visible")
            || !body.contains("onVisibleChanged: { if (visible) refresh(); }")
        {
            return fail(format!("hidden-page polling contract violated: {rel}"));
        }
    }
    Ok(())
}
pub fn run(command: &str, a: &Args) -> Result<i32> {
    a.check(&["historical"])?;
    let path = PathBuf::from(a.positional.first().ok_or("runtime path required")?);
    if command == "seal-runtime" {
        source_contract(&path)?;
        write_json(
            &path.join("FILES.json"),
            &json!({"schema":1,"files":inventory(&path)?}),
        )?;
        let mut build = json(&path.join("BUILD.json"))?;
        build["runtimeManifestSha256"] = json!(digest(fs::read(path.join("FILES.json"))?));
        write_json(&path.join("BUILD.json"), &build)?;
        validate(&path, false)?;
    } else {
        validate(&path, a.has("historical"))?;
    }
    println!("PASS: runtime integrity {}", path.display());
    Ok(0)
}
