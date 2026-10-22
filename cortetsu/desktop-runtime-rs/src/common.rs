use fs2::FileExt;
use serde_json::Value;
use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
pub fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}
pub fn xdg(var: &str, fallback: &str) -> PathBuf {
    env::var_os(var)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(fallback))
}
pub fn state() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("cortetsu")
}
pub fn config() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config")
}
pub fn cache() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("cortetsu")
}
pub fn expand(path: &str) -> PathBuf {
    if path == "~" {
        home()
    } else if let Some(p) = path.strip_prefix("~/") {
        home().join(p)
    } else {
        PathBuf::from(path)
    }
}
pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
pub fn json_load(path: &Path, default: Value) -> Value {
    fs::read(path)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or(default)
}
pub fn atomic(path: &Path, data: &[u8], mode: u32) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("path has no parent"))?;
    fs::create_dir_all(parent)?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let tmp = parent.join(format!(
        ".{}.{}.{}.tmp",
        path.file_name().unwrap_or_default().to_string_lossy(),
        std::process::id(),
        nonce
    ));
    let result = (|| {
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .open(&tmp)?;
        f.write_all(data)?;
        f.sync_all()?;
        fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))?;
        fs::rename(&tmp, path)?;
        File::open(parent)?.sync_all()
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}
pub fn json_save(path: &Path, value: &Value) -> Result<()> {
    let mut bytes = serde_json::to_vec_pretty(value)?;
    bytes.push(b'\n');
    atomic(path, &bytes, 0o600)?;
    Ok(())
}
pub fn lock(path: &Path, nonblock: bool) -> io::Result<File> {
    fs::create_dir_all(
        path.parent()
            .ok_or_else(|| io::Error::other("lock parent"))?,
    )?;
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(nix::libc::O_NOFOLLOW | nix::libc::O_CLOEXEC)
        .open(path)?;
    if nonblock {
        f.try_lock_exclusive()?
    } else {
        f.lock_exclusive()?
    }
    Ok(f)
}
pub fn emit(v: &Value) -> Result<()> {
    let mut out = io::stdout().lock();
    serde_json::to_writer(&mut out, v)?;
    out.write_all(b"\n")?;
    Ok(())
}
pub fn which(name: &str) -> Option<PathBuf> {
    let p = Path::new(name);
    if p.components().count() > 1 {
        return executable(p).then(|| p.to_path_buf());
    }
    env::split_paths(&env::var_os("PATH").unwrap_or_default())
        .map(|d| d.join(name))
        .find(|p| executable(p))
}
pub fn executable(p: &Path) -> bool {
    fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}
pub fn run(command: &mut Command, input: Option<&[u8]>, timeout: Duration) -> io::Result<Output> {
    command
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command.spawn()?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| io::Error::other("stdout unavailable"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| io::Error::other("stderr unavailable"))?;
    let reader = |stream: Box<dyn Read + Send>| {
        thread::spawn(move || {
            let mut bytes = Vec::new();
            let _ = stream.take(32 * 1024 * 1024).read_to_end(&mut bytes);
            bytes
        })
    };
    let out = reader(Box::new(stdout));
    let err = reader(Box::new(stderr));
    if let Some(bytes) = input
        && let Some(mut stream) = child.stdin.take()
        && let Err(e) = stream.write_all(bytes)
    {
        let _ = child.kill();
        let _ = child.wait();
        let _ = out.join();
        let _ = err.join();
        return Err(e);
    }
    let start = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait()? {
            break s;
        }
        if start.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            let _ = out.join();
            let _ = err.join();
            return Err(io::Error::new(io::ErrorKind::TimedOut, "command timed out"));
        }
        thread::sleep(Duration::from_millis(10));
    };
    Ok(Output {
        status,
        stdout: out.join().unwrap_or_default(),
        stderr: err.join().unwrap_or_default(),
    })
}
pub fn call(name: &str, args: &[&str], timeout: u64) -> io::Result<Output> {
    run(
        Command::new(name).args(args),
        None,
        Duration::from_secs(timeout),
    )
}
pub fn text(v: &Value) -> &str {
    v.as_str().unwrap_or("")
}
pub fn number(v: &Value) -> f64 {
    v.as_f64()
        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        .unwrap_or(0.0)
}
pub fn integer(v: &Value, fallback: i64) -> i64 {
    match v {
        Value::Bool(b) => i64::from(*b),
        Value::Number(n) => n
            .as_i64()
            .or_else(|| n.as_f64().filter(|v| v.is_finite()).map(|v| v as i64))
            .unwrap_or(fallback),
        Value::String(s) => s.parse().unwrap_or(fallback),
        _ => fallback,
    }
}

/// Immutable generation resources. Explicit source mode is for checkout tools/tests.
pub fn resources() -> PathBuf {
    if let Some(root) = env::var_os("CORTETSU_RESOURCE_ROOT") {
        return PathBuf::from(root);
    }
    if let Some(root) = env::var_os("CORTETSU_REPO_ROOT") {
        return PathBuf::from(root).join("cortetsu");
    }
    let runtime = env::var_os("CORTETSU_RUNTIME_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| config().join("quickshell/cortetsu"));
    runtime
        .join("current")
        .canonicalize()
        .unwrap_or_else(|_| runtime.join("current"))
}
