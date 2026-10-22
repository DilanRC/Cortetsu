use crate::util::*;
use nix::unistd::{SysconfVar, Uid, User, sysconf};
use regex::Regex;
use serde_json::{Map, Value, json};
use std::{
    collections::{BTreeSet, HashMap},
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
};
pub fn rounded(x: Option<f64>, digits: i32) -> Value {
    x.map(|n| round(n, digits)).unwrap_or(Value::Null)
}
fn gib(n: f64) -> Value {
    round(n / 1_073_741_824., 2)
}
fn max(values: impl Iterator<Item = f64>) -> Option<f64> {
    values.reduce(f64::max)
}
fn mean(values: &[f64]) -> Option<f64> {
    (!values.is_empty()).then(|| values.iter().sum::<f64>() / values.len() as f64)
}
pub fn cpu_policies() -> Vec<PathBuf> {
    children(&sysfs().join("devices/system/cpu"))
        .into_iter()
        .filter(|p| {
            basename(p)
                .strip_prefix("cpu")
                .is_some_and(|s| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit()))
        })
        .map(|p| p.join("cpufreq"))
        .filter(|p| p.exists())
        .collect()
}
pub fn hwmons() -> Vec<PathBuf> {
    children(&sysfs().join("class/hwmon"))
        .into_iter()
        .filter(|p| basename(p).starts_with("hwmon"))
        .collect()
}
pub fn hwmon_numbers(root: &Path, prefix: &str, suffix: &str, scale: f64) -> Vec<f64> {
    children(root)
        .iter()
        .filter(|p| {
            let n = basename(p);
            n.starts_with(prefix) && n.ends_with(suffix)
        })
        .filter_map(|p| number(p, scale))
        .collect()
}
pub fn gpu_cards() -> Vec<PathBuf> {
    children(&sysfs().join("class/drm"))
        .into_iter()
        .filter(|p| {
            basename(p)
                .strip_prefix("card")
                .is_some_and(|s| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit()))
        })
        .collect()
}
pub fn temperatures(root: &Path) -> Option<f64> {
    max(hwmon_numbers(root, "temp", "_input", 1000.)
        .into_iter()
        .filter(|t| *t > -20. && *t < 130.))
}
fn cpu_numbers(line: &str) -> (i64, i64) {
    let nums = line
        .split_whitespace()
        .skip(1)
        .filter_map(|x| x.parse::<i64>().ok())
        .collect::<Vec<_>>();
    (
        nums.iter().sum(),
        nums.get(3).unwrap_or(&0) + nums.get(4).unwrap_or(&0),
    )
}
fn percent(total: i64, idle: i64, old_total: i64, old_idle: i64) -> Value {
    let dt = (total - old_total).max(0);
    let di = (idle - old_idle).max(0);
    round(
        if dt > 0 {
            ((1. - di as f64 / dt as f64) * 100.).clamp(0., 100.)
        } else {
            0.
        },
        1,
    )
}
fn cpu(previous: &Value) -> (Value, Value) {
    let raw = read(&procfs().join("stat"));
    let (total, idle) = cpu_numbers(raw.lines().find(|l| l.starts_with("cpu ")).unwrap_or(""));
    let mut cores = Map::new();
    let mut usages = vec![];
    for l in raw.lines() {
        let name = l.split_whitespace().next().unwrap_or("");
        if let Some(n) = name
            .strip_prefix("cpu")
            .filter(|x| !x.is_empty() && x.chars().all(|x| x.is_ascii_digit()))
        {
            let (t, i0) = cpu_numbers(l);
            let old = &previous["cpu_cores"][n];
            usages.push(percent(t, i0, i(old, "total", t), i(old, "idle", i0)));
            cores.insert(n.into(), json!({"total":t,"idle":i0}));
        }
    }
    let mut model = "CPU".to_string();
    let mut freq = vec![];
    for l in read(&procfs().join("cpuinfo")).lines() {
        if let Some((k, v)) = l.split_once(':') {
            if k.trim() == "model name" && model == "CPU" {
                model = v.trim().into()
            }
            if k.trim() == "cpu MHz"
                && let Ok(n) = v.trim().parse::<f64>()
            {
                freq.push(n)
            }
        }
    }
    let policies = cpu_policies();
    let cur = policies
        .iter()
        .filter_map(|p| number(&p.join("scaling_cur_freq"), 1000.))
        .filter(|n| *n != 0.)
        .collect::<Vec<_>>();
    let frequency = mean(if cur.is_empty() { &freq } else { &cur });
    let governors = policies
        .iter()
        .map(|p| read(&p.join("scaling_governor")))
        .filter(|s| !s.is_empty())
        .collect::<BTreeSet<_>>();
    let temp = max(hwmons()
        .iter()
        .filter(|p| {
            ["k10temp", "zenpower", "coretemp"]
                .contains(&read(&p.join("name")).to_lowercase().as_str())
        })
        .filter_map(|p| temperatures(p)));
    (
        json!({"model":model,"usage":percent(total,idle,i(previous,"cpu_total",total),i(previous,"cpu_idle",idle)),"per_core":usages,"freq_mhz":rounded(frequency,0),"temp_c":rounded(temp,1),"governor":if governors.is_empty(){"unknown".into()}else{governors.into_iter().collect::<Vec<_>>().join(", ")},"cores":if usages.is_empty(){std::thread::available_parallelism().map(|n|n.get()).unwrap_or(0)}else{usages.len()}}),
        json!({"cpu_total":total,"cpu_idle":idle,"cpu_cores":cores}),
    )
}
fn memory() -> (Value, u64) {
    let mut info = HashMap::new();
    for l in read(&procfs().join("meminfo")).lines() {
        if let Some((k, v)) = l.split_once(':')
            && let Some(n) = v
                .split_whitespace()
                .next()
                .and_then(|x| x.parse::<u64>().ok())
        {
            info.insert(k.to_string(), n * 1024);
        }
    }
    let n = |k: &str| *info.get(k).unwrap_or(&0);
    let total = n("MemTotal");
    let available = n("MemAvailable");
    let used = total.saturating_sub(available);
    let swap_total = n("SwapTotal");
    (
        json!({"total_gb":gib(total as f64),"used_gb":gib(used as f64),"available_gb":gib(available as f64),"cache_gb":gib((n("Cached")+n("SReclaimable"))as f64),"buffers_gb":gib(n("Buffers")as f64),"usage":round(if total>0{used as f64/total as f64*100.}else{0.},1),"swap_used_gb":gib(swap_total.saturating_sub(n("SwapFree"))as f64),"swap_total_gb":gib(swap_total as f64)}),
        total,
    )
}
fn disk() -> Value {
    let total = fs2::total_space("/").unwrap_or(0);
    let free = fs2::available_space("/").unwrap_or(0);
    let used = total.saturating_sub(fs2::free_space("/").unwrap_or(0));
    json!({"total_gb":gib(total as f64),"used_gb":gib(used as f64),"free_gb":gib(free as f64),"usage":round(if total>0{used as f64/total as f64*100.}else{0.},1)})
}
fn root_source_name() -> String {
    let Ok(r) = run_str("findmnt", &["-n", "-o", "SOURCE", "/"], 0.7) else {
        return String::new();
    };
    let source = r.stdout.trim().split('[').next().unwrap_or("");
    if !source.starts_with("/dev/") {
        return String::new();
    }
    let name = basename(Path::new(source));
    let path = sysfs().join("class/block").join(&name);
    if !path.exists() {
        return String::new();
    }
    let underlying = |p: &Path| {
        if p.join("partition").exists() {
            p.canonicalize()
                .ok()
                .and_then(|p| p.parent().map(basename))
                .unwrap_or_default()
        } else {
            basename(p)
        }
    };
    if path.join("partition").exists() {
        return underlying(&path);
    }
    if name.starts_with("dm-")
        && let Some(p) = children(&path.join("slaves")).first()
    {
        return underlying(&sysfs().join("class/block").join(basename(p)));
    }
    name
}
fn disk_io(previous: &Value, now: f64) -> (Value, Vec<Value>, Value) {
    let old = &previous["disk_io"];
    let elapsed = (now - f(old, "time", now)).max(0.001);
    let mut metrics = vec![];
    let mut next = Map::new();
    let re = Regex::new(r"^(nvme\d+n\d+|sd[a-z]+|vd[a-z]+|mmcblk\d+)$").unwrap();
    for p in children(&sysfs().join("class/block")) {
        let name = basename(&p);
        if p.join("partition").exists() || !re.is_match(&name) {
            continue;
        }
        let nums = read(&p.join("stat"))
            .split_whitespace()
            .filter_map(|x| x.parse::<i64>().ok())
            .collect::<Vec<_>>();
        if nums.len() < 7 {
            continue;
        }
        let (reads, rs, writes, ws) = (nums[0], nums[2], nums[4], nums[6]);
        let sector = integer(&p.join("queue/hw_sector_size")).unwrap_or(512);
        let old = &old["devices"][&name];
        let rate = |value: i64, key: &str, unit: f64| {
            (value - i(old, key, value)).max(0) as f64 * unit / elapsed
        };
        let model = read(&p.join("device/model"));
        let model = if model.is_empty() {
            read(&p.join("device/name"))
        } else {
            model
        };
        metrics.push(json!({"device":name,"model":model,"serial":read(&p.join("device/serial")),"rotational":read(&p.join("queue/rotational"))=="1","read_mib_s":round(rate(rs,"read_sectors",sector as f64/1_048_576.),2),"write_mib_s":round(rate(ws,"write_sectors",sector as f64/1_048_576.),2),"read_iops":round(rate(reads,"reads",1.),1),"write_iops":round(rate(writes,"writes",1.),1),"read_total_gb":round(rs as f64*sector as f64/1_000_000_000.,2),"write_total_gb":round(ws as f64*sector as f64/1_000_000_000.,2)}));
        next.insert(
            name,
            json!({"read_sectors":rs,"write_sectors":ws,"reads":reads,"writes":writes}),
        );
    }
    let root = root_source_name();
    let metric=metrics.iter().find(|m|m["device"]==root).or_else(||metrics.first()).cloned().unwrap_or_else(||json!({"device":if root.is_empty(){"root"}else{&root},"model":"","serial":"","read_mib_s":0.0,"write_mib_s":0.0,"read_iops":0.0,"write_iops":0.0,"read_total_gb":0.0,"write_total_gb":0.0}));
    (
        metric,
        metrics,
        json!({"disk_io":{"time":now,"devices":next}}),
    )
}
pub fn battery_roots() -> Vec<PathBuf> {
    children(&sysfs().join("class/power_supply"))
        .into_iter()
        .filter(|p| basename(p).starts_with("BAT"))
        .collect()
}
fn battery() -> Value {
    let roots = battery_roots();
    let Some(root) = roots.first() else {
        return json!({"present":false});
    };
    let power = number(&root.join("power_now"), 1_000_000.).or_else(|| {
        number(&root.join("current_now"), 1_000_000.)
            .zip(number(&root.join("voltage_now"), 1_000_000.))
            .map(|(a, v)| a * v)
    });
    json!({"present":true,"name":basename(root),"percent":rounded(number(&root.join("capacity"),1.),0),"status":read_default(&root.join("status"),"Unknown"),"power_w":rounded(power,1)})
}
fn default_interface() -> String {
    for line in read(&procfs().join("net/route")).lines().skip(1) {
        let p = line.split_whitespace().collect::<Vec<_>>();
        if p.len() >= 4
            && p[1] == "00000000"
            && i64::from_str_radix(p[3], 16).is_ok_and(|n| n & 2 != 0)
        {
            return p[0].into();
        }
    }
    children(&sysfs().join("class/net"))
        .iter()
        .find(|p| basename(p) != "lo" && read(&p.join("operstate")) == "up")
        .map(|p| basename(p))
        .unwrap_or_default()
}
fn network_meta(iface: &str) -> Value {
    let root = sysfs().join("class/net").join(iface);
    let mut data = json!({"mac":read(&root.join("address")),"ipv4":"","ssid":"","signal_dbm":null,"bitrate_mbps":null});
    if let Ok(r) = run_str("ip", &["-4", "-o", "addr", "show", "dev", iface], 0.6)
        && let Some(c) = Regex::new(r"\binet\s+([0-9.]+)/")
            .unwrap()
            .captures(&r.stdout)
    {
        data["ipv4"] = json!(&c[1])
    }
    if root.join("wireless").exists()
        && let Ok(r) = run_str("iw", &["dev", iface, "link"], 0.7)
    {
        for line in r.stdout.lines() {
            let line = line.trim();
            if let Some(ssid) = line.strip_prefix("SSID:") {
                data["ssid"] = json!(ssid.trim())
            }
            for (prefix, key, digits) in [
                ("signal:", "signal_dbm", 0),
                ("tx bitrate:", "bitrate_mbps", 1),
            ] {
                if let Some(raw) = line.strip_prefix(prefix) {
                    data[key] = rounded(
                        raw.split_whitespace().next().and_then(|n| n.parse().ok()),
                        digits,
                    )
                }
            }
        }
    }
    data
}
fn network(previous: &Value, now: f64) -> (Value, Value) {
    let iface = default_interface();
    if iface.is_empty() {
        return (
            json!({"interface":"","rx_mbps":0.0,"tx_mbps":0.0}),
            json!({}),
        );
    }
    let root = sysfs().join("class/net").join(&iface).join("statistics");
    let rx = integer(&root.join("rx_bytes")).unwrap_or(0);
    let tx = integer(&root.join("tx_bytes")).unwrap_or(0);
    let old = &previous["network"];
    let elapsed = (now - f(old, "time", now)).max(0.001);
    let mut out = network_meta(&iface);
    let base = json!({"interface":iface,"rx_mbps":round((rx-i(old,"rx",rx)).max(0)as f64*8./elapsed/1_000_000.,2),"tx_mbps":round((tx-i(old,"tx",tx)).max(0)as f64*8./elapsed/1_000_000.,2),"rx_total_gb":round(rx as f64/1_000_000_000.,2),"tx_total_gb":round(tx as f64/1_000_000_000.,2)});
    out.as_object_mut()
        .unwrap()
        .extend(base.as_object().unwrap().clone());
    (out, json!({"network":{"time":now,"rx":rx,"tx":tx}}))
}
fn pci_ids_name(vendor: &str, device: &str) -> String {
    let brackets = Regex::new(r"\[(.+)\]").unwrap();
    for p in ["/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids"] {
        let mut inside = false;
        for line in read(Path::new(p)).lines() {
            if line.starts_with(vendor) {
                inside = true
            } else if inside && !line.is_empty() && !line.starts_with(['\t', '#']) {
                break;
            } else if inside && line.starts_with(&format!("\t{device} ")) {
                let name = line
                    .split_once(char::is_whitespace)
                    .map(|(_, s)| s.trim())
                    .unwrap_or("");
                let name = name.strip_prefix(device).unwrap_or(name).trim();
                return brackets
                    .captures(name)
                    .map(|c| c[1].into())
                    .unwrap_or_else(|| name.into());
            }
        }
    }
    String::new()
}
pub fn nvidia_devices() -> Vec<Value> {
    let mut devices = vec![];
    for d in children(&sysfs().join("bus/pci/devices")) {
        if read(&d.join("vendor")).to_lowercase() != "0x10de"
            || !read(&d.join("class")).starts_with("0x03")
        {
            continue;
        }
        let name = pci_ids_name(
            "10de",
            read(&d.join("device"))
                .to_lowercase()
                .trim_start_matches("0x"),
        );
        devices.push(json!({"slot":basename(&d),"status":read_default(&d.join("power/runtime_status"),"unknown"),"name":if name.is_empty(){"NVIDIA GPU"}else{&name}}));
    }
    devices
}
pub fn asleep(d: &Value) -> bool {
    ["suspended", "suspending"].contains(&d["status"].as_str().unwrap_or(""))
}
pub fn nvidia_query(query: &str, devices: &[Value]) -> Option<String> {
    if !devices.is_empty() && devices.iter().all(asleep) {
        return None;
    }
    let mut args = vec![
        format!("--query-gpu={query}"),
        "--format=csv,noheader,nounits".into(),
    ];
    if devices.iter().any(asleep) {
        let active = devices
            .iter()
            .filter(|d| !asleep(d))
            .map(|d| s(&d["slot"]))
            .collect::<Vec<_>>()
            .join(",");
        args.push(format!("--id={active}"));
    }
    run("nvidia-smi", &args, 1.5)
        .ok()
        .filter(|r| r.code == 0)
        .map(|r| r.stdout)
}
pub fn amd_gpus() -> Vec<Value> {
    let mut out = vec![];
    for card in gpu_cards() {
        let dev = card.join("device");
        if read(&dev.join("vendor")).to_lowercase() != "0x1002" {
            continue;
        }
        let mut temp = None;
        let mut power = None;
        for h in children(&dev.join("hwmon")) {
            if let Some(t) = temperatures(&h) {
                temp = Some(t)
            }
            if let Some(p) = number(&h.join("power1_average"), 1_000_000.) {
                power = Some(p)
            }
        }
        let slot = read(&dev.join("uevent"))
            .lines()
            .find_map(|l| l.strip_prefix("PCI_SLOT_NAME=").map(String::from))
            .unwrap_or_default();
        let name = if slot.is_empty() {
            None
        } else {
            run_str("lspci", &["-s", &slot], 0.8)
                .ok()
                .and_then(|r| r.stdout.trim().split_once(": ").map(|(_, s)| s.to_string()))
        }
        .unwrap_or_else(|| "AMD Radeon GPU".into());
        out.push(json!({"vendor":"AMD","card":basename(&card),"name":name,"usage":round(number(&dev.join("gpu_busy_percent"),1.).unwrap_or(0.).clamp(0.,100.),1),"temp_c":rounded(temp,1),"vram_total_gb":number(&dev.join("mem_info_vram_total"),1.).filter(|x|*x!=0.).map(gib),"vram_used_gb":number(&dev.join("mem_info_vram_used"),1.).filter(|x|*x!=0.).map(gib),"power_w":rounded(power,1)}));
    }
    out
}
fn nvidia_gpus() -> Vec<Value> {
    let devices = nvidia_devices();
    let mut out=devices.iter().filter(|d|asleep(d)).map(|d|json!({"vendor":"NVIDIA","name":d["name"],"state":"suspended","usage":null,"temp_c":null,"vram_used_gb":null,"vram_total_gb":null,"power_w":null})).collect::<Vec<_>>();
    if let Some(raw) = nvidia_query(
        "name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
        &devices,
    ) {
        for line in raw.lines() {
            let p = line.split(',').map(str::trim).collect::<Vec<_>>();
            if p.len() < 6 {
                continue;
            }
            let n = |i: usize| p[i].parse::<f64>().ok();
            out.push(json!({"vendor":"NVIDIA","name":p[0],"state":"active","usage":round(n(1).unwrap_or(0.).clamp(0.,100.),1),"temp_c":rounded(n(2),1),"vram_used_gb":rounded(n(3).map(|n|n/1024.),2),"vram_total_gb":rounded(n(4).map(|n|n/1024.),2),"power_w":rounded(n(5),1)}));
        }
    }
    out
}
pub fn gpus() -> Vec<Value> {
    let mut out = amd_gpus();
    out.extend(nvidia_gpus());
    out
}
fn fans() -> Vec<Value> {
    let mut out = vec![];
    for h in hwmons() {
        let chip = read_default(&h.join("name"), &basename(&h));
        for p in children(&h) {
            let name = basename(&p);
            if let Some(idx) = name
                .strip_prefix("fan")
                .and_then(|s| s.strip_suffix("_input"))
                && let Some(rpm) = number(&p, 1.).filter(|n| *n > 0.)
            {
                let label = read_default(
                    &h.join(format!("fan{idx}_label")),
                    &format!("{chip} fan {idx}"),
                );
                out.push(json!({"name":label,"rpm":round(rpm,0)}));
            }
        }
    }
    out.truncate(8);
    out
}
fn processes(previous: &Value, now: f64, uptime: f64, total_mem: u64) -> (Vec<Value>, Value) {
    let elapsed = (now - f(previous, "process_time", now)).max(0.001);
    let clock = sysconf(SysconfVar::CLK_TCK)
        .ok()
        .flatten()
        .unwrap_or(100)
        .max(1) as f64;
    let page = sysconf(SysconfVar::PAGE_SIZE)
        .ok()
        .flatten()
        .unwrap_or(4096) as f64;
    let mut ticks = Map::new();
    let mut users = HashMap::new();
    let mut out = vec![];
    for p in children(&procfs()) {
        let pid = match basename(&p).parse::<u32>() {
            Ok(pid) if pid != std::process::id() => pid,
            _ => continue,
        };
        let stat = read(&p.join("stat"));
        let Some(end) = stat.rfind(')') else { continue };
        let fields = stat[end + 1..].split_whitespace().collect::<Vec<_>>();
        if fields.len() < 22 {
            continue;
        }
        let parse = |i: usize| fields[i].parse::<i64>().ok();
        let Some((ppid, user_ticks, sys_ticks, nthreads, start, rss)) = parse(1)
            .zip(parse(11))
            .zip(parse(12))
            .zip(parse(17))
            .zip(parse(19))
            .zip(parse(21))
            .map(|(((((a, b), c), d), e), f)| (a, b, c, d, e, f))
        else {
            continue;
        };
        let Ok(meta) = p.metadata() else { continue };
        let uid = meta.uid();
        let user = users.entry(uid).or_insert_with(|| {
            User::from_uid(Uid::from_raw(uid))
                .ok()
                .flatten()
                .map(|u| u.name)
                .unwrap_or_else(|| uid.to_string())
        });
        let tick = user_ticks + sys_ticks;
        let key = pid.to_string();
        ticks.insert(key.clone(), json!(tick));
        let old = previous["process_ticks"]
            .get(&key)
            .and_then(Value::as_i64)
            .unwrap_or(tick);
        let cpu = (tick - old).max(0) as f64 / clock / elapsed * 100.;
        let mem = if total_mem > 0 {
            rss as f64 * page / total_mem as f64 * 100.
        } else {
            0.
        };
        let name = read_default(&p.join("comm"), &key);
        let cmd = read(&p.join("cmdline")).replace('\0', " ");
        let cmd = if cmd.trim().is_empty() {
            name.clone()
        } else {
            cmd.trim().chars().take(700).collect()
        };
        out.push(json!({"pid":pid,"ppid":ppid,"name":name,"user":user,"state":fields[0],"threads":nthreads,"elapsed_sec":round((uptime-start as f64/clock).max(0.),0),"cpu":round(cpu,1),"mem":round(mem,1),"command":cmd}));
    }
    out.sort_by(|a, b| {
        f(b, "cpu", 0.)
            .total_cmp(&f(a, "cpu", 0.))
            .then_with(|| f(b, "mem", 0.).total_cmp(&f(a, "mem", 0.)))
            .then_with(|| {
                text(a, "name", "")
                    .to_lowercase()
                    .cmp(&text(b, "name", "").to_lowercase())
            })
    });
    (out, json!({"process_time":now,"process_ticks":ticks}))
}
pub fn main(args: &[String]) -> (Value, i32) {
    let (mut top, mut only_gpus) = (0_i64, false);
    let mut options = args.iter();
    while let Some(option) = options.next() {
        match option.as_str() {
            "--gpus" => only_gpus = true,
            "--top-processes" => match options.next().and_then(|s| s.parse().ok()) {
                Some(n) => top = n,
                None => {
                    eprintln!("cortetsu-hardware-probe: --top-processes requires an integer");
                    return (Value::Null, 2);
                }
            },
            "-h" | "--help" => {
                eprintln!("usage: cortetsu-hardware-probe [--gpus] [--top-processes N]");
                return (Value::Null, 0);
            }
            _ => {
                eprintln!("cortetsu-hardware-probe: unrecognized argument {option}");
                return (Value::Null, 2);
            }
        }
    }
    if only_gpus {
        return (json!({"gpus":gpus()}), 0);
    }
    let state = runtime().join("cortetsu-hardware-probe-state.json");
    let _lock = lock(&state.with_extension("lock")).ok();
    let previous = json_file(&state, json!({}));
    let now_mono = monotonic();
    let uptime = read(&procfs().join("uptime"))
        .split_whitespace()
        .next()
        .and_then(|x| x.parse::<f64>().ok())
        .unwrap_or(0.);
    let (cpu, cpu_state) = cpu(&previous);
    let (memory, total) = memory();
    let (net, net_state) = network(&previous, now_mono);
    let (disk_io, disks_io, disk_state) = disk_io(&previous, now_mono);
    let (mut processes, process_state) = processes(&previous, now_mono, uptime, total);
    let count = processes.len();
    let mut next = Map::new();
    for v in [cpu_state, net_state, disk_state, process_state] {
        next.extend(v.as_object().unwrap().clone())
    }
    let _ = atomic_json(&state, &Value::Object(next));
    if top > 0 {
        processes.truncate(top as usize)
    }
    let load = read(&procfs().join("loadavg"))
        .split_whitespace()
        .take(3)
        .filter_map(|n| n.parse::<f64>().ok())
        .map(|n| round(n, 2))
        .collect::<Vec<_>>();
    (
        json!({"timestamp":now()as i64,"host":read(&procfs().join("sys/kernel/hostname")),"kernel":read(&procfs().join("sys/kernel/osrelease")),"uptime_sec":round(uptime,0),"load":load,"cpu":cpu,"memory":memory,"disk":disk(),"disk_io":disk_io,"disks_io":disks_io,"battery":battery(),"network":net,"gpus":gpus(),"fans":fans(),"processes":processes,"process_count":count}),
        0,
    )
}
