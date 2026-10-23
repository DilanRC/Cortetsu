use crate::common::*;
use fs2::FileExt;
use nix::{
    sys::signal::{Signal, kill},
    sys::time::TimeSpec,
    time::{ClockId, ClockNanosleepFlags, clock_nanosleep},
    unistd::Pid,
};
use serde_json::{Value, json};
use std::{
    env,
    fs::File,
    io::{Read, Seek, SeekFrom, Write},
    path::PathBuf,
    sync::mpsc,
    thread,
    time::Duration,
};

const CONFIG: [&str; 4] = [
    "focusMinutes",
    "shortBreakMinutes",
    "longBreakMinutes",
    "sessionsBeforeLongBreak",
];
fn defaults() -> Value {
    json!({"schema":2,"phase":"IDLE","targetEndTimestamp":0.0,"pausedRemainingMs":0,"pausedPhase":"FOCUS","completedSessions":0,"focusMinutes":25,"shortBreakMinutes":5,"longBreakMinutes":15,"sessionsBeforeLongBreak":4})
}
fn active(phase: &str) -> bool {
    matches!(phase, "FOCUS" | "BREAK" | "LONG_BREAK")
}
pub fn normalize(raw: Value) -> Value {
    let mut s = defaults();
    if let Some(m) = raw.as_object() {
        for (k, v) in m {
            s[k] = v.clone();
        }
    }
    if !matches!(
        text(&s["phase"]),
        "IDLE" | "FOCUS" | "BREAK" | "LONG_BREAK" | "PAUSED" | "COMPLETED"
    ) {
        s["phase"] = json!("IDLE");
    }
    if s["phase"] == "PAUSED" && !active(text(&s["pausedPhase"])) {
        s["pausedPhase"] = json!("FOCUS");
    }
    for (k, d) in CONFIG.into_iter().zip([25, 5, 15, 4]) {
        s[k] = json!(integer(&s[k], d).max(1));
    }
    for k in ["completedSessions", "pausedRemainingMs"] {
        s[k] = json!(integer(&s[k], 0).max(0));
    }
    let t = number(&s["targetEndTimestamp"]);
    s["targetEndTimestamp"] = json!(if t.is_finite() { t.max(0.0) } else { 0.0 });
    if active(text(&s["phase"])) && number(&s["targetEndTimestamp"]) == 0.0 {
        s["phase"] = json!("IDLE");
        s["pausedPhase"] = json!("FOCUS");
    }
    s["schema"] = json!(2);
    s
}
fn duration(s: &Value, p: &str) -> f64 {
    number(
        &s[match p {
            "FOCUS" => "focusMinutes",
            "LONG_BREAK" => "longBreakMinutes",
            _ => "shortBreakMinutes",
        }],
    ) * 60.0
}
pub fn advance(raw: Value, now: f64) -> Value {
    let mut s = normalize(raw);
    let phase = text(&s["phase"]).to_owned();
    if !active(&phase) {
        return s;
    }
    let target = number(&s["targetEndTimestamp"]);
    let d = duration(&s, &phase);
    if target - now > d {
        s["targetEndTimestamp"] = json!(now + d);
        return s;
    }
    if now < target {
        return s;
    }
    let next = if phase == "FOCUS" {
        s["completedSessions"] = json!(integer(&s["completedSessions"], 0).saturating_add(1));
        if integer(&s["completedSessions"], 0) % integer(&s["sessionsBeforeLongBreak"], 4) == 0 {
            "LONG_BREAK"
        } else {
            "BREAK"
        }
    } else {
        "FOCUS"
    };
    s["phase"] = json!(next);
    s["targetEndTimestamp"] = json!(now + duration(&s, next));
    s["pausedRemainingMs"] = json!(0);
    s["pausedPhase"] = json!(next);
    s
}
pub fn apply(raw: Value, command: &str, now: f64) -> Result<Value> {
    if !matches!(
        command,
        "status" | "start" | "pause" | "resume" | "skip" | "reset"
    ) {
        return Err(format!("unknown command: {command}").into());
    }
    let mut s = advance(raw, now);
    let p = text(&s["phase"]).to_owned();
    match command {
        "start" => {
            s["phase"] = json!("FOCUS");
            s["targetEndTimestamp"] = json!(now + duration(&s, "FOCUS"));
            s["pausedRemainingMs"] = json!(0);
            s["pausedPhase"] = json!("FOCUS");
        }
        "pause" if active(&p) => {
            s["pausedRemainingMs"] =
                json!(((number(&s["targetEndTimestamp"]) - now) * 1000.0).max(0.0) as i64);
            s["pausedPhase"] = json!(p);
            s["targetEndTimestamp"] = json!(0.0);
            s["phase"] = json!("PAUSED");
        }
        "resume" if p == "PAUSED" => {
            s["phase"] = s["pausedPhase"].clone();
            s["targetEndTimestamp"] =
                json!(now + integer(&s["pausedRemainingMs"], 0).max(1) as f64 / 1000.0);
            s["pausedRemainingMs"] = json!(0);
        }
        "skip" if matches!(p.as_str(), "BREAK" | "LONG_BREAK") => {
            s["phase"] = json!("FOCUS");
            s["targetEndTimestamp"] = json!(now + duration(&s, "FOCUS"));
            s["pausedRemainingMs"] = json!(0);
            s["pausedPhase"] = json!("FOCUS");
        }
        "reset" => {
            let previous = s;
            s = defaults();
            for k in CONFIG {
                s[k] = previous[k].clone();
            }
        }
        _ => {}
    }
    Ok(normalize(s))
}
fn path() -> PathBuf {
    env::var("CORTETSU_POMODORO_STATE")
        .ok()
        .filter(|s| !s.is_empty())
        .map(|s| expand(&s))
        .unwrap_or_else(|| state().join("pomodoro.json"))
}
fn sibling(name: &str) -> PathBuf {
    path().with_file_name(name)
}
fn settle(now: f64) -> Result<Value> {
    let old = normalize(json_load(&path(), json!({})));
    let new = advance(old.clone(), now);
    if new != old {
        json_save(&path(), &new)?;
        let title = match (text(&old["phase"]), text(&new["phase"])) {
            ("FOCUS", "BREAK") => Some((
                "Sesión de concentración completada",
                "Toca un descanso corto",
            )),
            ("FOCUS", "LONG_BREAK") => Some((
                "Ciclo de concentración completado",
                "Toca un descanso largo",
            )),
            ("BREAK" | "LONG_BREAK", "FOCUS") => {
                Some(("Descanso terminado", "Listo para concentrarte"))
            }
            _ => None,
        };
        if let Some((title, message)) = title {
            json_save(
                &sibling("pomodoro-notification.json"),
                &json!({"sequence":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_nanos()as u64,"title":title,"message":message}),
            )?;
        }
    }
    Ok(new)
}
fn wake() {
    if let Ok(mut f) = File::open(sibling("pomodoro-daemon.lock")) {
        if FileExt::try_lock_shared(&f).is_ok() {
            return;
        }
        let mut s = String::new();
        if f.read_to_string(&mut s).is_ok()
            && let Ok(pid) = s.trim().parse::<i32>()
            && pid > 1
        {
            let _ = kill(Pid::from_raw(pid), Signal::SIGUSR1);
        }
    }
}
/// Sends one tick after `seconds` of CLOCK_BOOTTIME, which keeps counting
/// while the machine is suspended: a phase that ends during s2idle is settled
/// right after resume instead of after the rest of a monotonic wait.
fn boottime_tick(tx: mpsc::Sender<()>, seconds: f64) {
    thread::spawn(move || {
        let t = TimeSpec::from_duration(Duration::from_secs_f64(seconds.max(0.0)));
        let _ = clock_nanosleep(ClockId::CLOCK_BOOTTIME, ClockNanosleepFlags::empty(), &t);
        let _ = tx.send(());
    });
}
/// True when the installed helper now resolves into another helpers
/// generation than the running binary. The helper is a wrapper script next to
/// the multicall binary, so the generation directories are compared.
fn replaced(running: &std::path::Path, installed: &std::path::Path) -> bool {
    let dir = |p: &std::path::Path| {
        p.canonicalize()
            .ok()
            .and_then(|p| p.parent().map(|d| d.to_path_buf()))
    };
    match (dir(running), dir(installed)) {
        (Some(a), Some(b)) => a != b,
        _ => false,
    }
}
fn installed_helper() -> PathBuf {
    PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".local/bin/cortetsu-pomodoro")
}
fn daemon() -> Result<i32> {
    let event = sibling("pomodoro-notification.json");
    if !event.exists() {
        json_save(&event, &json!({"sequence":0}))?;
    }
    let mut guard = match lock(&sibling("pomodoro-daemon.lock"), true) {
        Ok(v) => v,
        Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => return Ok(0),
        Err(e) => return Err(e.into()),
    };
    let mut signals = signal_hook::iterator::Signals::new([signal_hook::consts::SIGUSR1])?;
    let (tx, rx) = mpsc::channel();
    let signal_tx = tx.clone();
    thread::spawn(move || {
        for _ in signals.forever() {
            if signal_tx.send(()).is_err() {
                break;
            }
        }
    });
    guard.seek(SeekFrom::Start(0))?;
    guard.set_len(0)?;
    writeln!(guard, "{}", std::process::id())?;
    guard.flush()?;
    loop {
        let current = {
            let _l = lock(&sibling("pomodoro-state.lock"), false)?;
            settle(now())?
        };
        if active(text(&current["phase"])) {
            let seconds = (number(&current["targetEndTimestamp"]) - now()).clamp(0.0, 30.0);
            boottime_tick(tx.clone(), seconds);
        }
        if rx.recv().is_err() {
            break;
        }
        // Adopt a newly installed helper without a shell reload; same PID, so
        // the Quickshell Process keeps owning it. The lock fd is close-on-exec.
        let installed = installed_helper();
        if let Ok(running) = env::current_exe()
            && replaced(&running, &installed)
        {
            use std::os::unix::process::CommandExt;
            drop(guard);
            let error = std::process::Command::new(&installed).arg("daemon").exec();
            return Err(error.into());
        }
    }
    Ok(0)
}
pub fn main(args: &[String]) -> Result<i32> {
    let command = args.first().map(String::as_str).unwrap_or("status");
    if command == "daemon" {
        return daemon();
    }
    if command == "wake" {
        wake();
        return Ok(0);
    }
    if !matches!(
        command,
        "status" | "start" | "pause" | "resume" | "skip" | "reset"
    ) {
        eprintln!("unknown command: {command}");
        return Ok(2);
    }
    let (s, changed) = {
        let _l = lock(&sibling("pomodoro-state.lock"), false)?;
        let time = now();
        let current = settle(time)?;
        let next = apply(current.clone(), command, time)?;
        let changed = next != current;
        if changed {
            json_save(&path(), &next)?;
        }
        (next, changed)
    };
    if changed {
        wake();
    }
    emit(&s)?;
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn boottime_tick_wakes_the_loop() {
        let (tx, rx) = mpsc::channel();
        boottime_tick(tx, 0.05);
        assert!(rx.recv_timeout(Duration::from_secs(2)).is_ok());
    }
    #[test]
    fn replaced_compares_resolved_binaries() {
        // helpers-old/{binary,wrapper}, helpers-new/{binary,wrapper}; the
        // installed link points at a wrapper, the running exe is a binary.
        let d = tempfile::tempdir().unwrap();
        for g in ["old", "new"] {
            std::fs::create_dir(d.path().join(g)).unwrap();
            for f in ["cortetsu-desktop-runtime", "cortetsu-pomodoro"] {
                std::fs::write(d.path().join(g).join(f), "").unwrap();
            }
        }
        let link = d.path().join("installed");
        std::os::unix::fs::symlink(d.path().join("old/cortetsu-pomodoro"), &link).unwrap();
        let running = d.path().join("old/cortetsu-desktop-runtime");
        assert!(
            !replaced(&running, &link),
            "same generation must not re-exec"
        );
        std::fs::remove_file(&link).unwrap();
        std::os::unix::fs::symlink(d.path().join("new/cortetsu-pomodoro"), &link).unwrap();
        assert!(replaced(&running, &link));
        assert!(!replaced(&running, &d.path().join("missing")));
    }
    #[test]
    fn phase_clock_and_pause_contract() {
        let n = 1_000_000.;
        let mut s = defaults();
        s["phase"] = json!("FOCUS");
        s["targetEndTimestamp"] = json!(n + 600.);
        let p = apply(s.clone(), "pause", n).unwrap();
        assert_eq!(p["pausedRemainingMs"], 600000);
        assert_eq!(
            apply(p, "resume", n + 3600.).unwrap()["targetEndTimestamp"],
            n + 4200.
        );
        assert_eq!(
            advance(s, n - 7200.)["targetEndTimestamp"],
            n - 7200. + 1500.
        );
    }
    #[test]
    fn invalid_state_recovers_without_dropping_user_keys() {
        let s = normalize(
            json!({"phase":"FOCUS","targetEndTimestamp":"x","focusMinutes":-1,"own":"retained"}),
        );
        assert_eq!(s["phase"], "IDLE");
        assert_eq!(s["focusMinutes"], 1);
        assert_eq!(s["own"], "retained");
    }
}
