//! Reading Cortetsu's Hyprland Lua config the way the keybind editor needs:
//! `kb*` variables, `hl.bind("CHORD", BODY)` calls and `create_bind(...)`
//! literals. These are scanners for the files Cortetsu ships, not a Lua
//! parser; anything they do not recognise is left alone, never rewritten.

/// Lua string escapes only; every other character, ñ included, stays as is.
pub fn unescape(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('t') => out.push('\t'),
            Some(other) => out.push(other),
            None => out.push('\\'),
        }
    }
    out
}

pub fn quote(value: &str) -> String {
    let escaped = value.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', "\\n").replace('\r', "\\r");
    format!("\"{escaped}\"")
}

/// End (exclusive) of the double-quoted string that opens at `start`.
fn string_end(text: &str, start: usize) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut i = start + 1;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' => i += 2,
            b'"' => return Some(i + 1),
            _ => i += 1,
        }
    }
    None
}

/// The contents of every double-quoted string in `text`, unescaped.
pub fn strings(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cursor = 0;
    while let Some(offset) = text[cursor..].find('"') {
        let start = cursor + offset;
        let Some(end) = string_end(text, start) else { break };
        out.push(unescape(&text[start + 1..end - 1]));
        cursor = end;
    }
    out
}

/// `--` comments removed, except inside double-quoted strings.
fn without_comments(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut cursor = 0;
    let bytes = text.as_bytes();
    while cursor < bytes.len() {
        if bytes[cursor] == b'"' {
            let end = string_end(text, cursor).unwrap_or(bytes.len());
            out.push_str(&text[cursor..end]);
            cursor = end;
        } else if text[cursor..].starts_with("--") {
            cursor = text[cursor..].find('\n').map_or(bytes.len(), |n| cursor + n);
        } else {
            let next = text[cursor..].find(['"', '-']).map_or(bytes.len(), |n| cursor + n.max(1));
            out.push_str(&text[cursor..next]);
            cursor = next;
        }
    }
    out
}

fn is_ident_start(c: char) -> bool {
    c.is_ascii_alphabetic() || c == '_'
}

fn is_ident(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// `name = "value"` and `name = { "a", "b" }` entries, one per line, in file
/// order; a repeated name keeps its first position and its last value.
pub fn entries(text: &str) -> Vec<(String, Vec<String>)> {
    let mut result: Vec<(String, Vec<String>)> = Vec::new();
    for line in without_comments(text).lines() {
        let line = line.trim_start();
        let Some(first) = line.chars().next().filter(|&c| is_ident_start(c)) else { continue };
        let name_len = line.find(|c: char| !is_ident(c)).unwrap_or(line.len());
        let _ = first;
        let name = &line[..name_len];
        let Some(rhs) = line[name_len..].trim_start().strip_prefix('=') else { continue };
        let rhs = rhs.trim_start();
        let value = if rhs.starts_with('{') {
            match rhs.rfind('}') {
                Some(close) => &rhs[..=close],
                None => continue,
            }
        } else if rhs.starts_with('"') {
            match string_end(rhs, 0) {
                Some(end) => &rhs[..end],
                None => continue,
            }
        } else {
            continue;
        };
        let values = strings(value);
        match result.iter_mut().find(|(existing, _)| existing == name) {
            Some(entry) => entry.1 = values,
            None => result.push((name.to_owned(), values)),
        }
    }
    result
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BindBlock {
    pub start: usize,
    pub end: usize,
    pub chord: String,
    pub body: String,
}

/// Length of a `[[`, `[=[`… long bracket opener at the start of `text`, and
/// its closer.
fn long_bracket(text: &str) -> Option<(usize, String)> {
    let rest = text.strip_prefix('[')?;
    let level = rest.len() - rest.trim_start_matches('=').len();
    rest[level..].starts_with('[').then(|| (level + 2, format!("]{}]", "=".repeat(level))))
}

/// `hl.bind("CHORD", BODY)` calls, skipping comments and long strings. A call
/// whose first argument is not a plain string literal is skipped.
pub fn binding_blocks(text: &str) -> Vec<BindBlock> {
    const MARKER: &str = "hl.bind(";
    let mut blocks = Vec::new();
    let mut cursor = 0;
    while let Some(offset) = text[cursor..].find(MARKER) {
        let start = cursor + offset;
        let open = start + MARKER.len();
        let Some(close) = closing_paren(text, open) else {
            cursor = open;
            continue;
        };
        cursor = close + 1;
        let inner = &text[open..close];
        let after_space = inner.len() - inner.trim_start().len();
        if !inner[after_space..].starts_with('"') {
            continue;
        }
        let Some(chord_end) = string_end(inner, after_space) else { continue };
        let rest = &inner[chord_end..];
        let Some(body) = rest.trim_start().strip_prefix(',') else { continue };
        blocks.push(BindBlock {
            start,
            end: close + 1,
            chord: unescape(&inner[after_space + 1..chord_end - 1]),
            body: body.trim().to_owned(),
        });
    }
    blocks
}

/// The `)` that closes a call whose arguments start at `open`.
fn closing_paren(text: &str, open: usize) -> Option<usize> {
    let mut depth = 1;
    let mut i = open;
    while i < text.len() {
        let rest = &text[i..];
        if let Some(comment) = rest.strip_prefix("--") {
            if let Some((len, closer)) = long_bracket(comment) {
                i += 2 + len;
                i += text[i..].find(&closer).map_or(text.len() - i, |n| n + closer.len());
            } else {
                i += rest.find('\n').unwrap_or(rest.len());
            }
            continue;
        }
        if let Some((len, closer)) = long_bracket(rest) {
            i += len;
            i += text[i..].find(&closer).map_or(text.len() - i, |n| n + closer.len());
            continue;
        }
        let c = rest.chars().next()?;
        match c {
            '"' | '\'' => {
                let mut j = i + 1;
                let bytes = text.as_bytes();
                while j < bytes.len() && bytes[j] != c as u8 {
                    j += if bytes[j] == b'\\' { 2 } else { 1 };
                }
                i = j + 1;
                continue;
            }
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if depth == 0 {
                    return Some(i);
                }
            }
            _ => {}
        }
        i += c.len_utf8();
    }
    None
}

/// What a bind body does, when that is all it does: a global or a command.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    Global(String),
    Exec(String),
}

pub fn simple_action(body: &str) -> Option<Action> {
    // hl.dsp.global("name") with an optional trailing `, flags` identifier.
    if let Some(rest) = body.strip_prefix("hl.dsp.global(") {
        let rest = rest.trim_start().strip_prefix('"')?;
        let end = rest.find('"')?;
        let name = &rest[..end];
        if name.is_empty() || name.contains('\\') {
            return None;
        }
        let tail = rest[end + 1..].trim_start().strip_prefix(')')?.trim();
        let flags_ok = match tail.strip_prefix(',') {
            None => tail.is_empty(),
            Some(flags) => {
                let flags = flags.trim();
                !flags.is_empty() && flags.chars().all(|c| c.is_ascii_alphabetic() || c == '_')
            }
        };
        return flags_ok.then(|| Action::Global(name.to_owned()));
    }
    let rest = body.strip_prefix("hl.dsp.exec_cmd(")?.trim_start();
    let (command, tail) = if let Some(long) = rest.strip_prefix("[[") {
        let end = long.find("]]")?;
        (long[..end].to_owned(), &long[end + 2..])
    } else {
        let end = string_end(rest, 0).filter(|_| rest.starts_with('"'))?;
        (unescape(&rest[1..end - 1]), &rest[end..])
    };
    (tail.trim_start().strip_prefix(')')?.trim().is_empty()).then_some(Action::Exec(command))
}

/// `-- Cortetsu app shortcut: NAME (ID)` directly above the bind at `start`.
pub fn generated_app(text: &str, start: usize) -> Option<(String, String)> {
    const PREFIX: &str = "-- Cortetsu app shortcut: ";
    let before = &text[..start];
    let line_start = before.trim_end().rfind('\n').map_or(0, |n| n + 1);
    let line = before[line_start..].trim_end();
    let rest = line.strip_prefix(PREFIX)?;
    let open = rest.find(" (")?;
    let id = rest[open + 2..].strip_suffix(')')?;
    Some((rest[..open].to_owned(), id.to_owned()))
}

/// `create_bind(<literal>, <rest of line>)` in keybinds.lua: the chords and
/// the action text of binds written with a fixed chord.
pub fn literal_binds(text: &str) -> Vec<(Vec<String>, String)> {
    const MARKER: &str = "create_bind(";
    let mut result = Vec::new();
    let mut cursor = 0;
    while let Some(offset) = text[cursor..].find(MARKER) {
        let open = cursor + offset + MARKER.len();
        cursor = open;
        let inner = &text[open..];
        let first = inner.trim_start();
        let first_at = open + inner.len() - first.len();
        let literal_end = if first.starts_with('{') {
            first.find('}').map(|n| n + 1)
        } else if first.starts_with('"') {
            string_end(first, 0)
        } else {
            None
        };
        let Some(literal_end) = literal_end else { continue };
        let after = &first[literal_end..];
        let Some(action) = after.trim_start().strip_prefix(',') else { continue };
        let action = action.trim_start();
        let action = &action[..action.find('\n').unwrap_or(action.len())];
        result.push((strings(&first[..literal_end]), action.to_owned()));
        cursor = first_at + literal_end;
    }
    result
}

/// `vars.kbName` references.
pub fn used_variables(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cursor = 0;
    while let Some(offset) = text[cursor..].find("vars.kb") {
        let at = cursor + offset;
        let boundary = text[..at].chars().next_back().is_none_or(|c| !is_ident(c));
        let name_start = at + "vars.".len();
        let len = text[name_start..].find(|c: char| !is_ident(c)).unwrap_or(text.len() - name_start);
        if boundary {
            out.push(text[name_start..name_start + len].to_owned());
        }
        cursor = name_start + len;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entries_read_strings_and_lists_and_skip_comments() {
        let text = "return {\n    browser = \"firefox\",\n    -- kbRetired = \"SUPER + Z\",\n    kbBrowser = \"SUPER + W\",\n    kbNextWs = { \"SUPER + Right\", \"SUPER + Page_Down\" },\n    kbGoToWs = \"SUPER\",\n}\n";
        let entries = entries(text);
        let names: Vec<&str> = entries.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(names, vec!["browser", "kbBrowser", "kbNextWs", "kbGoToWs"]);
        assert_eq!(entries[2].1, vec!["SUPER + Right", "SUPER + Page_Down"]);
    }

    #[test]
    fn a_double_dash_inside_a_string_is_not_a_comment() {
        // The Python helper cut this value at "--"; nothing Cortetsu ships
        // has such a value, so the two still agree on every real file.
        let entries = entries("fileExplorer = \"nautilus --new-window\" -- trailing\n");
        assert_eq!(entries, vec![("fileExplorer".to_owned(), vec!["nautilus --new-window".to_owned()])]);
    }

    #[test]
    fn repeated_names_keep_the_first_position_and_the_last_value() {
        let entries = entries("a = \"1\"\nb = \"2\"\na = \"3\"\n");
        assert_eq!(entries, vec![("a".into(), vec!["3".into()]), ("b".into(), vec!["2".into()])]);
    }

    #[test]
    fn bind_blocks_span_lines_and_ignore_parentheses_in_strings_and_comments() {
        let text = "-- Cortetsu app shortcut: Spotify (spotify)\nhl.bind(\n    \"SUPER + O\",\n    hl.dsp.exec_cmd([[spotify (beta)]])\n)\n\
                    hl.bind(\"SUPER + G\", function() -- ) not the end\n  hl.dispatch(hl.dsp.exec_cmd(\")\")) end)\n\
                    hl.bind(chord, hl.dsp.global(\"x\"))\n";
        let blocks = binding_blocks(text);
        assert_eq!(blocks.len(), 2, "a bind whose chord is a variable is skipped");
        assert_eq!(blocks[0].chord, "SUPER + O");
        assert_eq!(blocks[0].body, "hl.dsp.exec_cmd([[spotify (beta)]])");
        assert!(blocks[1].body.ends_with("end"));
        assert_eq!(generated_app(text, blocks[0].start), Some(("Spotify".into(), "spotify".into())));
        assert_eq!(generated_app(text, blocks[1].start), None);
    }

    #[test]
    fn app_comment_takes_the_first_parenthesis_like_the_python_regex() {
        let text = "-- Cortetsu app shortcut: The Witcher 3 (Steam) (steam_app)\nhl.bind(\"SUPER + ALT + W\", x)";
        let start = text.find("hl.bind").unwrap();
        assert_eq!(generated_app(text, start), Some(("The Witcher 3".into(), "Steam) (steam_app".into())));
    }

    #[test]
    fn simple_actions() {
        assert_eq!(simple_action("hl.dsp.global(\"cortetsu:osd\")"), Some(Action::Global("cortetsu:osd".into())));
        assert_eq!(simple_action("hl.dsp.global(\"cortetsu:x\"), locked"), Some(Action::Global("cortetsu:x".into())));
        assert_eq!(simple_action("hl.dsp.exec_cmd([[spotify]])"), Some(Action::Exec("spotify".into())));
        assert_eq!(
            simple_action("hl.dsp.exec_cmd(\"xdg-open ~/Música/canción.flac\")"),
            Some(Action::Exec("xdg-open ~/Música/canción.flac".into()))
        );
        assert_eq!(simple_action("hl.dsp.exec_cmd(\"a \\\"b\\\"\")"), Some(Action::Exec("a \"b\"".into())));
        assert_eq!(simple_action("function() hl.dispatch(x) end"), None);
        assert_eq!(simple_action("hl.dsp.exec_cmd(\"a\") .. x"), None);
    }

    #[test]
    fn literal_create_binds() {
        let text = "create_bind(vars.kbLock, x)\ncreate_bind(\"SUPER + I\", hl.dsp.global(\"cortetsu:settings\"))\n\
                    create_bind({ \"XF86AudioPlay\", \"XF86AudioPause\" }, hl.dsp.global(\"cortetsu:mediaToggle\"), locked)\n";
        let binds = literal_binds(text);
        assert_eq!(binds.len(), 2);
        assert_eq!(binds[0].0, vec!["SUPER + I"]);
        assert_eq!(binds[1].0, vec!["XF86AudioPlay", "XF86AudioPause"]);
        assert!(binds[1].1.starts_with("hl.dsp.global(\"cortetsu:mediaToggle\")"));
    }

    #[test]
    fn used_variables_need_a_word_boundary() {
        assert_eq!(used_variables("create_bind(vars.kbA, x) myvars.kbB vars.kbC"), vec!["kbA", "kbC"]);
    }

    #[test]
    fn quote_and_unescape_round_trip() {
        for value in ["plain", "with \"quotes\"", "back\\slash", "line\nbreak", "ñandú"] {
            assert_eq!(unescape(&quote(value)[1..quote(value).len() - 1]), value);
        }
    }
}
