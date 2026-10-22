use crate::common::*;
use serde_json::Value;
use std::{
    env, fs,
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};

pub fn area(args: &[String]) -> Result<i32> {
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
    let result = (|| -> Result<i32> {
        let status = Command::new("grim")
            .args(["-g", geometry])
            .arg(&path)
            .status()?;
        if !status.success() {
            return Ok(status.code().unwrap_or(1));
        }
        if clipboard {
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
                .args(["Screenshot taken", "Screenshot copied to clipboard"])
                .status();
            Ok(0)
        } else {
            Ok(Command::new("swappy")
                .arg("-f")
                .arg(&path)
                .status()?
                .code()
                .unwrap_or(1))
        }
    })();
    let _ = fs::remove_file(&path);
    result
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
        ["-p"] | ["--picker"] => {
            if !path.is_file() {
                eprintln!("cortetsu-emoji: no such data file: {}", path.display());
                return Ok(1);
            }
            let entries = fs::read(&path)?;
            let mut child = Command::new("fuzzel")
                .args(["--dmenu", "--placeholder=Type to search emojis"])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .spawn()?;
            child
                .stdin
                .take()
                .ok_or("picker stdin unavailable")?
                .write_all(&entries)?;
            let out = child.wait_with_output()?;
            if !out.status.success() {
                return Ok(out.status.code().unwrap_or(1));
            }
            let chosen = String::from_utf8(out.stdout)?;
            let glyph = chosen.split_whitespace().next().unwrap_or("");
            let out = run(
                &mut Command::new("wl-copy"),
                Some(glyph.as_bytes()),
                Duration::from_secs(10),
            )?;
            if !out.status.success() {
                return Ok(out.status.code().unwrap_or(1));
            }
        }
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
