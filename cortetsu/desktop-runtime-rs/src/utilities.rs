use crate::common::*;
use serde_json::Value;
use std::{
    env, fs,
    io::Write,
    os::unix::fs::DirBuilderExt,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

/// `cortetsu-area-capture <geometry> <png> [--clipboard]` captures an area.
/// With --clipboard the image is copied and removed; otherwise it stays for
/// the shell's preview, which then runs one of the actions below on it.
pub fn area(args: &[String]) -> Result<i32> {
    if let [action, path] = args
        && let Some(code) = shot_action(action, Path::new(path))?
    {
        return Ok(code);
    }
    let clipboard = args.iter().any(|a| a == "--clipboard");
    let values: Vec<_> = args
        .iter()
        .filter(|a| a.as_str() != "--clipboard")
        .collect();
    if values.len() != 2 {
        return Ok(2);
    }
    let geometry = values[0];
    let path = PathBuf::from(values[1]);
    if !regex::Regex::new(r"^-?\d+,-?\d+ \d+x\d+$")?.is_match(geometry) {
        eprintln!("invalid capture geometry");
        return Ok(2);
    }
    if let Some(dir) = path.parent().filter(|d| !d.as_os_str().is_empty()) {
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(dir)?;
    }
    let result = (|| -> Result<i32> {
        let status = Command::new("grim")
            .args(["-g", geometry])
            .arg(&path)
            .status()?;
        if !status.success() {
            return Ok(status.code().unwrap_or(1));
        }
        if !clipboard {
            return Ok(0);
        }
        let status = Command::new("wl-copy")
            .args(["--type", "image/png"])
            .stdin(fs::File::open(&path)?)
            .status()?;
        if !status.success() {
            return Ok(status.code().unwrap_or(1));
        }
        let _ = Command::new("notify-send")
            .args(["-a", "cortetsu", "-i"])
            .arg(&path)
            .args(["Captura hecha", "Copiada al portapapeles"])
            .status();
        Ok(0)
    })();
    // Only a kept preview image outlives this call.
    if clipboard || !matches!(result, Ok(0)) {
        let _ = fs::remove_file(&path);
    }
    result
}

/// The preview's actions. Each takes only a capture this helper made, named
/// `cortetsu-shot-*.png`, so a wrong path never moves or deletes another file.
/// Returns None when `action` is not one of them.
fn shot_action(action: &str, path: &Path) -> Result<Option<i32>> {
    if !["--copy", "--save", "--edit", "--discard"].contains(&action) {
        return Ok(None);
    }
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
    if !(name.starts_with("cortetsu-shot-") && name.ends_with(".png") && path.is_file()) {
        eprintln!("not a Cortetsu capture: {}", path.display());
        return Ok(Some(2));
    }
    let status = match action {
        "--copy" => Command::new("wl-copy")
            .args(["--type", "image/png"])
            .stdin(fs::File::open(path)?)
            .status()?,
        // swappy writes the edit back over the capture, so the preview shows it.
        "--edit" => Command::new("swappy")
            .arg("-f")
            .arg(path)
            .arg("-o")
            .arg(path)
            .status()?,
        "--discard" => {
            fs::remove_file(path)?;
            return Ok(Some(0));
        }
        _ => {
            let dest = save_shot(path)?;
            println!("{}", dest.display());
            return Ok(Some(0));
        }
    };
    Ok(Some(status.code().unwrap_or(1)))
}

/// Moves a capture to <Pictures>/Capturas under a dated, unused name.
fn save_shot(path: &Path) -> Result<PathBuf> {
    let pictures = run(
        Command::new("xdg-user-dir").arg("PICTURES"),
        None,
        Duration::from_secs(5),
    )
    .ok()
    .filter(|o| o.status.success())
    .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned())
    .filter(|p| !p.is_empty())
    .map(PathBuf::from)
    .unwrap_or_else(|| home().join("Pictures"));
    let dir = pictures.join("Capturas");
    fs::create_dir_all(&dir)?;
    let stamp = chrono::Local::now().format("Captura_%Y-%m-%d_%H-%M-%S");
    let mut dest = dir.join(format!("{stamp}.png"));
    let mut n = 2;
    while dest.exists() {
        dest = dir.join(format!("{stamp}_{n}.png"));
        n += 1;
    }
    // The capture lives on the runtime tmpfs, so a rename would cross devices.
    fs::copy(path, &dest)?;
    fs::remove_file(path)?;
    Ok(dest)
}

fn emoji_path(fetch: bool) -> PathBuf {
    if let Some(path) = env::var_os("CORTETSU_EMOJI_DATA") {
        return PathBuf::from(path);
    }
    let cached = cache().join("emojis.txt");
    if fetch || cached.is_file() {
        cached
    } else {
        resources().join("data/emojis.txt")
    }
}
pub fn emoji(args: &[String]) -> Result<i32> {
    let path = emoji_path(args.iter().any(|a| a == "-f" || a == "--fetch"));
    let a: Vec<_> = args.iter().map(String::as_str).collect();
    match a.as_slice() {
        [] => match fs::read(&path) {
            Ok(data) => std::io::stdout().lock().write_all(&data)?,
            Err(_) => {
                eprintln!("cortetsu-emoji: no such data file: {}", path.display());
                return Ok(1);
            }
        },
        ["-f"] | ["--fetch"] => {
            let agent = ureq::AgentBuilder::new()
                .timeout(Duration::from_secs(30))
                .build();
            let mut data: Vec<String> = serde_json::from_str(include_str!("emoji-static.json"))?;
            let emojis:Value=agent.get("https://raw.githubusercontent.com/milesj/emojibase/refs/heads/master/packages/data/en/compact.raw.json").call()?.into_json()?;
            for emoji in emojis.as_array().ok_or("invalid emoji data")? {
                let mut line = vec![
                    emoji["unicode"]
                        .as_str()
                        .ok_or("missing emoji glyph")?
                        .to_owned(),
                ];
                if let Some(s) = emoji["emoticon"].as_str() {
                    line.push(s.to_owned());
                } else if let Some(values) = emoji["emoticon"].as_array() {
                    line.extend(values.iter().filter_map(Value::as_str).map(str::to_owned));
                }
                line.push(
                    emoji["label"]
                        .as_str()
                        .ok_or("missing emoji label")?
                        .to_owned(),
                );
                if let Some(tags) = emoji["tags"].as_array() {
                    line.extend(tags.iter().filter_map(Value::as_str).map(str::to_owned));
                }
                data.push(line.join(" "));
            }
            let glyphs:Value=agent.get("https://raw.githubusercontent.com/ryanoasis/nerd-fonts/refs/heads/master/glyphnames.json").call()?.into_json()?;
            let mut buckets: Vec<(String, Vec<String>)> = Vec::new();
            for (name, glyph) in glyphs.as_object().ok_or("invalid Nerd Fonts data")? {
                if name == "METADATA" {
                    continue;
                }
                let c = glyph["char"].as_str().ok_or("missing Nerd Fonts glyph")?;
                if let Some((_, names)) = buckets.iter_mut().find(|(ch, _)| ch == c) {
                    names.push(format!("nf-{name}"));
                } else {
                    buckets.push((c.to_owned(), vec![format!("nf-{name}")]));
                }
            }
            for (c, names) in buckets {
                data.push(format!("{c}  {}", names.join(" ")));
            }
            atomic(&path, format!("{}\n", data.join("\n")).as_bytes(), 0o600)?;
            println!(
                "cortetsu-emoji: fetched {} entries -> {}",
                data.len(),
                path.display()
            );
        }
        _ => return Ok(2),
    }
    Ok(0)
}
