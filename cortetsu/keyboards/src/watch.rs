//! `watch`: an inventory line now and another after every keyboard hotplug.
//!
//! Only the open editor runs this, and it ends with it:
//! - `udevadm monitor` is a child started through `setpriv --pdeathsig TERM`,
//!   so the kernel stops it when this process dies, even by SIGKILL.
//! - This process exits when its parent goes away (Quickshell crashed and it
//!   was reparented) or when stdout is closed. An empty line every few
//!   seconds is what notices a closed stdout; readers skip empty lines.
//! - Without setpriv it refuses to start rather than risk an orphan.
//!
//! udev sees a device before Hyprland's libinput does, so a rescan whose
//! nodes lack a Hyprland name is retried briefly; each change of the
//! inventory fingerprint is printed once.

use crate::inventory::{self, Inventory};
use crate::protocol::{self, Error};
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

const QUIET: Duration = Duration::from_millis(250);
const LINK_RETRY: Duration = Duration::from_millis(150);
const LINK_ATTEMPTS: u32 = 10;
const TICK: Duration = Duration::from_secs(1);
const HEARTBEAT: Duration = Duration::from_secs(5);

fn write_line(text: &str) -> bool {
    let mut out = std::io::stdout().lock();
    writeln!(out, "{text}").and_then(|()| out.flush()).is_ok()
}

fn emit(inventory: &Inventory, event: &str) -> bool {
    let mut value = protocol::ok("inventory", inventory);
    value["event"] = serde_json::json!(event);
    write_line(&value.to_string())
}

/// Every keyboard Hyprland could know by name has one.
fn settled(inventory: &Inventory) -> bool {
    !inventory.hyprland_available
        || inventory.keyboards.iter().all(|k| {
            k.hyprland_linked
                || k.kind == inventory::Kind::Virtual
                || k.interfaces.iter().any(|i| !i.hyprland_candidates.is_empty())
        })
}

fn on_path(program: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| std::env::split_paths(&path).any(|dir| dir.join(program).is_file()))
}

/// Runs until the editor goes away. Returns `Null` after a normal end (the
/// lines were already printed) or an error before anything was printed.
pub fn run() -> Result<serde_json::Value, Error> {
    if !on_path("setpriv") {
        return Err(Error::new("watch-unavailable", "Falta setpriv (util-linux): no se vigilan conexiones"));
    }
    let udevadm = crate::env_or("CORTETSU_UDEVADM", "udevadm");
    let mut child = Command::new("setpriv")
        .args(["--pdeathsig", "TERM", "--", &udevadm, "monitor", "--udev", "--subsystem-match=input"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| Error::new("watch-unavailable", format!("No se pudo vigilar udev: {error}")))?;
    let (events, received) = mpsc::channel();
    let stdout = child.stdout.take().expect("piped stdout");
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines() {
            let Ok(line) = line else { break };
            if line.starts_with("UDEV") && events.send(()).is_err() {
                break;
            }
        }
        let _ = events.send(()); // udevadm ended: let the loop notice
    });

    let parent = std::os::unix::process::parent_id();
    let mut last = inventory::now();
    let mut alive = emit(&last, "initial");
    let mut last_write = Instant::now();
    while alive {
        let event = received.recv_timeout(TICK);
        if std::os::unix::process::parent_id() != parent {
            break;
        }
        // Timed from the last write, so a stream of udev events that change
        // nothing cannot starve it.
        if last_write.elapsed() >= HEARTBEAT {
            alive = write_line("");
            last_write = Instant::now();
        }
        match event {
            Ok(()) => {}
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
        if child.try_wait().ok().flatten().is_some() {
            break;
        }
        // One plug is several udev events (each interface, then its eventN).
        while received.recv_timeout(QUIET).is_ok() {}
        let mut current = inventory::now();
        for _ in 0..LINK_ATTEMPTS {
            if settled(&current) {
                break;
            }
            std::thread::sleep(LINK_RETRY);
            current = inventory::now();
        }
        if alive && current.fingerprint != last.fingerprint {
            alive = emit(&current, "changed");
            last_write = Instant::now();
            last = current;
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    Ok(serde_json::Value::Null)
}
