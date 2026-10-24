use fs2::FileExt;
use nix::{
    sys::signal::{Signal, killpg},
    unistd::{Pid, Uid},
};
use serde_json::{Value, json};
use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::unix::{fs::OpenOptionsExt, net::UnixStream, process::CommandExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
pub type Result<T> = std::result::Result<T, String>;
static SEQUENCE: AtomicU64 = AtomicU64::new(0);
static CANCELLATION: std::sync::OnceLock<Arc<std::sync::atomic::AtomicBool>> =
    std::sync::OnceLock::new();
static REQUEST_DEADLINE: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();
// Read end of a self-pipe: SIGTERM/SIGINT write a byte to it, so a wait can
// block in read() until the timeout or the signal instead of polling a flag.
static WAKE: std::sync::OnceLock<UnixStream> = std::sync::OnceLock::new();
pub fn init_signals() -> Result<()> {
    let flag = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let (reader, writer) = UnixStream::pair().map_err(|e| e.to_string())?;
    writer.set_nonblocking(true).map_err(|e| e.to_string())?;
    for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(signal, flag.clone()).map_err(|e| e.to_string())?;
        let writer = writer.try_clone().map_err(|e| e.to_string())?;
        signal_hook::low_level::pipe::register(signal, writer).map_err(|e| e.to_string())?;
    }
    let _ = CANCELLATION.set(flag);
    let _ = WAKE.set(reader);
    Ok(())
}
pub fn cancelled() -> bool {
    CANCELLATION
        .get()
        .is_some_and(|f| f.load(Ordering::Relaxed))
}
pub fn deadline_expired() -> bool {
    REQUEST_DEADLINE.get().is_some_and(|d| Instant::now() >= *d)
}
pub fn set_deadline(ms: u64) {
    let _ = REQUEST_DEADLINE.set(Instant::now() + Duration::from_millis(ms));
}
/// Sleeps `seconds`, returning false as soon as SIGTERM/SIGINT arrives or
/// the request deadline passes. With init_signals() it blocks until one of
/// those happens (an idle watcher wakes once per period); without it, it
/// falls back to 50 ms slices.
pub fn wait_interruptible(seconds: f64) -> bool {
    let end = Instant::now() + Duration::from_secs_f64(seconds.max(0.));
    loop {
        if cancelled() || deadline_expired() {
            return false;
        }
        let now = Instant::now();
        let mut left = end.saturating_duration_since(now);
        if let Some(deadline) = REQUEST_DEADLINE.get() {
            left = left.min(deadline.saturating_duration_since(now));
        }
        if left.is_zero() {
            return !(cancelled() || deadline_expired());
        }
        match WAKE.get() {
            Some(mut wake) => {
                // A zero timeout would mean "block forever".
                let _ = wake.set_read_timeout(Some(left.max(Duration::from_millis(1))));
                // EOF cannot happen while signal-hook holds the writers; if it
                // did, sleeping keeps the loop from spinning.
                if let Ok(0) = wake.read(&mut [0u8; 64]) {
                    thread::sleep(left.min(Duration::from_millis(50)));
                }
            }
            None => thread::sleep(left.min(Duration::from_millis(50))),
        }
    }
}
pub fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/nonexistent"))
}
pub fn runtime() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", Uid::current())))
}
pub fn sysfs() -> PathBuf {
    env::var_os("CORTETSU_SYSFS_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| "/sys".into())
}
pub fn procfs() -> PathBuf {
    env::var_os("CORTETSU_PROCFS_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| "/proc".into())
}
pub fn state_home() -> PathBuf {
    env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".local/state"))
}
pub fn config_home() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
}
pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
pub fn monotonic() -> f64 {
    read(&procfs().join("uptime"))
        .split_whitespace()
        .next()
        .and_then(|x| x.parse().ok())
        .unwrap_or_else(now)
}
pub fn read(path: &Path) -> String {
    fs::read(path)
        .map(|x| String::from_utf8_lossy(&x).trim().to_string())
        .unwrap_or_default()
}
pub fn read_default(path: &Path, default: &str) -> String {
    fs::read(path)
        .map(|x| String::from_utf8_lossy(&x).trim().to_string())
        .unwrap_or_else(|_| default.into())
}
pub fn number(path: &Path, scale: f64) -> Option<f64> {
    read(path)
        .parse::<f64>()
        .ok()
        .filter(|x| x.is_finite())
        .map(|x| x / scale)
}
pub fn integer(path: &Path) -> Option<i64> {
    read(path).parse().ok()
}
pub fn children(path: &Path) -> Vec<PathBuf> {
    let mut x = fs::read_dir(path)
        .map(|x| {
            x.filter_map(|e| e.ok().map(|e| e.path()))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    x.sort();
    x
}
pub fn basename(path: &Path) -> String {
    path.file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string()
}
pub fn json_file(path: &Path, default: Value) -> Value {
    fs::read(path)
        .ok()
        .and_then(|x| serde_json::from_slice::<Value>(&x).ok())
        .filter(|x| x.is_object() == default.is_object() && x.is_array() == default.is_array())
        .unwrap_or(default)
}
pub fn lock(path: &Path) -> Result<File> {
    if let Some(p) = path.parent() {
        fs::create_dir_all(p).map_err(|e| e.to_string())?;
    }
    let f = OpenOptions::new()
        .create(true)
        .append(true)
        .read(true)
        .mode(0o600)
        .custom_flags(nix::libc::O_NOFOLLOW)
        .open(path)
        .map_err(|e| e.to_string())?;
    loop {
        if cancelled() || deadline_expired() {
            return Err("lock cancelled or deadline exceeded".into());
        }
        match f.try_lock_exclusive() {
            Ok(()) => break,
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(5))
            }
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok(f)
}
pub fn atomic(path: &Path, data: &[u8]) -> Result<()> {
    let parent = path.parent().ok_or("path has no parent")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let tmp = parent.join(format!(
        ".{}.{}.{}.tmp",
        basename(path),
        std::process::id(),
        SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut f = OpenOptions::new()
            .create_new(true)
            .write(true)
            .mode(0o600)
            .open(&tmp)
            .map_err(|e| e.to_string())?;
        f.write_all(data)
            .and_then(|_| f.sync_all())
            .map_err(|e| e.to_string())?;
        if let Ok(m) = fs::metadata(path) {
            fs::set_permissions(&tmp, m.permissions()).map_err(|e| e.to_string())?;
        }
        fs::rename(&tmp, path).map_err(|e| e.to_string())?;
        File::open(parent)
            .and_then(|f| f.sync_all())
            .map_err(|e| e.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(tmp);
    }
    result
}
pub fn atomic_json(path: &Path, value: &Value) -> Result<()> {
    atomic(path, &serde_json::to_vec(value).map_err(|e| e.to_string())?)
}
pub fn remove(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => {
            if let Some(p) = path.parent() {
                File::open(p)
                    .and_then(|x| x.sync_all())
                    .map_err(|e| e.to_string())?;
            }
            Ok(())
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}
#[derive(Debug)]
pub struct Output {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}
impl Output {
    pub fn detail(&self) -> String {
        if self.stderr.is_empty() {
            self.stdout.trim().into()
        } else {
            self.stderr.trim().into()
        }
    }
}
pub fn run(program: &str, args: &[String], seconds: f64) -> Result<Output> {
    let mut c = Command::new(program);
    c.args(args);
    run_command(c, seconds)
}
pub fn run_str(program: &str, args: &[&str], seconds: f64) -> Result<Output> {
    run(
        program,
        &args.iter().map(|s| s.to_string()).collect::<Vec<_>>(),
        seconds,
    )
}
pub fn run_command(mut command: Command, seconds: f64) -> Result<Output> {
    if cancelled() || deadline_expired() {
        return Err("command cancelled or deadline exceeded".into());
    }
    let mut child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .spawn()
        .map_err(|e| e.to_string())?;
    let pid = Pid::from_raw(child.id() as i32);
    let out = child.stdout.take().unwrap();
    let err = child.stderr.take().unwrap();
    let limit = 8 * 1024 * 1024u64;
    let overflow = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let collect = |mut pipe: Box<dyn Read + Send>, flag: Arc<std::sync::atomic::AtomicBool>| {
        thread::spawn(move || {
            let mut data = Vec::new();
            let mut buf = [0; 8192];
            while let Ok(n) = pipe.read(&mut buf) {
                if n == 0 {
                    break;
                }
                if data.len() as u64 + n as u64 > limit {
                    flag.store(true, Ordering::Relaxed);
                    break;
                }
                data.extend_from_slice(&buf[..n]);
            }
            String::from_utf8_lossy(&data).to_string()
        })
    };
    let out = collect(Box::new(out), overflow.clone());
    let err = collect(Box::new(err), overflow.clone());
    let deadline = Instant::now() + Duration::from_secs_f64(seconds);
    let status: Result<std::process::ExitStatus> = loop {
        if let Some(s) = child.try_wait().map_err(|e| e.to_string())? {
            let _ = killpg(pid, Signal::SIGKILL);
            break Ok(s);
        }
        if Instant::now() >= deadline
            || overflow.load(Ordering::Relaxed)
            || cancelled()
            || deadline_expired()
        {
            let _ = killpg(pid, Signal::SIGKILL);
            let _ = child.kill();
            let _ = child.wait();
            break Err("command exceeded deadline or output limit".into());
        }
        thread::sleep(Duration::from_millis(5));
    };
    let stdout = out.join().unwrap_or_default();
    let stderr = err.join().unwrap_or_default();
    let status = status?;
    Ok(Output {
        code: status.code().unwrap_or(1),
        stdout,
        stderr,
    })
}
pub fn which(name: &str) -> Option<PathBuf> {
    if name.contains('/') {
        let p = PathBuf::from(name);
        return p.is_file().then_some(p);
    }
    env::split_paths(&env::var_os("PATH").unwrap_or_default())
        .map(|p| p.join(name))
        .find(|p| p.is_file())
}
pub fn hypr(args: &[&str], timeout: f64) -> Result<Output> {
    run_str(
        &env::var("CORTETSU_HYPRCTL").unwrap_or_else(|_| "hyprctl".into()),
        args,
        timeout,
    )
}
pub fn hypr_json(args: &[&str]) -> Value {
    hypr(args, 3.)
        .ok()
        .filter(|r| r.code == 0)
        .and_then(|r| serde_json::from_str(&r.stdout).ok())
        .unwrap_or(Value::Null)
}
pub fn s(v: &Value) -> String {
    match v {
        Value::String(x) => x.clone(),
        Value::Null => "None".into(),
        Value::Bool(true) => "True".into(),
        Value::Bool(false) => "False".into(),
        x => x.to_string(),
    }
}
pub fn text(v: &Value, key: &str, default: &str) -> String {
    v.get(key).map(s).unwrap_or_else(|| default.into())
}
pub fn truth(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64() != Some(0.),
        Value::String(s) => !s.is_empty(),
        Value::Array(x) => !x.is_empty(),
        Value::Object(x) => !x.is_empty(),
    }
}
pub fn as_i(v: &Value) -> Option<i64> {
    v.as_i64()
        .or_else(|| v.as_f64().filter(|x| x.is_finite()).map(|x| x as i64))
        .or_else(|| v.as_str().and_then(|x| x.parse().ok()))
        .or_else(|| v.as_bool().map(i64::from))
}
pub fn as_f(v: &Value) -> Option<f64> {
    v.as_f64()
        .or_else(|| v.as_str().and_then(|x| x.parse().ok()))
        .or_else(|| v.as_bool().map(|x| if x { 1. } else { 0. }))
}
pub fn f(v: &Value, key: &str, default: f64) -> f64 {
    v.get(key).and_then(as_f).unwrap_or(default)
}
pub fn i(v: &Value, key: &str, default: i64) -> i64 {
    v.get(key).and_then(as_i).unwrap_or(default)
}
pub fn round(n: f64, decimals: i32) -> Value {
    if !n.is_finite() {
        Value::Null
    } else {
        let p = 10f64.powi(decimals);
        json!((n * p).round() / p)
    }
}
pub fn flag<'a>(args: &'a [String], key: &str) -> Option<&'a str> {
    args.windows(2).find(|x| x[0] == key).map(|x| x[1].as_str())
}
pub fn json_error(error: String) -> (Value, i32) {
    (json!({"ok":false,"error":error}), 2)
}
pub fn nonce() -> String {
    let mut bytes = [0; 16];
    if File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .is_ok()
    {
        bytes.iter().map(|x| format!("{x:02x}")).collect()
    } else {
        format!(
            "{:x}{:x}{:x}",
            now().to_bits(),
            std::process::id(),
            SEQUENCE.fetch_add(1, Ordering::Relaxed)
        )
    }
}
pub fn timestamp() -> String {
    run_str("date", &["+%Y%m%d-%H%M%S"], 1.)
        .ok()
        .filter(|x| x.code == 0)
        .map(|x| x.stdout.trim().to_string())
        .unwrap_or_else(|| format!("{}", now() as u64))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn orphaned_subprocess_pipe_cannot_outlive_deadline() {
        let started = Instant::now();
        let _ = run_str("sh", &["-c", "sleep 3 & exit 0"], 0.1);
        assert!(
            started.elapsed() < Duration::from_millis(600),
            "descendant retained a pipe after command exit"
        );
    }
}
