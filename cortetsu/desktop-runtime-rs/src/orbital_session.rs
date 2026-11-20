//! Orbital playback supervisor: `cortetsu-orbital session`.
//!
//! One instance per Wayland session, owned by the QML shell through a stdin/stdout
//! JSON-lines channel. It owns renderer processes, per-monitor ownership and
//! persisted preferences. Presentation is a two-phase handshake with the static
//! `cortetsu-background` surface: the cover is confirmed before a renderer starts
//! or stops, and the cover is only lifted after the renderer's own layer surface
//! is mapped on that monitor.

use crate::{common::{self, Result}, orbital};
use nix::{sys::signal::{killpg, Signal}, unistd::Pid};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::BTreeMap, ffi::OsString, fmt, hash::{BuildHasher, RandomState},
    io::{self, BufRead, Read}, os::unix::process::CommandExt, path::{Path, PathBuf},
    process::{Child, Command, Stdio}, sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}, mpsc},
    thread, time::{Duration, Instant}};

const PREFERENCES_VERSION: u32 = 1;
const ALMAMU_DIR: &str = "/opt/linux-wallpaperengine";
const MESA_EGL_VENDOR: &str = "/usr/share/glvnd/egl_vendor.d/50_mesa.json";
const TRANSITION_TIMEOUT: Duration = Duration::from_secs(15);
const COVER_TIMEOUT: Duration = Duration::from_secs(3);
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(30);
const RESTART_WINDOW: Duration = Duration::from_secs(120);
const RESTART_LIMIT: usize = 2;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
struct Selection {
    location: String,
    backend: String,
    assets: String,
    fps: u16,
    volume: u8,
    muted: bool,
    scaling: String,
    /// "integrated" pins EGL to Mesa and decodes video in software so the
    /// discrete NVIDIA GPU stays asleep; "system" leaves both to the driver.
    gpu: String,
    properties: BTreeMap<String, Value>,
    pause_on_battery: bool,
    pause_fullscreen: bool,
    restore_on_start: bool,
}
impl Default for Selection {
    fn default() -> Self {
        Self { location: String::new(), backend: "almamu-wayland".into(), assets: String::new(), fps: 30,
            volume: 15, muted: false, scaling: "fill".into(), gpu: "integrated".into(), properties: BTreeMap::new(),
            pause_on_battery: true, pause_fullscreen: true, restore_on_start: true }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
struct Playlist { entries: Vec<Selection>, interval: u64, shuffle: bool, enabled: bool }
impl Default for Playlist {
    fn default() -> Self { Self { entries: Vec::new(), interval: 300, shuffle: false, enabled: false } }
}

/// Versioned file at `$XDG_STATE_HOME/cortetsu/orbital.json`. Static wallpaper
/// state stays in its own files; this one only records animated choices.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
struct Preferences {
    version: u32,
    /// Last confirmed selection per connector.
    monitors: BTreeMap<String, Selection>,
    /// Selection replaced by the last confirmed change, for Restore.
    previous: BTreeMap<String, Selection>,
    library_roots: Vec<String>,
    favorites: Vec<String>,
    collections: BTreeMap<String, Vec<String>>,
    playlists: BTreeMap<String, Playlist>,
    profiles: BTreeMap<String, BTreeMap<String, Selection>>,
}
impl Default for Preferences {
    fn default() -> Self {
        Self { version: PREFERENCES_VERSION, monitors: BTreeMap::new(), previous: BTreeMap::new(), library_roots: Vec::new(),
            favorites: Vec::new(), collections: BTreeMap::new(), playlists: BTreeMap::new(), profiles: BTreeMap::new() }
    }
}

/// Structured refusal surfaced to QML as `{event:"error", code, message}`.
#[derive(Debug)]
struct Refusal { code: &'static str, message: String }
impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.write_str(&self.message) }
}
impl std::error::Error for Refusal {}
fn refuse(code: &'static str, message: impl Into<String>) -> Box<dyn std::error::Error> {
    Box::new(Refusal { code, message: message.into() })
}

/// A renderer that can present a Wallpaper Engine project on one monitor.
/// Adding a backend means implementing this trait and listing it in `backend`.
trait Backend: Sync {
    fn id(&self) -> &'static str;
    /// Layer-shell namespace the renderer maps; used to confirm presentation.
    fn namespace(&self) -> &'static str;
    fn available(&self) -> bool;
    /// What this backend can do for a catalog entry, without starting anything.
    fn inspect(&self, entry: &Value) -> std::result::Result<Value, Refusal>;
    fn prepare(&self, monitor: &str, selection: &Selection) -> Result<Command>;
}
fn backend(id: &str) -> Option<&'static dyn Backend> {
    static ALMAMU: Almamu = Almamu;
    match id { "almamu-wayland" => Some(&ALMAMU), _ => None }
}

struct Almamu;
impl Almamu {
    fn executable() -> PathBuf { Path::new(ALMAMU_DIR).join("linux-wallpaperengine") }
}
impl Backend for Almamu {
    fn id(&self) -> &'static str { "almamu-wayland" }
    fn namespace(&self) -> &'static str { "linux-wallpaperengine" }
    fn available(&self) -> bool { common::executable(&Self::executable()) }
    fn inspect(&self, entry: &Value) -> std::result::Result<Value, Refusal> {
        let no = |code, message: &str| Err(Refusal { code, message: message.into() });
        if entry["compatibility"] == "read-error" { return no("invalid", "project.json could not be read"); }
        let kind = entry["type"].as_str().unwrap_or("unknown");
        match kind {
            "scene" => {
                let packed = !entry["packedScene"].is_null() && !entry["entryFile"].is_null();
                if entry["entrypoint"].is_null() && !packed { return no("invalid", "scene has neither its declared file nor scene.pkg"); }
            },
            "video" => if entry["entrypoint"].is_null() { return no("invalid", "video file declared by the project is missing"); },
            // WebBrowserContext.cpp sets CefSettings.no_sandbox = true in the installed engine.
            "web" => return no("incompatible", "Web is disabled: the installed CEF runs without its sandbox and Orbital has no audited isolation for untrusted pages"),
            "image" => return no("incompatible", "Image projects belong to the static library, which keeps the colour pipeline"),
            _ => return no("incompatible", "Unknown project type; no backend claims it"),
        }
        let properties: Vec<&String> = entry["properties"].as_object().map(|p| p.iter()
            .filter(|(_, d)| matches!(d["type"].as_str(), Some("bool" | "slider" | "combo"))).map(|(k, _)| k).collect()).unwrap_or_default();
        Ok(json!({
            "backend": self.id(), "type": kind, "audio": true, "fps": true, "scaling": true,
            "liveChanges": false, "properties": properties,
            "limits": if kind == "scene" {
                "Scenes are rendered by Almamu's OpenGL reimplementation: some shaders, effects, SceneScript and audio-reactive behaviour can differ from Windows."
            } else {
                "Video is decoded by libmpv; with the integrated GPU policy decoding stays in software."
            },
        }))
    }
    fn prepare(&self, monitor: &str, s: &Selection) -> Result<Command> {
        if s.backend != self.id() { return Err(refuse("incompatible", "unsupported backend")); }
        if !self.available() { return Err(refuse("unavailable", format!("Almamu renderer not installed at {}", Self::executable().display()))); }
        let root = canonical_dir(&s.location, "wallpaper directory unavailable")?;
        if s.assets.is_empty() { return Err(refuse("unavailable", "Wallpaper Engine assets not found; install Wallpaper Engine in Steam")); }
        let assets = canonical_dir(&s.assets, "Wallpaper Engine assets unavailable")?;
        let entry = orbital::item(&root, "custom");
        self.inspect(&entry).map_err(|r| Box::new(r) as Box<dyn std::error::Error>)?;
        let mut c = Command::new(Self::executable());
        // Same library path as the package's /usr/bin wrapper; no shell between us and the renderer.
        c.current_dir(ALMAMU_DIR).env("LD_LIBRARY_PATH", Path::new(ALMAMU_DIR).join("lib"))
            .env("XDG_SESSION_TYPE", "wayland").env_remove("DISPLAY")
            .env_remove("DRI_PRIME").env_remove("__NV_PRIME_RENDER_OFFLOAD").env_remove("__GLX_VENDOR_LIBRARY_NAME")
            .args(renderer_args(monitor, &root, &assets, s, &entry)?);
        if s.gpu == "integrated" && Path::new(MESA_EGL_VENDOR).is_file() {
            c.env("__EGL_VENDOR_LIBRARY_FILENAMES", MESA_EGL_VENDOR);
        }
        Ok(c)
    }
}

fn canonical_dir(path: &str, message: &str) -> Result<PathBuf> {
    let p = Path::new(path);
    if !p.is_absolute() { return Err(refuse("invalid", format!("{message}: path must be absolute"))); }
    p.canonicalize().ok().filter(|p| p.is_dir()).ok_or_else(|| refuse("unavailable", message))
}

/// Pure argument builder. Every value is validated here and passed as its own
/// argv element; nothing from project.json reaches a shell.
fn renderer_args(monitor: &str, root: &Path, assets: &Path, s: &Selection, entry: &Value) -> Result<Vec<OsString>> {
    let invalid = |m: &str| refuse("invalid", m);
    if monitor.is_empty() || monitor.len() > 64 || !monitor.chars().all(|c| c.is_ascii_alphanumeric() || "-_.".contains(c)) {
        return Err(invalid("invalid monitor name"));
    }
    if !(1..=144).contains(&s.fps) { return Err(invalid("FPS must be between 1 and 144")); }
    if s.volume > 100 { return Err(invalid("volume must be between 0 and 100")); }
    if !["fill", "fit", "stretch", "default"].contains(&s.scaling.as_str()) { return Err(invalid("invalid scaling mode")); }
    if !["integrated", "system"].contains(&s.gpu.as_str()) { return Err(invalid("invalid GPU policy")); }
    if s.properties.len() > 64 { return Err(invalid("too many properties")); }
    let fps = s.fps.to_string();
    let volume = s.volume.to_string();
    // --screen-root must precede --bg and --scaling: Almamu applies them to the last screen.
    let mut a: Vec<OsString> = vec!["--screen-root".into(), monitor.into(), "--bg".into(), root.into()];
    a.extend(["--scaling", s.scaling.as_str(), "--layer", "background", "--fps", fps.as_str(),
        "--hwdec", if s.gpu == "integrated" { "no" } else { "auto" }].map(OsString::from));
    // --volume and --silent are a mutually exclusive argparse group in Almamu.
    if s.muted { a.push("--silent".into()); } else { a.extend(["--volume", volume.as_str()].map(OsString::from)); }
    if !s.pause_fullscreen { a.push("--no-fullscreen-pause".into()); }
    a.extend(["--disable-mouse", "--assets-dir"].map(OsString::from));
    a.push(assets.into());
    for (name, value) in &s.properties {
        if name.is_empty() || name.len() > 128 || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            return Err(invalid("invalid property name"));
        }
        let definition = &entry["properties"][name];
        let encoded = match definition["type"].as_str() {
            Some("bool") => match value.as_bool() { Some(true) => "true".to_string(), Some(false) => "false".to_string(), None => return Err(invalid("boolean property needs true or false")) },
            Some("slider") => {
                let n = value.as_f64().filter(|n| n.is_finite()).ok_or_else(|| invalid("invalid slider value"))?;
                let (min, max) = (definition["min"].as_f64(), definition["max"].as_f64());
                if min.is_none_or(|m| n < m) || max.is_none_or(|m| n > m) { return Err(invalid("slider outside the author's limits")); }
                n.to_string()
            },
            Some("combo") => {
                let wanted = scalar(value).ok_or_else(|| invalid("invalid combo value"))?;
                let allowed = definition["options"].as_array().is_some_and(|o| o.iter().any(|o| scalar(&o["value"]).as_deref() == Some(wanted.as_str())));
                if !allowed { return Err(invalid("combo value is not one of the author's options")); }
                wanted
            },
            _ => return Err(invalid("only the author's bool, slider and combo properties can be changed")),
        };
        if encoded.len() > 256 || encoded.contains('\0') { return Err(invalid("property value too long")); }
        a.push("--set-property".into());
        a.push(format!("{name}={encoded}").into());
    }
    Ok(a)
}
fn scalar(v: &Value) -> Option<String> {
    match v { Value::String(s) => Some(s.clone()), Value::Number(n) => Some(n.to_string()), _ => None }
}

/// A renderer this session started. Dropping it kills its whole process group.
struct Owned { child: Child, stderr: Arc<Mutex<Vec<u8>>> }
impl Owned {
    fn spawn(command: Command) -> Result<Self> {
        // The shim is this binary: it sets PR_SET_PDEATHSIG and execs the renderer,
        // so the renderer dies with the supervisor without unsafe pre_exec code.
        let mut shim = Command::new(std::env::current_exe()?);
        shim.args(["cortetsu-orbital", "renderer-child", &std::process::id().to_string()])
            .arg(command.get_program()).args(command.get_args())
            .current_dir(ALMAMU_DIR).stdin(Stdio::null()).stdout(Stdio::null())
            .stderr(Stdio::piped()).process_group(0);
        for (key, value) in command.get_envs() {
            match value { Some(v) => { shim.env(key, v); }, None => { shim.env_remove(key); } }
        }
        let mut child = shim.spawn()?;
        let mut pipe = child.stderr.take().ok_or("renderer stderr unavailable")?;
        let stderr = Arc::new(Mutex::new(Vec::new()));
        let tail = stderr.clone();
        thread::spawn(move || {
            let mut buffer = [0u8; 1024];
            while let Ok(n) = pipe.read(&mut buffer) {
                if n == 0 { break; }
                if let Ok(mut tail) = tail.lock() {
                    tail.extend_from_slice(&buffer[..n]);
                    let excess = tail.len().saturating_sub(4096);
                    tail.drain(..excess);
                }
            }
        });
        Ok(Self { child, stderr })
    }
    fn pid(&self) -> u32 { self.child.id() }
    fn diagnostic(&self) -> String {
        self.stderr.lock().map(|s| String::from_utf8_lossy(&s).trim().to_string()).unwrap_or_default()
    }
}
impl Drop for Owned {
    fn drop(&mut self) {
        // The unreaped leader keeps the process-group ID reserved, so this cannot hit a reused group.
        let _ = killpg(Pid::from_raw(self.child.id() as i32), Signal::SIGKILL);
        let _ = self.child.wait();
    }
}

/// `renderer-child PARENT_PID PROGRAM ARGS...`: internal exec shim used by `Owned::spawn`.
pub fn renderer_child(args: &[String]) -> Result<i32> {
    let parent: i32 = args.first().ok_or("missing parent PID")?.parse()?;
    let program = args.get(1).ok_or("missing program")?;
    if Path::new(program) != Almamu::executable() { return Err("renderer-child only executes registered renderers".into()); }
    nix::sys::prctl::set_pdeathsig(Signal::SIGKILL)?;
    if nix::unistd::getppid().as_raw() != parent { return Err("supervisor exited before renderer launch".into()); }
    Err(Command::new(program).args(&args[2..]).exec().into())
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
enum Phase { Stopped, Preparing, Applying, Active, Paused, Error }

struct Output {
    phase: Phase,
    /// Bumped on every transition; QML acknowledgements carry it.
    generation: u64,
    child: Option<Owned>,
    selection: Option<Selection>,
    command: Option<Command>,
    since: Instant,
    error: Option<Value>,
    pause_reason: Option<&'static str>,
    /// QML confirmed a frame with the static cover opaque for this generation.
    covered: bool,
    restarts: Vec<Instant>,
}
impl Default for Output {
    fn default() -> Self {
        Self { phase: Phase::Stopped, generation: 0, child: None, selection: None, command: None, since: Instant::now(),
            error: None, pause_reason: None, covered: true, restarts: Vec::new() }
    }
}
impl Output {
    fn transition(&mut self, generation: u64, phase: Phase) {
        self.generation = generation;
        self.phase = phase;
        self.covered = false;
        self.command = None;
        self.since = Instant::now();
    }
    fn fail(&mut self, generation: u64, code: &str, message: impl ToString) {
        if self.phase == Phase::Error && self.error.as_ref().is_some_and(|e| e["code"] == code) { return; }
        self.transition(generation, Phase::Error);
        self.error = Some(json!({"code": code, "message": message.to_string()}));
    }
    fn snapshot(&self) -> Value {
        json!({"state": self.phase, "generation": self.generation, "pid": self.child.as_ref().map(Owned::pid),
            "owner": if matches!(self.phase, Phase::Applying | Phase::Active) { self.selection.as_ref().map(|s| s.backend.as_str()) } else { Some("cortetsu-background") },
            "reveal": matches!(self.phase, Phase::Applying | Phase::Active), "covered": self.covered,
            "error": self.error, "pauseReason": self.pause_reason, "selection": self.selection,
            "restarts": self.restarts.len()})
    }
}

struct Session {
    outputs: BTreeMap<String, Output>,
    prefs: Preferences,
    path: PathBuf,
    battery: bool,
    /// A Cortetsu context (Gaming, Battery) asked to hold animated wallpapers.
    hold: bool,
    last_heartbeat: Instant,
    generation: u64,
    last_tick: f64,
    last_snapshot: String,
}

fn hypr(query: &str) -> Result<Value> {
    let output = common::call("hyprctl", &["-j", query], 2)?;
    if !output.status.success() { return Err(format!("Hyprland {query} query failed").into()); }
    Ok(serde_json::from_slice(&output.stdout)?)
}
/// Layer surfaces of `monitor`, as (level, namespace, pid, mapped).
fn surfaces(layers: &Value, monitor: &str) -> Vec<(String, String, Option<u64>, bool)> {
    let Some(levels) = layers.get(monitor).and_then(|m| m["levels"].as_object()) else { return Vec::new() };
    levels.iter().flat_map(|(level, list)| list.as_array().into_iter().flatten().map(move |l| (
        level.clone(), l["namespace"].as_str().unwrap_or("").to_string(), l["pid"].as_u64(),
        l["w"].as_u64().unwrap_or(0) > 0 && l["h"].as_u64().unwrap_or(0) > 0))).collect()
}

impl Session {
    fn next_generation(&mut self) -> u64 { self.generation += 1; self.generation }
    fn save(&mut self, next: Preferences) -> Result<()> {
        common::json_save(&self.path, &serde_json::to_value(&next)?)?;
        self.prefs = next;
        Ok(())
    }
    fn emit(&mut self) -> Result<()> {
        let outputs: BTreeMap<_, _> = self.outputs.iter().map(|(k, v)| (k, v.snapshot())).collect();
        let backends: Vec<_> = ["almamu-wayland"].iter().filter_map(|id| backend(id))
            .map(|b| json!({"id": b.id(), "available": b.available()})).collect();
        let value = json!({"event": "snapshot", "outputs": outputs, "preferences": self.prefs, "backends": backends});
        let text = serde_json::to_string(&value)?;
        if text != self.last_snapshot { common::emit(&value)?; self.last_snapshot = text; }
        Ok(())
    }
    /// Ownership request for one monitor. Prepares and validates the renderer,
    /// rejects foreign owners, and starts the cover handshake. The current
    /// renderer keeps presenting until QML confirms the cover.
    fn begin(&mut self, monitor: &str, selection: Selection) -> Result<()> {
        let out = self.outputs.get(monitor).ok_or_else(|| refuse("disconnected", "monitor disconnected"))?;
        if matches!(out.phase, Phase::Preparing | Phase::Applying) { return Err(refuse("busy", "this monitor is already changing wallpaper")); }
        let engine = backend(&selection.backend).ok_or_else(|| refuse("incompatible", "unknown backend"))?;
        let command = engine.prepare(monitor, &selection)?;
        let own = out.child.as_ref().map(|c| c.pid() as u64);
        for (level, namespace, pid, _) in surfaces(&hypr("layers")?, monitor) {
            if pid == own || namespace == "cortetsu-background" { continue; }
            // Level 0 is the background layer: any other client there would fight for the monitor.
            if level == "0" || namespace == engine.namespace() {
                return Err(refuse("foreign-owner", format!("{namespace} (PID {}) already presents a background on {monitor}; close it first",
                    pid.map_or("?".into(), |p| p.to_string()))));
            }
        }
        let generation = self.next_generation();
        let out = self.outputs.get_mut(monitor).ok_or_else(|| refuse("disconnected", "monitor disconnected"))?;
        out.transition(generation, Phase::Preparing);
        out.selection = Some(selection);
        out.command = Some(command);
        out.error = None;
        out.pause_reason = None;
        Ok(())
    }
    fn stop(&mut self, monitor: &str) -> Result<()> {
        let mut next = self.prefs.clone();
        if let Some(s) = next.monitors.get_mut(monitor) { s.restore_on_start = false; }
        if let Some(p) = next.playlists.get_mut(monitor) { p.enabled = false; }
        let saved = self.save(next);
        let generation = self.next_generation();
        let out = self.outputs.get_mut(monitor).ok_or_else(|| refuse("disconnected", "monitor disconnected"))?;
        out.transition(generation, Phase::Stopped);
        out.error = saved.err().map(|e| json!({"code": "persist", "message": format!("Stopped, but the preference could not be saved: {e}")}));
        out.pause_reason = None;
        Ok(())
    }
    fn request(&mut self, v: Value) -> Result<()> {
        let op = v["op"].as_str().ok_or("missing operation")?;
        let text = |key: &str, max: usize| v[key].as_str().filter(|s| !s.is_empty() && s.len() <= max)
            .ok_or_else(|| refuse("invalid", format!("invalid {key}")));
        match op {
            "heartbeat" => { self.last_heartbeat = Instant::now(); self.battery = v["battery"].as_bool().unwrap_or(false); self.hold = v["hold"].as_bool().unwrap_or(false); return Ok(()); },
            "inspect" => {
                let location = text("location", 4096)?;
                let engine = backend(v["backend"].as_str().unwrap_or("almamu-wayland")).ok_or_else(|| refuse("incompatible", "unknown backend"))?;
                let root = canonical_dir(location, "wallpaper directory unavailable")?;
                let entry = orbital::item(&root, "custom");
                let verdict = match engine.inspect(&entry) {
                    Ok(capabilities) => json!({"supported": true, "capabilities": capabilities}),
                    Err(r) => json!({"supported": false, "code": r.code, "message": r.message}),
                };
                common::emit(&json!({"event": "inspection", "location": location, "backend": engine.id(), "available": engine.available(), "verdict": verdict}))?;
                return Ok(());
            },
            "library" => {
                let roots: Vec<String> = serde_json::from_value(v["roots"].clone())?;
                if roots.len() > 32 || roots.iter().any(|r| r.len() > 4096 || !Path::new(r).is_absolute()) { return Err(refuse("invalid", "library folders must be absolute paths (32 at most)")); }
                let mut next = self.prefs.clone(); next.library_roots = roots;
                return self.save(next);
            },
            "favorite" => {
                let id = text("location", 4096)?.to_string();
                let mut next = self.prefs.clone();
                if next.favorites.contains(&id) { next.favorites.retain(|x| x != &id); }
                else if next.favorites.len() < 2000 { next.favorites.push(id); }
                return self.save(next);
            },
            "collection" => {
                let (name, location) = (text("name", 80)?, text("location", 4096)?);
                let mut next = self.prefs.clone();
                if next.collections.len() >= 100 && !next.collections.contains_key(name) { return Err(refuse("limit", "100 collections at most")); }
                let collection = next.collections.entry(name.into()).or_default();
                if collection.iter().any(|x| x == location) { collection.retain(|x| x != location); }
                else if collection.len() < 2000 { collection.push(location.into()); }
                if collection.is_empty() { next.collections.remove(name); }
                return self.save(next);
            },
            _ => {},
        }
        let monitor = text("monitor", 64)?.to_string();
        if !self.outputs.contains_key(&monitor) { return Err(refuse("disconnected", "monitor disconnected")); }
        match op {
            "apply" => {
                let selection: Selection = serde_json::from_value(v["selection"].clone()).map_err(|e| refuse("invalid", e.to_string()))?;
                if let Some(out) = self.outputs.get_mut(&monitor) { out.restarts.clear(); }
                self.begin(&monitor, selection)
            },
            "restore" => {
                let selection = self.prefs.previous.get(&monitor).ok_or_else(|| refuse("missing", "no previous animated wallpaper on this monitor; Stop returns to the static one"))?.clone();
                self.begin(&monitor, selection)
            },
            "stop" => self.stop(&monitor),
            "playlist" => {
                let playlist: Playlist = serde_json::from_value(v["playlist"].clone()).map_err(|e| refuse("invalid", e.to_string()))?;
                if playlist.entries.len() > 100 || !(60..=86400).contains(&playlist.interval) { return Err(refuse("limit", "playlists hold 100 wallpapers and rotate every 1 to 1440 minutes")); }
                for s in &playlist.entries { backend(&s.backend).ok_or_else(|| refuse("incompatible", "unknown backend"))?.prepare(&monitor, s)?; }
                let mut next = self.prefs.clone(); next.playlists.insert(monitor, playlist);
                self.save(next)
            },
            "profile-save" => {
                let name = text("name", 80)?;
                let selection = self.prefs.monitors.get(&monitor).ok_or_else(|| refuse("missing", "apply a wallpaper before saving it as a profile"))?.clone();
                let mut next = self.prefs.clone();
                let profiles = next.profiles.entry(monitor.clone()).or_default();
                if profiles.len() >= 32 && !profiles.contains_key(name) { return Err(refuse("limit", "32 profiles per monitor at most")); }
                profiles.insert(name.into(), selection);
                self.save(next)
            },
            "profile-delete" => {
                let name = text("name", 80)?;
                let mut next = self.prefs.clone();
                if let Some(p) = next.profiles.get_mut(&monitor) { p.remove(name); }
                self.save(next)
            },
            "profile-apply" => {
                let name = text("name", 80)?;
                let selection = self.prefs.profiles.get(&monitor).and_then(|p| p.get(name)).ok_or_else(|| refuse("missing", "profile not found"))?.clone();
                self.begin(&monitor, selection)
            },
            "covered" | "revealed" => self.acknowledge(&monitor, op, v["generation"].as_u64()),
            _ => Err(refuse("invalid", "unknown operation")),
        }
    }
    /// Frame acknowledgements from the static surface of `monitor`.
    fn acknowledge(&mut self, monitor: &str, op: &str, generation: Option<u64>) -> Result<()> {
        let Some(out) = self.outputs.get_mut(monitor) else { return Ok(()) };
        if generation != Some(out.generation) { return Ok(()); }
        if op == "covered" {
            if out.covered || matches!(out.phase, Phase::Applying | Phase::Active) { return Ok(()); }
            out.covered = true;
            // The cover is on screen: the previous renderer may go.
            out.child = None;
            if out.phase == Phase::Preparing {
                let command = out.command.take().ok_or("missing prepared command")?;
                match Owned::spawn(command) {
                    Ok(child) => { out.child = Some(child); out.since = Instant::now(); },
                    Err(e) => { let g = out.generation; out.fail(g, "spawn", e); },
                }
            }
            return Ok(());
        }
        if out.phase != Phase::Applying { return Ok(()); }
        let selection = out.selection.clone().ok_or("missing selection")?;
        let mut next = self.prefs.clone();
        if next.monitors.get(monitor) != Some(&selection)
            && let Some(old) = next.monitors.insert(monitor.into(), selection) { next.previous.insert(monitor.into(), old); }
        let saved = self.save(next);
        let out = self.outputs.get_mut(monitor).ok_or("monitor disconnected")?;
        out.phase = Phase::Active;
        out.since = Instant::now();
        if let Err(e) = saved {
            out.error = Some(json!({"code": "persist", "message": format!("Playing, but the choice could not be saved: {e}")}));
        }
        Ok(())
    }
    fn tick(&mut self) -> Result<()> {
        let now = common::now();
        // CLOCK_MONOTONIC stops during suspend; wall time does not.
        let resumed = now - self.last_tick > 25.0;
        self.last_tick = now;
        let monitors = hypr("monitors")?;
        let monitors = monitors.as_array().ok_or("invalid monitor response")?;
        let names: Vec<&str> = monitors.iter().filter_map(|m| m["name"].as_str()).collect();
        // Disconnected or disabled monitors drop their renderer with their Output.
        self.outputs.retain(|name, _| names.contains(&name.as_str()));
        let mut starts: Vec<(String, Selection)> = Vec::new();
        for name in &names {
            if self.outputs.contains_key(*name) { continue; }
            self.outputs.insert((*name).into(), Output::default());
            if let Some(s) = self.prefs.monitors.get(*name).filter(|s| s.restore_on_start) { starts.push(((*name).into(), s.clone())); }
        }
        let layers = hypr("layers")?;
        let mut generation = self.generation;
        for (name, out) in &mut self.outputs {
            let powered = monitors.iter().find(|m| m["name"] == name.as_str()).is_some_and(|m| m["dpmsStatus"] != false);
            let reason = pause_reason(powered, self.battery && out.selection.as_ref().is_some_and(|s| s.pause_on_battery), self.hold, resumed);
            let running = matches!(out.phase, Phase::Preparing | Phase::Applying | Phase::Active);
            if let (Some(reason), true) = (reason, running) {
                generation += 1;
                out.transition(generation, Phase::Paused);
                out.pause_reason = Some(reason);
                continue;
            }
            if out.phase == Phase::Paused && (reason.is_none() || reason == Some("resume")) && out.covered && out.child.is_none()
                && let Some(s) = &out.selection { starts.push((name.clone(), s.clone())); }
            if let Some(child) = &out.child {
                use nix::sys::wait::{waitid, Id, WaitPidFlag, WaitStatus};
                // WNOWAIT leaves the zombie in place so Owned::drop never signals a reused PID.
                let status = waitid(Id::Pid(Pid::from_raw(child.pid() as i32)), WaitPidFlag::WEXITED | WaitPidFlag::WNOHANG | WaitPidFlag::WNOWAIT)?;
                if !matches!(status, WaitStatus::StillAlive) {
                    let diagnostic = child.diagnostic();
                    let was_active = out.phase == Phase::Active;
                    out.child = None;
                    out.restarts.retain(|t| t.elapsed() < RESTART_WINDOW);
                    let restart = was_active && out.restarts.len() < RESTART_LIMIT;
                    if restart && let Some(s) = out.selection.clone() {
                        out.restarts.push(Instant::now());
                        starts.push((name.clone(), s));
                    }
                    generation += 1;
                    let limit = if was_active && !restart { "; restart limit reached, static wallpaper kept" } else { "" };
                    out.fail(generation, "renderer-exited", format!("renderer exited ({status:?}){limit}\n{diagnostic}"));
                    continue;
                }
                let mapped = surfaces(&layers, name).iter().any(|(_, ns, pid, mapped)| *mapped && *pid == Some(child.pid() as u64)
                    && out.selection.as_ref().and_then(|s| backend(&s.backend)).is_some_and(|b| b.namespace() == ns));
                if matches!(out.phase, Phase::Active | Phase::Applying) && !mapped {
                    generation += 1;
                    out.fail(generation, "surface-lost", "the renderer stopped presenting on this monitor");
                    continue;
                }
                if out.phase == Phase::Preparing && out.covered && mapped {
                    out.phase = Phase::Applying;
                    out.since = Instant::now();
                }
            }
            if matches!(out.phase, Phase::Preparing | Phase::Applying) && out.since.elapsed() > TRANSITION_TIMEOUT {
                let diagnostic = out.child.as_ref().map(Owned::diagnostic).unwrap_or_default();
                generation += 1;
                out.fail(generation, "transition-timeout", format!("no renderer surface on this monitor after 15 seconds\n{diagnostic}"));
                continue;
            }
            if out.phase == Phase::Active
                && let Some(list) = self.prefs.playlists.get(name).filter(|p| p.enabled && p.entries.len() > 1 && out.since.elapsed().as_secs() >= p.interval.max(60)) {
                let current = list.entries.iter().position(|s| Some(s) == out.selection.as_ref()).unwrap_or(0);
                let step = if list.shuffle { 1 + RandomState::new().hash_one(Instant::now()) as usize % (list.entries.len() - 1) } else { 1 };
                starts.push((name.clone(), list.entries[(current + step) % list.entries.len()].clone()));
            }
        }
        self.generation = generation;
        for (name, selection) in starts {
            if let Err(e) = self.begin(&name, selection) {
                let g = self.next_generation();
                if let Some(out) = self.outputs.get_mut(&name) { out.fail(g, "restore", e); }
            }
        }
        Ok(())
    }
    /// A cover that QML never confirms (surface gone, shell busy) must not keep
    /// a renderer alive or block the monitor.
    fn expire_covers(&mut self) -> bool {
        let mut changed = false;
        for out in self.outputs.values_mut() {
            if !out.covered && matches!(out.phase, Phase::Error | Phase::Stopped | Phase::Paused) && out.since.elapsed() > COVER_TIMEOUT {
                out.child = None;
                out.covered = true;
                changed = true;
            }
        }
        changed
    }
    fn cadence(&self) -> Duration {
        if self.outputs.values().any(|o| matches!(o.phase, Phase::Preparing | Phase::Applying)) { Duration::from_millis(500) }
        else if self.outputs.values().any(|o| o.child.is_some() || o.phase == Phase::Paused) { Duration::from_secs(3) }
        else { Duration::from_secs(10) }
    }
}

/// Why a monitor's renderer must stop now, most important first. `None`
/// keeps it playing. "resume" is the only reason that restarts by itself on
/// the next tick: the others hold until their cause goes away.
fn pause_reason(powered: bool, battery_pause: bool, hold: bool, resumed: bool) -> Option<&'static str> {
    if !powered { Some("monitor-off") }
    else if battery_pause { Some("battery") }
    else if hold { Some("context") }
    else if resumed { Some("resume") } else { None }
}

fn load_preferences(path: &Path) -> Result<Preferences> {
    if !path.exists() { return Ok(Preferences::default()); }
    let file = std::fs::File::open(path)?;
    let prefs: Preferences = serde_json::from_reader(file.take(2 * 1024 * 1024))
        .map_err(|e| format!("{} is not valid Orbital preferences ({e}); file preserved", path.display()))?;
    if prefs.version != PREFERENCES_VERSION { return Err(format!("unsupported Orbital preferences version {}; file preserved", prefs.version).into()); }
    Ok(prefs)
}

pub fn main() -> Result<i32> {
    if std::env::var("WAYLAND_DISPLAY").unwrap_or_default().is_empty() { return Err("Wayland session required".into()); }
    let runtime = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR missing")?);
    let _session_lock = common::lock(&runtime.join("cortetsu/orbital.lock"), true)
        .map_err(|e| format!("another Orbital supervisor owns this session ({e})"))?;
    let path = common::state().join("orbital.json");
    let prefs = load_preferences(&path)?;
    let quit = Arc::new(AtomicBool::new(false));
    for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT, signal_hook::consts::SIGHUP] {
        signal_hook::flag::register(signal, quit.clone())?;
    }
    let (tx, rx) = mpsc::sync_channel(32);
    thread::spawn(move || {
        let mut input = io::stdin().lock();
        loop {
            let mut line = Vec::new();
            match input.by_ref().take(65537).read_until(b'\n', &mut line) {
                Ok(0) | Err(_) => break,
                Ok(_) if line.len() > 65536 => break,
                Ok(_) => if tx.send(serde_json::from_slice::<Value>(&line).map_err(|e| e.to_string())).is_err() { break; },
            }
        }
    });
    let mut session = Session { outputs: BTreeMap::new(), prefs, path, battery: false, hold: false, last_heartbeat: Instant::now(),
        generation: 0, last_tick: common::now(), last_snapshot: String::new() };
    session.tick()?;
    session.emit()?;
    let mut tick = Instant::now();
    // Leaving this loop drops every Output, which kills every renderer group.
    while !quit.load(Ordering::Relaxed) && session.last_heartbeat.elapsed() < HEARTBEAT_TIMEOUT {
        let mut changed = session.expire_covers();
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(frame) => {
                changed = true;
                let result = frame.map_err(|e| refuse("invalid", e)).and_then(|v| session.request(v));
                if let Err(e) = result {
                    let code = e.downcast_ref::<Refusal>().map_or("request", |r| r.code);
                    common::emit(&json!({"event": "error", "code": code, "message": e.to_string()}))?;
                }
            },
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {},
        }
        if tick.elapsed() >= session.cadence() {
            if let Err(e) = session.tick() {
                let g = session.next_generation();
                for out in session.outputs.values_mut() {
                    if matches!(out.phase, Phase::Preparing | Phase::Applying | Phase::Active) { out.fail(g, "compositor", &e); }
                }
            }
            tick = Instant::now();
            changed = true;
        }
        if changed { session.emit()?; }
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(properties: Value) -> Value { json!({"type": "scene", "entrypoint": "/w/scene.json", "properties": properties}) }
    fn args(s: &Selection, e: &Value) -> Result<Vec<String>> {
        Ok(renderer_args("eDP-1", Path::new("/w"), Path::new("/a"), s, e)?.into_iter().map(|a| a.into_string().unwrap()).collect())
    }

    #[test]
    fn silent_replaces_volume() {
        let mut s = Selection::default();
        assert!(args(&s, &entry(json!({}))).unwrap().windows(2).any(|w| w == ["--volume", "15"]));
        s.muted = true;
        let a = args(&s, &entry(json!({}))).unwrap();
        assert!(a.contains(&"--silent".into()) && !a.contains(&"--volume".into()));
    }

    #[test]
    fn screen_root_precedes_per_screen_options() {
        let a = args(&Selection::default(), &entry(json!({}))).unwrap();
        assert_eq!(&a[..4], ["--screen-root", "eDP-1", "--bg", "/w"]);
        assert!(a.windows(2).any(|w| w == ["--layer", "background"]));
        assert!(a.windows(2).any(|w| w == ["--hwdec", "no"]));
    }

    #[test]
    fn properties_follow_author_definitions() {
        let e = entry(json!({
            "bloom": {"type": "bool", "value": true},
            "speed": {"type": "slider", "min": 0, "max": 2, "value": 1},
            "mode": {"type": "combo", "options": [{"label": "A", "value": 1}, {"label": "B", "value": "two"}]},
            "tint": {"type": "color", "value": "1 1 1"},
        }));
        let mut s = Selection::default();
        s.properties = BTreeMap::from([("bloom".into(), json!(false)), ("speed".into(), json!(1.5)), ("mode".into(), json!("two"))]);
        let a = args(&s, &e).unwrap();
        for expected in ["bloom=false", "speed=1.5", "mode=two"] { assert!(a.contains(&expected.into()), "{expected}"); }
        for (name, value) in [("speed", json!(3)), ("mode", json!("three")), ("tint", json!("0 0 0")), ("absent", json!(true)), ("bad name", json!(true))] {
            let mut s = Selection::default();
            s.properties.insert(name.into(), value);
            assert!(args(&s, &e).is_err(), "{name}");
        }
    }

    #[test]
    fn rejects_out_of_range_values() {
        let changes: [fn(&mut Selection); 4] = [|s| s.fps = 0, |s| s.volume = 101, |s| s.scaling = "zoom".into(), |s| s.gpu = "nvidia".into()];
        for change in changes {
            let mut s = Selection::default();
            change(&mut s);
            assert!(args(&s, &entry(json!({}))).is_err());
        }
        assert!(renderer_args("eDP-1;rm", Path::new("/w"), Path::new("/a"), &Selection::default(), &entry(json!({}))).is_err());
    }

    #[test]
    fn inspection_is_conservative() {
        let a = Almamu;
        assert!(a.inspect(&json!({"type": "web", "entrypoint": "/w/index.html"})).is_err_and(|r| r.code == "incompatible"));
        assert!(a.inspect(&json!({"type": "image", "entrypoint": "/w/a.png"})).is_err());
        assert!(a.inspect(&json!({"type": "video", "entrypoint": null})).is_err_and(|r| r.code == "invalid"));
        assert!(a.inspect(&json!({"type": "scene", "entrypoint": null, "packedScene": "/w/scene.pkg", "entryFile": "scene.json"})).is_ok());
        assert!(a.inspect(&json!({"type": "scene", "compatibility": "read-error"})).is_err());
    }

    #[test]
    fn preferences_are_versioned_and_strict() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("orbital.json");
        assert_eq!(load_preferences(&path).unwrap().version, PREFERENCES_VERSION);
        std::fs::write(&path, r#"{"version":2}"#).unwrap();
        assert!(load_preferences(&path).is_err());
        std::fs::write(&path, r#"{"version":1,"unknown":true}"#).unwrap();
        assert!(load_preferences(&path).is_err());
        std::fs::write(&path, r#"{"version":1,"monitors":{"HDMI-A-1":{"location":"/w","fps":24}}}"#).unwrap();
        let prefs = load_preferences(&path).unwrap();
        let s = &prefs.monitors["HDMI-A-1"];
        assert_eq!((s.fps, s.restore_on_start, s.gpu.as_str()), (24, true, "integrated"));
    }

    #[test]
    fn pause_reasons_rank_and_release() {
        assert_eq!(pause_reason(true, false, false, false), None);
        assert_eq!(pause_reason(false, true, true, true), Some("monitor-off"));
        assert_eq!(pause_reason(true, true, true, true), Some("battery"));
        // A context (Gaming, Batería) holds every monitor until it is lifted.
        assert_eq!(pause_reason(true, false, true, true), Some("context"));
        assert_eq!(pause_reason(true, false, true, false), Some("context"));
        assert_eq!(pause_reason(true, false, false, true), Some("resume"));
    }
}
