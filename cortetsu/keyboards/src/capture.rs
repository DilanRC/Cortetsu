//! `capture begin MS | end | status`: the submap that keeps Hyprland's
//! global binds from firing while the editor records a chord.
//!
//! The submap and its fail-safe timer live in hyprland/keybinds.lua
//! (`cortetsu_capture_begin`/`_end`). Each command reports the submap
//! Hyprland is actually in afterwards, so the editor never claims to listen
//! when it is not, or to have released the keyboard when it has not.

use crate::hypr;
use crate::protocol::Error;
use serde::Serialize;
use std::time::Duration;

pub const SUBMAP: &str = "cortetsu-capture";
const TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub active: bool,
    pub submap: String,
}

fn unavailable(message: impl Into<String>) -> Error {
    Error::new("hyprland-unavailable", message)
}

/// The current submap ("" is the default one).
fn current() -> Result<String, Error> {
    let text = hypr::run(&["repl", "return 'S=' .. tostring(hl.get_current_submap())"], TIMEOUT)
        .ok_or_else(|| unavailable("No se pudo consultar Hyprland"))?;
    text.trim()
        .strip_prefix("S=")
        .map(str::to_owned)
        .ok_or_else(|| unavailable(format!("Respuesta inesperada de Hyprland: {}", text.trim())))
}

fn eval(code: &str) -> Result<(), Error> {
    let text = hypr::run(&["eval", code], TIMEOUT).ok_or_else(|| unavailable("No se pudo hablar con Hyprland"))?;
    if text.trim() != "ok" {
        return Err(Error::new(
            "capture-unavailable",
            format!("La configuración cargada no admite la captura; recarga Hyprland ({})", text.trim()),
        ));
    }
    Ok(())
}

pub fn status() -> Result<Status, Error> {
    let submap = current()?;
    Ok(Status { active: submap == SUBMAP, submap })
}

pub fn begin(timeout_ms: u32) -> Result<Status, Error> {
    eval(&format!("cortetsu_capture_begin({timeout_ms})"))?;
    let status = status()?;
    if !status.active {
        return Err(Error::new("capture-failed", "Hyprland no entró en modo captura"));
    }
    Ok(status)
}

pub fn end() -> Result<Status, Error> {
    eval("cortetsu_capture_end()")?;
    let status = status()?;
    if status.active {
        return Err(Error::new("capture-failed", "Hyprland sigue en modo captura"));
    }
    Ok(status)
}
