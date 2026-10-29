//! The link between a native helper and the shell's password dialog
//! (`modules/SecretPromptHost.qml`). For each dialog the helper opens a
//! private 0600 socket, asks the shell over `qs ipc call secretprompt` to
//! connect, and exchanges one JSON line per prompt. Secrets only travel over
//! that socket, never over `qs ipc`, a command line or a log.
use crate::common::Result;
use serde_json::Value;
use std::{
    collections::HashMap,
    env, fs,
    io::{BufRead, BufReader, ErrorKind, Write},
    net::Shutdown,
    os::unix::{
        fs::{DirBuilderExt, PermissionsExt},
        net::{UnixListener, UnixStream},
    },
    path::PathBuf,
    process::Command,
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
        mpsc::{self, RecvTimeoutError},
    },
    thread,
    time::{Duration, Instant},
};
use zeroize::Zeroizing;

// Link ids start at 1; 0 is free for callers to mean "no link".
static LINKS: AtomicU64 = AtomicU64::new(1);

fn shell_path() -> PathBuf {
    env::var_os("CORTETSU_SHELL_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::common::config().join("quickshell/cortetsu/current"))
}

/// Runs `qs ipc call secretprompt <args>` and returns its stdout, or None when
/// no shell answers within `limit`, so a wedged shell never holds a prompt.
/// `qs` exits 0 even for a target the shell lacks ("Target not found."), so
/// callers check the output, not only the exit code.
pub fn qs_ipc(args: &[&std::ffi::OsStr], limit: Duration) -> Option<String> {
    let qs = env::var_os("CORTETSU_QS_BIN").unwrap_or_else(|| "qs".into());
    let mut command = Command::new(qs);
    command
        .arg("-p")
        .arg(shell_path())
        .args(["ipc", "call", "secretprompt"])
        .args(args);
    let out = crate::common::run(&mut command, None, limit).ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

pub fn socket_dir() -> Result<PathBuf> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .filter(|s| !s.is_empty())
        .ok_or("XDG_RUNTIME_DIR is not set")?;
    let dir = PathBuf::from(runtime).join("cortetsu");
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&dir)?;
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;
    Ok(dir)
}

fn random_token() -> Result<String> {
    Ok(crate::sxaes::random(16)?
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

fn accept(listener: &UnixListener, deadline: Instant) -> Result<UnixStream> {
    listener.set_nonblocking(true)?;
    loop {
        match listener.accept() {
            Ok((stream, _)) => {
                stream.set_nonblocking(false)?;
                return Ok(stream);
            }
            Err(e) if e.kind() == ErrorKind::WouldBlock && Instant::now() < deadline => {
                thread::sleep(Duration::from_millis(20));
            }
            Err(e) if e.kind() == ErrorKind::WouldBlock => {
                return Err("the shell did not connect".into());
            }
            Err(e) => return Err(e.into()),
        }
    }
}

/// One shell dialog. Dropping it closes the socket, which closes the dialog.
pub struct ShellLink {
    pub id: u64,
    pub token: String,
    pub stream: UnixStream,
}

impl Drop for ShellLink {
    fn drop(&mut self) {
        let _ = self.stream.shutdown(Shutdown::Both);
    }
}

impl ShellLink {
    /// Opens a dialog and calls `on_answer(id, Some(line))` for each line the
    /// shell writes back, then `on_answer(id, None)` once the socket closes.
    pub fn open(
        prefix: &str,
        on_answer: impl Fn(u64, Option<Value>) + Send + 'static,
    ) -> Result<Self> {
        let token = random_token()?;
        let path = socket_dir()?.join(format!(
            "{prefix}-{}-{}.sock",
            std::process::id(),
            &token[..8]
        ));
        let _ = fs::remove_file(&path);
        let listener = UnixListener::bind(&path)?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
        // `request` returns nothing; a shell that lacks it fails the accept.
        let asked = qs_ipc(
            &["request".as_ref(), path.as_os_str(), token.as_ref()],
            Duration::from_secs(5),
        );
        let stream = if asked.is_some() {
            accept(&listener, Instant::now() + Duration::from_secs(5))
        } else {
            Err("no shell".into())
        };
        let _ = fs::remove_file(&path);
        let stream = stream?;
        let id = LINKS.fetch_add(1, Ordering::Relaxed);
        let reader = stream.try_clone()?;
        thread::spawn(move || {
            for line in BufReader::new(reader).lines() {
                let Ok(line) = line.map(Zeroizing::new) else {
                    break;
                };
                on_answer(id, serde_json::from_str(&line).ok());
            }
            on_answer(id, None);
        });
        Ok(Self { id, token, stream })
    }

    pub fn send(&mut self, request: &Value) -> bool {
        let line = Zeroizing::new(format!("{request}\n"));
        self.stream
            .write_all(line.as_bytes())
            .and_then(|_| self.stream.flush())
            .is_ok()
    }
}

/// Requests that are waiting on a dialog, by caller-chosen key, so a cancel
/// from the client can close the dialog. An entry without a stream is a
/// dialog still opening; cancelling it removes the entry and `ask` gives up.
/// The number tells a request apart from a newer one under the same key.
#[derive(Default)]
pub struct Pending(Mutex<HashMap<String, (u64, Option<UnixStream>)>>);

static ASKS: AtomicU64 = AtomicU64::new(1);

impl Pending {
    fn map(&self) -> std::sync::MutexGuard<'_, HashMap<String, (u64, Option<UnixStream>)>> {
        self.0.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Closes every dialog whose key starts with `prefix`.
    pub fn cancel(&self, prefix: &str) {
        self.map().retain(|key, (_, stream)| {
            if !key.starts_with(prefix) {
                return true;
            }
            if let Some(stream) = stream {
                let _ = stream.shutdown(Shutdown::Both);
            }
            false
        });
    }

    /// Reserves `key` unless a dialog already holds it, in one step, so two
    /// calls racing for the same key never both open a dialog. `ask` takes
    /// the reservation over.
    pub fn claim(&self, key: &str) -> bool {
        let mut map = self.map();
        if map.contains_key(key) {
            return false;
        }
        map.insert(key.to_owned(), (0, None));
        true
    }
}

/// Shows one dialog and waits for its single answer. Returns None when no
/// dialog could be shown, the request was cancelled, `done()` became true, or
/// the answer carried a foreign token. `request` gets the link's token.
pub fn ask(
    mut request: Value,
    key: &str,
    pending: &Pending,
    done: impl Fn() -> bool,
) -> Option<Value> {
    let ask = ASKS.fetch_add(1, Ordering::Relaxed);
    // A newer request under the same key replaces the old dialog.
    if let Some((_, Some(old))) = pending.map().insert(key.to_owned(), (ask, None)) {
        let _ = old.shutdown(Shutdown::Both);
    }
    let ours = |map: &HashMap<String, (u64, Option<UnixStream>)>| {
        map.get(key).is_some_and(|(n, _)| *n == ask)
    };
    let (tx, rx) = mpsc::channel();
    let link = ShellLink::open("agent", move |_, answer| {
        let _ = tx.send(answer);
    });
    let mut link = match link {
        Ok(link) => link,
        Err(e) => {
            eprintln!("cortetsu-agents: {e}");
            let mut map = pending.map();
            if ours(&map) {
                map.remove(key);
            }
            return None;
        }
    };
    {
        let mut map = pending.map();
        if !ours(&map) {
            // Cancelled or replaced while the dialog was opening.
            return None;
        }
        map.insert(key.to_owned(), (ask, link.stream.try_clone().ok()));
    }
    request["token"] = Value::from(link.token.clone());
    let answer = if link.send(&request) {
        loop {
            match rx.recv_timeout(Duration::from_millis(500)) {
                Ok(answer) => break answer,
                Err(RecvTimeoutError::Timeout) if !done() => {}
                Err(_) => break None,
            }
        }
    } else {
        None
    };
    let mut map = pending.map();
    if ours(&map) {
        map.remove(key);
    }
    drop(map);
    answer.filter(|a| a["token"].as_str() == Some(link.token.as_str()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn claim_lets_one_caller_in_and_cancel_frees_the_key() {
        let pending = Pending::default();
        assert!(pending.claim("bt:display:a"));
        assert!(!pending.claim("bt:display:a"));
        assert!(pending.claim("bt:display:b"));
        pending.cancel("bt:display:a");
        assert!(pending.claim("bt:display:a"));
    }
}
