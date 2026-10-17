//! Backend of «Atajos y teclados»: keyboards, keys and keybinds.
//! The binary (`cortetsu-keybinds`) is a thin CLI over this library.

pub mod bitmap;
pub mod capture;
pub mod editor;
pub mod hypr;
pub mod inventory;
pub mod keycodes;
pub mod keymap;
pub mod keys;
pub mod legacy;
pub mod lua;
pub mod probe;
pub mod protocol;
pub mod scope;
pub mod sha256;
pub mod store;
pub mod testing;
pub mod watch;

use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// An environment override (tests point these at fixtures) or the default.
pub fn env_or(var: &str, default: &str) -> String {
    std::env::var(var).unwrap_or_else(|_| default.to_owned())
}

pub fn on_path(program: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| std::env::split_paths(&path).any(|dir| dir.join(program).is_file()))
}

/// Run a program with a timeout; stdout on success, None on failure or
/// timeout. stdout is drained on a thread: `hyprctl binds -j` is larger than
/// a pipe buffer and would otherwise block the child until the timeout.
pub fn run(program: &str, args: &[&str], timeout: Duration) -> Option<String> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let mut stdout = child.stdout.take()?;
    let reader = std::thread::spawn(move || {
        let mut text = String::new();
        stdout.read_to_string(&mut text).map(|_| text)
    });
    let started = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if started.elapsed() < timeout => std::thread::sleep(Duration::from_millis(2)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    };
    let text = reader.join().ok()?.ok()?;
    status.success().then_some(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn run_returns_large_output_without_blocking() {
        let output = run("sh", &["-c", "head -c 300000 /dev/zero | tr '\\0' x"], Duration::from_secs(5)).unwrap();
        assert_eq!(output.len(), 300_000);
    }

    #[test]
    fn run_gives_up_at_the_timeout_and_on_failure() {
        let started = Instant::now();
        assert_eq!(run("sleep", &["5"], Duration::from_millis(100)), None);
        assert!(started.elapsed() < Duration::from_secs(2));
        assert_eq!(run("false", &[], Duration::from_secs(1)), None);
        assert_eq!(run("/nonexistent/program", &[], Duration::from_secs(1)), None);
    }
}
