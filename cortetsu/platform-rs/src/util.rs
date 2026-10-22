use fs2::FileExt;
use serde_json::Value;
use std::{
    collections::BTreeMap,
    env,
    error::Error,
    fs::{self, File, OpenOptions},
    io::Write,
    os::unix::fs::{OpenOptionsExt, PermissionsExt, symlink},
    path::{Component, Path, PathBuf},
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};
pub type Result<T> = std::result::Result<T, Box<dyn Error>>;
pub fn fail<T>(msg: impl Into<String>) -> Result<T> {
    Err(std::io::Error::other(msg.into()).into())
}
pub fn home() -> Result<PathBuf> {
    let p = PathBuf::from(env::var_os("HOME").ok_or("HOME is required")?);
    if !p.is_absolute() {
        return fail("HOME must be absolute");
    }
    Ok(p)
}
pub fn expand(s: impl AsRef<Path>) -> Result<PathBuf> {
    let p = s.as_ref();
    let t = p.to_string_lossy();
    if t == "~" {
        home()
    } else if let Some(rest) = t.strip_prefix("~/") {
        Ok(home()?.join(rest))
    } else {
        Ok(p.to_path_buf())
    }
}
pub fn env_path(name: &str, default: PathBuf) -> Result<PathBuf> {
    let p = expand(env::var_os(name).map(PathBuf::from).unwrap_or(default))?;
    if !p.is_absolute() {
        return fail(format!("{name} must be absolute"));
    }
    Ok(p)
}
pub fn config_home() -> Result<PathBuf> {
    env_path("XDG_CONFIG_HOME", home()?.join(".config"))
}
pub fn data_root() -> Result<PathBuf> {
    env_path(
        "CORTETSU_DATA_ROOT",
        env_path("XDG_DATA_HOME", home()?.join(".local/share"))?.join("cortetsu"),
    )
}
pub fn runtime_root() -> Result<PathBuf> {
    env_path(
        "CORTETSU_RUNTIME_ROOT",
        config_home()?.join("quickshell/cortetsu"),
    )
}
pub fn roots() -> Result<cortetsu_rescue::Roots> {
    Ok(cortetsu_rescue::Roots {
        data: data_root()?,
        runtime: runtime_root()?,
    })
}
pub fn stamp() -> String {
    Command::new("date")
        .args(["-u", "+%Y%m%d-%H%M%S"])
        .output()
        .ok()
        .filter(|x| x.status.success())
        .map(|x| String::from_utf8_lossy(&x.stdout).trim().to_owned())
        .unwrap_or_else(|| {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs()
                .to_string()
        })
}
pub fn unique() -> String {
    format!(
        "{}-{}-{}",
        stamp(),
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .subsec_nanos()
    )
}
pub fn timestamp() -> String {
    Command::new("date")
        .args(["-u", "+%Y-%m-%dT%H:%M:%S+00:00"])
        .output()
        .ok()
        .filter(|x| x.status.success())
        .map(|x| String::from_utf8_lossy(&x.stdout).trim().to_owned())
        .unwrap_or_else(stamp)
}
pub fn json(path: &Path) -> Result<Value> {
    if fs::metadata(path)?.len() > 4 * 1024 * 1024 {
        return fail(format!("oversized metadata: {}", path.display()));
    }
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}
pub fn toml_json(path: &Path) -> Result<Value> {
    let v: toml::Value = fs::read_to_string(path)?.parse()?;
    Ok(serde_json::to_value(v)?)
}
pub fn atomic_write(path: &Path, data: impl AsRef<[u8]>, mode: u32) -> Result<()> {
    let parent = path.parent().ok_or("no parent")?;
    fs::create_dir_all(parent)?;
    let tmp = parent.join(format!(
        ".{}.tmp.{}",
        path.file_name().ok_or("no filename")?.to_string_lossy(),
        unique()
    ));
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .open(&tmp)?;
        file.write_all(data.as_ref())?;
        file.sync_all()?;
        fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))?;
        fs::rename(&tmp, path)?;
        File::open(parent)?.sync_all()?;
        Ok(())
    })();
    let _ = fs::remove_file(&tmp);
    result
}
pub fn write_json(path: &Path, value: &Value) -> Result<()> {
    let mut b = serde_json::to_vec_pretty(value)?;
    b.push(b'\n');
    atomic_write(path, b, 0o600)
}
pub fn atomic_link(target: &Path, link: &Path) -> Result<()> {
    let parent = link.parent().ok_or("no link parent")?;
    fs::create_dir_all(parent)?;
    let tmp = parent.join(format!(
        ".{}.tmp.{}",
        link.file_name().ok_or("no filename")?.to_string_lossy(),
        unique()
    ));
    symlink(target, &tmp)?;
    let result = fs::rename(&tmp, link);
    let _ = fs::remove_file(&tmp);
    result?;
    File::open(parent)?.sync_all()?;
    Ok(())
}
pub fn resolve_link(path: &Path) -> Option<PathBuf> {
    if path.is_symlink() {
        fs::canonicalize(path).ok()
    } else {
        None
    }
}
pub fn restore_link(path: &Path, target: &Option<PathBuf>) -> Result<()> {
    if let Some(t) = target {
        atomic_link(t, path)
    } else {
        if path.is_symlink() {
            fs::remove_file(path)?;
        }
        Ok(())
    }
}
pub fn safe_relative(s: &str) -> Result<PathBuf> {
    let p = PathBuf::from(s);
    if s.is_empty()
        || s == "."
        || p.is_absolute()
        || p.components().any(|x| {
            matches!(
                x,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return fail(format!("ruta no permitida en manifest: {s}"));
    }
    Ok(p)
}
pub fn copy_path(source: &Path, dest: &Path) -> Result<()> {
    fs::create_dir_all(dest.parent().ok_or("no parent")?)?;
    let m = fs::symlink_metadata(source)?;
    if m.file_type().is_symlink() {
        symlink(fs::read_link(source)?, dest)?;
    } else if m.is_dir() {
        fs::create_dir(dest)?;
        let mut children = fs::read_dir(source)?.collect::<std::result::Result<Vec<_>, _>>()?;
        children.sort_by_key(|x| x.file_name());
        for child in children {
            copy_path(&child.path(), &dest.join(child.file_name()))?;
        }
        fs::set_permissions(dest, m.permissions())?;
    } else if m.is_file() {
        fs::copy(source, dest)?;
        fs::set_permissions(dest, m.permissions())?;
    } else {
        return fail("non-regular source");
    }
    Ok(())
}
pub fn remove_path(p: &Path) -> Result<()> {
    match fs::symlink_metadata(p) {
        Ok(m) if m.is_dir() => fs::remove_dir_all(p)?,
        Ok(_) => fs::remove_file(p)?,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e.into()),
    }
    Ok(())
}
pub fn lock(path: &Path, nonblocking: bool) -> Result<File> {
    fs::create_dir_all(path.parent().ok_or("lock parent")?)?;
    if path.is_symlink() {
        return fail("lock is a symlink");
    }
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(path)?;
    if nonblocking {
        f.try_lock_exclusive()?;
    } else {
        FileExt::lock_exclusive(&f)?;
    }
    Ok(f)
}
pub fn revision(repo: &Path) -> String {
    Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()
        .filter(|x| x.status.success())
        .map(|x| String::from_utf8_lossy(&x.stdout).trim().to_owned())
        .unwrap_or_else(|| "unknown".into())
}
pub fn strings(v: &Value) -> Vec<String> {
    v.as_array()
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default()
}
pub fn which(cmd: &str) -> Option<PathBuf> {
    env::split_paths(&env::var_os("PATH")?)
        .map(|p| p.join(cmd))
        .find(|p| fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0))
}
#[derive(Default)]
pub struct Args {
    pub positional: Vec<String>,
    pub opts: BTreeMap<String, Vec<String>>,
}
impl Args {
    pub fn parse(values: &[String]) -> Result<Self> {
        let mut r = Self::default();
        let mut i = 0;
        while i < values.len() {
            let s = &values[i];
            if let Some(key) = s.strip_prefix("--") {
                if let Some((key, v)) = key.split_once('=') {
                    r.opts.entry(key.into()).or_default().push(v.into());
                } else if [
                    "json",
                    "apply",
                    "dry-run",
                    "archive",
                    "commit",
                    "check",
                    "strict",
                    "historical",
                ]
                .contains(&key)
                {
                    r.opts.entry(key.into()).or_default().push("true".into());
                } else {
                    i += 1;
                    r.opts
                        .entry(key.into())
                        .or_default()
                        .push(values.get(i).ok_or("missing flag value")?.clone());
                }
            } else {
                r.positional.push(s.clone());
            }
            i += 1;
        }
        Ok(r)
    }
    pub fn get(&self, key: &str) -> Option<&str> {
        self.opts.get(key)?.last().map(String::as_str)
    }
    pub fn has(&self, key: &str) -> bool {
        self.opts.contains_key(key)
    }
    pub fn action(&self, default: &str) -> String {
        self.positional
            .first()
            .cloned()
            .unwrap_or_else(|| default.into())
    }
    pub fn repo(&self) -> Result<PathBuf> {
        let p = self
            .get("repo")
            .map(PathBuf::from)
            .or_else(|| env::var_os("CORTETSU_REPO_ROOT").map(PathBuf::from))
            .unwrap_or(env::current_dir()?);
        Ok(fs::canonicalize(expand(p)?)?)
    }
    pub fn home(&self) -> Result<PathBuf> {
        self.get("home").map(expand).unwrap_or_else(home)
    }
    pub fn check(&self, allowed: &[&str]) -> Result<()> {
        for k in self.opts.keys() {
            if !allowed.contains(&k.as_str()) {
                return fail(format!("unknown option --{k}"));
            }
        }
        Ok(())
    }
}
