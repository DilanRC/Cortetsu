//! Lyrics for the dashboard.
//!
//! `serve` is the bridge the spicetify extension talks to: it listens on
//! loopback, accepts one JSON document per POST from Spotify's own page and
//! prints it, normalised, as one line on stdout for the shell to read.
//! `lookup` finds lyrics for players other than Spotify, or for a Spotify
//! track it has none for: first an `Artist - Title.lrc` file in the local
//! lyrics folder, then lrclib.net.
//!
//! Both print the same shape:
//! `{"source":..,"trackId":..,"synced":bool,"lines":[{"t":ms,"text":..}]}`.

use crate::common::*;
use serde_json::{Value, json};
use std::{
    io::{BufRead, BufReader, Read, Write},
    net::{TcpListener, TcpStream},
    time::Duration,
};

pub const PORT: u16 = 47853;
const MAX_BODY: usize = 1 << 20;
const MAX_LINES: usize = 2000;
const MAX_TEXT: usize = 400;
// The page spicetify injects into. Any other origin is a website trying to
// write into the shell, and is refused.
const SPOTIFY_ORIGIN: &str = "https://xpui.app.spotify.com";

pub fn main(args: &[String]) -> Result<i32> {
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    match a.first().copied() {
        Some("serve") => serve(),
        Some("lookup") => lookup(&a[1..]),
        _ => {
            eprintln!(
                "usage: cortetsu-lyrics serve\n       cortetsu-lyrics lookup --title T --artist A [--album B] [--duration S] [--local-dir D] [--offline | --online-only]"
            );
            Ok(2)
        }
    }
}

fn serve() -> Result<i32> {
    let listener = TcpListener::bind(("127.0.0.1", PORT))?;
    let mut out = std::io::stdout().lock();
    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        // One slow or broken client must not stall the next song change.
        let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
        let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
        if let Some(line) = handle(stream) {
            writeln!(out, "{line}")?;
            out.flush()?;
        }
    }
    Ok(0)
}

struct Request {
    method: String,
    path: String,
    origin: Option<String>,
    body: Vec<u8>,
}

fn read_request(stream: &TcpStream) -> Option<Request> {
    let mut reader = BufReader::new(stream.take((MAX_BODY + 16384) as u64));
    let mut first = String::new();
    reader.read_line(&mut first).ok()?;
    let mut parts = first.split_whitespace();
    let method = parts.next()?.to_owned();
    let path = parts.next()?.to_owned();
    let mut length = 0usize;
    let mut origin = None;
    let mut header_bytes = 0usize;
    loop {
        let mut line = String::new();
        let n = reader.read_line(&mut line).ok()?;
        header_bytes += n;
        if n == 0 || header_bytes > 16384 {
            return None;
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        let (name, value) = line.split_once(':')?;
        let value = value.trim();
        match name.trim().to_ascii_lowercase().as_str() {
            "content-length" => length = value.parse().ok()?,
            "origin" => origin = Some(value.to_owned()),
            _ => {}
        }
    }
    if length > MAX_BODY {
        return None;
    }
    let mut body = vec![0; length];
    reader.read_exact(&mut body).ok()?;
    Some(Request {
        method,
        path,
        origin,
        body,
    })
}

fn respond(mut stream: &TcpStream, status: &str) {
    let _ = write!(
        stream,
        "HTTP/1.1 {status}\r\nAccess-Control-Allow-Origin: {SPOTIFY_ORIGIN}\r\n\
         Access-Control-Allow-Methods: POST\r\nAccess-Control-Allow-Headers: content-type\r\n\
         Content-Length: 0\r\nConnection: close\r\n\r\n"
    );
}

fn handle(stream: TcpStream) -> Option<String> {
    let Some(req) = read_request(&stream) else {
        respond(&stream, "400 Bad Request");
        return None;
    };
    if req.origin.as_deref().is_some_and(|o| o != SPOTIFY_ORIGIN) {
        respond(&stream, "403 Forbidden");
        return None;
    }
    if req.method == "OPTIONS" {
        respond(&stream, "204 No Content");
        return None;
    }
    if req.method != "POST" || req.path != "/lyrics" {
        respond(&stream, "404 Not Found");
        return None;
    }
    let line = serde_json::from_slice::<Value>(&req.body)
        .ok()
        .and_then(|v| normalise_spotify(&v));
    respond(
        &stream,
        if line.is_some() {
            "204 No Content"
        } else {
            "422 Unprocessable Entity"
        },
    );
    line.map(|v| v.to_string())
}

fn clean_text(s: &str) -> String {
    s.chars()
        .filter(|c| !c.is_control())
        .take(MAX_TEXT)
        .collect()
}

/// Accepts what the extension sends and keeps only well-formed fields, so
/// the shell never sees anything but the documented shape.
pub fn normalise_spotify(v: &Value) -> Option<Value> {
    let id = v["trackId"].as_str()?;
    if id.is_empty() || id.len() > 64 || !id.chars().all(|c| c.is_ascii_alphanumeric()) {
        return None;
    }
    let lines: Vec<Value> = v["lines"]
        .as_array()?
        .iter()
        .take(MAX_LINES)
        .filter_map(|l| {
            let t = l["t"].as_f64().filter(|t| t.is_finite() && *t >= 0.0)? as u64;
            Some(json!({"t": t, "text": clean_text(l["text"].as_str()?)}))
        })
        .collect();
    Some(json!({
        "source": "spotify",
        "trackId": id,
        "synced": v["synced"].as_bool().unwrap_or(false) && !lines.is_empty(),
        "lines": lines,
    }))
}

/// `[mm:ss.xx] text` lines; one LRC line may carry several stamps.
pub fn parse_lrc(lrc: &str) -> Vec<Value> {
    let mut out: Vec<(u64, String)> = Vec::new();
    for raw in lrc.lines() {
        let mut rest = raw.trim();
        let mut stamps = Vec::new();
        while let Some(body) = rest.strip_prefix('[') {
            let Some((stamp, after)) = body.split_once(']') else {
                break;
            };
            let Some((m, s)) = stamp.split_once(':') else {
                break;
            };
            let (Ok(m), Ok(s)) = (m.parse::<u64>(), s.parse::<f64>()) else {
                break;
            };
            stamps.push(m * 60_000 + (s * 1000.0).round() as u64);
            rest = after.trim_start();
        }
        for t in stamps {
            out.push((t, clean_text(rest)));
        }
    }
    out.sort_by_key(|(t, _)| *t);
    out.into_iter()
        .map(|(t, text)| json!({"t": t, "text": text}))
        .collect()
}

fn from_lrclib(v: &Value) -> Option<Value> {
    if let Some(lrc) = v["syncedLyrics"].as_str().filter(|s| !s.trim().is_empty()) {
        let lines = parse_lrc(lrc);
        if !lines.is_empty() {
            return Some(json!({"source": "lrclib", "synced": true, "lines": lines}));
        }
    }
    let plain = v["plainLyrics"].as_str().filter(|s| !s.trim().is_empty())?;
    let lines: Vec<Value> = plain
        .lines()
        .take(MAX_LINES)
        .map(|l| json!({"t": 0, "text": clean_text(l.trim())}))
        .collect();
    Some(json!({"source": "lrclib", "synced": false, "lines": lines}))
}

fn flag<'a>(args: &[&'a str], name: &str) -> Option<&'a str> {
    args.windows(2).find(|w| w[0] == name).map(|w| w[1])
}

/// `<dir>/**/Artist - Title.lrc`, compared without case, two levels deep.
fn local_file(dir: &std::path::Path, artist: &str, title: &str) -> Option<String> {
    let want = format!("{artist} - {title}.lrc").to_lowercase();
    let mut dirs = vec![(dir.to_path_buf(), 0)];
    while let Some((d, depth)) = dirs.pop() {
        for e in std::fs::read_dir(&d).ok()?.flatten() {
            let path = e.path();
            if path.is_dir() && depth < 2 {
                dirs.push((path, depth + 1));
            } else if e.file_name().to_string_lossy().to_lowercase() == want {
                return std::fs::read_to_string(path).ok();
            }
        }
    }
    None
}

fn lookup(args: &[&str]) -> Result<i32> {
    let (Some(title), Some(artist)) = (flag(args, "--title"), flag(args, "--artist")) else {
        eprintln!("cortetsu-lyrics: --title and --artist are required");
        return Ok(2);
    };
    let offline = args.contains(&"--offline");
    let local = flag(args, "--local-dir")
        .filter(|_| !args.contains(&"--online-only"))
        .and_then(|dir| local_file(std::path::Path::new(dir), artist, title));
    if let Some(lrc) = local {
        let lines = parse_lrc(&lrc);
        let synced = !lines.is_empty();
        let lines = if synced {
            lines
        } else {
            lrc.lines()
                .map(|l| json!({"t": 0, "text": clean_text(l.trim())}))
                .collect()
        };
        emit(&json!({"source": "local", "synced": synced, "lines": lines}))?;
        return Ok(0);
    }
    if offline {
        emit(&json!({"source": "local", "synced": false, "lines": []}))?;
        return Ok(0);
    }
    let album = flag(args, "--album").unwrap_or("");
    let duration = flag(args, "--duration")
        .and_then(|d| d.parse::<f64>().ok())
        .unwrap_or(0.0);
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(8))
        .user_agent("Cortetsu (https://github.com/dilan/cortetsu)")
        .build();

    // The exact lookup first; it needs the album and length to match.
    let mut found = None;
    if !album.is_empty() && duration > 0.0 {
        let res = agent
            .get("https://lrclib.net/api/get")
            .query("track_name", title)
            .query("artist_name", artist)
            .query("album_name", album)
            .query("duration", &format!("{}", duration.round() as u64))
            .call();
        if let Ok(res) = res {
            found = res.into_json::<Value>().ok().and_then(|v| from_lrclib(&v));
        }
    }
    // Otherwise the closest search hit, preferring synced ones.
    if found.is_none() {
        let hits: Value = agent
            .get("https://lrclib.net/api/search")
            .query("track_name", title)
            .query("artist_name", artist)
            .call()?
            .into_json()?;
        let hits = hits.as_array().cloned().unwrap_or_default();
        let near = |h: &&Value| {
            duration <= 0.0 || (h["duration"].as_f64().unwrap_or(0.0) - duration).abs() < 4.0
        };
        found = hits
            .iter()
            .filter(near)
            .find(|h| h["syncedLyrics"].as_str().is_some_and(|s| !s.is_empty()))
            .or_else(|| hits.iter().find(near))
            .and_then(from_lrclib);
    }
    emit(&found.unwrap_or_else(|| json!({"source": "lrclib", "synced": false, "lines": []})))?;
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lrc_lines_are_sorted_and_multi_stamped() {
        let lines = parse_lrc("[00:12.50]b\n[00:01.00][00:20.00]a\n[ar:x]\nplain");
        let got: Vec<(u64, &str)> = lines
            .iter()
            .map(|l| (l["t"].as_u64().unwrap(), l["text"].as_str().unwrap()))
            .collect();
        assert_eq!(got, vec![(1000, "a"), (12500, "b"), (20000, "a")]);
    }

    #[test]
    fn spotify_payload_is_normalised() {
        let v = json!({"trackId": "4uLU6hMCjMI75M1A2tKUQC", "synced": true,
            "lines": [{"t": 1200, "text": "hola\u{0007}"}, {"t": -1, "text": "x"}, {"text": "y"}], "extra": 1});
        let n = normalise_spotify(&v).unwrap();
        assert_eq!(n["lines"], json!([{"t": 1200, "text": "hola"}]));
        assert_eq!(n["source"], "spotify");
        assert!(n.get("extra").is_none());
    }

    #[test]
    fn bad_track_ids_are_refused() {
        assert!(normalise_spotify(&json!({"trackId": "../etc", "lines": []})).is_none());
        assert!(normalise_spotify(&json!({"trackId": "", "lines": []})).is_none());
        assert!(normalise_spotify(&json!({"trackId": "abc"})).is_none());
    }

    #[test]
    fn local_files_match_without_case() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("sub")).unwrap();
        std::fs::write(
            dir.path()
                .join("sub/Enanitos Verdes - Lamento Boliviano.LRC"),
            "[00:01.00]x",
        )
        .unwrap();
        assert_eq!(
            local_file(dir.path(), "enanitos verdes", "lamento boliviano").as_deref(),
            Some("[00:01.00]x")
        );
        assert!(local_file(dir.path(), "otro", "tema").is_none());
    }

    #[test]
    fn empty_lyrics_are_not_synced() {
        let n = normalise_spotify(&json!({"trackId": "abc", "synced": true, "lines": []})).unwrap();
        assert_eq!(n["synced"], false);
    }
}
