use crate::util::*;
use regex::Regex;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeSet, HashMap},
    fs,
    os::unix::process::CommandExt,
    path::PathBuf,
    process::{Command, Stdio},
    thread,
    time::Duration,
};
const MARKER: &str = "-- CORTETSU_DISPLAY_MANAGED";
const BEGIN: &str = "-- CORTETSU_WORKSPACE_POLICY_BEGIN";
const END: &str = "-- CORTETSU_WORKSPACE_POLICY_END";
const ALLOWED_CM: [&str; 9] = [
    "auto", "srgb", "dcip3", "dp3", "adobe", "wide", "edid", "hdr", "hdredid",
];
fn cfg() -> PathBuf {
    home().join(".config/hypr/hypr-user.lua")
}
fn saved() -> PathBuf {
    home().join(".config/cortetsu/display-persisted.json")
}
fn workspace_state() -> PathBuf {
    home().join(".config/cortetsu/display-workspaces.json")
}
fn preview_state() -> PathBuf {
    runtime().join("cortetsu-display-preview.json")
}
fn command_lock() -> Result<fs::File> {
    lock(&runtime().join("cortetsu-display.lock"))
}
fn depth(m: &Value) -> i64 {
    let fmt = crate::util::text(m, "current_format", "").to_uppercase();
    if fmt.contains("2101010") || fmt.contains("101010") {
        10
    } else {
        8
    }
}
fn monitors(v: &Value) -> Vec<Value> {
    v["hyprland"].as_array().cloned().unwrap_or_default()
}
#[derive(Clone)]
struct Block {
    start: usize,
    end: usize,
    name: String,
    text: String,
    marker: Option<usize>,
}
fn blocks(text: &str) -> Vec<Block> {
    let mut out = vec![];
    let needle = "hl.monitor({";
    let mut pos = 0;
    let re = Regex::new(r#"(?m)^\s*output\s*=\s*"([^"]+)"\s*,?"#).unwrap();
    while let Some(offset) = text[pos..].find(needle) {
        let start = pos + offset;
        let mut nesting = 0;
        let mut quote = None;
        let mut escaped = false;
        let mut end = None;
        for (i, c) in text[start..].char_indices() {
            if let Some(q) = quote {
                if escaped {
                    escaped = false
                } else if c == '\\' {
                    escaped = true
                } else if c == q {
                    quote = None
                }
                continue;
            }
            if c == '"' || c == '\'' {
                quote = Some(c);
                continue;
            }
            if c == '{' {
                nesting += 1
            } else if c == '}' {
                nesting -= 1;
                if nesting == 0 {
                    if let Some(close) = text[start + i..].find(')') {
                        end = Some(start + i + close + 1)
                    }
                    break;
                }
            }
        }
        let Some(end) = end else { break };
        let body = &text[start..end];
        if let Some(c) = re.captures(body) {
            let marker = text[..start]
                .rfind(MARKER)
                .filter(|i| text[*i + MARKER.len()..start].trim().is_empty());
            out.push(Block {
                start,
                end,
                name: c[1].into(),
                text: body.into(),
                marker,
            });
        }
        pos = end;
    }
    out
}
fn configured() -> HashMap<String, Value> {
    let mut out = HashMap::new();
    let re_cm = Regex::new(r#"(?m)^\s*cm\s*=\s*"([^"]+)"\s*,?"#).unwrap();
    for b in blocks(&fs::read_to_string(cfg()).unwrap_or_default()) {
        let mut m = Map::new();
        for key in ["bitdepth", "vrr"] {
            let re = Regex::new(&format!(r"(?m)^\s*{key}\s*=\s*(\d+)\s*,?")).unwrap();
            if let Some(c) = re.captures(&b.text)
                && let Ok(n) = c[1].parse::<i64>()
            {
                m.insert(key.into(), json!(n));
            }
        }
        if let Some(c) = re_cm.captures(&b.text) {
            m.insert("cm".into(), json!(&c[1]));
        }
        out.insert(b.name, Value::Object(m));
    }
    out
}
pub fn probe() -> Value {
    let root = sysfs().join("class/drm");
    let mut drm = vec![];
    for path in children(&root) {
        let name = basename(&path);
        let Some((card, output)) = name.split_once('-') else {
            continue;
        };
        if !card
            .strip_prefix("card")
            .is_some_and(|c| !c.is_empty() && c.chars().all(|c| c.is_ascii_digit()))
            || output.starts_with("Writeback-")
            || !path.join("status").exists()
        {
            continue;
        }
        let vendor = read(&root.join(card).join("device/vendor")).to_lowercase();
        let vendor = match vendor.as_str() {
            "0x1002" => "AMD",
            "0x10de" => "NVIDIA",
            "0x8086" => "Intel",
            "" => "unknown",
            _ => &vendor,
        };
        let edid = path.join("edid");
        let edid_bytes = fs::metadata(&edid).map(|m| m.len()).unwrap_or(0);
        let mut hdr = Value::Null;
        let mut wide = Value::Null;
        if edid_bytes > 0
            && which("edid-decode").is_some()
            && let Ok(r) = run_str("edid-decode", &[&edid.to_string_lossy()], 3.)
            && r.code == 0
        {
            let text = r.stdout.to_lowercase();
            hdr = json!(
                text.contains("hdr static metadata")
                    || text.contains("smpte st 2084")
                    || text.contains("hybrid log-gamma")
            );
            wide = json!(
                text.contains("bt2020") || text.contains("display p3") || text.contains("dci-p3")
            );
        }
        drm.push(json!({"connector":name,"output_name":output,"card":card,"gpu_vendor":vendor,"status":read_default(&path.join("status"),"unknown"),"enabled":read_default(&path.join("enabled"),"unknown"),"modes":read(&path.join("modes")).lines().filter(|s|!s.is_empty()).collect::<Vec<_>>(),"vrr_capable":integer(&path.join("vrr_capable")),"max_bpc":integer(&path.join("max_bpc")),"edid_bytes":edid_bytes,"hdr_capable":hdr,"wide_color_capable":wide}));
    }
    let configs = configured();
    let raw = hypr_json(&["-j", "monitors", "all"]);
    let mut hypr = vec![];
    for m in raw
        .as_array()
        .into_iter()
        .flatten()
        .filter(|m| m.is_object())
    {
        let name = crate::util::text(m, "name", "");
        let d = drm
            .iter()
            .find(|d| d["output_name"] == name)
            .cloned()
            .unwrap_or(json!({}));
        let config = configs.get(&name).cloned().unwrap_or(json!({}));
        let mut v = json!({"id":m["id"],"name":name,"description":m.get("description").unwrap_or(&json!("")),"make":m.get("make").unwrap_or(&json!("")),"model":m.get("model").unwrap_or(&json!("")),"serial":m.get("serial").unwrap_or(&json!("")),"width":m["width"],"height":m["height"],"refresh_hz":m["refreshRate"],"x":m["x"],"y":m["y"],"scale":m["scale"],"transform":m["transform"],"focused":truth(&m["focused"]),"disabled":truth(&m["disabled"]),"dpms":m["dpmsStatus"],"vrr":m["vrr"],"current_format":m["currentFormat"],"available_modes":m["availableModes"].as_array().cloned().unwrap_or_default(),"workspace":m.get("activeWorkspace").unwrap_or(&json!({})),"special_workspace":m.get("specialWorkspace").unwrap_or(&json!({})),"gpu_vendor":d.get("gpu_vendor").unwrap_or(&json!("unknown")),"drm_card":d.get("card").unwrap_or(&json!("")),"drm_connector":d.get("connector").unwrap_or(&json!("")),"drm_status":d.get("status").unwrap_or(&json!("unknown")),"edid_bytes":d.get("edid_bytes").unwrap_or(&json!(0)),"configured_bitdepth":config["bitdepth"],"configured_cm":config["cm"],"configured_vrr":config["vrr"]});
        v["color_management_preset"] = m["colorManagementPreset"].clone();
        for key in [
            "vrr_capable",
            "max_bpc",
            "hdr_capable",
            "wide_color_capable",
        ] {
            v[key] = d[key].clone()
        }
        hypr.push(v)
    }
    let raw = hypr_json(&["-j", "workspaces"]);
    let workspaces=raw.as_array().into_iter().flatten().filter(|v|v.is_object()).map(|v|json!({"id":v["id"],"name":v.get("name").unwrap_or(&json!("")),"monitor":v.get("monitor").unwrap_or(&json!("")),"monitor_id":v["monitorID"],"windows":v.get("windows").unwrap_or(&json!(0)),"last_window":v.get("lastwindow").unwrap_or(&json!("")),"last_window_title":v.get("lastwindowtitle").unwrap_or(&json!(""))})).collect::<Vec<_>>();
    let vendors = hypr
        .iter()
        .map(|m| crate::util::text(m, "gpu_vendor", "unknown"))
        .collect::<BTreeSet<_>>();
    json!({"hyprland":hypr,"drm":drm,"workspaces":workspaces,"summary":{"connected":hypr.iter().filter(|m|!truth(&m["disabled"])).count(),"focused":hypr.iter().find(|m|truth(&m["focused"])).map(|m|crate::util::text(m,"name","")).unwrap_or_default(),"gpu_vendors":vendors},"write_capability":false,"planner_capability":true,"capability_policy":"HDR/wide-color are reported only when edid-decode can establish support; unknown remains null. VRR/max_bpc come from DRM sysfs when exposed.","rollback_policy":"configured cm/bitdepth/vrr are read from hypr-user.lua when present so preview rollback can restore color policy as well as geometry","safety":"probe is read-only; monitor writes require the preview/confirm/persist workflow"})
}
fn dimensions(mode: &str) -> Option<(f64, f64)> {
    let head = mode.split('@').next()?;
    let (a, b) = head.split_once('x')?;
    Some((a.parse::<f64>().ok()?, b.parse::<f64>().ok()?))
}
fn scale_text(scale: f64) -> String {
    if scale.fract() == 0. {
        format!("{scale:.1}")
    } else {
        scale.to_string()
    }
}
pub fn plan(candidate: &Value, snapshot: &Value) -> Result<Value> {
    if !candidate.is_object() {
        return Err("candidate root must be an object".into());
    }
    let outputs = candidate["outputs"]
        .as_array()
        .ok_or("candidate.outputs must be an array")?;
    let current = monitors(snapshot);
    let mut errors = vec![];
    let mut warnings = vec![];
    let mut normalized = vec![];
    let mut seen = BTreeSet::new();
    for (index, raw) in outputs.iter().enumerate() {
        if !raw.is_object() {
            errors.push(format!("outputs[{index}] must be an object"));
            continue;
        }
        let name = crate::util::text(raw, "name", "").trim().to_string();
        if name.is_empty() {
            errors.push(format!("outputs[{index}] has no name"));
            continue;
        }
        if name.chars().any(|c| c.is_control() || c == ',') {
            errors.push(format!("{name}: invalid output name"));
            continue;
        }
        if !seen.insert(name.clone()) {
            errors.push(format!("duplicate output {name}"));
            continue;
        }
        let Some(monitor) = current.iter().find(|m| m["name"] == name) else {
            errors.push(format!("output {name} is not currently known to Hyprland"));
            continue;
        };
        if !raw.get("enabled").map(truth).unwrap_or(true) {
            normalized.push(json!({"name":name,"enabled":false}));
            continue;
        }
        let mut mode = crate::util::text(raw, "mode", "").trim().to_string();
        if mode.is_empty() {
            let (w, h, r) = (
                i(monitor, "width", 0),
                i(monitor, "height", 0),
                f(monitor, "refresh_hz", 0.),
            );
            mode = if w != 0 && h != 0 && r != 0. {
                format!("{w}x{h}@{r:.2}Hz")
            } else {
                "preferred".into()
            };
        }
        let allowed = monitor["available_modes"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        if !["preferred", "highrr", "highres"].contains(&mode.as_str())
            && !allowed.is_empty()
            && !allowed.iter().any(|m| s(m) == mode)
        {
            errors.push(format!(
                "{name}: mode {mode} is not in Hyprland availableModes"
            ));
        }
        if mode.contains(',') || mode.chars().any(char::is_control) {
            errors.push(format!("{name}: invalid mode"));
        }
        let scale_valid = raw
            .get("scale")
            .or_else(|| monitor.get("scale"))
            .map(as_f)
            .unwrap_or(Some(1.))
            .is_some();
        let scale = raw
            .get("scale")
            .or_else(|| monitor.get("scale"))
            .map(|v| as_f(v).unwrap_or(-1.))
            .unwrap_or(1.);
        if !(0.5..=3.).contains(&scale) || !scale.is_finite() {
            errors.push(format!(
                "{name}: scale {} outside safe range 0.5..3.0",
                if scale_valid {
                    scale_text(scale)
                } else {
                    "-1".into()
                }
            ));
        }
        let nums = [
            ("x", 0),
            ("y", 0),
            ("transform", 0),
            ("bitdepth", depth(monitor)),
            ("vrr", if truth(&monitor["vrr"]) { 1 } else { 0 }),
        ]
        .iter()
        .map(|(key, default)| {
            raw.get(*key)
                .or_else(|| {
                    if ["x", "y", "transform"].contains(key) {
                        monitor.get(*key)
                    } else {
                        None
                    }
                })
                .map(as_i)
                .unwrap_or(Some(*default))
        })
        .collect::<Option<Vec<_>>>();
        let Some(nums) = nums else {
            errors.push(format!(
                "{name}: x/y/transform/bitdepth/vrr must be numeric"
            ));
            continue;
        };
        let (x, y, transform, bitdepth, vrr) = (nums[0], nums[1], nums[2], nums[3], nums[4]);
        if !(0..=7).contains(&transform) {
            errors.push(format!(
                "{name}: transform {transform} outside Hyprland range 0..7"
            ))
        }
        if ![8, 10].contains(&bitdepth) {
            errors.push(format!("{name}: bitdepth must be 8 or 10"))
        }
        if bitdepth == 10 && !(i(monitor, "max_bpc", 0) >= 10 || depth(monitor) == 10) {
            errors.push(format!(
                "{name}: 10-bit was requested but support is not established by DRM/current format"
            ))
        }
        if !(0..=3).contains(&vrr) {
            errors.push(format!("{name}: vrr {vrr} outside Hyprland range 0..3"))
        }
        if vrr > 0 && !truth(&monitor["vrr_capable"]) {
            errors.push(format!(
                "{name}: VRR was requested but DRM does not report VRR capability"
            ))
        }
        let cm = crate::util::text(raw, "cm", "srgb").trim().to_lowercase();
        let cm = if cm.is_empty() {
            "srgb".to_string()
        } else {
            cm
        };
        if !ALLOWED_CM.contains(&cm.as_str()) {
            errors.push(format!("{name}: unsupported color-management preset {cm}"))
        }
        if ["wide", "hdr", "hdredid"].contains(&cm.as_str()) && bitdepth != 10 {
            errors.push(format!(
                "{name}: {cm} requires 10-bit in Cortetsu safety policy"
            ))
        }
        if ["hdr", "hdredid"].contains(&cm.as_str()) && monitor["hdr_capable"] != true {
            errors.push(format!(
                "{name}: HDR requested but EDID support is not established"
            ))
        }
        if cm == "wide" && monitor["wide_color_capable"] != true {
            errors.push(format!(
                "{name}: wide color requested but EDID support is not established"
            ))
        }
        if cm == "auto" && bitdepth == 10 && monitor["wide_color_capable"] != true {
            warnings.push(format!(
                "{name}: 10-bit auto color mode has no established wide-color EDID capability"
            ))
        }
        normalized.push(json!({"name":name,"enabled":true,"mode":mode,"x":x,"y":y,"scale":if scale_valid {round(scale,3)} else {json!(-1)},"transform":transform,"bitdepth":bitdepth,"cm":cm,"vrr":vrr}));
    }
    if normalized.is_empty() {
        errors.push("candidate contains no valid outputs".into())
    } else if !normalized.iter().any(|m| m["enabled"] == true) {
        errors.push("candidate disables every output".into())
    }
    let enabled = normalized
        .iter()
        .filter(|m| m["enabled"] == true)
        .collect::<Vec<_>>();
    for (a, left) in enabled.iter().enumerate() {
        let Some((lw, lh)) = dimensions(&crate::util::text(left, "mode", "")) else {
            continue;
        };
        let (lw, lh) = (
            lw / f(left, "scale", 1.).max(0.5),
            lh / f(left, "scale", 1.).max(0.5),
        );
        for right in &enabled[a + 1..] {
            let Some((rw, rh)) = dimensions(&crate::util::text(right, "mode", "")) else {
                continue;
            };
            let (rw, rh) = (
                rw / f(right, "scale", 1.).max(0.5),
                rh / f(right, "scale", 1.).max(0.5),
            );
            let overlap = !(f(left, "x", 0.) + lw <= f(right, "x", 0.)
                || f(right, "x", 0.) + rw <= f(left, "x", 0.)
                || f(left, "y", 0.) + lh <= f(right, "y", 0.)
                || f(right, "y", 0.) + rh <= f(left, "y", 0.));
            if overlap {
                warnings.push(format!(
                    "{} and {} overlap; this may be intentional for mirroring",
                    s(&left["name"]),
                    s(&right["name"])
                ));
            }
        }
    }
    let mut commands = vec![];
    let mut lines = vec![];
    if errors.is_empty() {
        for m in &normalized {
            let value = if m["enabled"] != true {
                format!("{},disable", s(&m["name"]))
            } else {
                format!(
                    "{},{},{}x{},{},transform,{},bitdepth,{},cm,{},vrr,{}",
                    s(&m["name"]),
                    s(&m["mode"]),
                    m["x"],
                    m["y"],
                    scale_text(f(m, "scale", 1.)),
                    m["transform"],
                    m["bitdepth"],
                    s(&m["cm"]),
                    m["vrr"]
                )
            };
            commands.push(json!(["hyprctl", "keyword", "monitor", value]));
            lines.push(format!("monitor = {value}"));
        }
    }
    Ok(
        json!({"ok":errors.is_empty(),"errors":errors,"warnings":warnings,"candidate":{"outputs":normalized},"commands":commands,"hypr_lines":lines,"applied":false,"safety":"dry-run only; 10-bit/VRR/HDR require established capability; no hyprctl write command was executed"}),
    )
}
fn checked_plan(c: &Value) -> Result<Value> {
    let p = plan(c, &probe())?;
    if p["ok"] != true {
        return Err(format!("candidate validation failed: {}", p["errors"]));
    }
    Ok(p)
}
fn mode_for(m: &Value) -> String {
    let modes = m["available_modes"].as_array().cloned().unwrap_or_default();
    let mut best = None;
    for mode in &modes {
        let text = s(mode);
        if let Some((dim, hz)) = text.split_once('@')
            && let Some((w, h)) = dimensions(dim)
            && w as i64 == i(m, "width", 0)
            && h as i64 == i(m, "height", 0)
            && let Ok(hz) = hz.trim_end_matches("Hz").parse::<f64>()
        {
            let delta = (hz - f(m, "refresh_hz", 0.)).abs();
            if best.as_ref().is_none_or(|(d, _)| delta < *d) {
                best = Some((delta, text));
            }
        }
    }
    best.map(|(_, s)| s).unwrap_or_else(|| {
        let (width, height, hz) = (i(m, "width", 0), i(m, "height", 0), f(m, "refresh_hz", 0.));
        if width > 0 && height > 0 && hz > 0. {
            format!("{width}x{height}@{hz:.2}Hz")
        } else {
            "preferred".into()
        }
    })
}
fn candidate_from_snapshot(snap: &Value) -> Value {
    let outputs = monitors(snap)
        .iter()
        .filter(|m| m.is_object())
        .map(|m| {
            let bitdepth = m["configured_bitdepth"]
                .as_i64()
                .filter(|n| [8, 10].contains(n))
                .unwrap_or_else(|| depth(m));
            let vrr = m["configured_vrr"]
                .as_i64()
                .filter(|n| (0..=3).contains(n))
                .unwrap_or_else(|| if truth(&m["vrr"]) { 1 } else { 0 });
            let cm = m["configured_cm"]
                .as_str()
                .filter(|s| !s.trim().is_empty())
                .unwrap_or("srgb");
            json!({"name":text(m,"name",""),"enabled":!truth(&m["disabled"]),
            "mode":mode_for(m),"x":i(m,"x",0),"y":i(m,"y",0),
            "scale":f(m,"scale",1.),"transform":i(m,"transform",0),
            "bitdepth":bitdepth,"cm":cm,"vrr":vrr,
            "observed_cm":m["color_management_preset"],"observed_bitdepth":depth(m),
            "observed_vrr":m["vrr"]})
        })
        .collect::<Vec<_>>();
    json!({"outputs":outputs})
}
fn lua_command(command: &Value) -> Result<String> {
    let a = command
        .as_array()
        .ok_or("planner returned an unexpected command")?;
    if a.len() != 4 || a[0] != "hyprctl" || a[1] != "keyword" || a[2] != "monitor" {
        return Err("planner returned an unexpected command".into());
    }
    let fields = a[3]
        .as_str()
        .ok_or("invalid monitor command")?
        .split(',')
        .collect::<Vec<_>>();
    if fields.len() < 2 || fields[0].is_empty() {
        return Err("planner returned an invalid monitor command".into());
    }
    if fields.len() == 2 && fields[1] == "disable" {
        return Ok(format!(
            "hl.monitor({{ output = {}, disable = true }})",
            json!(fields[0])
        ));
    }
    if fields.len() < 4 {
        return Err("planner returned an incomplete monitor command".into());
    }
    let mut fieldsmap = HashMap::from([
        ("mode", fields[1]),
        ("position", fields[2]),
        ("scale", fields[3]),
    ]);
    for pair in fields[4..].as_chunks::<2>().0 {
        fieldsmap.insert(pair[0], pair[1]);
    }
    let mut lua = vec![format!("output = {}", json!(fields[0]))];
    for key in [
        "mode",
        "position",
        "scale",
        "transform",
        "bitdepth",
        "cm",
        "vrr",
    ] {
        if let Some(raw) = fieldsmap.get(key) {
            let value = match key {
                "scale" => raw.parse::<f64>().map_err(|e| e.to_string())?.to_string(),
                "transform" | "bitdepth" | "vrr" => {
                    raw.parse::<i64>().map_err(|e| e.to_string())?.to_string()
                }
                _ => json!(raw).to_string(),
            };
            lua.push(format!("{key} = {value}"));
        }
    }
    Ok(format!("hl.monitor({{{}}})", lua.join(", ")))
}
fn execute(plan: &Value) -> Result<()> {
    if plan["ok"] != true {
        return Err("candidate plan is not valid".into());
    }
    for cmd in plan["commands"]
        .as_array()
        .ok_or("planner returned unexpected commands")?
    {
        let lua = lua_command(cmd)?;
        let r = hypr(&["eval", &lua], 6.)?;
        if r.code != 0 {
            return Err(r.detail());
        }
    }
    Ok(())
}
fn verify(candidate: &Value, color: bool) -> Result<()> {
    let live = probe();
    let current = monitors(&live);
    for item in candidate["outputs"].as_array().into_iter().flatten() {
        let name = crate::util::text(item, "name", "");
        let m = current.iter().find(|m| m["name"] == name);
        if item["enabled"] == false {
            if m.is_some_and(|m| m["disabled"] != true) {
                return Err(format!("{name} remained enabled after persistence"));
            }
            continue;
        }
        let m = m
            .filter(|m| m["disabled"] != true)
            .ok_or_else(|| format!("{name} is not active after display change"))?;
        let mode = crate::util::text(item, "mode", "");
        if let Some((width, height)) = dimensions(&mode)
            && ((f(m, "width", 0.) - width).abs() > 1. || (f(m, "height", 0.) - height).abs() > 1.)
        {
            return Err(format!("{name} mode did not match preview"));
        }
        if let Some((_, refresh)) = mode.split_once('@')
            && let Ok(hz) = refresh.trim_end_matches("Hz").parse::<f64>()
            && (f(m, "refresh_hz", 0.) - hz).abs() > 0.1
        {
            return Err(format!("{name} refresh rate did not match preview"));
        }
        if i(m, "transform", 0) != i(item, "transform", 0) {
            return Err(format!("{name} transform did not match preview"));
        }
        if (f(m, "scale", 1.) - f(item, "scale", 1.)).abs() > 0.03 {
            return Err(format!("{name} scale did not match preview"));
        }
        for key in ["x", "y"] {
            if (i(m, key, 0) - i(item, key, 0)).abs() > 2 {
                return Err(format!("{name} {key} position did not match preview"));
            }
        }
        if color && depth(m) != i(item, "bitdepth", 8) {
            return Err(format!("{name} bit depth did not match preview"));
        }
        if color && let Some(actual) = m["color_management_preset"].as_str() {
            let expected = item["cm"].as_str().unwrap_or("srgb");
            let alias = |s: &str| {
                if s == "dcip3" {
                    "dp3".to_string()
                } else {
                    s.to_string()
                }
            };
            if expected != "auto" && alias(expected) != alias(actual) {
                return Err(format!("{name} color management did not match preview"));
            }
        }
        if color && i(item, "vrr", 0) == 0 && truth(&m["vrr"]) {
            return Err(format!("{name} VRR remained enabled after display change"));
        }
        if color && i(item, "vrr", 0) == 1 && !truth(&m["vrr"]) {
            return Err(format!("{name} always-on VRR did not become active"));
        }
    }
    Ok(())
}
fn restore_original(original: &Value) -> Result<()> {
    let p = checked_plan(original).map_err(|e| format!("could not plan original layout: {e}"))?;
    execute(&p)?;
    thread::sleep(Duration::from_millis(700));
    verify(original, true)
}
fn session() -> String {
    std::env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default()
}
fn load_preview() -> Result<Value> {
    let path = preview_state();
    if !path.exists() {
        return Ok(json!({}));
    }
    let raw = fs::read(&path).map_err(|e| e.to_string())?;
    let v: Value =
        serde_json::from_slice(&raw).map_err(|_| "display journal is corrupt; left untouched")?;
    if !v.is_object() {
        return Err("display journal is not an object; left untouched".into());
    }
    if v.get("instance").is_some_and(|i| i != &session()) {
        return Err("display preview belongs to another Hyprland session".into());
    }
    Ok(v)
}
fn configuration_fingerprint() -> String {
    format!("{:x}", Sha256::digest(fs::read(cfg()).unwrap_or_default()))
}
fn same_observation(a: &Value, b: &Value) -> bool {
    if let (Some(a), Some(b)) = (a.as_f64(), b.as_f64()) {
        a == b
    } else {
        a == b
    }
}
fn guarded_rollback(state: &Value) -> Result<Value> {
    if state
        .get("configuration_fingerprint")
        .is_some_and(|fp| fp != &configuration_fingerprint())
    {
        return Err(
            "configuration changed externally during preview; rollback left pending".into(),
        );
    }
    let live = candidate_from_snapshot(&probe());
    let expected = state.get("applied").unwrap_or(&state["candidate"]);
    let mut restore = Vec::new();
    for target in state["candidate"]["outputs"]
        .as_array()
        .ok_or("invalid preview candidate")?
    {
        let name = &target["name"];
        let original = state["original"]["outputs"]
            .as_array()
            .and_then(|a| a.iter().find(|o| &o["name"] == name))
            .ok_or("original output missing; rollback left pending")?;
        let applied = expected["outputs"]
            .as_array()
            .and_then(|a| a.iter().find(|o| &o["name"] == name))
            .unwrap_or(target);
        let current = live["outputs"]
            .as_array()
            .and_then(|a| a.iter().find(|o| &o["name"] == name))
            .ok_or("output disconnected; rollback left pending")?;
        for key in [
            "enabled",
            "mode",
            "x",
            "y",
            "scale",
            "transform",
            "bitdepth",
            "vrr",
        ] {
            if !same_observation(&current[key], &applied[key])
                && !same_observation(&current[key], &original[key])
            {
                return Err(format!(
                    "{} {key} changed externally; rollback left pending",
                    s(name)
                ));
            }
        }
        // Configuration describes desired policy, while these fields describe
        // what the compositor actually did. Preserve direct external changes
        // even when nobody edited the saved configuration file.
        for key in ["observed_cm", "observed_bitdepth", "observed_vrr"] {
            if original.get(key).is_some_and(|v| !v.is_null())
                && applied.get(key).is_some_and(|v| !v.is_null())
                && !same_observation(&current[key], &applied[key])
                && !same_observation(&current[key], &original[key])
            {
                return Err(format!(
                    "{} {key} changed externally; rollback left pending",
                    s(name)
                ));
            }
        }
        restore.push(original.clone());
    }
    Ok(json!({"outputs":restore}))
}

fn revert_internal(token: Option<&str>) -> (Value, i32) {
    let mut state = match load_preview() {
        Ok(x) => x,
        Err(e) => return json_error(e),
    };
    if state["active"] != true {
        return (
            json!({"ok":true,"reverted":false,"reason":"no active preview"}),
            0,
        );
    }
    if token.is_some_and(|t| state["token"] != t) {
        return (json!({"ok":false,"error":"preview token mismatch"}), 3);
    }
    match guarded_rollback(&state).and_then(|original| restore_original(&original)) {
        Ok(()) => match remove(&preview_state()) {
            Ok(()) => (
                json!({"ok":true,"reverted":true,"error":"","restored_color_policy":true}),
                0,
            ),
            Err(e) => json_error(e),
        },
        Err(e) => {
            state["recovery_required"] = json!(true);
            state["last_error"] = json!(e);
            let _ = atomic_json(&preview_state(), &state);
            (
                json!({"ok":false,"reverted":false,"error":e,"restored_color_policy":false,"recovery_required":true}),
                5,
            )
        }
    }
}
fn preview(candidate: &Value, timeout: i64) -> (Value, i32) {
    let existing = match load_preview() {
        Ok(v) => v,
        Err(e) => return json_error(e),
    };
    if existing["active"] == true {
        return (
            json!({"ok":false,"error":"a display preview is already active","state":existing}),
            4,
        );
    }
    let plan = match checked_plan(candidate) {
        Ok(p) => p,
        Err(e) => return json_error(e),
    };
    let original = candidate_from_snapshot(&probe());
    if let Err(e) = checked_plan(&original) {
        return json_error(format!("could not snapshot current layout: {e}"));
    }
    let token = nonce();
    let started = now();
    let normalized = plan["candidate"].clone();
    let mut state = json!({"active":true,"token":token,"started":started as i64,"deadline":started+timeout as f64,"timeout_seconds":timeout,"original":original,"candidate":normalized,"confirmed":false,"instance":session(),"configuration_fingerprint":configuration_fingerprint()});
    if let Err(e) = atomic_json(&preview_state(), &state) {
        return json_error(e);
    }
    let watcher = std::env::current_exe()
        .map_err(|e| e.to_string())
        .and_then(|exe| {
            Command::new(exe)
                .args(["cortetsu-display-transaction", "watch", "--token", &token])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .process_group(0)
                .spawn()
                .map_err(|e| e.to_string())
        });
    if let Err(e) = watcher {
        let _ = remove(&preview_state());
        return json_error(format!("cannot start display rollback watcher: {e}"));
    }
    let applied = execute(&plan);
    if applied.is_ok() {
        thread::sleep(Duration::from_millis(700))
    }
    let result = applied.and_then(|_| verify(&normalized, true));
    if let Err(e) = result {
        let (rollback, code) = revert_internal(Some(&token));
        return (
            json!({"ok":false,"error":e,"reverted":rollback["reverted"],"recovery_required":code!=0,"rollback":rollback}),
            5,
        );
    }
    state["applied"] = candidate_from_snapshot(&probe());
    if let Err(e) = atomic_json(&preview_state(), &state) {
        return json_error(e);
    }
    (
        json!({"ok":true,"preview":true,"deadline":state["deadline"],"timeout_seconds":timeout,"token":token,"candidate":normalized,"rollback_captures_color_policy":true}),
        0,
    )
}
pub fn transaction(args: &[String]) -> (Value, i32) {
    let action = args.first().map(String::as_str).unwrap_or("");
    if action == "watch" {
        let Some(token) = flag(args, "--token") else {
            return json_error("missing --token".into());
        };
        loop {
            let state = match load_preview() {
                Ok(v) => v,
                Err(e) => return json_error(e),
            };
            if state["token"] != token || state["active"] != true {
                return (Value::Null, 0);
            }
            let remaining = f(&state, "deadline", 0.) - now();
            if remaining <= 0. {
                let _owner_lock = match crate::owner::domain_lock("display") {
                    Ok(l) => l,
                    Err(e) => return json_error(e),
                };
                let _lock = match command_lock() {
                    Ok(l) => l,
                    Err(e) => return json_error(e),
                };
                let result = revert_internal(Some(token));
                return (Value::Null, result.1);
            }
            if !wait_interruptible(remaining.clamp(0.1, 0.5)) {
                return (Value::Null, 130);
            }
        }
    }
    let _lock = match command_lock() {
        Ok(l) => l,
        Err(e) => return json_error(e),
    };
    match action {
        "status" => match load_preview() {
            Ok(v) if v["active"] == true => (
                json!({"active":true,"token":v["token"],"started":v["started"],"deadline":v["deadline"],"remaining_seconds":round((f(&v,"deadline",0.)-now()).max(0.),1),"candidate":v["candidate"],"rollback":v["original"]}),
                0,
            ),
            Ok(_) => (json!({"active":false}), 0),
            Err(e) => json_error(e),
        },
        "preview" => {
            let Some(raw) = flag(args, "--candidate") else {
                return json_error("missing --candidate".into());
            };
            let candidate = match serde_json::from_str(raw) {
                Ok(c) => c,
                Err(e) => return json_error(e.to_string()),
            };
            match flag(args, "--timeout").unwrap_or("15").parse::<i64>() {
                Ok(timeout) => preview(&candidate, timeout.clamp(8, 30)),
                Err(e) => json_error(e.to_string()),
            }
        }
        "revert" | "recover" => revert_internal(None),
        "confirm" => {
            let mut state = match load_preview() {
                Ok(v) => v,
                Err(e) => return json_error(e),
            };
            if state["active"] != true {
                return (json!({"ok":false,"error":"no active preview"}), 2);
            }
            if f(&state, "deadline", 0.) <= now() {
                return revert_internal(None);
            }
            if let Err(e) = verify(&state["candidate"], true) {
                return json_error(format!("preview readback failed: {e}"));
            }
            state["confirmed"] = json!(true);
            state["active"] = json!(false);
            if let Err(e) = atomic_json(&preview_state(), &state).and_then(|_| remove(&preview_state())) {
                return json_error(e);
            }
            (
                json!({"ok":true,"confirmed":true,"persistent":false,"candidate":state["candidate"],"note":"layout kept for this Hyprland session; persistence is a separate step"}),
                0,
            )
        }
        _ => json_error("usage: preview --candidate JSON [--timeout N] | confirm | revert | status | watch --token TOKEN".into()),
    }
}

fn set_field(block: &str, key: &str, value: &str) -> Result<String> {
    let p = Regex::new(&format!(
        r"(?m)^([ \t]*){}\s*=\s*[^\n]*$",
        regex::escape(key)
    ))
    .map_err(|e| e.to_string())?;
    if let Some(c) = p.captures(block) {
        let m = c.get(0).unwrap();
        return Ok(format!(
            "{}{}{key} = {value},{}",
            &block[..m.start()],
            &c[1],
            &block[m.end()..]
        ));
    }
    let close = block
        .rfind("})")
        .ok_or_else(|| format!("malformed hl.monitor block while adding {key}"))?;
    Ok(format!(
        "{}\n    {key} = {value},\n{}",
        block[..close].trim_end(),
        &block[close..]
    ))
}
fn remove_field(block: &str, key: &str) -> String {
    let p = Regex::new(&format!(
        r"(?m)^[ \t]*{}\s*=\s*[^\n]*\n?",
        regex::escape(key)
    ))
    .unwrap();
    p.replace(block, "").to_string()
}
fn render_block(item: &Value, existing: Option<&str>) -> Result<String> {
    let name = crate::util::text(item, "name", "");
    if name.is_empty() {
        return Err("cannot persist unnamed output".into());
    }
    let mut block = existing
        .map(str::to_string)
        .unwrap_or_else(|| format!("hl.monitor({{\n    output = {},\n}})", json!(name)));
    if item["enabled"] != false {
        block = remove_field(&remove_field(&block, "disabled"), "disable");
        for (key, value) in [
            (
                "mode",
                json!(crate::util::text(item, "mode", "preferred")).to_string(),
            ),
            (
                "position",
                json!(format!("{}x{}", i(item, "x", 0), i(item, "y", 0))).to_string(),
            ),
            ("scale", f(item, "scale", 1.).to_string()),
            ("transform", i(item, "transform", 0).to_string()),
        ] {
            block = set_field(&block, key, &value)?
        }
    } else {
        block = set_field(&block, "disabled", "true")?
    }
    Ok(format!("{MARKER}\n{block}"))
}
fn rewrite_config(text: &str, candidate: &Value) -> Result<(String, Vec<String>)> {
    let bs = blocks(text);
    let mut replacements = vec![];
    let mut additions = vec![];
    let mut managed = vec![];
    for item in candidate["outputs"].as_array().into_iter().flatten() {
        let name = crate::util::text(item, "name", "");
        if name.is_empty() {
            continue;
        }
        let existing = bs.iter().rev().find(|b| b.name == name);
        let rendered = render_block(item, existing.map(|b| b.text.as_str()))?;
        managed.push(name);
        if let Some(b) = existing {
            replacements.push((b.marker.unwrap_or(b.start), b.end, rendered))
        } else {
            additions.push(rendered)
        }
    }
    let mut updated = text.to_string();
    replacements.sort_by_key(|r| std::cmp::Reverse(r.0));
    for (start, end, rendered) in replacements {
        updated.replace_range(start..end, &rendered)
    }
    if !additions.is_empty() {
        let payload = format!("\n\n{}\n\n", additions.join("\n\n"));
        let anchor = "-- ============================================================\n-- APLICACIONES PERSONALIZADAS";
        if let Some(i) = updated.find(anchor) {
            updated.insert_str(i, &payload)
        } else {
            updated = format!("{}{payload}\n", updated.trim_end())
        }
    }
    Ok((updated, managed))
}
fn workspace_policy(candidate: &Value) -> Result<(String, String, String)> {
    let outputs = candidate["outputs"]
        .as_array()
        .ok_or("invalid outputs")?
        .iter()
        .filter(|m| m["enabled"] != false)
        .collect::<Vec<_>>();
    let primary = outputs
        .iter()
        .find(|m| crate::util::text(m, "name", "").starts_with("eDP-"))
        .or_else(|| outputs.first())
        .ok_or("no enabled output")?;
    let m1 = crate::util::text(primary, "name", "");
    let m2 = outputs
        .iter()
        .find(|m| m["name"] != m1 && !crate::util::text(m, "name", "").starts_with("eDP-"))
        .map(|m| crate::util::text(m, "name", ""))
        .unwrap_or_else(|| m1.clone());
    let block = format!(
        "{BEGIN}\n-- Managed by Display Manager. 1-10 follow the internal/primary output;\n-- 11-20 follow the selected external output and fall back to the primary output.\nfor i = 1, 10 do\n    hl.workspace_rule({{\n        workspace = tostring(i),\n        monitor = {},\n        default = i == 1,\n        persistent = true,\n    }})\n\n    hl.workspace_rule({{\n        workspace = tostring(i + 10),\n        monitor = {},\n        default = i == 1,\n        persistent = true,\n    }})\nend\n{END}",
        json!(m1),
        json!(m2)
    );
    Ok((block, m1, m2))
}
fn rewrite_workspace(text: &str, block: &str) -> String {
    if let Some(a) = text.find(BEGIN)
        && let Some(b) = text[a..].find(END)
    {
        return format!("{}{}{}", &text[..a], block, &text[a + b + END.len()..]);
    }
    let anchor = "-- ============================================================\n-- TECLADO";
    let payload = format!("\n\n{block}\n\n");
    if let Some(i) = text.find(anchor) {
        format!("{}{payload}{}", &text[..i], &text[i..])
    } else {
        format!("{}{payload}\n", text.trim_end())
    }
}
fn output_policy(text: &str, candidate: &Value) -> Result<(String, Vec<String>)> {
    let mut updates = vec![];
    let mut changed = vec![];
    for b in blocks(text) {
        if b.marker.is_none() {
            continue;
        }
        let Some(m) = candidate["outputs"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|m| m["name"] == b.name && m["enabled"] != false)
        else {
            continue;
        };
        let mut body = b.text.clone();
        for (key, value) in [
            ("bitdepth", i(m, "bitdepth", 8).to_string()),
            ("cm", json!(crate::util::text(m, "cm", "srgb")).to_string()),
            ("vrr", i(m, "vrr", 0).to_string()),
        ] {
            body = set_field(&body, key, &value)?
        }
        if body != b.text {
            updates.push((b.start, b.end, body));
            changed.push(b.name)
        }
    }
    let mut updated = text.to_string();
    updates.sort_by_key(|x| std::cmp::Reverse(x.0));
    for (start, end, body) in updates {
        updated.replace_range(start..end, &body)
    }
    Ok((updated, changed))
}
fn backup(prefix: &str, original: &str) -> Result<PathBuf> {
    let path = home()
        .join(".local/share/cortetsu/upstream/snapshots")
        .join(format!("{prefix}-{}-{}", timestamp(), &nonce()[..8]))
        .join("hypr-user.lua");
    atomic(&path, original.as_bytes())?;
    Ok(path)
}
fn reload() -> Result<()> {
    let r = hypr(&["reload"], 10.)?;
    if r.code == 0 { Ok(()) } else { Err(r.detail()) }
}
fn restore_file(original: &str, expected: &str, live: Option<&Value>) -> Result<()> {
    let current = fs::read_to_string(cfg()).map_err(|e| e.to_string())?;
    if current != expected {
        return Err(
            "configuration changed externally; backup preserved, automatic overwrite refused"
                .into(),
        );
    }
    atomic(&cfg(), original.as_bytes())?;
    reload()?;
    if let Some(c) = live {
        restore_original(c)?
    }
    Ok(())
}
fn sync_inner(candidate: &Value) -> Result<(Value, i32)> {
    if !cfg().is_file() {
        return Ok((
            json!({"ok":false,"error":format!("missing {}",cfg().display())}),
            2,
        ));
    }
    let normalized = checked_plan(candidate)?["candidate"].clone();
    let (block, m1, m2) = workspace_policy(&normalized)?;
    let original = fs::read_to_string(cfg()).map_err(|e| e.to_string())?;
    let (updated, color) = output_policy(&original, &normalized)?;
    let updated = rewrite_workspace(&updated, &block);
    let backup = backup("display-workspaces", &original)?;
    if fs::read_to_string(cfg()).map_err(|e| e.to_string())? != original {
        return Err("configuration changed externally before persistence".into());
    }
    atomic(&cfg(), updated.as_bytes())?;
    if let Err(e) = reload().and_then(|_| verify(&normalized, true)) {
        let rollback = restore_file(&original, &updated, None);
        return Ok((
            json!({"ok":false,"error":e,"rolled_back":rollback.is_ok(),"rollback_error":rollback.err(),"backup":backup}),
            4,
        ));
    }
    let state = json!({"version":2,"primary":m1,"secondary":m2,"saved_at":now()as i64,"backup":backup,"output_policy":color});
    atomic_json(&workspace_state(), &state)?;
    Ok((
        json!({"ok":true,"synced":true,"primary":m1,"secondary":m2,"output_policy":color,"backup":backup}),
        0,
    ))
}
pub fn workspaces(args: &[String]) -> (Value, i32) {
    if args.first().map(String::as_str) == Some("status") {
        let text = fs::read_to_string(cfg()).unwrap_or_default();
        return (
            json!({"ok":true,"managed":text.contains(BEGIN),"display_policy_managed":text.contains(MARKER),"state":json_file(&workspace_state(),json!({}))}),
            0,
        );
    }
    if args.first().map(String::as_str) != Some("sync") {
        return json_error("usage: sync --candidate JSON | status".into());
    }
    let _lock = match command_lock() {
        Ok(l) => l,
        Err(e) => return json_error(e),
    };
    let result = flag(args, "--candidate")
        .ok_or("missing --candidate".to_string())
        .and_then(|raw| serde_json::from_str(raw).map_err(|e| e.to_string()))
        .and_then(|c| sync_inner(&c));
    result.unwrap_or_else(json_error)
}
fn persist_inner(candidate: &Value) -> Result<(Value, i32)> {
    if !cfg().is_file() {
        return Ok((
            json!({"ok":false,"error":format!("missing {}",cfg().display())}),
            2,
        ));
    }
    if load_preview()?["active"] == true {
        return Err("confirm or revert the active display preview before saving".into());
    }
    let plan = checked_plan(candidate)?;
    let normalized = &plan["candidate"];
    let original_live = candidate_from_snapshot(&probe());
    checked_plan(&original_live)?;
    let original = fs::read_to_string(cfg()).map_err(|e| e.to_string())?;
    let (updated, managed) = rewrite_config(&original, normalized)?;
    let (updated, color) = output_policy(&updated, normalized)?;
    let (block, m1, m2) = workspace_policy(normalized)?;
    let updated = rewrite_workspace(&updated, &block);
    let backup = backup("display-persist", &original)?;
    if fs::read_to_string(cfg()).map_err(|e| e.to_string())? != original {
        return Err("configuration changed externally before persistence".into());
    }
    let changed = updated != original;
    if changed {
        atomic(&cfg(), updated.as_bytes())?;
        let result = reload().and_then(|_| {
            thread::sleep(Duration::from_millis(800));
            verify(normalized, true)
        });
        if let Err(e) = result {
            let rollback = restore_file(&original, &updated, Some(&original_live));
            return Ok((
                json!({"ok":false,"error":e,"rolled_back":rollback.is_ok(),"rollback_error":rollback.err(),"backup":backup}),
                6,
            ));
        }
    }
    let policy = json!({"ok":true,"synced":true,"primary":m1,"secondary":m2,"output_policy":color,"backup":backup});
    let policy_state = json!({"version":2,"primary":m1,"secondary":m2,"saved_at":now()as i64,"backup":backup,"output_policy":color});
    let state = json!({"version":2,"saved_at":now()as i64,"outputs":normalized["outputs"],"managed_outputs":managed,"workspace_policy":policy,"backup":backup});
    if let Err(e) =
        atomic_json(&workspace_state(), &policy_state).and_then(|_| atomic_json(&saved(), &state))
    {
        let rollback = restore_file(&original, &updated, Some(&original_live));
        return Ok((
            json!({"ok":false,"error":e,"rolled_back":rollback.is_ok(),"rollback_error":rollback.err(),"backup":backup}),
            7,
        ));
    }
    Ok((
        json!({"ok":true,"persisted":true,"changed":changed,"outputs":managed,"workspace_policy":policy,"backup":backup,"atomic":true}),
        0,
    ))
}
pub fn persist(args: &[String]) -> (Value, i32) {
    if args.first().map(String::as_str) == Some("status") {
        let text = fs::read_to_string(cfg()).unwrap_or_default();
        return (
            json!({"available":cfg().is_file(),"managed":text.contains(MARKER),"state":json_file(&saved(),json!({})),"config":cfg(),"atomic_scope":"geometry + color/bitdepth/vrr + workspace ranges"}),
            0,
        );
    }
    if args.first().map(String::as_str) != Some("persist") {
        return json_error("usage: persist --candidate JSON | status".into());
    }
    let _lock = match command_lock() {
        Ok(l) => l,
        Err(e) => return json_error(e),
    };
    let result = flag(args, "--candidate")
        .ok_or("missing --candidate".to_string())
        .and_then(|raw| serde_json::from_str(raw).map_err(|e| e.to_string()))
        .and_then(|c| persist_inner(&c));
    result.unwrap_or_else(json_error)
}
pub fn planner(args: &[String]) -> (Value, i32) {
    let p = flag(args, "--candidate")
        .ok_or("missing --candidate".to_string())
        .and_then(|raw| serde_json::from_str(raw).map_err(|e| e.to_string()))
        .and_then(|c| plan(&c, &probe()));
    match p {
        Ok(p) => {
            let code = if p["ok"] == true { 0 } else { 3 };
            (p, code)
        }
        Err(e) => (
            json!({"ok":false,"errors":[e],"warnings":[],"commands":[],"hypr_lines":[]}),
            2,
        ),
    }
}

pub fn owner_snapshot() -> Result<Value> {
    let live = probe();
    let mut outputs = candidate_from_snapshot(&live)["outputs"].clone();
    for output in outputs.as_array_mut().into_iter().flatten() {
        if let Some(fields) = output.as_object_mut() {
            for key in ["observed_cm", "observed_bitdepth", "observed_vrr"] {
                fields.remove(key);
            }
        }
        if let Some(actual) = monitors(&live)
            .into_iter()
            .find(|m| m["name"] == output["name"])
        {
            output["current_cm"] = actual["color_management_preset"].clone();
            output["current_bitdepth"] = json!(depth(&actual));
            output["active_vrr"] = actual["vrr"].clone();
        }
    }
    if outputs.as_array().is_none_or(Vec::is_empty) {
        return Err("OWNER_UNAVAILABLE".into());
    }
    let journal = load_preview()?;
    let preview = if journal["active"] == true {
        json!({"active":true,"token":journal["token"],"candidate":journal["candidate"],"recovery_required":truth(&journal["recovery_required"])})
    } else {
        json!({"active":false})
    };
    Ok(json!({"outputs":outputs,"preview":preview}))
}
pub fn profile_candidate(monitor: &str, profile: &str) -> Result<Value> {
    let presets = json_file(
        &home().join(".config/cortetsu/display-presets.json"),
        json!({}),
    );
    let candidate = &presets["presets"][profile]["candidate"];
    let Some(outputs) = candidate["outputs"].as_array() else {
        return Err("saved display profile not found".into());
    };
    if outputs.len() != 1 || outputs[0]["name"] != monitor {
        return Err("saved display profile conflicts with requested monitor".into());
    }
    let live = probe();
    let known = monitors(&live)
        .into_iter()
        .find(|m| m["name"] == monitor)
        .is_some_and(|m| {
            m["color_management_preset"]
                .as_str()
                .is_some_and(|s| ALLOWED_CM.contains(&s))
        });
    if !known {
        return Err("UNSUPPORTED_CAPABILITY".into());
    }
    Ok(candidate.clone())
}
pub fn preview_profile(monitor: &str, profile: &str) -> (Value, i32) {
    let candidate = match profile_candidate(monitor, profile) {
        Ok(c) => c,
        Err(e) => return json_error(e),
    };
    transaction(&[
        "preview".into(),
        "--candidate".into(),
        candidate.to_string(),
    ])
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn planner_matches_legacy_golden_cases() {
        let fixtures: Value =
            serde_json::from_str(include_str!("../tests/fixtures/display-planner.json")).unwrap();
        for (index, case) in fixtures.as_array().unwrap().iter().enumerate() {
            assert_eq!(
                plan(&case["candidate"], &case["snapshot"]).unwrap(),
                case["expected"],
                "case {index}: {}",
                case["candidate"]
            );
        }
    }
    #[test]
    fn lua_monitor_command_never_uses_legacy_keyword_parser() {
        let cmd = json!([
            "hyprctl",
            "keyword",
            "monitor",
            "eDP-1,1920x1080@60Hz,0x0,1,transform,0,bitdepth,8,cm,srgb,vrr,0"
        ]);
        assert_eq!(
            lua_command(&cmd).unwrap(),
            r#"hl.monitor({output = "eDP-1", mode = "1920x1080@60Hz", position = "0x0", scale = 1, transform = 0, bitdepth = 8, cm = "srgb", vrr = 0})"#
        );
        assert!(lua_command(&json!(["sh", "-c", "whoami"])).is_err());
    }
}
