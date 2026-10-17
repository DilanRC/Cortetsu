//! `watch`: an inventory line now and another after every keyboard hotplug.
//!
//! Only the open editor runs this, and it ends with it:
//! - `udevadm monitor` is a child started through `setpriv --pdeathsig TERM`,
//!   so the kernel stops it when this process dies, even by SIGKILL.
//! - This process exits when its parent goes away (Quickshell crashed and it
//!   was reparented) or when stdout is closed.
//! - Without setpriv it refuses to start rather than risk an orphan.
//!
//! udev sees a device before Hyprland's libinput does, so a rescan whose
//! nodes lack a Hyprland name is retried briefly; each change of the
//! inventory fingerprint is printed once.

use crate::{inventory, inventory_now, protocol};
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::Duration;

const QUIET: Duration = Duration::from_millis(250);
const LINK_RETRY: Duration = Duration::from_millis(150);
const LINK_ATTEMPTS: u32 = 10;

fn emit(inventory: &inventory::Inventory, event: &str) -> bool {
    let mut value = protocol::ok("inventory", inventory);
    value["event"] = serde_json::json!(event);
    let mut out = std::io::stdout().lock();
    writeln!(out, "{value}").and_then(|()| out.flush()).is_ok()
}

fn fully_linked(inventory: &inventory::Inventory) -> bool {
    !inventory.hyprland_available
        || inventory.keyboards.iter().all(|k| k.hyprland_linked || k.ambiguous || k.kind == inventory::Kind::Virtual)
}

fn found(program: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| std::env::split_paths(&path).any(|dir| dir.join(program).is_file()))
}

pub fn run() {
    let udevadm = std::env::var("CORTETSU_UDEVADM").unwrap_or_else(|_| "udevadm".into());
    if !found("setpriv") {
        let error = protocol::Error::new("watch-unavailable", "Falta setpriv (util-linux): no se vigilan conexiones");
        println!("{}", protocol::failure("inventory", &error));
        std::process::exit(1);
    }
    let child = Command::new("setpriv")
        .args(["--pdeathsig", "TERM", "--", &udevadm, "monitor", "--udev", "--subsystem-match=input"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(error) => {
            let error = protocol::Error::new("watch-unavailable", format!("No se pudo vigilar udev: {error}"));
            println!("{}", protocol::failure("inventory", &error));
            std::process::exit(1);
        }
    };
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
    let mut last = inventory_now();
    if !emit(&last, "initial") {
        return;
    }
    loop {
        match received.recv_timeout(Duration::from_secs(1)) {
            Ok(()) => {}
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if std::os::unix::process::parent_id() != parent {
                    break;
                }
                continue;
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
        if child.try_wait().ok().flatten().is_some() {
            break;
        }
        // One plug is several udev events (each interface, then its eventN).
        while received.recv_timeout(QUIET).is_ok() {}
        let mut current = inventory_now();
        for _ in 0..LINK_ATTEMPTS {
            if fully_linked(&current) {
                break;
            }
            std::thread::sleep(LINK_RETRY);
            current = inventory_now();
        }
        if current.fingerprint != last.fingerprint {
            if !emit(&current, "changed") {
                break;
            }
            last = current;
        }
    }
    let _ = child.kill();
    let _ = child.wait();
}
