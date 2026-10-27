use crate::{
    hardware::{self, rounded},
    util::*,
};
use regex::Regex;
use serde_json::{Value, json};
use std::path::PathBuf;
const VALID: [&str; 3] = ["power-saver", "balanced", "performance"];
const SERVICE: &str = "cortetsu-power-auto.service";
fn config_path() -> PathBuf {
    home().join(".config/cortetsu/power-auto.json")
}
fn state_path() -> PathBuf {
    runtime().join("cortetsu-power-auto-state.json")
}
fn events_path() -> PathBuf {
    home().join(".local/state/cortetsu/power-auto-events.jsonl")
}
fn defaults() -> Value {
    json!({"enabled":false,"ac_profile":"performance","battery_profile":"balanced","low_battery_enabled":true,"low_battery_threshold":25,"low_battery_profile":"power-saver","poll_seconds":4})
}
fn normalize(parsed: &Value) -> Value {
    let mut cfg = defaults();
    if let Some(p) = parsed.as_object() {
        cfg.as_object_mut().unwrap().extend(p.clone());
    }
    for key in ["enabled", "low_battery_enabled"] {
        cfg[key] = json!(truth(&cfg[key]));
    }
    for key in ["ac_profile", "battery_profile", "low_battery_profile"] {
        if !VALID.contains(&cfg[key].as_str().unwrap_or("")) {
            cfg[key] = defaults()[key].clone()
        }
    }
    cfg["low_battery_threshold"] = json!(
        as_i(&cfg["low_battery_threshold"])
            .unwrap_or(25)
            .clamp(5, 80)
    );
    cfg["poll_seconds"] = json!(as_i(&cfg["poll_seconds"]).unwrap_or(4).clamp(2, 30));
    cfg
}
fn config() -> Value {
    normalize(&json_file(&config_path(), json!({})))
}
fn save(cfg: &Value) -> Result<()> {
    let mut data = serde_json::to_vec_pretty(&normalize(cfg)).map_err(|e| e.to_string())?;
    data.push(b'\n');
    atomic(&config_path(), &data)
}
fn bool_arg(s: &str) -> Result<bool> {
    match s.to_lowercase().as_str() {
        "1" | "true" | "yes" | "on" | "enabled" => Ok(true),
        "0" | "false" | "no" | "off" | "disabled" => Ok(false),
        _ => Err("expected true/false".into()),
    }
}
fn systemctl(args: &[&str]) -> Result<Output> {
    let mut a = vec!["--user"];
    a.extend_from_slice(args);
    run_str("systemctl", &a, 8.)
}
pub fn current_profile() -> String {
    run_str("powerprofilesctl", &["get"], 3.)
        .ok()
        .filter(|r| r.code == 0)
        .map(|r| r.stdout.trim().to_string())
        .unwrap_or_default()
}
fn profiles() -> Value {
    if which("powerprofilesctl").is_none() {
        return json!({"backend":"none","current":"","available":[],"can_set":false,"degraded":null});
    }
    let current = current_profile();
    let listing = run_str("powerprofilesctl", &["list"], 1.5)
        .ok()
        .filter(|r| r.code == 0)
        .map(|r| r.stdout)
        .unwrap_or_default();
    let mut available = VALID
        .iter()
        .filter(|p| {
            Regex::new(&format!(r"(?m)^\s*\*?\s*{}:\s*$", regex::escape(p)))
                .unwrap()
                .is_match(&listing)
        })
        .map(|p| p.to_string())
        .collect::<Vec<_>>();
    if !current.is_empty() && !available.contains(&current) {
        available.push(current.clone())
    }
    let mut in_current = false;
    let mut degraded = Value::Null;
    for line in listing.lines() {
        let stripped = line.trim().trim_start_matches('*').trim();
        if VALID.iter().any(|p| stripped == format!("{p}:")) {
            in_current = stripped == format!("{current}:");
        } else if in_current && let Some(value) = stripped.to_lowercase().strip_prefix("degraded:")
        {
            degraded = json!(!["no", "false", "0"].contains(&value.trim()));
        }
    }
    json!({"backend":"powerprofilesctl","current":current,"available":available,"can_set":!available.is_empty(),"degraded":degraded})
}
fn ac() -> Value {
    let mut sources = vec![];
    for p in children(&sysfs().join("class/power_supply")) {
        let kind = read(&p.join("type"));
        if !["Mains", "USB", "USB_C", "USB_PD"].contains(&kind.as_str()) {
            continue;
        }
        sources
            .push(json!({"name":basename(&p),"type":kind,"online":read(&p.join("online"))=="1"}));
    }
    json!({"online":sources.iter().any(|s|s["online"]==true),"sources":sources})
}
fn battery() -> Value {
    let roots = hardware::battery_roots();
    let Some(root) = roots.first() else {
        return json!({"present":false});
    };
    let status = read_default(&root.join("status"), "Unknown");
    let voltage = number(&root.join("voltage_now"), 1_000_000.);
    let power = number(&root.join("power_now"), 1_000_000.).or_else(|| {
        number(&root.join("current_now"), 1_000_000.)
            .zip(voltage)
            .map(|(a, v)| a * v)
    });
    let energy = |field: &str, charge: &str| {
        number(&root.join(field), 1_000_000.).or_else(|| {
            number(&root.join(charge), 1_000_000.)
                .zip(voltage)
                .map(|(a, v)| a * v)
        })
    };
    let enow = energy("energy_now", "charge_now");
    let full = energy("energy_full", "charge_full");
    let design = energy("energy_full_design", "charge_full_design");
    let health = full
        .zip(design.filter(|n| *n > 0.))
        .map(|(f, d)| (f / d * 100.).clamp(0., 100.));
    let remaining = if status.to_lowercase() == "discharging" {
        enow.zip(power.filter(|n| *n > 0.2))
            .map(|(e, p)| (e / p * 60.).max(0.))
    } else {
        None
    };
    let to_full = if status.to_lowercase() == "charging" {
        enow.zip(full)
            .zip(power.filter(|n| *n > 0.2))
            .map(|((e, f), p)| ((f - e) / p * 60.).max(0.))
    } else {
        None
    };
    json!({"present":true,"name":basename(root),"percent":rounded(number(&root.join("capacity"),1.),0),"status":status,"power_w":rounded(power,2),"voltage_v":rounded(voltage,2),"energy_now_wh":rounded(enow,2),"energy_full_wh":rounded(full,2),"energy_design_wh":rounded(design,2),"health_percent":rounded(health,1),"remaining_minutes":rounded(remaining,0),"time_to_full_minutes":rounded(to_full,0)})
}
fn unique(values: impl Iterator<Item = String>) -> Vec<String> {
    let mut out = vec![];
    for v in values {
        if !v.is_empty() && !out.contains(&v) {
            out.push(v)
        }
    }
    out
}
fn cpu_policy() -> Value {
    let policies = hardware::cpu_policies();
    let drivers = unique(policies.iter().map(|p| read(&p.join("scaling_driver"))));
    let governors = unique(policies.iter().map(|p| read(&p.join("scaling_governor"))));
    let epp = unique(
        policies
            .iter()
            .map(|p| read(&p.join("energy_performance_preference"))),
    );
    let choices = unique(policies.iter().flat_map(|p| {
        read(&p.join("energy_performance_available_preferences"))
            .split_whitespace()
            .map(String::from)
            .collect::<Vec<_>>()
    }));
    let cur = policies
        .iter()
        .filter_map(|p| number(&p.join("scaling_cur_freq"), 1000.))
        .collect::<Vec<_>>();
    let min = policies
        .iter()
        .filter_map(|p| number(&p.join("cpuinfo_min_freq"), 1000.))
        .reduce(f64::min);
    let max = policies
        .iter()
        .filter_map(|p| number(&p.join("cpuinfo_max_freq"), 1000.))
        .reduce(f64::max);
    let power = hardware::hwmons()
        .iter()
        .filter(|h| {
            ["k10temp", "zenpower", "amd_energy", "coretemp"]
                .contains(&read(&h.join("name")).to_lowercase().as_str())
        })
        .flat_map(|h| {
            let mut n = hardware::hwmon_numbers(h, "power", "_average", 1_000_000.);
            n.extend(hardware::hwmon_numbers(h, "power", "_input", 1_000_000.));
            n
        })
        .filter(|n| (0.0..=350.0).contains(n))
        .reduce(f64::max);
    json!({"driver":if drivers.is_empty(){"unknown".into()}else{drivers.join(", ")},"governor":if governors.is_empty(){"unknown".into()}else{governors.join(", ")},"epp":epp.join(", "),"epp_choices":choices,"current_mhz":rounded((!cur.is_empty()).then(||cur.iter().sum::<f64>()/cur.len()as f64),0),"min_mhz":rounded(min,0),"max_mhz":rounded(max,0),"platform_profile":read(&sysfs().join("firmware/acpi/platform_profile")),"platform_profile_choices":read(&sysfs().join("firmware/acpi/platform_profile_choices")).split_whitespace().collect::<Vec<_>>(),"package_power_w":rounded(power,2)})
}
fn gpu_power() -> Vec<Value> {
    let mut out = vec![];
    for c in hardware::gpu_cards() {
        let d = c.join("device");
        if read(&d.join("vendor")).to_lowercase() != "0x1002" {
            continue;
        }
        let mut temp = None;
        let mut power = None;
        for h in children(&d.join("hwmon")) {
            if let Some(t) = hardware::temperatures(&h) {
                temp = Some(t)
            }
            if let Some(w) = number(&h.join("power1_average"), 1_000_000.)
                .or_else(|| number(&h.join("power1_input"), 1_000_000.))
            {
                power = Some(w)
            }
        }
        out.push(json!({"vendor":"AMD","card":basename(&c),"performance_level":read(&d.join("power_dpm_force_performance_level")),"power_state":read(&d.join("power_dpm_state")),"runtime_status":read(&d.join("power/runtime_status")),"temp_c":rounded(temp,1),"power_w":rounded(power,2)}));
    }
    let devices = hardware::nvidia_devices();
    if !devices.is_empty() && devices.iter().all(hardware::asleep) {
        out.push(json!({"vendor":"NVIDIA","name":"NVIDIA GPU","state":"suspended","power_w":null,"temp_c":null}));
        return out;
    }
    for d in devices.iter().filter(|d| hardware::asleep(d)) {
        out.push(json!({"vendor":"NVIDIA","name":d["name"],"state":"suspended","power_w":null,"temp_c":null}));
    }
    let before = out.len();
    if let Some(raw) = hardware::nvidia_query(
        "name,pstate,power.draw,power.limit,temperature.gpu,clocks.gr,clocks.mem",
        &devices,
    ) {
        for l in raw.lines() {
            let p = l.split(',').map(str::trim).collect::<Vec<_>>();
            if p.len() < 7 {
                continue;
            }
            let n = |i: usize| p[i].parse::<f64>().ok();
            out.push(json!({"vendor":"NVIDIA","name":p[0],"state":"active","pstate":p[1],"power_w":rounded(n(2),2),"power_limit_w":rounded(n(3),2),"temp_c":rounded(n(4),1),"graphics_clock_mhz":rounded(n(5),0),"memory_clock_mhz":rounded(n(6),0)}));
        }
    }
    if out.len() == before {
        for d in devices.iter().filter(|d| !hardware::asleep(d)) {
            out.push(json!({"vendor":"NVIDIA","name":d["name"],"state":"unavailable","power_w":null,"temp_c":null}));
        }
    }
    out
}
pub fn hardware(args: &[String]) -> (Value, i32) {
    if args.first().map(String::as_str) == Some("set-profile") {
        let p = args.get(1).map(String::as_str).unwrap_or("");
        if !VALID.contains(&p) {
            return json_error("invalid profile".into());
        }
        if which("powerprofilesctl").is_none() {
            return (
                json!({"ok":false,"error":"powerprofilesctl not installed"}),
                3,
            );
        }
        let r = match run_str("powerprofilesctl", &["set", p], 8.) {
            Ok(r) => r,
            Err(_) => {
                return (
                    json!({"ok":false,"error":"failed to execute powerprofilesctl"}),
                    4,
                );
            }
        };
        if r.code != 0 {
            return (json!({"ok":false,"error":r.detail()}), r.code);
        }
        let current = current_profile();
        let ok = current == p;
        return (
            json!({"ok":ok,"profile":p,"current":current}),
            if ok { 0 } else { 6 },
        );
    }
    let gpus = gpu_power();
    let watts = gpus
        .iter()
        .filter_map(|g| g["power_w"].as_f64())
        .collect::<Vec<_>>();
    (
        json!({"profiles":profiles(),"ac":ac(),"battery":battery(),"cpu":cpu_policy(),"gpus":gpus,"total_gpu_power_w":rounded((!watts.is_empty()).then(||watts.iter().sum::<f64>()),2)}),
        0,
    )
}
fn events(limit: usize) -> Vec<Value> {
    let raw = read(&events_path());
    let lines = raw.lines().collect::<Vec<_>>();
    lines[lines.len().saturating_sub(limit)..]
        .iter()
        .rev()
        .filter_map(|s| serde_json::from_str::<Value>(s).ok())
        .filter(Value::is_object)
        .collect()
}
fn status() -> Value {
    let active = systemctl(&["is-active", SERVICE]).ok();
    let enabled = systemctl(&["is-enabled", SERVICE]).ok();
    let mut state = json_file(&state_path(), json!({}));
    let live = current_profile();
    if !live.is_empty() {
        state["profile"] = json!(live)
    }
    json!({"config":config(),"service":{"active":active.as_ref().is_some_and(|r|r.code==0),"enabled":enabled.as_ref().is_some_and(|r|r.code==0),"active_state":active.map(|r|if r.stdout.trim().is_empty(){"inactive".into()}else{r.stdout.trim().to_string()}).unwrap_or_else(||"inactive".into()),"enable_state":enabled.map(|r|if r.stdout.trim().is_empty(){"disabled".into()}else{r.stdout.trim().to_string()}).unwrap_or_else(||"disabled".into()),"name":SERVICE},"last":state,"events":events(12)})
}
fn refresh(cfg: &Value) {
    if cfg["enabled"] == true {
        let _ = systemctl(&["try-restart", SERVICE]);
    }
}
fn with_status(ok: bool, error: Option<String>) -> Value {
    let mut v = status();
    v["ok"] = json!(ok);
    if let Some(e) = error {
        v["error"] = json!(e)
    }
    v
}
fn control_action(args: &[String]) -> Result<(Value, i32)> {
    let mut cfg = config();
    let command = args.first().map(String::as_str).unwrap_or("status");
    if command == "status" {
        save(&cfg)?;
        return Ok((status(), 0));
    }
    match command {
        "set-enabled" => {
            let value = bool_arg(args.get(1).ok_or("expected true/false")?)?;
            let previous = cfg["enabled"].clone();
            cfg["enabled"] = json!(value);
            save(&cfg)?;
            let _ = systemctl(&["daemon-reload"]);
            let r = systemctl(&[if value { "enable" } else { "disable" }, "--now", SERVICE]);
            let result = match r {
                Ok(r) if r.code == 0 => return Ok((with_status(true, None), 0)),
                Ok(r) => (r.detail(), r.code),
                Err(e) => (e, 2),
            };
            cfg["enabled"] = previous;
            save(&cfg)?;
            return Ok((with_status(false, Some(result.0)), result.1));
        }
        "set-profile" => {
            let slot = args.get(1).ok_or("invalid slot/profile")?;
            let profile = args.get(2).ok_or("invalid slot/profile")?;
            let key = match slot.as_str() {
                "ac" => "ac_profile",
                "battery" => "battery_profile",
                "low" => "low_battery_profile",
                _ => return Err("invalid slot/profile".into()),
            };
            if !VALID.contains(&profile.as_str()) {
                return Err("invalid slot/profile".into());
            }
            cfg[key] = json!(profile)
        }
        "set-low-enabled" => {
            cfg["low_battery_enabled"] = json!(bool_arg(args.get(1).ok_or("expected true/false")?)?)
        }
        "set-threshold" | "set-poll" => {
            let value = args
                .get(1)
                .ok_or("missing numeric value")?
                .parse::<i64>()
                .map_err(|e| e.to_string())?;
            let (key, min, max) = if command == "set-threshold" {
                ("low_battery_threshold", 5, 80)
            } else {
                ("poll_seconds", 2, 30)
            };
            cfg[key] = json!(value.clamp(min, max));
        }
        "apply-now" => {
            let (_, _, ok) = iteration(true, "")?;
            let mut s = with_status(ok, None);
            s["watcher_stdout"] = json!("");
            s["watcher_stderr"] = json!("");
            return Ok((s, if ok { 0 } else { 1 }));
        }
        "clear-events" => {
            remove(&events_path())?;
            return Ok((with_status(true, None), 0));
        }
        "reset-defaults" => {
            let enabled = cfg["enabled"].clone();
            cfg = defaults();
            cfg["enabled"] = enabled
        }
        _ => return Err("unknown command".into()),
    }
    save(&cfg)?;
    refresh(&cfg);
    Ok((with_status(true, None), 0))
}
pub fn control(args: &[String]) -> (Value, i32) {
    let _lock = match lock(&config_path().with_extension("lock")) {
        Ok(l) => l,
        Err(e) => return json_error(e),
    };
    match control_action(args) {
        Ok(r) => r,
        Err(e) => (with_status(false, Some(e)), 2),
    }
}
fn write_state(value: &Value) -> Result<()> {
    let mut v = json!({"timestamp":now()as i64});
    v.as_object_mut()
        .unwrap()
        .extend(value.as_object().unwrap().clone());
    atomic_json(&state_path(), &v)
}
fn append_event(value: &Value) -> Result<()> {
    let _lock = lock(&events_path().with_extension("lock"))?;
    let mut v = json!({"timestamp":now()as i64});
    v.as_object_mut()
        .unwrap()
        .extend(value.as_object().unwrap().clone());
    let raw = read(&events_path());
    let old = raw.lines().collect::<Vec<_>>();
    let mut lines = old[old.len().saturating_sub(199)..]
        .iter()
        .map(|s| s.to_string())
        .collect::<Vec<_>>();
    lines.push(v.to_string());
    atomic(&events_path(), format!("{}\n", lines.join("\n")).as_bytes())
}
fn desired(cfg: &Value, ac: bool, percent: Option<f64>) -> (String, String) {
    if ac {
        return (
            text(cfg, "ac_profile", "performance"),
            "AC connected".into(),
        );
    }
    if cfg["low_battery_enabled"] == true
        && percent.is_some_and(|p| p <= f(cfg, "low_battery_threshold", 25.))
    {
        return (
            text(cfg, "low_battery_profile", "power-saver"),
            format!("battery <= {}%", cfg["low_battery_threshold"]),
        );
    }
    (
        text(cfg, "battery_profile", "balanced"),
        "on battery".into(),
    )
}
fn iteration(force: bool, settled: &str) -> Result<(bool, String, bool)> {
    let _lock = lock(&state_path().with_extension("lock"))?;
    let cfg = config();
    let previous = json_file(&state_path(), json!({}));
    let enabled = cfg["enabled"] == true;
    if !enabled && !force {
        write_state(&json!({"enabled":false,"active":false,"reason":"automation disabled"}))?;
        return Ok((false, String::new(), true));
    }
    if which("powerprofilesctl").is_none() {
        let state = json!({"enabled":enabled,"active":false,"one_shot":force,"ok":false,"error":"powerprofilesctl not found"});
        write_state(&state)?;
        let mut event = state;
        event["kind"] = json!("error");
        append_event(&event)?;
        return Ok((enabled && !force, String::new(), false));
    }
    let ac = ac()["online"] == true;
    let roots = hardware::battery_roots();
    let percent = roots.first().and_then(|r| number(&r.join("capacity"), 1.));
    let battery_status = roots
        .first()
        .map(|r| read(&r.join("status")))
        .unwrap_or_default();
    let (desired, reason) = desired(&cfg, ac, percent);
    let rule = json!([ac, reason, desired, cfg]).to_string();
    if !force && rule == settled {
        write_state(
            &json!({"enabled":true,"active":true,"one_shot":false,"ac_online":ac,"battery_percent":percent,"battery_status":battery_status,"desired_profile":desired,"profile":previous.get("profile").unwrap_or(&json!(desired)),"reason":reason,"changed":false,"ok":true,"error":""}),
        )?;
        return Ok((true, settled.into(), true));
    }
    let _owner_lock = crate::owner::domain_lock("power")?;
    if !force && crate::owner::automation_override()? {
        write_state(
            &json!({"enabled":enabled,"active":true,"one_shot":false,"manual_override":true,"reason":"manual override","changed":false,"ok":true,"error":""}),
        )?;
        return Ok((enabled, String::new(), true));
    }
    let before = current_profile();
    let requested = !before.is_empty() && before != desired;
    let (mut ok, mut error) = (true, String::new());
    if requested {
        match run_str("powerprofilesctl", &["set", &desired], 8.) {
            Ok(r) if r.code == 0 => {}
            Ok(r) => {
                ok = false;
                error = r.detail()
            }
            Err(e) => {
                ok = false;
                error = e
            }
        }
    }
    let after = if requested {
        current_profile()
    } else {
        before.clone()
    };
    let verified = after == desired;
    let current = if after.is_empty() {
        before.clone()
    } else {
        after.clone()
    };
    if !verified && ok {
        ok = false;
        error = format!(
            "profile verification failed: expected {desired}, got {}",
            if after.is_empty() { "unknown" } else { &after }
        )
    }
    let state = json!({"enabled":enabled,"active":enabled&&!force,"one_shot":force,"ac_online":ac,"battery_percent":percent,"battery_status":battery_status,"desired_profile":desired,"previous_profile":before,"profile":current,"reason":reason,"changed":requested&&verified,"ok":ok,"error":error});
    write_state(&state)?;
    let source_changed = !previous["ac_online"].is_null() && previous["ac_online"] != ac;
    let desired_changed =
        truth(&previous["desired_profile"]) && previous["desired_profile"] != desired;
    if force || source_changed || desired_changed || before != current || !ok {
        append_event(
            &json!({"kind":if ok{"apply"}else{"error"},"source":if ac{"ac"}else{"battery"},"battery_percent":percent,"desired_profile":desired,"previous_profile":before,"profile":current,"reason":reason,"changed":requested&&verified,"one_shot":force,"ok":ok,"error":error}),
        )?
    }
    if ok {
        crate::owner::automation_finish(&current, force)?;
    }
    Ok((
        enabled && !force,
        if ok && current == desired {
            rule
        } else {
            String::new()
        },
        ok,
    ))
}
pub fn watcher(args: &[String]) -> (Value, i32) {
    if args.iter().any(|a| a == "--once") {
        return match iteration(true, "") {
            Ok((_, _, ok)) => (Value::Null, if ok { 0 } else { 1 }),
            Err(e) => json_error(e),
        };
    }
    if !args.is_empty() {
        return json_error("usage: cortetsu-power-auto [--once]".into());
    }
    let mut settled = String::new();
    loop {
        match iteration(false, &settled) {
            Ok((keep, next, _)) => {
                if !keep {
                    return (Value::Null, 0);
                }
                settled = next
            }
            Err(e) => return json_error(e),
        }
        if !crate::util::wait_interruptible(i(&config(), "poll_seconds", 4) as f64) {
            return (Value::Null, 130);
        }
    }
}
