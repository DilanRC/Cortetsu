//! Which keyboards a bind listens to.
//!
//! A bind in the store may carry `"devices": {"only": bool, "names": [...]}`:
//! with `only` it fires on the named keyboards alone, without it on every
//! keyboard except those. hyprland.lua passes it to `hl.bind` as Hyprland's
//! `device = {inclusive, list}` flag. Names are Hyprland's, as `hyprctl
//! devices` lists them. A bind without the field fires everywhere.
//!
//! `scope ID only|except|all [NAME…]` changes it, for store binds only: the
//! defaults and hypr-user.lua are bound by Lua this editor does not write.

use crate::legacy::{self, Binding, EDIT_TAG, Refusal};
use crate::store::{Paths, Result, commit, load_store, text};
use crate::{hypr, lua};
use serde_json::{Map, Value, json};
use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum Scope {
    #[default]
    All,
    Only(BTreeSet<String>),
    Except(BTreeSet<String>),
}

impl Scope {
    /// The scope a stored bind declares. A field this version cannot read
    /// is taken as "every keyboard", which is what hyprland.lua does with it.
    pub fn of(bind: &Map<String, Value>) -> Scope {
        let Some(Value::Object(devices)) = bind.get("devices") else { return Scope::All };
        let Some(Value::Array(names)) = devices.get("names") else { return Scope::All };
        let names: BTreeSet<String> = names.iter().filter_map(Value::as_str).map(str::to_owned).collect();
        match devices.get("only") {
            Some(Value::Bool(only)) => Scope::new(*only, names),
            _ => Scope::All,
        }
    }

    /// `only` with no names would fire nowhere; except-nothing is everywhere.
    pub fn new(only: bool, names: BTreeSet<String>) -> Scope {
        match (only, names.is_empty()) {
            (_, true) => Scope::All,
            (true, false) => Scope::Only(names),
            (false, false) => Scope::Except(names),
        }
    }

    /// Whether some keyboard would fire both binds. An exception list is
    /// assumed not to cover every keyboard: another one can be plugged in.
    pub fn overlaps(&self, other: &Scope) -> bool {
        match (self, other) {
            (Scope::Only(a), Scope::Only(b)) => !a.is_disjoint(b),
            (Scope::Only(a), Scope::Except(b)) | (Scope::Except(b), Scope::Only(a)) => !a.is_subset(b),
            _ => true,
        }
    }

    pub fn names(&self) -> Option<&BTreeSet<String>> {
        match self {
            Scope::All => None,
            Scope::Only(names) | Scope::Except(names) => Some(names),
        }
    }

    fn only(&self) -> bool {
        matches!(self, Scope::Only(_))
    }

    /// The store field; None for a bind that fires everywhere.
    pub fn to_json(&self) -> Option<Value> {
        self.names().map(|names| json!({ "only": self.only(), "names": names }))
    }

    /// The `device = {...}` entry of the compiled bind.
    pub fn to_lua(&self) -> Option<String> {
        self.names().map(|names| {
            let list: Vec<String> = names.iter().map(|name| lua::quote(name)).collect();
            format!("device = {{ inclusive = {}, list = {{ {} }} }}", self.only(), list.join(", "))
        })
    }

    /// For messages, worded like the surface: "solo en a, b", "en todos
    /// salvo a", "en todos los teclados".
    pub fn describe(&self) -> String {
        let joined = |names: &BTreeSet<String>| names.iter().map(String::as_str).collect::<Vec<_>>().join(", ");
        match self {
            Scope::All => "en todos los teclados".into(),
            Scope::Only(names) => format!("solo en {}", joined(names)),
            Scope::Except(names) => format!("en todos salvo {}", joined(names)),
        }
    }

    /// One line of the live report hyprland.lua answers through `repl`:
    /// `ID<TAB>true|false<TAB>NAME<TAB>NAME…`, as `HL.Keybind` keeps it.
    pub fn parse_live(line: &str) -> Option<(String, Scope)> {
        let mut fields = line.split('\t');
        let id = fields.next().filter(|id| !id.is_empty())?.to_owned();
        let only = match fields.next()? {
            "true" => true,
            "false" => false,
            _ => return None,
        };
        Some((id, Scope::new(only, fields.filter(|n| !n.is_empty()).map(str::to_owned).collect())))
    }
}

/// The scope `scope ID MODE NAME…` asks for.
pub fn requested(mode: &str, names: &[String]) -> std::result::Result<Scope, Refusal> {
    let names: BTreeSet<String> = names.iter().cloned().collect();
    match (mode, names.is_empty()) {
        ("all", true) => Ok(Scope::All),
        ("only" | "except", false) => Ok(Scope::new(mode == "only", names)),
        ("all", false) => Err(Refusal::Invalid("«all» no lleva teclados".into())),
        ("only" | "except", true) => Err(Refusal::Invalid("Elige al menos un teclado".into())),
        _ => Err(Refusal::Invalid(format!("Modo desconocido: {mode}; usa only, except o all"))),
    }
}

/// The names that stay on their keyboard. Two identical keyboards are `x`
/// and `x-1` in the order they were connected, which a replug or a reboot
/// can swap: a scope on either would follow the wrong keyboard.
pub fn distinct(names: &[String]) -> Vec<String> {
    let twin = |a: &String| names.iter().any(|b| b != a && (hypr::is_instance_of(a, b) || hypr::is_instance_of(b, a)));
    names.iter().filter(|n| !twin(n)).cloned().collect()
}

/// Every check `scope` makes before it writes. `keyboards`: the names
/// `hyprctl devices` lists now. A name already in the bind's scope may stay
/// while its keyboard is unplugged; a new one must be connected.
pub fn plan(
    items: &[Binding],
    keyboards: &[String],
    identifier: &str,
    wanted: &Scope,
) -> std::result::Result<Binding, Refusal> {
    let entry =
        items.iter().find(|e| e.id == identifier).cloned().ok_or_else(|| Refusal::Locked(legacy::GONE.into()))?;
    if !entry.scopable {
        return Err(Refusal::Locked(
            "Este atajo es de la configuración base; cámbialo primero para limitarlo a un teclado".into(),
        ));
    }
    let kept = entry.scope.names().cloned().unwrap_or_default();
    if let Some(unknown) = wanted.names().into_iter().flatten().find(|n| !keyboards.contains(n) && !kept.contains(*n)) {
        return Err(Refusal::Invalid(format!(
            "Hyprland no tiene ningún teclado llamado {unknown}, o tiene dos iguales que no distingue"
        )));
    }
    legacy::ensure_free(&entry.chord, wanted, &[], Some(identifier), items)
        .map_err(|e| Refusal::Taken(format!("{e} {}", wanted.describe())))?;
    Ok(entry)
}

pub fn set_scope(paths: &Paths, identifier: &str, mode: &str, names: &[String]) -> Result<Value> {
    let wanted = requested(mode, names)?;
    let listed: Vec<String> = hypr::keyboards()
        .ok_or("No se pudo leer la lista de teclados de Hyprland")?
        .into_iter()
        .map(|k| k.name)
        .collect();
    let keyboards = distinct(&listed);
    let entry = plan(&legacy::list_bindings(paths)?, &keyboards, identifier, &wanted)?;
    let mut store = load_store(&paths.store)?;
    for bind in store.binds.iter_mut().filter(|bind| text(bind, "id") == Some(identifier)) {
        match wanted.to_json() {
            Some(devices) => bind.insert("devices".into(), devices),
            None => bind.remove("devices"),
        };
    }
    let saved = commit(paths, &store, &[(entry.chord.clone(), format!("{EDIT_TAG}{identifier}"))], &[])?;
    let message = format!("Guardado · {} {}", entry.label, wanted.describe());
    Ok(legacy::saved_reply(&saved, json!({ "devices": wanted.to_json(), "message": message })))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn set(names: &[&str]) -> BTreeSet<String> {
        names.iter().map(|n| (*n).to_owned()).collect()
    }

    #[test]
    fn overlap_follows_the_keyboards_both_binds_fire_on() {
        let only_a = Scope::Only(set(&["a"]));
        let only_b = Scope::Only(set(&["b"]));
        let only_ab = Scope::Only(set(&["a", "b"]));
        let except_a = Scope::Except(set(&["a"]));
        let except_ab = Scope::Except(set(&["a", "b"]));
        assert!(!only_a.overlaps(&only_b), "disjoint lists never meet");
        assert!(only_a.overlaps(&only_ab));
        assert!(!only_a.overlaps(&except_a), "a is excluded from the other");
        assert!(!only_ab.overlaps(&except_ab) && !except_ab.overlaps(&only_ab));
        assert!(only_b.overlaps(&except_a), "b fires both");
        assert!(except_a.overlaps(&except_ab), "an unlisted keyboard fires both");
        for scope in [&only_a, &except_a] {
            assert!(Scope::All.overlaps(scope) && scope.overlaps(&Scope::All));
        }
    }

    #[test]
    fn the_store_field_round_trips_and_empty_lists_mean_everywhere() {
        let only = Scope::Only(set(&["at-translated-set-2-keyboard", "hp-wmi-hotkeys"]));
        let mut bind = Map::new();
        bind.insert("devices".into(), only.to_json().unwrap());
        assert_eq!(Scope::of(&bind), only);
        assert_eq!(Scope::new(true, BTreeSet::new()), Scope::All);
        assert_eq!(Scope::new(false, BTreeSet::new()), Scope::All);
        assert_eq!(Scope::All.to_json(), None);
        bind.insert("devices".into(), json!({ "only": true, "names": [] }));
        assert_eq!(Scope::of(&bind), Scope::All, "an empty list never means nowhere");
        bind.insert("devices".into(), json!({ "only": "yes", "names": ["a"] }));
        assert_eq!(Scope::of(&bind), Scope::All, "an unreadable field is ignored like hyprland.lua does");
    }

    #[test]
    fn compiles_to_the_hyprland_device_flag() {
        let scope = Scope::Except(set(&["b", "a \"x\""]));
        assert_eq!(scope.to_lua().unwrap(), r#"device = { inclusive = false, list = { "a \"x\"", "b" } }"#);
        assert_eq!(Scope::All.to_lua(), None);
    }

    #[test]
    fn twin_keyboards_are_not_targets() {
        let names: Vec<String> = ["kb", "kb-1", "kb-extra", "other"].iter().map(|n| (*n).to_owned()).collect();
        assert_eq!(distinct(&names), vec!["kb-extra".to_owned(), "other".to_owned()]);
    }

    #[test]
    fn reads_the_live_report() {
        assert_eq!(Scope::parse_live("app:1\ttrue\tb\ta"), Some(("app:1".into(), Scope::Only(set(&["a", "b"])))));
        assert_eq!(Scope::parse_live("app:1\tfalse"), Some(("app:1".into(), Scope::All)));
        assert_eq!(Scope::parse_live("app:1\tmaybe\ta"), None);
        assert_eq!(Scope::parse_live("\ttrue\ta"), None);
    }
}
