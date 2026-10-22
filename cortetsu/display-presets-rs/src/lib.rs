//! Named display presets, **not** a display controller. It never calls
//! `hyprctl` or writes to monitors: save delegates to the existing validating
//! planner with a fixed argv, timeout, and no shell. Opt-in until parity and
//! owner/readback checks pass on a real Hyprland session.
use fs2::FileExt;
use serde_json::{Map, Value, json};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Debug)]
pub struct Failure(pub String);
type Result<T> = std::result::Result<T, Failure>;
fn failed(message: &str) -> Failure {
    Failure(message.into())
}

pub struct Paths {
    pub config: PathBuf,
    pub planner: PathBuf,
}
impl Paths {
    pub fn from_env(executable: &Path) -> Result<Self> {
        let home = std::env::var_os("HOME").ok_or_else(|| failed("missing HOME"))?;
        let config = std::env::var_os("CORTETSU_DISPLAY_PRESETS_CONFIG")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(home).join(".config/cortetsu/display-presets.json"));
        let planner = std::env::var_os("CORTETSU_DISPLAY_PLANNER")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                executable
                    .parent()
                    .unwrap_or(Path::new("/nonexistent"))
                    .join("cortetsu-display-plan")
            });
        if !config.is_absolute() || !planner.is_absolute() {
            return Err(failed("paths must be absolute"));
        }
        Ok(Self { config, planner })
    }
}

fn read_data(path: &Path) -> Map<String, Value> {
    if let Ok(raw) = fs::read(path)
        && let Ok(Value::Object(map)) = serde_json::from_slice::<Value>(&raw)
    {
        return map;
    }
    let mut default = Map::new();
    default.insert("version".into(), json!(1));
    default.insert("presets".into(), json!({}));
    default
}
fn presets(data: &mut Map<String, Value>) -> &mut Map<String, Value> {
    let valid = data.get("presets").and_then(Value::as_object).is_some();
    if !valid {
        data.insert("presets".into(), json!({}));
    }
    data.get_mut("presets")
        .and_then(Value::as_object_mut)
        .expect("just initialized")
}
fn name_is_safe(name: &str) -> bool {
    let count = name.chars().count();
    count > 0
        && count <= 40
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b' ' || b == b'_' || b == b'.' || b == b'-')
}
fn normalize_name(s: &str) -> Result<String> {
    let n = s.trim();
    if !name_is_safe(n) {
        return Err(failed("preset name must be 1..40 safe characters"));
    }
    Ok(n.into())
}
fn synced_parent(path: &Path) -> Result<()> {
    File::open(path)
        .and_then(|f| f.sync_all())
        .map_err(|_| failed("cannot sync config directory"))
}
fn save(path: &Path, data: &Map<String, Value>) -> Result<()> {
    let parent = path.parent().ok_or_else(|| failed("invalid config path"))?;
    fs::create_dir_all(parent).map_err(|_| failed("cannot create config directory"))?;
    if let Ok(meta) = fs::symlink_metadata(path)
        && (meta.file_type().is_symlink() || !meta.is_file())
    {
        return Err(failed("unsafe config file"));
    }
    let key = path
        .file_name()
        .ok_or_else(|| failed("invalid config name"))?
        .to_string_lossy();
    let tmp = parent.join(format!(".{key}.{}.tmp", std::process::id()));
    let bytes = serde_json::to_vec(data).map_err(|_| failed("cannot serialize presets"))?;
    let mut f = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&tmp)
        .map_err(|_| failed("cannot create staging file"))?;
    let result = (|| {
        f.write_all(&bytes)
            .and_then(|_| f.sync_all())
            .map_err(|_| failed("cannot save presets"))?;
        fs::rename(&tmp, path).map_err(|_| failed("cannot publish presets"))?;
        synced_parent(parent)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}
fn acquire_lock(path: &Path) -> Result<File> {
    let parent = path
        .parent()
        .ok_or_else(|| failed("missing config directory"))?;
    fs::create_dir_all(parent).map_err(|_| failed("cannot create config directory"))?;
    let lock = parent.join(".display-presets-rs.lock");
    if let Ok(meta) = fs::symlink_metadata(&lock)
        && (meta.file_type().is_symlink() || !meta.is_file())
    {
        return Err(failed("unsafe presets lock"));
    }
    let f = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(lock)
        .map_err(|_| failed("cannot open presets lock"))?;
    f.lock_exclusive()
        .map_err(|_| failed("cannot lock presets"))?;
    Ok(f)
}
fn validate_candidate(planner: &Path, candidate: &Value) -> Result<Value> {
    if !candidate.is_object() {
        return Err(failed("candidate must be an object"));
    }
    let raw = serde_json::to_string(candidate).map_err(|_| failed("invalid candidate"))?;
    let mut child = Command::new(planner)
        .arg("--candidate")
        .arg(raw)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|_| failed("display planner unavailable"))?;
    let start = Instant::now();
    loop {
        let status = child
            .try_wait()
            .map_err(|_| failed("cannot wait for display planner"))?;
        if status.is_some() {
            break;
        }
        if start.elapsed() > Duration::from_secs(12) {
            let _ = child.kill();
            let _ = child.wait();
            return Err(failed("display planner timed out"));
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    let output = child
        .wait_with_output()
        .map_err(|_| failed("cannot collect display planner"))?;
    if output.stdout.len() > 128 * 1024 {
        return Err(failed("planner response too large"));
    }
    if output.status.code() != Some(0) && output.status.code() != Some(3) {
        return Err(failed("display planner failed"));
    }
    let parsed: Value = serde_json::from_slice(&output.stdout)
        .map_err(|_| failed("display planner returned invalid JSON"))?;
    if parsed.get("ok") != Some(&Value::Bool(true)) {
        return Err(failed("candidate is not valid"));
    }
    Ok(parsed
        .get("candidate")
        .cloned()
        .unwrap_or_else(|| candidate.clone()))
}
fn truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null) | Some(Value::Bool(false)) => false,
        Some(Value::Number(n)) => n.as_i64() != Some(0),
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(a)) => !a.is_empty(),
        Some(Value::Object(m)) => !m.is_empty(),
        _ => true,
    }
}
/// stdout/value and process code, matching the historical command names.
/// A parsed error is a JSON object (the caller prints it and exits with 2).
pub fn run(args: &[String], paths: &Paths) -> (Value, u8) {
    let result = (|| -> Result<(Value, u8)> {
        let mut data = read_data(&paths.config);
        if args.len() == 1 && args[0] == "list" {
            let mut items = Vec::<Value>::new();
            for (name, value) in presets(&mut data).iter() {
                if let Value::Object(map) = value {
                    let mut item = map.clone();
                    item.insert("name".into(), Value::String(name.clone()));
                    items.push(Value::Object(item));
                }
            }
            items.sort_by_key(|v| v["name"].as_str().unwrap_or("").to_lowercase());
            return Ok((
                json!({"ok":true,"presets":items,"config":paths.config.to_string_lossy()}),
                0,
            ));
        }
        let (command, name, extra) = match args {
            [command, a, b] if (command == "get" || command == "delete") && a == "--name" => {
                (command.as_str(), b.as_str(), None)
            }
            [command, a, b, c, d] if command == "save" && a == "--name" && c == "--candidate" => {
                (command.as_str(), b.as_str(), Some(d.as_str()))
            }
            _ => {
                return Err(failed(
                    "usage: cortetsu-display-presets list|get --name NAME|save --name NAME --candidate JSON|delete --name NAME",
                ));
            }
        };
        let name = normalize_name(name)?;
        if command == "get" {
            let item = presets(&mut data).get(&name);
            let found = truthy(item);
            return Ok((
                json!({"ok":found,"name":name,"preset":if found{item.cloned().unwrap_or_else(||json!({}))}else{json!({})},"error":if found{""}else{"preset not found"}}),
                if found { 0 } else { 2 },
            ));
        }
        let _guard = acquire_lock(&paths.config)?;
        // Re-read after acquiring the Rust writer lock; active Python and
        // Quickshell users are not using this lock yet, so no cutover.
        data = read_data(&paths.config);
        if command == "delete" {
            let removed = presets(&mut data).remove(&name).is_some();
            save(&paths.config, &data)?;
            return Ok((json!({"ok":true,"deleted":removed,"name":name}), 0));
        }
        let candidate: Value =
            serde_json::from_str(extra.ok_or_else(|| failed("missing candidate"))?)
                .map_err(|_| failed("invalid candidate JSON"))?;
        let normalized = validate_candidate(&paths.planner, &candidate)?;
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| failed("invalid clock"))?
            .as_secs();
        let entry = json!({"candidate":normalized,"saved_at":timestamp});
        presets(&mut data).insert(name.clone(), entry.clone());
        data.insert("version".into(), json!(1));
        save(&paths.config, &data)?;
        Ok((
            json!({"ok":true,"saved":true,"name":name,"preset":entry}),
            0,
        ))
    })();
    match result {
        Ok((v, c)) => (v, c),
        Err(e) => (json!({"ok":false,"error":e.0}), 2),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    struct Sandbox(PathBuf);
    impl Sandbox {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "cortetsu-presets-rs-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
        fn paths(&self) -> Paths {
            Paths {
                config: self.0.join("display-presets.json"),
                planner: self.0.join("nonexistent-planner"),
            }
        }
    }
    impl Drop for Sandbox {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn argv(args: &[&str]) -> Vec<String> {
        args.iter().map(|s| s.to_string()).collect()
    }
    #[test]
    fn missing_config_is_read_only_until_explicit_delete() {
        let home = Sandbox::new();
        let paths = home.paths();
        let (answer, code) = run(&argv(&["list"]), &paths);
        assert_eq!(code, 0);
        assert!(answer["presets"].as_array().unwrap().is_empty());
        assert!(!paths.config.exists());
        let (answer, code) = run(&argv(&["get", "--name", "nope"]), &paths);
        assert_eq!(code, 2);
        assert_eq!(answer["error"], "preset not found");
        assert!(!paths.config.exists());
        let (_, code) = run(&argv(&["delete", "--name", "nope"]), &paths);
        assert_eq!(code, 0);
        assert!(paths.config.is_file());
    }
    #[test]
    fn does_not_follow_config_symlink() {
        let home = Sandbox::new();
        let paths = home.paths();
        let secret = home.0.join("other.json");
        fs::write(&secret, "PRIVATE").unwrap();
        std::os::unix::fs::symlink(&secret, &paths.config).unwrap();
        let (answer, code) = run(&argv(&["delete", "--name", "example"]), &paths);
        assert_eq!(code, 2);
        assert_eq!(answer["ok"], false);
        assert_eq!(fs::read_to_string(&secret).unwrap(), "PRIVATE");
    }
    #[test]
    fn illegal_names_and_non_objects_are_rejected() {
        let home = Sandbox::new();
        let paths = home.paths();
        for bad in ["../bad", "/absolute", "x?", ""] {
            let (_, code) = run(&argv(&["delete", "--name", bad]), &paths);
            assert_eq!(code, 2);
        }
        let (_, code) = run(
            &argv(&["save", "--name", "example", "--candidate", "[]"]),
            &paths,
        );
        assert_eq!(code, 2);
        assert!(!paths.config.exists());
    }
}
