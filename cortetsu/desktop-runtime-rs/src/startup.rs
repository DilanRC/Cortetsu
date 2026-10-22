//! Startup inventory and explicit, verified per-entry edits. Lua is read, never evaluated.
use crate::common::*;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    env,
    fs::{self, OpenOptions},
    io::Write,
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

fn unit_valid(unit: &str) -> bool {
    let Some((name, ext)) = unit.rsplit_once('.') else {
        return false;
    };
    !name.is_empty()
        && !name.starts_with('-')
        && matches!(ext, "service" | "socket" | "timer" | "path")
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_.@:-".contains(&b))
}
fn normalize_unit_state(s: &str) -> Value {
    let (category, label) = match s {
        "enabled" => ("persistent", "Persistente"),
        "enabled-runtime" => ("runtime", "Temporal"),
        "disabled" => ("disabled", "Deshabilitado"),
        "linked" => ("special", "Enlazada; disponible, sin autoinicio"),
        "linked-runtime" => (
            "special",
            "Enlazada esta sesión; disponible, sin autoinicio",
        ),
        _ => ("special", "No administrable"),
    };
    json!({"category":category,"label":label,"configured":matches!(category,"persistent"|"runtime"),"modifiable":matches!(s,"enabled"|"enabled-runtime"|"disabled"),"persistent":category=="persistent","runtime":category=="runtime"})
}
fn field<'a>(v: &'a BTreeMap<String, String>, key: &str) -> &'a str {
    v.get(key).map(String::as_str).unwrap_or("")
}
fn activation_reason(
    unit: &str,
    v: &BTreeMap<String, String>,
    state: &str,
) -> (String, &'static str) {
    if unit.ends_with(".service") {
        for (suffix, label) in [
            (".socket", "Puede activarse por socket"),
            (".timer", "Programada por timer"),
            (".path", "Puede activarse por path"),
        ] {
            if let Some(a) = field(v, "TriggeredBy")
                .split_whitespace()
                .find(|a| a.ends_with(suffix))
            {
                return (
                    format!("{label} {a}; no se confirma que lo haya iniciado ahora."),
                    "activator",
                );
            }
        }
    }
    if matches!(state, "enabled" | "enabled-runtime")
        && let Some(target) = field(v, "WantedBy")
            .split_whitespace()
            .chain(field(v, "RequiredBy").split_whitespace())
            .next()
    {
        return (
            format!(
                "Instalada para iniciarse con {target}{}",
                if state == "enabled-runtime" {
                    " durante esta sesión"
                } else {
                    ""
                }
            ),
            "target",
        );
    }
    if unit.ends_with(".service")
        && let Some(dep) = field(v, "BoundBy").split_whitespace().next()
    {
        return (
            format!(
                "Puede iniciarse por dependencia de {dep}; la causalidad de esta ejecución no está confirmada."
            ),
            "dependency",
        );
    }
    if field(v, "ActiveState") == "active" {
        return (
            "Activa; inicio manual o activador exacto no determinado.".into(),
            "unknown",
        );
    }
    if matches!(state, "linked" | "linked-runtime") {
        return (
            "Unidad enlazada para disponibilidad; no está habilitada para inicio automático."
                .into(),
            "unknown",
        );
    }
    (
        "Configurada mediante systemd --user. Activador exacto no determinado.".into(),
        "unknown",
    )
}
fn shell_join(args: &[String]) -> String {
    args.iter()
        .map(|arg| {
            if !arg.is_empty()
                && arg
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"_@%+=:,./-".contains(&b))
            {
                arg.clone()
            } else {
                format!("'{}'", arg.replace('\'', "'\"'\"'"))
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}
fn glob_match(pattern: &str, value: &str) -> bool {
    // Commands declare only '*' wildcards. Preserve fnmatch's ? and [..] classes too.
    let mut expression = String::from("^");
    let mut chars = pattern.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '*' => expression.push_str(".*"),
            '?' => expression.push('.'),
            '[' => {
                let mut class = String::from("[");
                if chars.peek() == Some(&'!') {
                    chars.next();
                    class.push('^');
                }
                let mut closed = false;
                for c in chars.by_ref() {
                    class.push(c);
                    if c == ']' {
                        closed = true;
                        break;
                    }
                }
                if closed {
                    expression.push_str(&class)
                } else {
                    expression.push_str(&regex::escape(&class))
                }
            }
            _ => expression.push_str(&regex::escape(&c.to_string())),
        }
    }
    expression.push('$');
    regex::Regex::new(&expression).is_ok_and(|r| r.is_match(value))
}
fn canonical(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| {
        if path.is_absolute() {
            path.to_path_buf()
        } else {
            env::current_dir().unwrap_or_default().join(path)
        }
    })
}
fn process_matches(command: &[String], argv: &[String], executable: &Path, running: &Path) -> bool {
    if command.is_empty() || argv.is_empty() {
        return false;
    }
    let name = Path::new(&command[0]).file_name().unwrap_or_default();
    let expected = canonical(executable);
    let current = canonical(running);
    let actual = which(&argv[0]).unwrap_or_else(|| PathBuf::from(&argv[0]));

    let offset = if Path::new(&argv[0]).file_name() == Some(name) {
        if canonical(&actual) != expected || current != expected {
            return false;
        }
        1
    } else if Path::new(&argv[0])
        .file_name()
        .is_some_and(|n| n.to_string_lossy().starts_with("python"))
        && argv.len() > 1
        && canonical(Path::new(&argv[1])) == expected
        && canonical(&actual) == current
    {
        2
    } else if argv.len() > 1
        && argv[1] == command[0]
        && [
            "cortetsu-desktop-runtime",
            "cortetsu-hardware-runtime",
            "cortetsu-platform",
        ]
        .iter()
        .any(|n| Path::new(&argv[0]).file_name().is_some_and(|f| f == *n))
    {
        let file = Path::new(&argv[0]).file_name().unwrap_or_default();
        let adjacent = expected.parent().unwrap_or(Path::new("/")).join(file);
        if canonical(&adjacent) != current || canonical(&actual) != current {
            return false;
        }
        2
    } else {
        return false;
    };
    argv.len() - offset >= command.len() - 1
        && argv[offset..]
            .iter()
            .zip(&command[1..])
            .all(|(a, p)| glob_match(p, a))
}
fn process_running(command: &[String], unambiguous: bool) -> Option<bool> {
    if !unambiguous
        || command.is_empty()
        || !Path::new(&command[0])
            .file_name()
            .is_some_and(|p| p.to_string_lossy().starts_with("cortetsu-"))
    {
        return None;
    }
    let executable = which(&command[0]).unwrap_or_else(|| PathBuf::from(&command[0]));
    let Ok(entries) = fs::read_dir("/proc") else {
        return Some(false);
    };
    for proc in entries.flatten() {
        let Some(pid) = proc
            .file_name()
            .to_str()
            .and_then(|p| p.parse::<u32>().ok())
        else {
            continue;
        };
        if pid == std::process::id() {
            continue;
        }
        let Ok(raw) = fs::read(proc.path().join("cmdline")) else {
            continue;
        };
        let Ok(running) = fs::canonicalize(proc.path().join("exe")) else {
            continue;
        };
        let argv: Vec<String> = raw
            .split(|b| *b == 0)
            .filter(|b| !b.is_empty())
            .map(|b| String::from_utf8_lossy(b).into_owned())
            .collect();
        if process_matches(command, &argv, &executable, &running) {
            return Some(true);
        }
    }
    Some(false)
}
fn cortetsu_entries() -> Result<Vec<Value>> {
    let components: Vec<Value> = serde_json::from_str(include_str!("startup-components.json"))?;
    let root = resources();
    let mut counts = HashMap::new();
    for c in &components {
        if let Some(cmd) = c["command"][0].as_str()
            && cmd.starts_with("cortetsu-")
        {
            *counts.entry(cmd.to_owned()).or_insert(0) += 1;
        }
    }
    Ok(components.iter().map(|c|{let command:Vec<String>=c["command"].as_array().map(|v|v.iter().filter_map(Value::as_str).map(str::to_owned).collect()).unwrap_or_default();let phase=text(&c["startupPhase"]);let label=match phase{"always-on"=>"Siempre activo","conditional"=>"Condicional",_=>"Bajo demanda"};let running=command.first().and_then(|name|process_running(&command,counts.get(name)==Some(&1)));json!({"id":c["id"],"name":c["name"],"icon":"deployed_code","description":c["condition"],"sourceType":"cortetsu","origin":root.join(text(&c["source"])),"command":c.get("commandDisplay").cloned().unwrap_or(json!(shell_join(&command))),"startupPhase":phase,"startupState":phase,"startupLabel":label,"configured":phase!="on-demand","running":running,"modifiable":false,"reason":c["condition"]})}).collect())
}
fn desktop_values(path: &Path) -> Option<BTreeMap<String, String>> {
    let data = fs::read_to_string(path).ok()?;
    let mut active = false;
    let mut map = BTreeMap::new();
    for line in data.lines() {
        let s = line.trim();
        if s.starts_with('[') {
            active = s == "[Desktop Entry]";
            continue;
        }
        if active
            && !s.starts_with('#')
            && !s.starts_with(';')
            && let Some((k, v)) = s.split_once('=')
        {
            map.insert(k.trim().to_owned(), v.trim().to_owned());
        }
    }
    (!map.is_empty()).then_some(map)
}
fn desktop_entry(path: &Path, system: bool, desktops: &BTreeSet<String>) -> Option<Value> {
    let e = desktop_values(path)?;
    let hidden = field(&e, "Hidden").eq_ignore_ascii_case("true");
    let only: BTreeSet<_> = field(&e, "OnlyShowIn")
        .split(';')
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect();
    let no: BTreeSet<_> = field(&e, "NotShowIn")
        .split(';')
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect();
    let try_exec = field(&e, "TryExec").trim();
    let eligible = (only.is_empty() || !only.is_disjoint(desktops))
        && no.is_disjoint(desktops)
        && (try_exec.is_empty() || which(try_exec).is_some());
    let filename = path.file_name()?.to_str()?;
    let name = e.get("Name").cloned().unwrap_or_else(|| {
        path.file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned()
    });
    Some(
        json!({"id":format!("xdg:{filename}"),"name":name,"icon":field(&e,"Icon"),"description":field(&e,"Comment"),"sourceType":if system{"xdg-system"}else{"xdg-user"},"origin":path,"command":field(&e,"Exec"),"startupPhase":"login","configured":!hidden,"eligible":eligible,"running":null,"modifiable":true,"reason":if !hidden&&eligible{"Entrada efectiva de inicio de sesión"}else if !hidden{"Configurada, pero no aplicable en este escritorio o TryExec no disponible"}else{"Deshabilitada mediante Hidden=true"},"_path":path,"_system":system}),
    )
}
fn config_dirs() -> Vec<PathBuf> {
    env::var("XDG_CONFIG_DIRS")
        .unwrap_or_else(|_| "/etc/xdg".into())
        .split(':')
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .collect()
}
fn xdg_entries() -> Vec<Value> {
    let mut dirs: Vec<_> = config_dirs()
        .into_iter()
        .rev()
        .map(|d| (d.join("autostart"), true))
        .collect();
    dirs.push((config().join("autostart"), false));
    let desktops = env::var("XDG_CURRENT_DESKTOP")
        .unwrap_or_default()
        .split(':')
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect();
    let mut paths = BTreeMap::new();
    for (dir, system) in dirs {
        if let Ok(entries) = fs::read_dir(dir) {
            for e in entries.flatten() {
                if e.path().extension().is_some_and(|v| v == "desktop") {
                    paths.insert(e.file_name(), (e.path(), system));
                }
            }
        }
    }
    paths
        .values()
        .filter_map(|(path, system)| desktop_entry(path, *system, &desktops))
        .collect()
}
fn systemd_command(raw: &str) -> String {
    let re = regex::Regex::new(r"argv\[\]=([^;]+)").expect("static regex");
    re.captures_iter(raw)
        .filter_map(|c| shell_words::split(c[1].trim()).ok())
        .map(|v| shell_join(&v))
        .collect::<Vec<_>>()
        .join("\n")
}
fn systemctl(args: &[String], user: bool) -> Option<std::process::Output> {
    let mut c = Command::new("systemctl");
    if user {
        c.arg("--user");
    }
    c.args(args);
    run(&mut c, None, Duration::from_secs(4)).ok()
}
fn sd(args: &[&str], user: bool) -> Option<std::process::Output> {
    systemctl(
        &args.iter().map(|s| (*s).to_owned()).collect::<Vec<_>>(),
        user,
    )
}
fn systemd_entries(user: bool) -> Vec<Value> {
    let mut units = BTreeMap::new();
    if let Some(o) = sd(
        &[
            "list-unit-files",
            "--type=service",
            "--type=socket",
            "--type=timer",
            "--type=path",
            "--no-legend",
            "--no-pager",
        ],
        user,
    )
    .filter(|o| o.status.success())
    {
        for line in String::from_utf8_lossy(&o.stdout).lines() {
            let f: Vec<_> = line.split_whitespace().collect();
            if f.len() >= 2 && unit_valid(f[0]) {
                units.insert(f[0].to_owned(), f[1].to_owned());
            }
        }
    }
    if let Some(o) = sd(
        &[
            "list-units",
            "--all",
            "--type=service",
            "--type=socket",
            "--type=timer",
            "--type=path",
            "--no-legend",
            "--no-pager",
        ],
        user,
    )
    .filter(|o| o.status.success())
    {
        for line in String::from_utf8_lossy(&o.stdout).lines() {
            let f: Vec<_> = line.split_whitespace().collect();
            if f.len() >= 4 && unit_valid(f[0]) {
                units.entry(f[0].to_owned()).or_insert("transient".into());
            }
        }
    }
    let names: Vec<_> = units.keys().cloned().collect();
    let mut snapshots = HashMap::new();
    for chunk in names.chunks(80) {
        let mut args = vec!["show".to_owned()];
        args.extend_from_slice(chunk);
        args.push("--property=Id,Description,ActiveState,UnitFileState,WantedBy,RequiredBy,TriggeredBy,BoundBy,ConsistsOf,FragmentPath,ExecStart".into());
        if let Some(o) = systemctl(&args, user) {
            for block in String::from_utf8_lossy(&o.stdout).split("\n\n") {
                let v: BTreeMap<_, _> = block
                    .lines()
                    .filter_map(|l| l.split_once('='))
                    .map(|(k, v)| (k.to_owned(), v.to_owned()))
                    .collect();
                if let Some(id) = v.get("Id") {
                    snapshots.insert(id.clone(), v);
                }
            }
        }
    }
    units.into_iter().map(|(unit,file_state)|{let v=snapshots.remove(&unit).unwrap_or_default();let active=if v.contains_key("ActiveState"){field(&v,"ActiveState")}else{"unknown"};let state=normalize_unit_state(&file_state);let source=if user&&unit.starts_with("cortetsu-"){"cortetsu"}else if user{"systemd-user"}else{"systemd-system"};let (mut reason,activation)=if user{activation_reason(&unit,&v,&file_state)}else{("Configurada mediante systemd del sistema. Activador exacto no determinado.".into(),"unknown")};if unit=="cortetsu-shell.service"{reason.push_str(" · Servicio principal de Cortetsu; esta página no permite desactivarlo");}let target=field(&v,"WantedBy").split_whitespace().chain(field(&v,"RequiredBy").split_whitespace()).collect::<Vec<_>>().join(", ");json!({"id":format!("{}{unit}",if user{"user-unit:"}else{"system-unit:"}),"name":v.get("Description").filter(|s|!s.is_empty()).unwrap_or(&unit),"icon":"settings_suggest","description":unit,"sourceType":source,"origin":v.get("FragmentPath").unwrap_or(&unit),"command":systemd_command(field(&v,"ExecStart")),"startupPhase":if user{"login"}else{"boot"},"configured":state["configured"],"startupState":state["category"],"startupLabel":state["label"],"persistent":state["persistent"],"runtimeOnly":state["runtime"],"running":match active{"active"=>Some(true),"inactive"|"failed"=>Some(false),_=>None},"activeState":active,"unitState":file_state,"activationType":activation,"target":target,"modifiable":user&&source=="systemd-user"&&state["modifiable"]==true,"reason":reason,"_unit":unit,"_user":user,"_exec_start":field(&v,"ExecStart"),"_file_state":file_state})}).collect()
}
fn hypr_sources() -> Vec<PathBuf> {
    let root = config().join("hypr/hyprland.lua");
    if !root.is_file() {
        return Vec::new();
    }
    let mut sources = BTreeSet::from([root.clone()]);
    let wrapper = fs::read_to_string(&root).unwrap_or_default();
    let re = regex::Regex::new(r#"dofile\(\s*["']([^"']+)["']\s*\)"#).expect("static regex");
    let active = re.captures(&wrapper).map(|m| expand(&m[1])).unwrap_or(root);
    if active.is_file() {
        sources.insert(active.clone());
        let text = fs::read_to_string(&active).unwrap_or_default();
        let names = regex::Regex::new(r#"["']([A-Za-z0-9_.-]+)["']"#).expect("static regex");
        for (pattern, user) in [
            (r"(?s)local required_modules\s*=\s*\{(.*?)\}", false),
            (r"(?s)for _, name in ipairs\(\{(.*?)\}\)", true),
        ] {
            let r = regex::Regex::new(pattern).expect("static regex");
            if let Some(c) = r.captures(&text) {
                for m in names.captures_iter(&c[1]) {
                    let candidate = if user {
                        config().join(format!("hypr/custom/{}.lua", &m[1]))
                    } else {
                        active
                            .parent()
                            .unwrap_or(Path::new("."))
                            .join(format!("{}.lua", m[1].replace('.', "/")))
                    };
                    if candidate.is_file() {
                        sources.insert(candidate);
                    }
                }
            }
        }
        let user = config().join("hypr/hypr-user.lua");
        if user.is_file() {
            sources.insert(user);
        }
    }
    sources.into_iter().collect()
}
fn command_key(raw: &str) -> String {
    let Ok(mut args) = shell_words::split(raw) else {
        return String::new();
    };
    if args.is_empty() || args.iter().any(|a| a.contains('%')) {
        return String::new();
    }
    if let Some(p) = which(&args[0]) {
        args[0] = if p.is_absolute() {
            p
        } else {
            env::current_dir().unwrap_or_default().join(p)
        }
        .to_string_lossy()
        .into_owned();
    }
    format!(
        "command:{}",
        serde_json::to_string(&args).unwrap_or_default()
    )
}
fn duplicate_keys(item: &Value, lookup: &HashMap<String, Vec<String>>) -> Vec<String> {
    let source = text(&item["sourceType"]);
    if matches!(source, "systemd-user" | "cortetsu") && item.get("_unit").is_some() {
        if item["configured"] != true {
            return Vec::new();
        }
        let unit = text(&item["_unit"]);
        let mut keys = Vec::new();
        if !unit.is_empty() && item["_file_state"] != "alias" {
            keys.push(format!("unit:{unit}"));
        }
        for command in text(&item["command"]).lines() {
            let k = command_key(command);
            if !k.is_empty() && !keys.contains(&k) {
                keys.push(k);
            }
        }
        return keys;
    }
    if !matches!(source, "xdg-user" | "xdg-system" | "hyprland" | "cortetsu") {
        return Vec::new();
    }
    if source.starts_with("xdg-") && (item["configured"] != true || item["eligible"] == false) {
        return Vec::new();
    }
    let raw = text(&item["command"]);
    if source == "hyprland" && raw.starts_with("hl.exec_cmd(") {
        return Vec::new();
    }
    let Ok(args) = shell_words::split(raw) else {
        return Vec::new();
    };
    if args.first().is_some_and(|s| s == "systemctl") && args.iter().any(|s| s == "--user") {
        if let Some(unit) = args.iter().find(|s| unit_valid(s)) {
            let mut keys = vec![format!("unit:{unit}")];
            keys.extend(lookup.get(unit).cloned().unwrap_or_default());
            return keys;
        }
        return Vec::new();
    }
    let key = command_key(raw);
    if key.is_empty() {
        Vec::new()
    } else {
        vec![key]
    }
}
fn group(parents: &mut [usize], index: usize) -> usize {
    if parents[index] != index {
        parents[index] = group(parents, parents[index]);
    }
    parents[index]
}
fn scan() -> Result<Vec<Value>> {
    let mut entries = xdg_entries();
    entries.extend(systemd_entries(true));
    entries.extend(systemd_entries(false));
    let start = regex::Regex::new(r#"hl\.on\(\s*["']hyprland\.start["']"#)?;
    let end = regex::Regex::new(r"^end\s*\)\s*$")?;
    let invoke = regex::Regex::new(r"^\s+hl\.exec_cmd\(")?;
    let command = regex::Regex::new(
        r#"hl\.exec_cmd\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|\[\[(.*?)\]\])"#,
    )?;
    for path in hypr_sources() {
        let mut active = false;
        for (i, line) in fs::read_to_string(&path)
            .unwrap_or_default()
            .lines()
            .enumerate()
        {
            if start.is_match(line) {
                active = true;
            } else if active && end.is_match(line) {
                active = false;
            } else if active && invoke.is_match(line) {
                let command = command
                    .captures(line)
                    .and_then(|m| (1..=3).find_map(|i| m.get(i).map(|s| s.as_str().to_owned())))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| line.trim().to_owned());
                let origin = format!("{}:{}", path.display(), i + 1);
                entries.push(json!({"id":format!("hyprland:{origin}"),"name":"Hyprland startup command","icon":"terminal","description":"","sourceType":"hyprland","origin":origin,"command":command,"startupPhase":"shell","configured":true,"running":null,"modifiable":false,"reason":"Hyprland ejecuta esta entrada al iniciar la sesión"}));
            }
        }
    }
    entries.extend(cortetsu_entries()?);
    let lookup: HashMap<_, _> = entries
        .iter()
        .filter(|v| v["_user"] == true && v["_unit"].is_string())
        .map(|v| {
            (
                text(&v["_unit"]).to_owned(),
                text(&v["command"])
                    .lines()
                    .map(command_key)
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>(),
            )
        })
        .collect();
    let keys: Vec<_> = entries.iter().map(|v| duplicate_keys(v, &lookup)).collect();
    let mut parents: Vec<_> = (0..entries.len()).collect();
    let mut owners = HashMap::new();
    for (i, ks) in keys.iter().enumerate() {
        for k in ks {
            if let Some(old) = owners.get(k) {
                let a = group(&mut parents, i);
                let b = group(&mut parents, *old);
                parents[b] = a;
            } else {
                owners.insert(k.clone(), i);
            }
        }
    }
    let mut counts = HashMap::new();
    for (i, ks) in keys.iter().enumerate() {
        if !ks.is_empty() {
            *counts.entry(group(&mut parents, i)).or_insert(0) += 1;
        }
    }
    for (i, item) in entries.iter_mut().enumerate() {
        item["duplicateCount"] = json!(if keys[i].is_empty() {
            0
        } else {
            *counts.get(&group(&mut parents, i)).unwrap_or(&0)
        });
        if let Some(m) = item.as_object_mut() {
            for k in [
                "_path",
                "_system",
                "_unit",
                "_user",
                "_exec_start",
                "_file_state",
            ] {
                m.remove(k);
            }
        }
    }
    Ok(entries)
}
fn set_hidden(path: &Path, hidden: bool) -> Result<()> {
    let bytes = fs::read(path)?;
    let backups = state().join("startup/backups");
    fs::create_dir_all(&backups)?;
    fs::set_permissions(&backups, fs::Permissions::from_mode(0o700))?;
    fs::set_permissions(
        backups.parent().ok_or("backup parent")?,
        fs::Permissions::from_mode(0o700),
    )?;
    let backup = backups.join(format!("{:x}.desktop", Sha256::digest(&bytes)));
    if !backup.exists() {
        atomic(&backup, &bytes, 0o600)?;
    }
    let text = String::from_utf8_lossy(&bytes);
    let mut lines: Vec<String> = text.lines().map(str::to_owned).collect();
    let start = lines
        .iter()
        .position(|l| l.trim() == "[Desktop Entry]")
        .ok_or("falta [Desktop Entry]")?;
    let end = (start + 1..lines.len())
        .find(|i| lines[*i].starts_with('['))
        .unwrap_or(lines.len());
    let positions: Vec<_> = (start + 1..end)
        .filter(|i| lines[*i].starts_with("Hidden="))
        .collect();
    let value = format!("Hidden={hidden}");
    if let Some(first) = positions.first() {
        lines[*first] = value;
        for pos in positions.iter().skip(1).rev() {
            lines.remove(*pos);
        }
    } else {
        lines.insert(end, value);
    }
    let mode = fs::metadata(path)?.permissions().mode() & 0o777;
    atomic(
        path,
        format!("{}\n", lines.join("\n").trim_end_matches('\n')).as_bytes(),
        mode,
    )?;
    Ok(())
}
fn record_change(found: &Value, old: Value, new: Value, action: &str) -> Result<()> {
    let path = state().join("startup/changes.jsonl");
    fs::create_dir_all(path.parent().ok_or("change parent")?)?;
    fs::set_permissions(
        path.parent().ok_or("change parent")?,
        fs::Permissions::from_mode(0o700),
    )?;
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(path)?;
    writeln!(
        file,
        "{}",
        json!({"timestamp":now()as u64,"source":found["sourceType"],"item":found["name"],"oldState":old,"newState":new,"action":action})
    )?;
    file.sync_all()?;
    Ok(())
}
fn require_systemctl(args: &[&str]) -> Result<()> {
    let output = sd(args, true).ok_or("systemctl no disponible")?;
    if !output.status.success() {
        let text = String::from_utf8_lossy(&output.stderr);
        return Err(if text.trim().is_empty() {
            "systemctl falló".to_owned()
        } else {
            text.trim().to_owned()
        }
        .into());
    }
    Ok(())
}
fn action(id: &str, desired: &str) -> Result<Value> {
    if !matches!(desired, "enable" | "disable" | "stop") {
        return Err("acción inválida".into());
    }
    let _guard = lock(&state().join("startup/action.lock"), false)?;
    let found = scan()?
        .into_iter()
        .find(|v| v["id"] == id && v["modifiable"] == true)
        .ok_or("esta entrada no se puede modificar")?;
    if desired == "stop" {
        let unit = id
            .strip_prefix("user-unit:")
            .ok_or("sólo se pueden detener unidades de usuario activas")?;
        if found["running"] != true {
            return Err("sólo se pueden detener unidades de usuario activas".into());
        }
        if !unit_valid(unit) {
            return Err("unidad inválida".into());
        }
        require_systemctl(&["stop", unit])?;
        let updated = scan()?
            .into_iter()
            .find(|v| v["id"] == id && v["running"] == false)
            .ok_or("la verificación posterior no confirmó que la unidad se detuviera")?;
        record_change(&found, json!("running"), json!("stopped"), "stop")?;
        return Ok(json!({"ok":true,"entry":updated}));
    }
    let mut transition = None;
    if let Some(filename) = id.strip_prefix("xdg:") {
        if Path::new(filename)
            .file_name()
            .is_none_or(|f| f != filename)
            || !filename.ends_with(".desktop")
        {
            return Err("identificador de archivo inválido".into());
        }
        let target = config().join("autostart").join(filename);
        let dir = target.parent().ok_or("autostart parent")?;
        if dir.is_symlink() || target.is_symlink() {
            return Err("no se modifican enlaces simbólicos de autostart".into());
        }
        if !target.exists() {
            let source = PathBuf::from(text(&found["origin"]));
            let source_canonical = canonical(&source);
            if !config_dirs().iter().any(|d| {
                d.exists()
                    && source_canonical.parent() == Some(canonical(d).join("autostart").as_path())
            }) {
                return Err("origen XDG fuera de los directorios permitidos".into());
            }
            atomic(&target, &fs::read(source)?, 0o600)?;
        }
        set_hidden(&target, desired == "disable")?;
    } else if let Some(unit) = id.strip_prefix("user-unit:") {
        if !unit_valid(unit) || unit == "cortetsu-shell.service" {
            return Err("unidad no administrable".into());
        }
        match (desired, text(&found["unitState"])) {
            ("enable", "disabled") => {
                require_systemctl(&["enable", unit])?;
                transition = Some("enabled");
            }
            ("disable", "enabled") => {
                require_systemctl(&["disable", unit])?;
                transition = Some("disabled");
            }
            ("disable", "enabled-runtime") => {
                require_systemctl(&["--runtime", "disable", unit])?;
                transition = Some("disabled-runtime");
            }
            _ => return Err("el estado actual de systemd no permite esa transición".into()),
        }
    } else {
        return Err("origen no administrable".into());
    }
    let updated = scan()?
        .into_iter()
        .find(|v| v["id"] == id)
        .ok_or("la verificación posterior no confirmó el estado systemd esperado")?;
    let verified = match transition {
        Some("enabled") => updated["unitState"] == "enabled",
        Some("disabled") => updated["unitState"] == "disabled",
        Some("disabled-runtime") => {
            updated["unitState"].is_string()
                && !matches!(text(&updated["unitState"]), "enabled" | "enabled-runtime")
        }
        _ => updated["configured"] == (desired == "enable"),
    };
    if !verified {
        return Err("la verificación posterior no confirmó el estado systemd esperado".into());
    }
    record_change(
        &found,
        if transition.is_some() {
            found["unitState"].clone()
        } else {
            found["configured"].clone()
        },
        if transition.is_some() {
            updated["unitState"].clone()
        } else {
            json!(desired == "enable")
        },
        desired,
    )?;
    Ok(json!({"ok":true,"entry":updated}))
}
pub fn main(args: &[String]) -> Result<i32> {
    let a: Vec<_> = args.iter().map(String::as_str).collect();
    let output = match a.as_slice() {
        ["scan"] => scan().map(|entries| json!({"ok":true,"entries":entries})),
        ["set", id, desired] => action(id, desired),
        _ => {
            emit(
                &json!({"ok":false,"error":"uso: cortetsu-startup scan | set ID enable|disable|stop"}),
            )?;
            return Ok(2);
        }
    };
    match output {
        Ok(v) => {
            emit(&v)?;
            Ok(0)
        }
        Err(e) => {
            emit(&json!({"ok":false,"error":e.to_string()}))?;
            Ok(1)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn runtime_and_linked_states_are_distinct() {
        assert_eq!(normalize_unit_state("enabled-runtime")["runtime"], true);
        assert_eq!(normalize_unit_state("linked")["configured"], false);
        assert_eq!(normalize_unit_state("linked")["modifiable"], false);
        assert!(!unit_valid("--bad.service"));
    }
    #[test]
    fn duplicate_fieldcodes_and_exec_parse() {
        assert_eq!(
            shell_join(&["notify-send", "--app-name=Cortetsu", "*"].map(str::to_owned)),
            "notify-send --app-name=Cortetsu '*'"
        );
        assert_eq!(command_key("app %U"), "");
        assert_eq!(
            systemd_command(
                "{ path=/usr/bin/a ; argv[]=a --flag 'two words' ; ignore_errors=no ; }"
            ),
            "a --flag 'two words'"
        );
        assert!(glob_match("foo*", "foobar"));
        assert!(!glob_match("bar*", "foobar"));
    }
}
