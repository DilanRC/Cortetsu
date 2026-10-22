use crate::util::*;
use regex::Regex;
use serde_json::{Map, Value, json};
use std::{env, path::PathBuf};
#[derive(Debug)]
struct Error {
    code: &'static str,
    message: String,
}
type R<T> = std::result::Result<T, Error>;
fn err<T>(code: &'static str, message: impl Into<String>) -> R<T> {
    Err(Error {
        code,
        message: message.into(),
    })
}
fn directory() -> PathBuf {
    state_home().join("cortetsu")
}
fn connectors() -> Vec<Value> {
    let root = env::var_os("CORTETSU_DRM_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| sysfs().join("class/drm"));
    let mut out = vec![];
    for p in children(&root) {
        let name = basename(&p);
        let Some((card, conn)) = name.split_once('-') else {
            continue;
        };
        let Some(cardnum) = card
            .strip_prefix("card")
            .and_then(|x| x.parse::<u32>().ok())
        else {
            continue;
        };
        if read(&root.join(card).join("device/vendor")).to_lowercase() != "0x10de"
            || conn.starts_with("Writeback")
        {
            continue;
        }
        out.push((
            cardnum,
            integer(&p.join("connector_id")).unwrap_or(i64::MAX),
            conn.to_string(),
            card.to_string(),
            read(&p.join("status")) == "connected",
        ));
    }
    out.sort();
    out.into_iter().enumerate().map(|(index,(_,_,name,card,connected))|json!({"connector":name,"card":card,"connected":connected,"index":index})).collect()
}
fn profile() -> Map<String, Value> {
    json_file(&directory().join("nvibrant.json"), json!({}))["profile"]
        .as_object()
        .map(|p| {
            p.iter()
                .filter(|(_, v)| v.as_i64().is_some_and(|i| (-1024..=1023).contains(&i)))
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect()
        })
        .unwrap_or_default()
}
fn save(p: &Map<String, Value>) -> R<()> {
    atomic_json(&directory().join("nvibrant.json"), &json!({"profile":p})).map_err(|e| Error {
        code: "profile-write-failed",
        message: e,
    })
}
fn value(raw: &str) -> R<i64> {
    let n = raw.parse::<i64>().map_err(|_| Error {
        code: "value-invalid",
        message: "La vibrance debe ser un entero".into(),
    })?;
    if !(-1024..=1023).contains(&n) {
        return err("value-invalid", "La vibrance va de -1024 a 1023");
    }
    Ok(n)
}
fn apply(outputs: &[Value], values: &[i64]) -> R<()> {
    let bin = env::var("CORTETSU_NVIBRANT").unwrap_or_else(|_| "nvibrant".into());
    let r = run(
        &bin,
        &values.iter().map(ToString::to_string).collect::<Vec<_>>(),
        15.,
    )
    .map_err(|e| Error {
        code: "nvibrant-unavailable",
        message: format!("nvibrant no se pudo ejecutar: {e}"),
    })?;
    if r.code != 0 {
        return err(
            "nvibrant-failed",
            r.detail().lines().next().unwrap_or("nvibrant failed"),
        );
    }
    let pattern =
        Regex::new(r"\(\s*(\d+)\s*,\s*([A-Za-z-]+)\s*\)\s*\S*\s*Set vibrance \(\s*(-?\d+)\s*\)")
            .unwrap();
    let echoed = pattern
        .captures_iter(&r.stdout)
        .map(|c| {
            (
                c[1].parse::<usize>().unwrap_or(usize::MAX),
                (c[2].to_string(), c[3].parse::<i64>().unwrap_or(i64::MIN)),
            )
        })
        .collect::<std::collections::HashMap<_, _>>();
    for (o, wanted) in outputs.iter().zip(values) {
        let index = o["index"].as_u64().unwrap_or(0) as usize;
        let name = s(&o["connector"]);
        let Some((kind, got)) = echoed.get(&index) else {
            return err(
                "mapping-mismatch",
                format!("nvibrant no confirmó {name} como display {index}"),
            );
        };
        if !name.to_uppercase().starts_with(&kind.to_uppercase()) {
            return err(
                "mapping-mismatch",
                format!("nvibrant no confirmó {name} como display {index}"),
            );
        }
        if wanted != got {
            return err(
                "not-applied",
                format!("nvibrant aplicó {got} en lugar de {wanted}"),
            );
        }
    }
    Ok(())
}
fn action(args: &[String]) -> R<Value> {
    if args == ["status"] {
        let p = profile();
        let mut out = connectors();
        for o in &mut out {
            o["value"] = p.get(&s(&o["connector"])).cloned().unwrap_or(Value::Null)
        }
        let conflict = children(&config_home().join("systemd/user"))
            .iter()
            .any(|x| {
                basename(x).ends_with(".wants")
                    && x.join("nvibrant.service").symlink_metadata().is_ok()
            });
        return Ok(
            json!({"ok":true,"conflict":if conflict{"nvibrant.service"}else{""},"outputs":out}),
        );
    }
    if args.first().is_none_or(|a| a != "set" && a != "apply") {
        return err(
            "usage",
            "status | set CONNECTOR VALUE | apply [--default N]",
        );
    }
    let _lock = lock(&directory().join("nvibrant.lock")).map_err(|e| Error {
        code: "lock-failed",
        message: e,
    })?;
    let outputs = connectors();
    let mut p = profile();
    if args[0] == "set" && args.len() == 3 {
        let n = value(&args[2])?;
        let Some(target) = outputs.iter().find(|o| o["connector"] == args[1]) else {
            return err(
                "connector-unknown",
                format!("{} no es una salida NVIDIA", args[1]),
            );
        };
        if target["connected"] != true {
            return err(
                "connector-disconnected",
                format!("{} no está conectado", args[1]),
            );
        }
        p.insert(args[1].clone(), json!(n));
        let values = outputs
            .iter()
            .map(|o| {
                p.get(&s(&o["connector"]))
                    .and_then(Value::as_i64)
                    .unwrap_or(0)
            })
            .collect::<Vec<_>>();
        apply(&outputs, &values)?;
        save(&p)?;
        return Ok(json!({"ok":true,"connector":args[1],"value":n}));
    }
    let default = if args.len() == 1 {
        0
    } else if args.len() == 3 && args[1] == "--default" {
        value(&args[2])?
    } else {
        return err(
            "usage",
            "status | set CONNECTOR VALUE | apply [--default N]",
        );
    };
    if !outputs.iter().any(|o| o["connected"] == true) {
        return Ok(json!({"ok":true,"applied":false,"reason":"no-nvidia-output"}));
    }
    let values = outputs
        .iter()
        .map(|o| {
            p.get(&s(&o["connector"]))
                .and_then(Value::as_i64)
                .unwrap_or(default)
        })
        .collect::<Vec<_>>();
    apply(&outputs, &values)?;
    let mut applied = Map::new();
    for (o, n) in outputs.iter().zip(values) {
        let k = s(&o["connector"]);
        p.insert(k.clone(), json!(n));
        applied.insert(k, json!(n));
    }
    save(&p)?;
    Ok(json!({"ok":true,"applied":true,"values":applied}))
}
pub fn main(args: &[String]) -> (Value, i32) {
    match action(args) {
        Ok(v) => (v, 0),
        Err(e) => {
            let status = if e.code == "usage" { 2 } else { 1 };
            (json!({"ok":false,"code":e.code,"error":e.message}), status)
        }
    }
}
