//! Read-only, offline Cortetsu generation verification.
//!
//! Verification remains available from a TTY without Quickshell, Go, Python
//! or a Git checkout. Native installs seal runtime files, helper manifests and
//! stable user launchers; historical generations retain explicit compatibility.
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::env;
use std::error::Error;
use std::fmt;
use std::fs;
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use walkdir::WalkDir;

#[derive(Debug)]
pub struct CheckError(pub String);
impl fmt::Display for CheckError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl Error for CheckError {}
fn invalid(reason: &str) -> CheckError {
    CheckError(reason.to_owned())
}

type Result<T> = std::result::Result<T, CheckError>;

#[derive(Debug, Clone)]
pub struct Roots {
    pub data: PathBuf,
    pub runtime: PathBuf,
}

impl Roots {
    pub fn from_env() -> Result<Self> {
        let home = env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| invalid("HOME is required"))?;
        if !home.is_absolute() {
            return Err(invalid("HOME must be absolute"));
        }
        let data = env::var_os("CORTETSU_DATA_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                env::var_os("XDG_DATA_HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| home.join(".local/share"))
                    .join("cortetsu")
            });
        let runtime = env::var_os("CORTETSU_RUNTIME_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                env::var_os("XDG_CONFIG_HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| home.join(".config"))
                    .join("quickshell/cortetsu")
            });
        if !data.is_absolute() || !runtime.is_absolute() {
            return Err(invalid("generation roots must be absolute"));
        }
        Ok(Self { data, runtime })
    }
    fn system_root(&self) -> PathBuf {
        self.data.join("system")
    }
    fn dot_root(&self) -> PathBuf {
        self.data.join("dotfiles")
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SystemMeta {
    schema: u32,
    shell_generation: String,
    dotfiles_generation: String,
    repository_revision: Option<String>,
    helpers_generation: Option<String>,
    helpers_manifest_sha256: Option<String>,
    shell_manifest_sha256: Option<String>,
    dotfiles_manifest_sha256: Option<String>,
    legacy_source_system: Option<String>,
    #[serde(default)]
    native_runtime: bool,
    #[serde(default)]
    managed_launchers: Vec<String>,
}
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ShellMeta {
    schema: u32,
    runtime_manifest_sha256: Option<String>,
    source_project: Option<String>,
    repository_revision: Option<String>,
}
#[derive(Debug, Clone, Deserialize)]
struct DotfilesMeta {
    schema: u32,
    entries: Vec<DotfileEntry>,
}
#[derive(Debug, Clone, Deserialize)]
struct DotfileEntry {
    target: String,
    sha256: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct VerifiedGeneration {
    pub system: String,
    pub shell: String,
    pub dotfiles: String,
    pub revision: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub helpers: Option<String>,
}

fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T> {
    let meta =
        fs::symlink_metadata(path).map_err(|_| invalid("cannot stat generation metadata"))?;
    if !meta.is_file() || meta.file_type().is_symlink() {
        return Err(invalid("metadata must be a regular file"));
    }
    if meta.len() > 4 * 1024 * 1024 {
        return Err(invalid("metadata exceeds safety bound"));
    }
    let source = fs::read(path).map_err(|_| invalid("cannot read generation metadata"))?;
    serde_json::from_slice(&source).map_err(|_| invalid("malformed generation metadata"))
}

fn canonical_existing(path: &Path) -> Result<PathBuf> {
    fs::canonicalize(path).map_err(|_| invalid("missing or inaccessible generation"))
}

/// Refuse non-symlink managed pointers and paths outside one generation level.
/// This is stricter than the historic Python implementation by design.
fn managed_link(link: &Path, builds: &Path) -> Result<PathBuf> {
    let metadata = fs::symlink_metadata(link).map_err(|_| invalid("missing generation link"))?;
    if !metadata.file_type().is_symlink() {
        return Err(invalid("generation pointer is not a symlink"));
    }
    let target = canonical_existing(link)?;
    let canonical_builds = canonical_existing(builds)?;
    if !target.is_dir() || target.parent() != Some(canonical_builds.as_path()) {
        return Err(invalid("generation link escapes managed builds"));
    }
    Ok(target)
}

fn managed_generation(source: &str, builds: &Path) -> Result<PathBuf> {
    let path = Path::new(source);
    if !path.is_absolute() {
        return Err(invalid("non-absolute generation metadata path"));
    }
    if fs::symlink_metadata(path)
        .map_err(|_| invalid("missing generation directory"))?
        .file_type()
        .is_symlink()
    {
        return Err(invalid("generation directory is a symlink"));
    }
    let canonical = canonical_existing(path)?;
    let managed_builds = canonical_existing(builds)?;
    if !canonical.is_dir() || canonical.parent() != Some(managed_builds.as_path()) {
        return Err(invalid("metadata points outside managed builds"));
    }
    Ok(canonical)
}

fn hex_digest(hash: &[u8]) -> String {
    hash.iter().map(|b| format!("{b:02x}")).collect::<String>()
}

/// Reproduce Python core/dotfiles.py::hash_path (schema 1) exactly:
/// file = F\0+bytes, link = L\0+target, directory = D\0+sorted descendants.
/// All paths in a generation must be valid UTF-8 for wire portability.
pub fn hash_path(path: &Path) -> Result<String> {
    let meta =
        fs::symlink_metadata(path).map_err(|_| invalid("missing file in dotfiles generation"))?;
    let mut digest = Sha256::new();
    if meta.file_type().is_symlink() {
        digest.update(b"L\0");
        let link = fs::read_link(path).map_err(|_| invalid("unreadable link"))?;
        let name = link.to_str().ok_or_else(|| invalid("non-utf8 link"))?;
        digest.update(name.as_bytes());
    } else if meta.is_file() {
        digest.update(b"F\0");
        let mut f = fs::File::open(path).map_err(|_| invalid("unreadable dotfile"))?;
        let mut buffer = [0u8; 64 * 1024];
        loop {
            let bytes_read = f
                .read(&mut buffer)
                .map_err(|_| invalid("failed to read dotfile"))?;
            if bytes_read == 0 {
                break;
            }
            digest.update(&buffer[..bytes_read]);
        }
    } else if meta.is_dir() {
        digest.update(b"D\0");
        let mut children = WalkDir::new(path)
            .follow_links(false)
            .min_depth(1)
            .into_iter()
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|_| invalid("unreadable dotfiles directory"))?;
        children.sort_by_key(|entry| entry.path().to_path_buf());
        if children.len() > 100_000 {
            return Err(invalid("too many generation files"));
        }
        for child in children {
            let relative = child
                .path()
                .strip_prefix(path)
                .map_err(|_| invalid("bad descendant"))?;
            let relative = relative
                .to_str()
                .ok_or_else(|| invalid("non-utf8 descendant"))?;
            digest.update(relative.as_bytes());
            digest.update([0]);
            digest.update(hash_path(child.path())?.as_bytes());
            digest.update([0]);
        }
    } else {
        return Err(invalid("unsupported file kind"));
    }
    Ok(hex_digest(&digest.finalize()))
}

fn is_safe_target(value: &str) -> bool {
    let path = Path::new(value);
    !value.is_empty()
        && value != "."
        && !path.is_absolute()
        && path.components().all(|c| matches!(c, Component::Normal(_)))
}

fn verify_dotfiles(path: &Path) -> Result<()> {
    let meta: DotfilesMeta = read_json(&path.join("MANIFEST.json"))?;
    if meta.schema != 1 || meta.entries.is_empty() || meta.entries.len() > 100_000 {
        return Err(invalid("unsupported or empty dotfiles manifest"));
    }
    let mut targets = std::collections::HashSet::new();
    for entry in &meta.entries {
        if !targets.insert(&entry.target)
            || !is_safe_target(&entry.target)
            || entry.sha256.len() != 64
            || !entry.sha256.bytes().all(|b| b.is_ascii_hexdigit())
        {
            return Err(invalid("invalid dotfiles path or digest"));
        }
        let candidate = path.join("home").join(&entry.target);
        let measured = hash_path(&candidate)?;
        if measured != entry.sha256 {
            return Err(invalid("dotfiles digest mismatch"));
        }
    }
    Ok(())
}

fn verify_digest(path: &Path, expected: &str) -> Result<()> {
    if expected.len() != 64 || !expected.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(invalid("invalid manifest digest"));
    }
    let mut file = fs::File::open(path).map_err(|_| invalid("cannot read digest source"))?;
    let mut digest = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let n = file
            .read(&mut buffer)
            .map_err(|_| invalid("digest source read failed"))?;
        if n == 0 {
            break;
        }
        digest.update(&buffer[..n]);
    }
    if hex_digest(&digest.finalize()) != expected {
        return Err(invalid("generation manifest or file digest mismatch"));
    }
    Ok(())
}
#[derive(Deserialize)]
struct RuntimeFiles {
    schema: u32,
    files: std::collections::BTreeMap<String, String>,
}
fn verify_shell_manifest(path: &Path, require_seal: bool) -> Result<()> {
    if !path.join("shell.qml").is_file() || !path.join("BUILD_ID").is_file() {
        return Err(invalid("shell generation missing required files"));
    }
    let manifest: ShellMeta = read_json(&path.join("BUILD.json"))?;
    if manifest.schema != 1 {
        return Err(invalid("unsupported shell manifest"));
    }
    if let Some(expected) = &manifest.runtime_manifest_sha256 {
        if manifest.source_project.as_deref() != Some("Cortetsu")
            || manifest
                .repository_revision
                .as_ref()
                .is_none_or(String::is_empty)
        {
            return Err(invalid("invalid native shell provenance"));
        }
        verify_digest(&path.join("FILES.json"), expected)?;
        let files: RuntimeFiles = read_json(&path.join("FILES.json"))?;
        if files.schema != 1 || files.files.is_empty() || files.files.len() > 100_000 {
            return Err(invalid("invalid native runtime file manifest"));
        }
        let mut actual = std::collections::BTreeSet::new();
        for entry in WalkDir::new(path).follow_links(false).min_depth(1) {
            let entry = entry.map_err(|_| invalid("cannot scan runtime"))?;
            if entry.file_type().is_dir() {
                continue;
            }
            let rel = entry
                .path()
                .strip_prefix(path)
                .map_err(|_| invalid("runtime path"))?
                .to_str()
                .ok_or_else(|| invalid("runtime path encoding"))?;
            if ["BUILD.json", "FILES.json"].contains(&rel) {
                continue;
            }
            if entry.file_type().is_symlink()
                && !canonical_existing(entry.path())?.starts_with(canonical_existing(path)?)
            {
                return Err(invalid("runtime symlink escapes generation"));
            }
            if !entry.path().is_file() {
                return Err(invalid("non-file native runtime entry"));
            }
            actual.insert(rel.to_owned());
        }
        if actual != files.files.keys().cloned().collect() {
            return Err(invalid("runtime manifest file set mismatch"));
        }
        for (name, hash) in &files.files {
            if !is_safe_target(name) || ["BUILD.json", "FILES.json"].contains(&name.as_str()) {
                return Err(invalid("unsafe runtime manifest path"));
            }
            verify_digest(&path.join(name), hash)?;
        }
    } else if require_seal {
        return Err(invalid("native runtime requires a sealed file manifest"));
    }
    Ok(())
}
fn verify_shell(path: &Path) -> Result<()> {
    verify_shell_manifest(path, false)
}
fn safe_launcher(name: &str) -> bool {
    (name == "cortetsu" || name.starts_with("cortetsu-"))
        && name.len() <= 120
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

fn verify_system_path(path: &Path, roots: &Roots) -> Result<VerifiedGeneration> {
    let meta: SystemMeta = read_json(&path.join("SYSTEM.json"))?;
    if meta.schema != 1 && meta.schema != 2 {
        return Err(invalid("unsupported system schema"));
    }
    if (meta.schema == 1 && meta.helpers_generation.is_some())
        || (meta.schema == 2 && meta.helpers_generation.is_none())
    {
        return Err(invalid("system schema and helper generation mismatch"));
    }
    let helpers = if let Some(ref source) = meta.helpers_generation {
        let builds = roots.data.join("helpers/builds");
        let path = managed_generation(source, &builds)?;
        let id = path
            .file_name()
            .and_then(|v| v.to_str())
            .ok_or_else(|| invalid("invalid helper generation id"))?;
        helper_bundle::verify(roots, id)?;
        if let Some(expected) = &meta.helpers_manifest_sha256 {
            verify_digest(&path.join("HELPERS.json"), expected)?;
        } else if meta.native_runtime {
            return Err(invalid("native system requires helper manifest digest"));
        }
        let bundle: serde_json::Value = read_json(&path.join("HELPERS.json"))?;
        let entries = bundle["helpers"]
            .as_array()
            .ok_or_else(|| invalid("helper entries"))?;
        let mut names = std::collections::HashSet::new();
        for name in &meta.managed_launchers {
            if !safe_launcher(name)
                || !names.insert(name)
                || !entries.iter().any(|e| e["name"].as_str() == Some(name))
            {
                return Err(invalid("invalid managed launcher ownership"));
            }
        }
        Some(path.to_string_lossy().into_owned())
    } else {
        None
    };
    let shell = managed_generation(&meta.shell_generation, &roots.data.join("builds"))?;
    let dotfiles = managed_generation(&meta.dotfiles_generation, &roots.dot_root().join("builds"))?;
    if let Some(source) = &meta.legacy_source_system {
        let original = managed_generation(source, &roots.system_root().join("builds"))?;
        let old: SystemMeta = read_json(&original.join("SYSTEM.json"))?;
        if old.schema != 1
            || old.shell_generation != meta.shell_generation
            || old.dotfiles_generation != meta.dotfiles_generation
            || old.helpers_generation.is_some()
        {
            return Err(invalid(
                "legacy checkpoint does not match original schema1 generation",
            ));
        }
    }
    verify_shell_manifest(
        &shell,
        meta.native_runtime && meta.legacy_source_system.is_none(),
    )?;
    if let Some(expected) = &meta.shell_manifest_sha256 {
        verify_digest(&shell.join("BUILD.json"), expected)?;
    } else if meta.native_runtime {
        return Err(invalid("native system requires shell manifest digest"));
    }
    verify_dotfiles(&dotfiles)?;
    if let Some(expected) = &meta.dotfiles_manifest_sha256 {
        verify_digest(&dotfiles.join("MANIFEST.json"), expected)?;
    } else if meta.native_runtime {
        return Err(invalid("native system requires dotfiles manifest digest"));
    }
    Ok(VerifiedGeneration {
        system: path.to_string_lossy().into_owned(),
        shell: shell.to_string_lossy().into_owned(),
        dotfiles: dotfiles.to_string_lossy().into_owned(),
        revision: meta.repository_revision,
        helpers,
    })
}

/// Verify an immutable system without requiring it to be currently selected.
pub fn verify_generation(roots: &Roots, path: &Path) -> Result<VerifiedGeneration> {
    let path = managed_generation(&path.to_string_lossy(), &roots.system_root().join("builds"))?;
    verify_system_path(&path, roots)
}

pub fn current(roots: &Roots) -> Result<VerifiedGeneration> {
    let system = managed_link(
        &roots.system_root().join("current"),
        &roots.system_root().join("builds"),
    )?;
    let snapshot = verify_system_path(&system, roots)?;
    let active_shell = managed_link(&roots.runtime.join("current"), &roots.data.join("builds"))?;
    let active_dots = managed_link(
        &roots.dot_root().join("current"),
        &roots.dot_root().join("builds"),
    )?;
    if let Some(ref helpers) = snapshot.helpers {
        let active_helpers = managed_link(
            &roots.data.join("helpers/current"),
            &roots.data.join("helpers/builds"),
        )?;
        if Path::new(helpers) != active_helpers {
            return Err(invalid("system/helpers current pointer drift"));
        }
        let meta: SystemMeta = read_json(&system.join("SYSTEM.json"))?;
        if !meta.managed_launchers.is_empty() {
            let home = env::var_os("HOME")
                .map(PathBuf::from)
                .filter(|p| p.is_absolute())
                .ok_or_else(|| invalid("HOME required for launcher verification"))?;
            for name in &meta.managed_launchers {
                let target = roots.data.join("helpers/current").join(name);
                if fs::read_link(home.join(".local/bin").join(name))
                    .ok()
                    .as_ref()
                    != Some(&target)
                {
                    return Err(invalid("managed launcher target drift"));
                }
            }
        }
    } else if fs::symlink_metadata(roots.data.join("helpers/current")).is_ok() {
        return Err(invalid(
            "schema1 system cannot own an active helper pointer",
        ));
    }
    if Path::new(&snapshot.shell) != active_shell || Path::new(&snapshot.dotfiles) != active_dots {
        return Err(invalid("system/shell/dotfiles current pointer drift"));
    }
    Ok(snapshot)
}

pub fn previous(roots: &Roots) -> Result<VerifiedGeneration> {
    let system = managed_link(
        &roots.system_root().join("previous"),
        &roots.system_root().join("builds"),
    )?;
    verify_system_path(&system, roots)
}

pub fn plan_rollback(roots: &Roots) -> Result<(VerifiedGeneration, VerifiedGeneration)> {
    let now = current(roots)?;
    let target = previous(roots)?;
    if now.system == target.system {
        return Err(invalid("current and previous identify the same generation"));
    }
    if now.helpers.is_some() != target.helpers.is_some() {
        return Err(invalid(
            "cannot roll back across schema 1/2 without an explicit migration",
        ));
    }
    Ok((now, target))
}

/// Offline, journaled rollback transaction used by the native CLI.
pub mod transaction;

/// Immutable helper bundle staging for schema-2 installation and rollback.
pub mod helper_bundle;

/// Read-only cross-language exec/1 adapter; no mutation dispatch.
pub mod exec_read;

/// Durable replay tombstones for future typed Rust owners; no active dispatch.
pub mod idempotency;

/// Strict, duplicate-free JSON envelope validation shared by Rust adapters.
pub mod strict_json;
