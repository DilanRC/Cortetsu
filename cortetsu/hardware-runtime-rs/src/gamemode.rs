use crate::util::*;
use serde_json::{Map, Value, json};
use std::{env, fs, path::Path};
const PENDING: [&str; 3] = ["APPLYING", "RESTORING", "RECOVERY_REQUIRED"];
fn game() -> Value {
    json!({"animations:enabled":false,"decoration:shadow:enabled":false,"decoration:blur:enabled":false,"general:gaps_in":0,"general:gaps_out":0,"general:border_size":1,"decoration:rounding":0,"general:allow_tearing":true})
}
fn instance() -> Result<String> {
    let s = env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default();
    if s.is_empty() {
        return Err("HYPRLAND_INSTANCE_SIGNATURE is not set".into());
    }
    if s.contains('/') || s.contains('\0') || s.len() > 200 {
        return Err("invalid HYPRLAND_INSTANCE_SIGNATURE".into());
    }
    Ok(s)
}
fn call(args: &[&str]) -> Result<String> {
    let r = hypr(args, 5.)?;
    if r.code != 0 {
        return Err(format!("hyprctl {} failed: {}", args[0], r.detail()));
    }
    Ok(r.stdout)
}
fn get(option: &str) -> Result<Value> {
    let v: Value = serde_json::from_str(&call(&["getoption", option, "-j"])?)
        .map_err(|_| format!("hyprctl getoption {option}: no JSON"))?;
    if let Some(b) = v.get("bool") {
        return Ok(json!(truth(b)));
    }
    if let Some(n) = v.get("int").and_then(as_i) {
        return Ok(json!(n));
    }
    if let Some(css) = v.get("css").and_then(Value::as_str) {
        let a = css
            .split_whitespace()
            .map(|x| x.parse::<i64>())
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;
        return Ok(json!(a));
    }
    Err(format!("unsupported option type for {option}: {v}"))
}
fn same(a: &Value, b: &Value) -> bool {
    if let Some(a) = a.as_array()
        && !b.is_array()
    {
        return a.iter().all(|v| same(v, b));
    }
    a == b || (as_f(a).is_some() && as_f(a) == as_f(b))
}
fn value_text(v: &Value) -> String {
    match v {
        Value::Bool(b) => (*b as i32).to_string(),
        Value::Array(a) => {
            if !a.is_empty() && a.iter().all(|x| x == &a[0]) {
                s(&a[0])
            } else {
                a.iter().map(s).collect::<Vec<_>>().join(" ")
            }
        }
        _ => s(v),
    }
}
fn lua_value(v: &Value) -> String {
    if v.is_boolean() {
        return v.to_string();
    }
    let t = value_text(v);
    if !t.is_empty() && t.chars().all(|c| c.is_ascii_digit()) {
        t
    } else {
        json!(t).to_string()
    }
}
fn insert_path(node: &mut Map<String, Value>, parts: &[&str], value: &Value) {
    if parts.len() == 1 {
        node.insert(parts[0].into(), value.clone());
        return;
    }
    let child = node
        .entry(parts[0].to_string())
        .or_insert_with(|| json!({}));
    insert_path(child.as_object_mut().unwrap(), &parts[1..], value)
}
fn render(node: &Map<String, Value>) -> String {
    format!(
        "{{ {} }}",
        node.iter()
            .map(|(k, v)| format!(
                "{k} = {}",
                v.as_object().map(render).unwrap_or_else(|| lua_value(v))
            ))
            .collect::<Vec<_>>()
            .join(", ")
    )
}
fn lua_config(values: &Value) -> String {
    let mut tree = Map::new();
    for (k, v) in values.as_object().unwrap() {
        insert_path(&mut tree, &k.split(':').collect::<Vec<_>>(), v)
    }
    format!("hl.config({})", render(&tree))
}
fn write(values: &Value, backend: &str) -> Result<()> {
    let map = values.as_object().ok_or("invalid game values")?;
    if map.is_empty() {
        return Ok(());
    }
    let result = if backend == "lua" {
        call(&["eval", &lua_config(values)]).map(|_| ())
    } else {
        map.iter()
            .try_for_each(|(k, v)| call(&["keyword", k, &value_text(v)]).map(|_| ()))
    };
    let mut wrong = vec![];
    for (k, v) in map {
        if !same(&get(k)?, v) {
            wrong.push(k.clone())
        }
    }
    result?;
    if wrong.is_empty() {
        Ok(())
    } else {
        Err(format!("not applied: {}", wrong.join(", ")))
    }
}
fn load(path: &Path) -> Result<Option<Value>> {
    let raw = match fs::read(path) {
        Ok(x) => x,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("{}: {e}", path.display())),
    };
    let v: Value = serde_json::from_slice(&raw).map_err(|_| {
        format!(
            "{}: not a game mode transaction; left untouched",
            path.display()
        )
    })?;
    let target = game();
    let keys = |a: &Value| {
        a.as_object()
            .map(|o| o.keys().cloned().collect::<std::collections::BTreeSet<_>>())
    };
    let valid = v["schema"] == 2
        && v["instance"] == instance()?
        && (v["state"] == "ACTIVE" || PENDING.contains(&v["state"].as_str().unwrap_or("")))
        && ["lua", "keyword"].contains(&v["backend"].as_str().unwrap_or(""))
        && keys(&v["original"]) == keys(&target)
        && keys(&v["target"]) == keys(&target)
        && v["original"].as_object().is_some_and(|o| {
            o.values().all(|x| {
                x.is_number()
                    || x.is_boolean()
                    || x.as_array()
                        .is_some_and(|a| !a.is_empty() && a.iter().all(|v| v.as_i64().is_some()))
            })
        });
    if !valid {
        return Err(format!(
            "{}: not a game mode transaction; left untouched",
            path.display()
        ));
    }
    Ok(Some(v))
}
fn restore(path: &Path, data: &mut Value) -> Result<()> {
    data["state"] = json!("RESTORING");
    data["desired"] = json!("off");
    atomic_json(path, data)?;
    let result = (|| {
        let mut values = Map::new();
        for (k, original) in data["original"].as_object().unwrap() {
            let current = get(k)?;
            if same(&current, &data["target"][k]) && !same(&current, original) {
                values.insert(k.clone(), original.clone());
            }
        }
        write(&Value::Object(values), data["backend"].as_str().unwrap())
    })();
    if let Err(e) = result {
        data["state"] = json!("RECOVERY_REQUIRED");
        data["last_error"] = json!(e);
        atomic_json(path, data)?;
        return Err(e);
    }
    remove(path)
}
fn enable(path: &Path, backend: &str) -> Result<()> {
    if let Some(v) = load(path)? {
        if v["state"] == "ACTIVE" {
            return Ok(());
        }
        return Err(format!(
            "game mode is {}; run recover first",
            s(&v["state"])
        ));
    }
    let target = game();
    let mut original = Map::new();
    for k in target.as_object().unwrap().keys() {
        original.insert(k.clone(), get(k)?);
    }
    let mut data = json!({"schema":2,"instance":instance()?,"state":"APPLYING","backend":backend,"desired":"on","original":original,"target":target,"last_error":null});
    atomic_json(path, &data)?;
    if let Err(e) = write(&target, backend) {
        return match restore(path, &mut data) {
            Ok(()) => Err(format!("{e}; rolled back")),
            Err(r) => Err(format!("{e}; rollback failed: {r}")),
        };
    }
    data["state"] = json!("ACTIVE");
    atomic_json(path, &data)
}
pub fn main(args: &[String]) -> (Value, i32) {
    let commands = args
        .iter()
        .filter(|a| *a != "--keyword")
        .collect::<Vec<_>>();
    let action = commands.first().map(|a| a.as_str()).unwrap_or("status");
    if commands.len() > 1 || !["enable", "disable", "recover", "status"].contains(&action) {
        return json_error(
            "usage: cortetsu-gamemode enable|disable|recover|status [--keyword]".into(),
        );
    }
    let inst = match instance() {
        Ok(x) => x,
        Err(e) => return json_error(e),
    };
    let path = runtime().join(format!("cortetsu-gamemode-{inst}.json"));
    let _lock = match lock(&path.with_extension("lock")) {
        Ok(l) => l,
        Err(e) => return json_error(e),
    };
    let backend = if args.iter().any(|a| a == "--keyword") {
        "keyword"
    } else {
        "lua"
    };
    let result = match action {
        "enable" => enable(&path, backend),
        "disable" | "recover" => load(&path).and_then(|v| {
            if let Some(mut v) = v
                && (action == "disable" || PENDING.contains(&v["state"].as_str().unwrap_or("")))
            {
                restore(&path, &mut v)?
            }
            Ok(())
        }),
        _ => Ok(()),
    };
    let ok = result.is_ok();
    let mut error = result.err();
    let state = match load(&path) {
        Ok(Some(v)) => {
            if error.is_none() {
                error = v["last_error"].as_str().map(String::from)
            }
            match call(&["version"]) {
                Ok(_) => s(&v["state"]),
                Err(e) => {
                    if error.is_none() {
                        error = Some(e)
                    }
                    "UNKNOWN".into()
                }
            }
        }
        Ok(None) => "INACTIVE".into(),
        Err(e) => {
            if error.is_none() {
                error = Some(e)
            }
            "UNKNOWN".into()
        }
    };
    (
        json!({"state":state,"enabled":state=="ACTIVE","ok":ok,"error":error}),
        if ok { 0 } else { 1 },
    )
}

pub fn owner_snapshot() -> Result<Value> {
    let (state, code) = main(&["status".into()]);
    if code != 0 || state["state"] == "UNKNOWN" {
        return Err("OWNER_UNAVAILABLE".into());
    }
    let mut result = state;
    let mut options = Map::new();
    for key in game().as_object().unwrap().keys() {
        options.insert(key.clone(), get(key).map_err(|_| "OWNER_UNAVAILABLE")?);
    }
    result.as_object_mut().unwrap().remove("ok");
    result.as_object_mut().unwrap().remove("error");
    result["options"] = Value::Object(options);
    Ok(result)
}
