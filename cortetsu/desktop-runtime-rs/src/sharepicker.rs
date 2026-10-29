//! `cortetsu-share-picker`: the screencopy picker that xdg-desktop-portal-hyprland
//! runs through `screencopy:custom_picker_binary`.
//!
//! xdph passes the shareable windows in `XDPH_WINDOW_SHARING_LIST` and reads one
//! `[SELECTION]<flags>/<kind>:<value>` line from stdout. The choice itself is
//! made in the shell (`modules/screenshare`): this helper opens a private 0600
//! socket, asks the shell over `qs ipc` to connect to it, sends the request and
//! waits for one answer line. It composes the selection line itself, so the
//! shell can only pick among the outputs and windows it was offered.
//!
//! Electron and Chromium open several screencast sessions for one share. A
//! choice is reused for the requests that follow it within a few seconds,
//! when what it names is still offered, so one share asks once.
//!
//! Without a running shell it hands over to `hyprland-share-picker`, so screen
//! sharing never depends on the shell being up. A cancel or a 60 s timeout
//! exits non-zero and prints nothing, which xdph reports as a refused request.
use crate::common::Result;
use serde_json::{Value, json};
use std::{
    env, fs,
    io::{BufRead, BufReader, ErrorKind, Read, Write},
    os::unix::{
        fs::{DirBuilderExt, PermissionsExt},
        net::{UnixListener, UnixStream},
        process::CommandExt,
        fs::OpenOptionsExt,
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Clone, PartialEq)]
pub struct Window {
    pub handle: u32,
    pub class: String,
    pub title: String,
    pub address: u64,
}

/// Parses `{handle}[HC>]{class}[HT>]{title}[HE>]{address}[HA>]...` (xdph 1.4.1).
/// Malformed entries are dropped rather than offered.
pub fn parse_list(raw: &str) -> Vec<Window> {
    raw.split("[HA>]")
        .filter_map(|entry| {
            let (handle, rest) = entry.split_once("[HC>]")?;
            let (class, rest) = rest.split_once("[HT>]")?;
            let (title, address) = rest.split_once("[HE>]")?;
            Some(Window {
                handle: handle.trim().parse().ok()?,
                class: class.to_owned(),
                title: title.to_owned(),
                address: address.trim().parse().unwrap_or(0),
            })
        })
        .collect()
}

fn valid_output(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 64
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'))
}

/// The xdph selection line for one shell answer, or None for a cancel or any
/// answer that does not name something it was offered.
pub fn selection(answer: &Value, token: &str, windows: &[Window]) -> Option<String> {
    if answer["token"].as_str() != Some(token) {
        return None;
    }
    let flags = if answer["remember"].as_bool() == Some(true) { "r" } else { "" };
    let target = match answer["type"].as_str()? {
        "screen" => {
            let output = answer["output"].as_str()?;
            valid_output(output).then(|| format!("screen:{output}"))?
        }
        "window" => {
            let handle = u32::try_from(answer["handle"].as_u64()?).ok()?;
            windows
                .iter()
                .any(|w| w.handle == handle)
                .then(|| format!("window:{handle}"))?
        }
        "region" => {
            let output = answer["output"].as_str()?;
            let n = |k: &str| answer[k].as_i64();
            let (x, y, w, h) = (n("x")?, n("y")?, n("w")?, n("h")?);
            (valid_output(output) && x >= 0 && y >= 0 && w > 0 && h > 0)
                .then(|| format!("region:{output}@{x},{y},{w},{h}"))?
        }
        _ => return None,
    };
    // xdph drops the last character of a screen name, expecting a newline.
    Some(format!("[SELECTION]{flags}/{target}\n"))
}

pub fn request(token: &str, windows: &[Window]) -> Value {
    json!({
        "token": token,
        "windows": windows.iter().map(|w| json!({
            "handle": w.handle,
            "class": w.class,
            "title": w.title,
            // Hyprland's own window address, as HyprlandToplevel.address spells it.
            "address": format!("{:x}", w.address),
        })).collect::<Vec<_>>(),
    })
}

fn token() -> Result<String> {
    let mut bytes = [0u8; 16];
    fs::File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

fn socket_dir() -> Result<PathBuf> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .filter(|s| !s.is_empty())
        .ok_or("XDG_RUNTIME_DIR is not set")?;
    let dir = PathBuf::from(runtime).join("cortetsu");
    fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir)?;
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;
    Ok(dir)
}

struct Socket(PathBuf);
impl Drop for Socket {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn shell_path() -> PathBuf {
    env::var_os("CORTETSU_SHELL_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::common::config().join("quickshell/cortetsu/current"))
}

/// Asks the shell to connect. False when no shell answers the IPC call within
/// a few seconds, so a wedged shell never blocks the portal.
fn ask_shell(socket: &Path, token: &str) -> bool {
    let qs = env::var_os("CORTETSU_QS_BIN").unwrap_or_else(|| "qs".into());
    let Ok(mut child) = Command::new(qs)
        .arg("-p")
        .arg(shell_path())
        .args(["ipc", "call", "screenshare", "request"])
        .arg(socket)
        .arg(token)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match child.try_wait() {
            // `qs ipc call` exits 0 and prints "Target not found." when the
            // running shell lacks the target; `request` itself prints nothing.
            Ok(Some(status)) => {
                let mut out = String::new();
                if let Some(mut stdout) = child.stdout.take() {
                    let _ = stdout.read_to_string(&mut out);
                }
                return status.success() && out.trim().is_empty();
            }
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return false;
            }
        }
    }
}

fn fallback() -> Result<i32> {
    let picker = env::var_os("CORTETSU_SHARE_PICKER_FALLBACK")
        .unwrap_or_else(|| "hyprland-share-picker".into());
    // exec only returns on failure; xdph's environment goes along unchanged.
    let error = Command::new(&picker).exec();
    eprintln!("cortetsu-share-picker: no shell and no fallback picker: {error}");
    Ok(1)
}

fn accept(listener: &UnixListener, deadline: Instant) -> Result<Option<UnixStream>> {
    listener.set_nonblocking(true)?;
    loop {
        match listener.accept() {
            Ok((stream, _)) => {
                stream.set_nonblocking(false)?;
                return Ok(Some(stream));
            }
            Err(e) if e.kind() == ErrorKind::WouldBlock => {
                if Instant::now() >= deadline {
                    return Ok(None);
                }
                thread::sleep(Duration::from_millis(20));
            }
            Err(e) => return Err(e.into()),
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// The last choice, kept so the sessions that follow it reuse it.
fn last_path() -> Result<PathBuf> {
    Ok(socket_dir()?.join("share-picker-last.json"))
}

/// The selection a recent choice gives for this request, if it is recent
/// enough and still names something offered now.
pub fn reuse(saved: &Value, now: u64, window_ms: u64, token: &str, windows: &[Window]) -> Option<String> {
    let at = saved["at"].as_u64()?;
    if now < at || now - at > window_ms {
        return None;
    }
    let mut answer = saved["answer"].clone();
    answer["token"] = Value::from(token);
    selection(&answer, token, windows)
}

fn remember(answer: &Value) {
    let Ok(path) = last_path() else { return };
    let mut kept = answer.clone();
    if let Some(map) = kept.as_object_mut() {
        map.remove("token");
    }
    let tmp = path.with_extension("tmp");
    let saved = json!({"at": now_ms(), "answer": kept}).to_string();
    let written = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)
        .and_then(|mut f| f.write_all(saved.as_bytes()));
    if written.is_ok() {
        let _ = fs::rename(&tmp, &path);
    }
}

pub fn main(_args: &[String]) -> Result<i32> {
    let windows = parse_list(&env::var("XDPH_WINDOW_SHARING_LIST").unwrap_or_default());
    let reuse_ms = env::var("CORTETSU_SHARE_PICKER_REUSE_MS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(15_000);
    let timeout = env::var("CORTETSU_SHARE_PICKER_TIMEOUT_MS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(60_000);
    let deadline = Instant::now() + Duration::from_millis(timeout);
    let token = token()?;
    let saved = last_path()
        .ok()
        .and_then(|p| fs::read_to_string(p).ok())
        .and_then(|t| serde_json::from_str::<Value>(&t).ok());
    if let Some(sel) = saved.and_then(|s| reuse(&s, now_ms(), reuse_ms, &token, &windows)) {
        std::io::stdout().lock().write_all(sel.as_bytes())?;
        return Ok(0);
    }
    let path = socket_dir()?.join(format!("share-picker-{}-{}.sock", std::process::id(), &token[..8]));
    let _ = fs::remove_file(&path);
    let listener = UnixListener::bind(&path)?;
    let _guard = Socket(path.clone());
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;

    if !ask_shell(&path, &token) {
        drop(listener);
        return fallback();
    }
    let Some(mut stream) = accept(&listener, deadline)? else {
        eprintln!("cortetsu-share-picker: the shell did not answer in time");
        return Ok(1);
    };
    stream.write_all(format!("{}\n", request(&token, &windows)).as_bytes())?;
    stream.flush()?;
    let remaining = deadline.saturating_duration_since(Instant::now());
    stream.set_read_timeout(Some(remaining.max(Duration::from_millis(1))))?;
    let mut line = String::new();
    match BufReader::new(&stream).read_line(&mut line) {
        Ok(_) => {}
        Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
            eprintln!("cortetsu-share-picker: no choice within the time limit");
            return Ok(1);
        }
        Err(e) => return Err(e.into()),
    }
    let answer: Value = serde_json::from_str(line.trim()).unwrap_or(Value::Null);
    match selection(&answer, &token, &windows) {
        Some(sel) => {
            remember(&answer);
            std::io::stdout().lock().write_all(sel.as_bytes())?;
            Ok(0)
        }
        None => {
            if let Ok(p) = last_path() {
                let _ = fs::remove_file(p);
            }
            Ok(1)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST: &str = "12[HC>]firefox[HT>]Docs — Mozilla[HE>]94046512345680[HA>]\
        7[HC>]kitty[HT>]a [b] c[HE>]0[HA>]broken[HA>]x[HC>]y[HT>]z[HE>]1[HA>]";

    #[test]
    fn parses_the_xdph_list_and_drops_malformed_entries() {
        let w = parse_list(LIST);
        assert_eq!(w.len(), 2);
        assert_eq!(w[0].handle, 12);
        assert_eq!(w[0].title, "Docs — Mozilla");
        assert_eq!(w[0].address, 94046512345680);
        assert_eq!(w[1].title, "a [b] c");
        assert!(parse_list("").is_empty());
    }

    #[test]
    fn composes_each_selection_kind() {
        let w = parse_list(LIST);
        let t = "tok";
        let s = |v: Value| selection(&v, t, &w);
        assert_eq!(
            s(json!({"token": t, "type": "screen", "output": "DP-1", "remember": true})).as_deref(),
            Some("[SELECTION]r/screen:DP-1\n")
        );
        assert_eq!(
            s(json!({"token": t, "type": "window", "handle": 7})).as_deref(),
            Some("[SELECTION]/window:7\n")
        );
        assert_eq!(
            s(json!({"token": t, "type": "region", "output": "eDP-1", "x": 10, "y": 20, "w": 300, "h": 200})).as_deref(),
            Some("[SELECTION]/region:eDP-1@10,20,300,200\n")
        );
    }

    #[test]
    fn refuses_anything_not_offered() {
        let w = parse_list(LIST);
        let t = "tok";
        let s = |v: Value| selection(&v, t, &w);
        assert_eq!(s(json!({"token": "other", "type": "screen", "output": "DP-1"})), None);
        assert_eq!(s(json!({"token": t, "type": "window", "handle": 99})), None);
        assert_eq!(s(json!({"token": t, "type": "screen", "output": "DP-1\n[SELECTION]x"})), None);
        assert_eq!(s(json!({"token": t, "type": "region", "output": "DP-1", "x": 0, "y": 0, "w": 0, "h": 5})), None);
        assert_eq!(s(json!({"token": t, "type": "cancel"})), None);
        assert_eq!(s(Value::Null), None);
    }

    #[test]
    fn reuses_a_recent_choice_only_while_it_is_offered() {
        let windows = parse_list(LIST);
        let saved = json!({"at": 1_000, "answer": {"type": "window", "handle": 12, "remember": false}});
        assert_eq!(reuse(&saved, 5_000, 15_000, "t", &windows).as_deref(), Some("[SELECTION]/window:12\n"));
        assert!(reuse(&saved, 20_000, 15_000, "t", &windows).is_none(), "too old");
        assert!(reuse(&saved, 500, 15_000, "t", &windows).is_none(), "clock went back");
        assert!(reuse(&saved, 5_000, 15_000, "t", &[]).is_none(), "window gone");
        let screen = json!({"at": 1_000, "answer": {"type": "screen", "output": "DP-1"}});
        assert_eq!(reuse(&screen, 2_000, 15_000, "t", &[]).as_deref(), Some("[SELECTION]/screen:DP-1\n"));
    }

    #[test]
    fn request_carries_hyprland_addresses_in_hex() {
        let r = request("t", &parse_list(LIST));
        assert_eq!(r["windows"][0]["address"], "5588e8f5f250");
        assert_eq!(r["windows"][1]["class"], "kitty");
    }
}
