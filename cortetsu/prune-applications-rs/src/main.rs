//! Native application-entry quarantiner with the frozen CLI contract.
//! Quarantines only broken *.desktop entries in a user's XDG applications
//! directory. Never removes applications or touches system-owned desktops.
use std::env;
use std::ffi::OsStr;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

fn xdg_data_home() -> Result<PathBuf, String> {
    let root = if let Some(path) = env::var_os("XDG_DATA_HOME") {
        PathBuf::from(path)
    } else {
        PathBuf::from(env::var_os("HOME").ok_or("HOME missing")?).join(".local/share")
    };
    if !root.is_absolute() {
        return Err("XDG_DATA_HOME must be absolute".into());
    }
    Ok(root)
}

// Match shlex.split's relevant POSIX shell tokenization without invoking a
// shell. Unterminated quotes and a trailing escape invalidate the Exec field.
fn split_shell(source: &str) -> Option<Vec<String>> {
    let mut result = Vec::new();
    let mut token = String::new();
    let mut active = false;
    let mut quote: Option<char> = None;
    let mut chars = source.chars().peekable();
    while let Some(ch) = chars.next() {
        match quote {
            Some('\'') => match ch {
                '\'' => quote = None,
                _ => token.push(ch),
            },
            Some('"') => match ch {
                '"' => quote = None,
                '\\' => match chars.next() {
                    Some(next @ ('"' | '\\')) => token.push(next),
                    Some(next) => {
                        token.push('\\');
                        token.push(next);
                    }
                    None => return None,
                },
                _ => token.push(ch),
            },
            Some(_) => return None,
            None => match ch {
                '\'' | '"' => {
                    quote = Some(ch);
                    active = true;
                }
                '\\' => {
                    let next = chars.next()?;
                    active = true;
                    token.push(next);
                }
                ' ' | '\t' | '\r' | '\n' => {
                    if active {
                        result.push(std::mem::take(&mut token));
                        active = false;
                    }
                }
                _ => {
                    active = true;
                    token.push(ch);
                }
            },
        }
    }
    if quote.is_some() {
        return None;
    }
    if active {
        result.push(token);
    }
    Some(result)
}

fn command_target(value: &str) -> Option<String> {
    let mut tokens = split_shell(value)?;
    while !tokens.is_empty()
        && (tokens[0] == "env" || tokens[0] == "nohup" || tokens[0].contains('='))
    {
        tokens.remove(0);
    }
    if tokens.is_empty() || tokens[0].starts_with('%') {
        return None;
    }
    Some(tokens.remove(0))
}

fn executable(path: &Path) -> bool {
    fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

fn which(binary: &str) -> bool {
    if binary.contains('/') {
        return executable(Path::new(binary));
    }
    if let Some(path) = env::var_os("PATH") {
        for segment in env::split_paths(&path) {
            if executable(&segment.join(binary)) {
                return true;
            }
        }
    }
    false
}

// Match the legacy RawConfigParser contract, including DEFAULT inheritance,
// colon delimiters, duplicate keys, indentation and errors in other groups.
// An invalid file is left untouched; parsing never executes its Exec value.
fn desktop_fields(path: &Path) -> Option<(String, String)> {
    use std::collections::BTreeMap;
    let raw = fs::read_to_string(path).ok()?;
    let mut sections: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
    let mut section: Option<String> = None;
    let mut previous_key: Option<String> = None;
    let mut previous_indent = 0;
    for line in raw.split('\n') {
        let value = line.trim();
        if value.starts_with('#') || value.starts_with(';') {
            continue;
        }
        if value.is_empty() {
            if let (Some(group), Some(key)) = (&section, &previous_key) {
                sections.get_mut(group)?.get_mut(key)?.push('\n');
            }
            continue;
        }
        let indent = line.chars().take_while(|ch| ch.is_whitespace()).count();
        if indent > previous_indent
            && let (Some(group), Some(key)) = (&section, &previous_key)
        {
            let old = sections.get_mut(group)?.get_mut(key)?;
            old.push('\n');
            old.push_str(value);
            continue;
        }
        previous_indent = indent;
        if value.starts_with('[')
            && let Some(close) = value.rfind(']').filter(|close| *close > 1)
        {
            let name = value[1..close].to_owned();
            sections.entry(name.clone()).or_default();
            section = Some(name);
            previous_key = None;
            continue;
        }
        let group = section.as_ref()?;
        let delimiter = value.find(['=', ':'])?;
        let key = value[..delimiter].trim_end();
        if key.is_empty() {
            return None;
        }
        sections
            .get_mut(group)?
            .insert(key.to_owned(), value[delimiter + 1..].trim().to_owned());
        previous_key = Some(key.to_owned());
    }
    let fields = sections.get("Desktop Entry")?;
    let defaults = sections.get("DEFAULT");
    let get = |key: &str, fallback: &str| {
        fields
            .get(key)
            .or_else(|| defaults.and_then(|map| map.get(key)))
            .map(|s| s.trim_end())
            .unwrap_or(fallback)
            .to_owned()
    };
    Some((get("Type", "Application"), get("Exec", "")))
}

fn broken(path: &Path) -> bool {
    let Some((typ, exec)) = desktop_fields(path) else {
        return false;
    };
    if typ != "Application" {
        return false;
    }
    let Some(command) = command_target(&exec) else {
        return true;
    };
    if command.starts_with('/') {
        return !Path::new(&command).is_file();
    }
    !which(&command)
}

fn candidate_paths(apps: &Path) -> io::Result<Vec<PathBuf>> {
    let mut result = Vec::new();
    if !apps.is_dir() {
        return Ok(result);
    }
    for entry in fs::read_dir(apps)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension() == Some(OsStr::new("desktop")) && path.is_file() && broken(&path) {
            result.push(path);
        }
    }
    result.sort();
    Ok(result)
}

fn run(dry: bool) -> Result<(), String> {
    let data = xdg_data_home()?;
    let apps = data.join("applications");
    let candidates = candidate_paths(&apps).map_err(|_| "cannot enumerate applications")?;
    if dry {
        for candidate in candidates {
            println!("{}", candidate.display());
        }
        return Ok(());
    }
    if candidates.is_empty() {
        println!("No hay entradas de usuario rotas.");
        return Ok(());
    }
    let quarantine = data.join("cortetsu/quarantine/applications");
    fs::create_dir_all(&quarantine).map_err(|_| "cannot create quarantine")?;
    for candidate in candidates {
        let file = candidate.file_name().ok_or("invalid application entry")?;
        let mut destination = quarantine.join(file);
        if destination.exists() {
            let stem = candidate
                .file_stem()
                .and_then(OsStr::to_str)
                .ok_or("invalid file name")?;
            destination = quarantine.join(format!("{}-{}.desktop", stem, std::process::id()));
        }
        fs::rename(&candidate, &destination).map_err(|_| "cannot quarantine application")?;
        println!(
            "Cuarentena: {} -> {}",
            candidate.display(),
            destination.display()
        );
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let dry = match args.as_slice() {
        [] => false,
        [flag] if flag == "--dry-run" => true,
        _ => {
            eprintln!("usage: cortetsu-prune-applications [--dry-run]");
            std::process::exit(2);
        }
    };
    if let Err(err) = run(dry) {
        eprintln!("cortetsu-prune-applications: {err}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shlex_handles_quotes_escaped_spaces_and_invalid_tokens() {
        assert_eq!(
            command_target("env FOO=bar '/path/a b' %u"),
            Some("/path/a b".into())
        );
        assert_eq!(
            command_target("nohup SOME=thing missing"),
            Some("missing".into())
        );
        assert_eq!(
            command_target("command\\ with\\ spaces"),
            Some("command with spaces".into())
        );
        assert_eq!(command_target("unclosed 'quote"), None);
        assert_eq!(command_target("%u"), None);
    }
}
