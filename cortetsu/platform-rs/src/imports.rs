use crate::util::*;
use regex::Regex;
use std::{
    collections::BTreeSet,
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
};
#[derive(Clone)]
struct Candidate {
    source: PathBuf,
    target: PathBuf,
    relative: PathBuf,
    group: String,
    tag: String,
    size: u64,
}
struct Scope {
    kind: String,
    name: String,
    prefix: String,
    target: String,
    begin: String,
    end: String,
}
fn scope(kind: &str, a: &Args) -> Result<Scope> {
    if kind == "hyprland" {
        let name = a.get("scope").unwrap_or("modules");
        if !["core", "modules"].contains(&name) {
            return fail("invalid Hyprland scope");
        }
        let core = name == "core";
        Ok(Scope {
            kind: kind.into(),
            name: name.into(),
            prefix: format!(
                "dotfiles/home/.config/hypr{}",
                if core { "" } else { "/hyprland" }
            ),
            target: format!(".config/hypr{}", if core { "" } else { "/hyprland" }),
            begin: format!(
                "# BEGIN CORTETSU HYPRLAND{} IMPORT",
                if core { " CORE" } else { "" }
            ),
            end: format!(
                "# END CORTETSU HYPRLAND{} IMPORT",
                if core { " CORE" } else { "" }
            ),
        })
    } else {
        Ok(Scope {
            kind: kind.into(),
            name: kind.into(),
            prefix: format!("dotfiles/imported/{kind}/home"),
            target: String::new(),
            begin: format!("# BEGIN CORTETSU {} IMPORT", kind.to_uppercase()),
            end: format!("# END CORTETSU {} IMPORT", kind.to_uppercase()),
        })
    }
}
fn backupish(path: &Path) -> bool {
    let name = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_lowercase();
    path.components().any(|p| {
        let s = p.as_os_str().to_string_lossy().to_lowercase();
        [".git", "backup", "backups", "cache", "logs", "tmp", "temp"].contains(&s.as_str())
            || s.starts_with("legacy-backup")
    }) || name == "fish_variables"
        || name.contains(".backup")
        || [
            ".bak", ".old", ".orig", ".tmp", ".swp", ".swo", ".lock", ".log", "~",
        ]
        .iter()
        .any(|s| name.ends_with(s))
        || Regex::new(r"\.(bak|old|orig|tmp|swp|swo)([.-]|$)")
            .unwrap()
            .is_match(&name)
}
fn inspect(p: &Path, limit: u64) -> Result<(String, u64)> {
    let m = fs::symlink_metadata(p)?;
    if m.file_type().is_symlink() {
        return Ok(("symlink".into(), m.len()));
    }
    if !m.is_file() {
        return Ok(("non-regular".into(), m.len()));
    }
    if m.len() > limit {
        return Ok(("too-large".into(), m.len()));
    }
    let b = fs::read(p)?;
    if b.contains(&0) {
        return Ok(("binary".into(), m.len()));
    }
    let text = match std::str::from_utf8(&b) {
        Ok(x) => x,
        Err(_) => return Ok(("non-utf8".into(), m.len())),
    };
    let sensitive = Regex::new(
        r"(?i)\b(password|passwd|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret[_-]?access[_-]?key|private[_-]?key)\b\s*[:=]",
    )?;
    if sensitive.is_match(text)
        || [
            "BEGIN OPENSSH PRIVATE KEY",
            "BEGIN RSA PRIVATE KEY",
            "BEGIN EC PRIVATE KEY",
            "BEGIN PRIVATE KEY",
        ]
        .iter()
        .any(|m| text.contains(m))
    {
        return Ok(("sensitive".into(), m.len()));
    }
    Ok(("ok".into(), m.len()))
}
type Rejected = (String, PathBuf, String);
fn scan(h: &Path, s: &Scope, a: &Args) -> Result<(Vec<Candidate>, Vec<Rejected>)> {
    let mut inputs = Vec::new();
    let mut rejected = Vec::new();
    let selected: BTreeSet<String> = a
        .opts
        .get("group")
        .cloned()
        .unwrap_or_else(|| vec!["kitty".into(), "zsh".into(), "gtk".into(), "qt".into()])
        .into_iter()
        .collect();
    if !selected
        .iter()
        .all(|x| ["kitty", "zsh", "gtk", "qt"].contains(&x.as_str()))
    {
        return fail("invalid desktop group");
    }
    let dirs: Vec<(&str, &str, &str)> = match s.kind.as_str() {
        "fish" => vec![("fish", "user-shell", ".config/fish")],
        "hyprland" => vec![("hyprland", "hyprland", &s.target)],
        _ => vec![
            ("kitty", "terminal", ".config/kitty"),
            ("zsh", "user-shell", ".config/zsh"),
            ("gtk", "toolkit", ".config/gtk-3.0"),
            ("gtk", "toolkit", ".config/gtk-4.0"),
            ("qt", "toolkit", ".config/qt5ct"),
            ("qt", "toolkit", ".config/qt6ct"),
            ("qt", "toolkit", ".config/Kvantum"),
        ],
    };
    for (group, tag, rel) in dirs {
        if s.kind == "desktop" && !selected.contains(group) {
            continue;
        }
        let root = h.join(rel);
        if root.is_symlink() {
            rejected.push((group.into(), PathBuf::from(rel), "symlink-root".into()));
            continue;
        }
        if !root.is_dir() {
            rejected.push((group.into(), PathBuf::from(rel), "missing".into()));
            continue;
        }
        if s.kind == "hyprland" && s.name == "core" {
            for name in [
                "hyprland.lua",
                "variables.lua",
                "utils/functions.lua",
                "utils/json.lua",
                "scheme/default.lua",
                "verify.fish",
            ] {
                let p = root.join(name);
                if p.exists() || p.is_symlink() {
                    inputs.push((p, group.to_owned(), tag.to_owned()));
                }
            }
        } else {
            let mut count = 0;
            for e in walkdir::WalkDir::new(&root)
                .follow_links(false)
                .min_depth(1)
                .into_iter()
            {
                let e = e?;
                if e.file_type().is_dir() {
                    continue;
                }
                inputs.push((e.path().to_path_buf(), group.to_owned(), tag.to_owned()));
                count += 1;
            }
            if count == 0 {
                rejected.push((group.into(), PathBuf::from(rel), "empty".into()));
            }
        }
    }
    if s.kind == "desktop" {
        for (group, tag, rel) in [
            ("zsh", "user-shell", ".zshrc"),
            ("zsh", "user-shell", ".zprofile"),
            ("zsh", "user-shell", ".zshenv"),
            ("zsh", "user-shell", ".zlogin"),
            ("gtk", "toolkit", ".gtkrc-2.0"),
            ("qt", "toolkit", ".config/kdeglobals"),
        ] {
            if !selected.contains(group) {
                continue;
            }
            let p = h.join(rel);
            if p.exists() || p.is_symlink() {
                inputs.push((p, group.to_owned(), tag.to_owned()));
            } else {
                rejected.push((group.into(), PathBuf::from(rel), "missing".into()));
            }
        }
    }
    inputs.sort_by_key(|(p, _, _)| p.clone());
    inputs.dedup_by(|a, b| a.0 == b.0);
    let mut accepted = Vec::new();
    for (p, group, tag) in inputs {
        let target = p.strip_prefix(h)?.to_path_buf();
        let relative = if s.kind == "hyprland" {
            p.strip_prefix(h.join(&s.target))?.to_path_buf()
        } else {
            target.clone()
        };
        let theme = [
            ".config/kitty/caelestia-theme.conf",
            ".config/kitty/cortetsu-theme.conf",
            ".config/gtk-3.0/cortetsu-colors.css",
            ".config/gtk-4.0/cortetsu-colors.css",
        ]
        .iter()
        .any(|x| target == Path::new(x));
        let (reason, size) = if target == Path::new(".config/kdeglobals") {
            ("user-owned".into(), 0)
        } else if theme {
            ("theme-owned".into(), 0)
        } else if backupish(&target) {
            (
                if s.kind == "fish" {
                    "state/backup/temp"
                } else {
                    "backup/temp"
                }
                .into(),
                0,
            )
        } else {
            match inspect(
                &p,
                if s.kind == "hyprland" {
                    1024 * 1024
                } else {
                    2 * 1024 * 1024
                },
            ) {
                Ok(v) => v,
                Err(e) => (format!("unreadable:{e}"), 0),
            }
        };
        if reason == "ok" {
            accepted.push(Candidate {
                source: p,
                target,
                relative,
                group,
                tag,
                size,
            });
        } else {
            rejected.push((
                group,
                if s.kind == "hyprland" {
                    relative
                } else {
                    target
                },
                reason,
            ));
        }
    }
    rejected.sort();
    if accepted.is_empty() {
        return fail("no se encontraron archivos de configuración importables");
    }
    Ok((accepted, rejected))
}
/// Kitty theme header owned by Cortetsu: the sealed ui.toml palette, then the
/// mutable scheme overlay that `cortetsu-scheme` writes outside generations.
const KITTY_HEADER: &str = "include cortetsu-theme.conf
# Live scheme colours, written outside the sealed generation by cortetsu-scheme.
# If the file is missing Kitty logs it and keeps the ui.toml palette above.
include ~/.local/state/cortetsu/kitty-colors.conf
";
fn normalize(c: &Candidate, text: &str) -> String {
    if c.target == Path::new(".config/kitty/kitty.conf") {
        let body = text
            .lines()
            .filter(|line| {
                let t = line.trim().to_lowercase();
                !KITTY_HEADER.lines().any(|h| h.to_lowercase() == t)
                    && !(t.starts_with("include ")
                        && [
                            "caelestia-theme.conf",
                            "state/caelestia/theme/kitty",
                            "kitty-caerice.conf",
                            "cortetsu-theme.conf",
                            "kitty-colors.conf",
                        ]
                        .iter()
                        .any(|m| t.contains(m))
                        || t.contains("caerice:")
                        || t.contains("cortetsu: caelestia active scheme"))
            })
            .collect::<Vec<_>>()
            .join("\n");
        format!("{KITTY_HEADER}\n{}\n", body.trim_matches('\n'))
    } else if [
        Path::new(".config/gtk-3.0/gtk.css"),
        Path::new(".config/gtk-4.0/gtk.css"),
    ]
    .contains(&c.target.as_path())
    {
        let body = text
            .lines()
            .filter(|s| {
                !s.trim_start().starts_with("@define-color ") && !s.contains("cortetsu-colors.css")
            })
            .collect::<Vec<_>>()
            .join("\n");
        format!(
            "@import \"cortetsu-colors.css\";\n{}",
            if body.trim_matches('\n').is_empty() {
                String::new()
            } else {
                format!("{}\n", body.trim_matches('\n'))
            }
        )
    } else {
        text.into()
    }
}
fn render(s: &Scope, candidates: &[Candidate]) -> Result<String> {
    let mut text = format!(
        "{}\n# Generated by cortetsu-platform import_{}. Re-run the importer instead of editing this block by hand.\n",
        s.begin, s.kind
    );
    for c in candidates {
        let source = format!("{}/{}", s.prefix, c.relative.display());
        text += &format!(
            "\n[[entry]]\nsource = {}\ntarget = {}\ntags = [{}]\n",
            serde_json::to_string(&source)?,
            serde_json::to_string(&c.target.to_string_lossy())?,
            serde_json::to_string(&c.tag)?
        );
    }
    text += &format!("{}\n", s.end);
    Ok(text)
}
fn replace_block(text: &str, block: &str, begin: &str, end: &str) -> Result<String> {
    if text.contains(begin) || text.contains(end) {
        if text.matches(begin).count() != 1 || text.matches(end).count() != 1 {
            return fail("manifest contiene marcadores inconsistentes");
        }
        let start = text.find(begin).unwrap();
        let finish = text[start..].find(end).ok_or("end marker before start")? + start + end.len();
        Ok(format!(
            "{}\n\n{}{}",
            text[..start].trim_end(),
            block,
            text[finish..].trim_start_matches('\n')
        ))
    } else {
        Ok(format!("{}\n\n{}", text.trim_end(), block))
    }
}
fn validate_manifest(text: &str) -> Result<()> {
    let v: toml::Value = text.parse()?;
    if v.get("schema").and_then(toml::Value::as_integer) != Some(1) {
        return fail("invalid manifest schema");
    }
    let mut targets = BTreeSet::new();
    for e in v
        .get("entry")
        .and_then(toml::Value::as_array)
        .ok_or("missing entries")?
    {
        let t = e
            .get("target")
            .and_then(toml::Value::as_str)
            .ok_or("missing target")?;
        safe_relative(t)?;
        if !targets.insert(t) {
            return fail(format!("target duplicado tras importación: {t}"));
        }
    }
    Ok(())
}
pub fn run(kind: &str, a: &Args) -> Result<i32> {
    a.check(&["repo", "home", "group", "scope", "commit"])?;
    let scope = scope(kind, a)?;
    let h = a.home()?;
    let repo = a.repo()?;
    let (candidates, rejected) = scan(&h, &scope, a)?;
    println!("Cortetsu {} import · home={}", scope.kind, h.display());
    for c in &candidates {
        println!(
            "  import       [{}] {} ({} B)",
            c.group,
            c.relative.display(),
            c.size
        );
    }
    for (group, p, reason) in &rejected {
        println!(
            "  {:12} [{}] {} [{}]",
            if reason == "sensitive" {
                "BLOCKED"
            } else {
                "skip"
            },
            group,
            p.display(),
            reason
        );
    }
    println!(
        "SUMMARY import={} skipped={}",
        candidates.len(),
        rejected.len()
    );
    if a.action("plan") == "plan" {
        return Ok(
            if rejected.iter().any(|x| x.2 == "sensitive") && kind != "fish" {
                2
            } else {
                0
            },
        );
    }
    if a.action("plan") != "apply" {
        return fail("unknown import action");
    }
    if rejected.iter().any(|x| x.2 == "sensitive") {
        return fail("importación bloqueada por posibles secretos");
    }
    let mut paths = vec!["dotfiles/manifest.toml".to_owned()];
    if kind == "hyprland" {
        paths.extend(
            candidates
                .iter()
                .map(|c| format!("{}/{}", scope.prefix, c.relative.display())),
        );
    } else {
        paths.push(format!("dotfiles/imported/{kind}"));
    }
    let status = Command::new("git")
        .arg("-C")
        .arg(&repo)
        .args(["status", "--porcelain", "--"])
        .args(&paths)
        .output()?;
    if !status.status.success() {
        return fail("no se pudo consultar git status");
    }
    if !status.stdout.is_empty() {
        return fail("el área de importación ya tiene cambios locales");
    }
    let manifest = repo.join("dotfiles/manifest.toml");
    let original = fs::read_to_string(&manifest)?;
    let updated = replace_block(
        &original,
        &render(&scope, &candidates)?,
        &scope.begin,
        &scope.end,
    )?;
    validate_manifest(&updated)?;
    let stage = repo
        .join("dotfiles")
        .join(format!(".import-stage-{}", unique()));
    fs::create_dir(&stage)?;
    let mut originals = Vec::new();
    let operation: Result<()> = (|| {
        if kind != "hyprland" {
            let destination = repo.join("dotfiles/imported").join(kind);
            let replacement = stage.join("replacement");
            let backup = stage.join("previous");
            fs::create_dir_all(replacement.join("home"))?;
            for c in &candidates {
                let text = fs::read_to_string(&c.source)?;
                atomic_write(
                    &replacement.join("home").join(&c.relative),
                    if kind == "desktop" {
                        normalize(c, &text)
                    } else {
                        text
                    },
                    fs::metadata(&c.source)?.permissions().mode(),
                )?;
            }
            fs::create_dir_all(destination.parent().ok_or("import parent")?)?;
            let had_previous = destination.exists() || destination.is_symlink();
            if had_previous {
                fs::rename(&destination, &backup)?;
            }
            let swap: Result<()> = (|| {
                fs::rename(&replacement, &destination)?;
                atomic_write(
                    &manifest,
                    &updated,
                    fs::metadata(&manifest)?.permissions().mode(),
                )?;
                Ok(())
            })();
            if let Err(err) = swap {
                remove_path(&destination)?;
                if had_previous {
                    fs::rename(&backup, &destination)?;
                }
                return Err(err);
            }
            return Ok(());
        }
        for (i, c) in candidates.iter().enumerate() {
            let dest = repo.join(&scope.prefix).join(&c.relative);
            let staged = stage.join(format!("source-{i}"));
            let text = fs::read_to_string(&c.source)?;
            atomic_write(
                &staged,
                if kind == "desktop" {
                    normalize(c, &text)
                } else {
                    text
                },
                fs::metadata(&c.source)?.permissions().mode(),
            )?;
            let before = if dest.exists() || dest.is_symlink() {
                let b = stage.join(format!("before-{i}"));
                copy_path(&dest, &b)?;
                Some(b)
            } else {
                None
            };
            originals.push((dest, staged, before));
        }
        let mut written = 0;
        let mutate: Result<()> = (|| {
            for (dest, staged, _) in &originals {
                fs::create_dir_all(dest.parent().ok_or("missing parent")?)?;
                fs::rename(staged, dest)?;
                written += 1;
            }
            atomic_write(
                &manifest,
                &updated,
                fs::metadata(&manifest)?.permissions().mode(),
            )?;
            Ok(())
        })();
        if let Err(err) = mutate {
            for (dest, _, before) in originals[..written].iter().rev() {
                remove_path(dest)?;
                if let Some(b) = before {
                    copy_path(b, dest)?;
                }
            }
            return Err(err);
        }
        Ok(())
    })();
    let _ = fs::remove_dir_all(&stage);
    operation?;
    println!(
        "IMPORTED {}={}\nMANIFEST entries={}",
        kind,
        repo.join(&scope.prefix).display(),
        candidates.len()
    );
    if a.has("commit") {
        let s = Command::new("git")
            .arg("-C")
            .arg(&repo)
            .args(["add", "--"])
            .args(&paths)
            .status()?;
        if !s.success() {
            return fail("git add failed");
        }
        let diff = Command::new("git")
            .arg("-C")
            .arg(&repo)
            .args(["diff", "--cached", "--quiet", "--"])
            .args(&paths)
            .status()?;
        if diff.success() {
            println!("COMMIT skipped=no changes");
        } else {
            let s = Command::new("git")
                .arg("-C")
                .arg(&repo)
                .args(["commit", "--only", "-m"])
                .arg(format!(
                    "feat(dotfiles): import {kind} config ({})",
                    stamp()
                ))
                .arg("--")
                .args(&paths)
                .status()?;
            if !s.success() {
                return fail("git commit failed");
            }
            println!("COMMIT created={kind} import");
        }
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn kitty(text: &str) -> String {
        let c = Candidate {
            source: PathBuf::new(),
            target: PathBuf::from(".config/kitty/kitty.conf"),
            relative: PathBuf::new(),
            group: String::new(),
            tag: String::new(),
            size: 0,
        };
        normalize(&c, text)
    }
    #[test]
    fn committed_kitty_conf_is_the_normalized_fixed_point() {
        let committed =
            include_str!("../../../dotfiles/imported/desktop/home/.config/kitty/kitty.conf");
        assert!(committed.starts_with(KITTY_HEADER));
        assert_eq!(kitty(committed), committed);
    }
    #[test]
    fn kitty_import_drops_legacy_includes_and_keeps_one_state_overlay() {
        let legacy = "include caelestia-theme.conf\ninclude ~/.local/state/cortetsu/kitty-colors.conf\n\
                      font_size 11\n\ninclude caelestia-theme.conf\ninclude ~/.local/state/cortetsu/kitty-colors.conf\n";
        let out = kitty(legacy);
        assert_eq!(out, format!("{KITTY_HEADER}\nfont_size 11\n"));
        assert_eq!(kitty(&out), out);
    }
}
