use crate::common::{self, Result};
use serde_json::{json, Value};
use std::{collections::BTreeSet, fs, io::Read, os::unix::fs::OpenOptionsExt, path::{Component, Path, PathBuf}, time::UNIX_EPOCH};

const MAX_METADATA: u64 = 2 * 1024 * 1024;
const MAX_ITEMS: usize = 20_000;
const MAX_CATALOG_BYTES: usize = 16 * 1024 * 1024;

fn read_small(path: &Path) -> Result<String> {
    if !fs::metadata(path)?.is_file() { return Err("not a regular file".into()); }
    let file = fs::OpenOptions::new().read(true).custom_flags(nix::libc::O_NONBLOCK).open(path)?;
    if !file.metadata()?.is_file() { return Err("not a regular file".into()); }
    let mut bytes = Vec::new();
    file.take(MAX_METADATA + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_METADATA { return Err("metadata exceeds 2 MiB".into()); }
    Ok(String::from_utf8(bytes)?)
}

// Steam's text VDF uses quoted tokens, braces and line comments. Preserve
// unknown escapes so a library path is never silently rewritten.
fn vdf_tokens(input: &str) -> Result<Vec<String>> {
    let mut out = Vec::new();
    let mut chars = input.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            c if c.is_whitespace() => {},
            '/' if chars.peek() == Some(&'/') => { for c in chars.by_ref() { if c == '\n' { break; } } },
            '{' | '}' => out.push(c.to_string()),
            '"' => {
                let mut token = String::new();
                let mut closed = false;
                while let Some(c) = chars.next() {
                    if c == '"' { closed = true; break; }
                    if c == '\\' {
                        let next = chars.next().ok_or("unfinished VDF escape")?;
                        if next != '\\' && next != '"' { token.push('\\'); }
                        token.push(next);
                    } else { token.push(c); }
                }
                if !closed { return Err("unterminated VDF string".into()); }
                out.push(token);
            },
            _ => return Err("unsupported unquoted VDF token".into()),
        }
    }
    Ok(out)
}

fn library_paths(input: &str) -> Result<Vec<PathBuf>> {
    let tokens = vdf_tokens(input)?;
    let mut paths = Vec::new();
    let mut depth = 0usize;
    let mut i = 0;
    while i < tokens.len() {
        match tokens[i].as_str() {
            "{" => { depth += 1; i += 1; },
            "}" => { depth = depth.checked_sub(1).ok_or("unbalanced VDF")?; i += 1; },
            key => {
                let value = tokens.get(i + 1).ok_or("missing VDF value")?;
                if value == "{" { i += 1; continue; }
                if value == "}" { return Err("missing VDF value".into()); }
                if (depth == 2 && key == "path") || (depth == 1 && key.chars().all(|c| c.is_ascii_digit())) {
                    let path = PathBuf::from(value);
                    if path.is_absolute() { paths.push(path); }
                }
                i += 2;
            }
        }
    }
    if depth != 0 { return Err("unbalanced VDF".into()); }
    Ok(paths)
}

fn local_resource(root: &Path, value: Option<&str>) -> Option<PathBuf> {
    let relative = Path::new(value?);
    if relative.as_os_str().is_empty() || relative.components().any(|c| !matches!(c, Component::Normal(_) | Component::CurDir)) { return None; }
    let path = root.join(relative).canonicalize().ok()?;
    if path.starts_with(root) && path.is_file() { Some(path) } else { None }
}

pub(super) fn item(root: &Path, source: &str) -> Value {
    let modified = fs::metadata(root).ok().and_then(|m| m.modified().ok()).and_then(|m| m.duration_since(UNIX_EPOCH).ok()).map(|m| m.as_secs());
    let workshop_id = if source == "steam" { root.file_name().and_then(|n| n.to_str()).filter(|s| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit())) } else { None };
    let mut entry = json!({"id": root, "location": root, "source": source, "workshopId": workshop_id, "modified": modified, "title": null, "author": null, "preview": null, "type": "unknown", "properties": {}, "compatibility": "undetermined", "errors": []});
    let project = root.join("project.json");
    let metadata = (|| -> Result<Value> {
        let resolved = project.canonicalize()?;
        if !resolved.starts_with(root) { return Err("project.json escapes wallpaper directory".into()); }
        let value: Value = serde_json::from_str(&read_small(&resolved)?)?;
        if !value.is_object() { return Err("project.json must be an object".into()); }
        Ok(value)
    })();
    match metadata {
        Err(e) => { entry["compatibility"] = json!("read-error"); entry["errors"] = json!([e.to_string()]); },
        Ok(metadata) => {
            entry["title"] = metadata.get("title").filter(|v| v.is_string()).cloned().unwrap_or(Value::Null);
            entry["author"] = metadata.get("author").filter(|v| v.is_string()).cloned().unwrap_or(Value::Null);
            entry["type"] = json!(metadata.get("type").and_then(Value::as_str).unwrap_or("unknown").to_lowercase());
            entry["preview"] = json!(local_resource(root, metadata.get("preview").and_then(Value::as_str)));
            entry["entrypoint"] = json!(local_resource(root, metadata.get("file").and_then(Value::as_str)));
            let declared = metadata.get("file").and_then(Value::as_str).filter(|s| !s.is_empty() && Path::new(s).components().all(|c| matches!(c, Component::Normal(_) | Component::CurDir)));
            entry["entryFile"] = json!(declared);
            entry["packedScene"] = json!(local_resource(root, Some("scene.pkg")).or_else(||local_resource(root, Some("gifscene.pkg"))));
            entry["properties"] = metadata.pointer("/general/properties").filter(|v| v.is_object()).cloned().unwrap_or(json!({}));
            entry["reason"] = json!("Renderer compatibility has not been verified for this wallpaper");
        }
    }
    entry
}

pub fn main(args: &[String]) -> Result<i32> {
    if args.first().map(String::as_str) == Some("session") { return crate::orbital_session::main(); }
    if args.first().map(String::as_str) == Some("renderer-child") { return crate::orbital_session::renderer_child(&args[1..]); }
    if args.first().map(String::as_str) != Some("catalog") { return Err("usage: cortetsu-orbital catalog [absolute-wallpaper-root ...] | session".into()); }
    let home = common::home();
    let mut libraries = BTreeSet::new();
    let mut roots = Vec::new();
    let mut errors = Vec::new();
    for relative in [".local/share/Steam", ".steam/steam", ".steam/root", ".var/app/com.valvesoftware.Steam/.local/share/Steam"] {
        let candidate = home.join(relative);
        let Ok(root) = candidate.canonicalize() else { continue; };
        if !libraries.insert(root.clone()) { continue; }
        let vdf = root.join("steamapps/libraryfolders.vdf");
        if vdf.exists() {
            match read_small(&vdf).and_then(|text| library_paths(&text)) {
                Ok(paths) => { for path in paths { if let Ok(path) = path.canonicalize() { libraries.insert(path); } } },
                Err(e) => errors.push(json!({"path": vdf, "error": e.to_string()})),
            }
        }
    }
    let assets: Vec<_> = libraries.iter().map(|p| p.join("steamapps/common/wallpaper_engine/assets")).filter(|p| p.is_dir()).collect();
    for library in libraries { let root = library.join("steamapps/workshop/content/431960"); if root.is_dir() { roots.push((root, "steam")); } }
    for argument in &args[1..] {
        let path = PathBuf::from(argument);
        if !path.is_absolute() { return Err("custom roots must be absolute paths".into()); }
        roots.push((path, "custom"));
    }
    let mut entries = Vec::new();
    let mut catalog_bytes = 0usize;
    let mut seen = BTreeSet::new();
    'roots: for (root, source) in roots {
        let children = match fs::read_dir(&root) { Ok(children) => children, Err(e) => { errors.push(json!({"path": root, "error": e.to_string()})); continue; } };
        for (index, child) in children.take(MAX_ITEMS + 1).enumerate() {
            if index == MAX_ITEMS { errors.push(json!({"path": root, "error": "directory entry limit reached (20000)"})); break; }
            if entries.len() >= MAX_ITEMS { errors.push(json!({"path": root, "error": "catalog limit reached (20000)"})); break; }
            let child = match child { Ok(child) => child, Err(e) => { errors.push(json!({"path": root, "error": e.to_string()})); continue; } };
            let path = match child.path().canonicalize() { Ok(path) => path, Err(e) => { errors.push(json!({"path": child.path(), "error": e.to_string()})); continue; } };
            if path.is_dir() && seen.insert(path.clone()) {
                let entry = item(&path, source);
                let bytes = serde_json::to_vec(&entry)?.len();
                if bytes > MAX_CATALOG_BYTES.saturating_sub(catalog_bytes) {
                    errors.push(json!({"path": root, "error": "catalog metadata limit reached (16 MiB)"}));
                    break 'roots;
                }
                catalog_bytes += bytes;
                entries.push(entry);
            }
        }
    }
    entries.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    println!("{}", json!({"schemaVersion": 1, "entries": entries, "assets": assets, "errors": errors}));
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reads_modern_and_legacy_libraries() {
        let paths = library_paths(r#""libraryfolders" { "0" { "path" "/home/user/Steam" "apps" { "431960" "1" } } "1" "/mnt/games" }"#).unwrap();
        assert_eq!(paths, vec![PathBuf::from("/home/user/Steam"), PathBuf::from("/mnt/games")]);
    }
    #[test]
    fn rejects_truncated_vdf() { assert!(library_paths("\"libraryfolders\" {").is_err()); }
    #[test]
    fn rejects_escape_resources() {
        let dir = tempfile::tempdir().unwrap();
        assert!(local_resource(dir.path(), Some("../preview.png")).is_none());
        assert!(local_resource(dir.path(), Some("/etc/passwd")).is_none());
    }
    #[test]
    fn malformed_metadata_remains_visible() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("project.json"), "broken").unwrap();
        assert_eq!(item(dir.path(), "custom")["compatibility"], "read-error");
    }
}
