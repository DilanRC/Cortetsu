use crate::common::*;
use chrono::Local;
use nix::{
    sys::signal::{Signal, kill},
    unistd::Pid,
};
use serde_json::{Value, json};
use std::{
    fs,
    os::unix::process::CommandExt,
    path::PathBuf,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

const RECORDER: &str = "gpu-screen-recorder";
#[derive(Default)]
struct Options {
    action: String,
    region: Option<String>,
    sound: bool,
    pause: bool,
    clipboard: bool,
    self_test: bool,
}
fn options(args: &[String]) -> Option<Options> {
    let mut o = Options {
        action: "status".into(),
        ..Default::default()
    };
    let mut action = false;
    let mut iter = args.iter().peekable();
    while let Some(a) = iter.next() {
        match a.as_str() {
            "-s" | "--sound" => o.sound = true,
            "-p" | "--pause" => o.pause = true,
            "-c" | "--clipboard" => o.clipboard = true,
            "--self-test" => o.self_test = true,
            "-r" | "--region" => {
                o.region = Some(if iter.peek().is_some_and(|n| !n.starts_with('-')) {
                    iter.next()?.clone()
                } else {
                    "slurp".into()
                });
            }
            "status" | "start" | "stop" | "pause" if !action => {
                o.action = a.clone();
                action = true;
            }
            a if a.starts_with("--region=") => o.region = Some(a[9..].into()),
            _ => return None,
        }
    }
    Some(o)
}
fn directory() -> PathBuf {
    state().join("record")
}
fn state_path() -> PathBuf {
    directory().join("state.json")
}
fn load() -> Value {
    let v = json_load(&state_path(), json!({}));
    if v.is_object() { v } else { json!({}) }
}
fn starttime(pid: u32) -> Option<u64> {
    let text = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    text.rsplit_once(')')?
        .1
        .split_whitespace()
        .nth(19)?
        .parse()
        .ok()
}
fn ours(state: &Value) -> bool {
    let Some(pid) = state["pid"]
        .as_u64()
        .filter(|p| *p > 1 && *p <= i32::MAX as u64)
        .map(|p| p as u32)
    else {
        return false;
    };
    let Some(start) = starttime(pid) else {
        return false;
    };
    if state["starttime"].as_u64() != Some(start) {
        return false;
    }
    fs::read(format!("/proc/{pid}/cmdline")).is_ok_and(|raw| {
        raw.split(|c| *c == 0)
            .filter_map(|s| std::str::from_utf8(s).ok())
            .any(|arg| {
                std::path::Path::new(arg)
                    .file_name()
                    .is_some_and(|n| n == RECORDER)
            })
    })
}
fn owned() -> Value {
    let s = load();
    if ours(&s) { s } else { json!({}) }
}
fn signal(s: &Value, signal: Signal) {
    if let Some(pid) = s["pid"]
        .as_i64()
        .filter(|p| *p > 1 && *p <= i32::MAX as i64)
    {
        let _ = kill(Pid::from_raw(pid as i32), signal);
    }
}
fn notify(args: &[&str], wait: bool) -> String {
    let mut cmd = Command::new("notify-send");
    cmd.args(["-a", "cortetsu"]).args(args);
    if wait {
        run(&mut cmd, None, Duration::from_secs(10))
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned())
            .unwrap_or_default()
    } else {
        let _ = cmd
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .process_group(0)
            .spawn();
        String::new()
    }
}
fn intersects(a: (f64, f64, f64, f64), b: (f64, f64, f64, f64)) -> bool {
    a.0 < b.0 + b.2 && a.0 + a.2 > b.0 && a.1 < b.1 + b.3 && a.1 + a.3 > b.1
}
fn start_args(o: &Options) -> Result<Vec<String>> {
    let output = call("hyprctl", &["monitors", "-j"], 5)?;
    if !output.status.success() {
        return Err("monitor query failed".into());
    }
    let monitors: Value = serde_json::from_slice(&output.stdout)?;
    let monitors = monitors.as_array().ok_or("invalid monitor snapshot")?;
    let mut command = vec!["-w".into()];
    if let Some(region) = &o.region {
        let region = if region == "slurp" {
            let out = call("slurp", &["-f", "%wx%h+%x+%y"], 300)?;
            if !out.status.success() {
                return Err("region selection cancelled".into());
            }
            String::from_utf8(out.stdout)?.trim().to_owned()
        } else {
            region.trim().to_owned()
        };
        let re = regex::Regex::new(r"^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$")?;
        let c = re
            .captures(&region)
            .ok_or_else(|| format!("Invalid region: {region}"))?;
        let values: Vec<f64> = (1..=4)
            .map(|i| c[i].parse())
            .collect::<std::result::Result<_, _>>()?;
        let selected = (values[2], values[3], values[0], values[1]);
        let fps = monitors
            .iter()
            .filter(|m| {
                intersects(
                    (
                        number(&m["x"]),
                        number(&m["y"]),
                        number(&m["width"]),
                        number(&m["height"]),
                    ),
                    selected,
                )
            })
            .map(|m| number(&m["refreshRate"]).round_ties_even() as i64)
            .max()
            .unwrap_or(60);
        command.extend([
            "region".into(),
            "-region".into(),
            region,
            "-f".into(),
            fps.to_string(),
        ]);
    } else {
        let focused = monitors
            .iter()
            .find(|m| m["focused"] == true)
            .ok_or("no focused monitor")?;
        let listed = call(RECORDER, &["--list-monitors"], 10)?;
        let out = format!(
            "{}{}",
            String::from_utf8_lossy(&listed.stdout),
            String::from_utf8_lossy(&listed.stderr)
        );
        let focused_name = text(&focused["name"]);
        let available = out
            .lines()
            .filter(|l| !l.trim().is_empty())
            .any(|l| l.split('|').next().unwrap_or("").trim() == focused_name);
        command.extend([
            if available {
                focused_name.into()
            } else {
                "screen".into()
            },
            "-f".into(),
            (number(&focused["refreshRate"]).round_ties_even() as i64).to_string(),
        ]);
    }
    if o.sound {
        command.extend([
            "-a".into(),
            "default_output".into(),
            "-a".into(),
            "default_input".into(),
        ]);
    }
    let config = json_load(&config().join("cortetsu/cli.json"), json!({}));
    if let Some(extra) = config.get("record").and_then(|c| c.get("extraArgs")) {
        let extra = extra
            .as_array()
            .ok_or("Config option 'record.extraArgs' should be an array")?;
        for value in extra {
            command.push(
                value
                    .as_str()
                    .map(str::to_owned)
                    .unwrap_or_else(|| match value {
                        Value::Bool(true) => "True".into(),
                        Value::Bool(false) => "False".into(),
                        Value::Null => "None".into(),
                        _ => value.to_string(),
                    }),
            );
        }
    }
    Ok(command)
}
fn start(o: &Options) -> Result<i32> {
    let _guard = lock(&directory().join("lock"), true)?;
    if !owned().as_object().is_none_or(|m| m.is_empty()) {
        return Ok(0);
    }
    let output = directory().join(format!(
        "recording-{}-{}.mp4",
        std::process::id(),
        now() as u64
    ));
    let mut process = Command::new(RECORDER)
        .args(start_args(o)?)
        .arg("-o")
        .arg(&output)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()?;
    let start = Instant::now();
    while start.elapsed() < Duration::from_secs(1) {
        if let Some(status) = process.try_wait()? {
            let code = status.code().unwrap_or(1);
            notify(
                &[
                    "Recording failed",
                    &format!("Command failed with exit code {code}"),
                ],
                false,
            );
            return Ok(if code == 0 { 1 } else { code });
        }
        thread::sleep(Duration::from_millis(20));
    }
    let Some(starttime) = starttime(process.id()) else {
        signal(&json!({"pid":process.id()}), Signal::SIGINT);
        notify(
            &[
                "Recording failed",
                "Could not establish recorder process ownership",
            ],
            false,
        );
        return Ok(1);
    };
    let s = json!({"pid":process.id(),"starttime":starttime,"mode":if o.region.is_some(){"region"}else{"fullscreen"},"sound":o.sound,"region":o.region.as_deref().unwrap_or(""),"paused":false,"startedAt":Local::now().to_rfc3339(),"outputTempPath":output,"notificationId":notify(&["-p","Recording started","Recording..."],true)});
    if let Err(e) = json_save(&state_path(), &s) {
        signal(&s, Signal::SIGINT);
        return Err(e);
    }
    Ok(0)
}
fn stop(o: &Options) -> Result<i32> {
    let _guard = lock(&directory().join("lock"), true)?;
    let s = load();
    if s.as_object().is_none_or(|m| m.is_empty()) {
        return Ok(0);
    }
    if ours(&s) {
        signal(&s, Signal::SIGINT);
    }
    let start = Instant::now();
    while ours(&s) && start.elapsed() < Duration::from_secs(5) {
        thread::sleep(Duration::from_millis(100));
    }
    if ours(&s) {
        return Err("recorder did not stop; recording state retained".into());
    }
    let path = PathBuf::from(
        s["outputTempPath"]
            .as_str()
            .ok_or("missing recorder output path")?,
    );
    if path.parent() != Some(directory().as_path()) || path.is_symlink() {
        return Err("recording output is outside the owned state directory".into());
    }
    if !path.is_file() {
        let _ = fs::remove_file(state_path());
        notify(
            &[
                "Recording failed",
                &format!("No temporary recording was written at {}", path.display()),
            ],
            false,
        );
        return Ok(1);
    }
    let recordings = std::env::var_os("CORTETSU_RECORDINGS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| xdg("XDG_VIDEOS_DIR", "Vídeos").join("Recordings"));
    fs::create_dir_all(&recordings)?;
    let target = recordings.join(format!(
        "recording_{}.mp4",
        Local::now().format("%Y%m%d_%H-%M-%S")
    ));
    if target.exists() {
        return Err("recording destination already exists; temporary recording retained".into());
    }
    match fs::rename(&path, &target) {
        Ok(()) => {}
        Err(e) if e.raw_os_error() == Some(nix::libc::EXDEV) => {
            let mut source = fs::File::open(&path)?;
            let mut dest = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&target)?;
            std::io::copy(&mut source, &mut dest)?;
            dest.sync_all()?;
            fs::remove_file(&path)?;
        }
        Err(e) => return Err(e.into()),
    }
    let id = text(&s["notificationId"]);
    let message = format!("Recording saved in {}", target.display());
    if !id.is_empty() {
        notify(
            &["-r", id, "-t", "5000", "Recording stopped", &message],
            false,
        );
    } else {
        notify(&["Recording stopped", &message], false);
    }
    fs::remove_file(state_path())?;
    if o.clipboard {
        let uri = url::Url::from_file_path(fs::canonicalize(&target)?)
            .map_err(|_| "invalid recording URI")?;
        let _ = run(
            Command::new("wl-copy").args(["--type", "text/uri-list"]),
            Some(format!("{uri}\n").as_bytes()),
            Duration::from_secs(5),
        );
    }
    println!("{}", target.display());
    Ok(0)
}
pub fn main(args: &[String]) -> Result<i32> {
    let Some(o) = options(args) else { return Ok(2) };
    if o.self_test {
        assert!(!ours(&json!({"pid":std::process::id()})));
        assert!(intersects((0., 0., 10., 10.), (5., 5., 20., 20.)));
        return Ok(0);
    }
    let result = (|| {
        if o.pause || o.action == "pause" {
            let _guard = lock(&directory().join("lock"), true)?;
            let mut s = owned();
            if !s.as_object().is_none_or(|m| m.is_empty()) {
                signal(&s, Signal::SIGUSR2);
                s["paused"] = json!(!s["paused"].as_bool().unwrap_or(false));
                json_save(&state_path(), &s)?;
            }
            return Ok(0);
        }
        match o.action.as_str() {
            "status" => Ok(if owned().as_object().is_some_and(|m| !m.is_empty()) {
                0
            } else {
                1
            }),
            "stop" => stop(&o),
            _ => start(&o),
        }
    })();
    match result {
        Err(e)
            if e.downcast_ref::<std::io::Error>()
                .is_some_and(|e| e.kind() == std::io::ErrorKind::WouldBlock) =>
        {
            eprintln!("busy: another Cortetsu recording operation is active");
            Ok(75)
        }
        result => result,
    }
}
