//! Calendar read-only API, desktop OAuth PKCE and Secret Service token storage.
use crate::common::*;
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{Duration as Days, Local};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeSet,
    env,
    fs::{self, File},
    io::{Read, Write},
    net::TcpListener,
    path::PathBuf,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

const SCOPES: [&str; 2] = [
    "https://www.googleapis.com/auth/calendar.events.readonly",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
];
const TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const API_ROOT: &str = "https://www.googleapis.com/calendar/v3";
const SERVICE: &str = "cortetsu-google-calendar";
#[derive(Debug)]
struct Error {
    code: &'static str,
    status: Option<u16>,
}
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.code)
    }
}
impl std::error::Error for Error {}
impl From<ureq::Error> for Error {
    fn from(e: ureq::Error) -> Self {
        match e {
            ureq::Error::Status(s, _) => Self {
                code: "HTTPError",
                status: Some(s),
            },
            ureq::Error::Transport(_) => Self {
                code: "URLError",
                status: None,
            },
        }
    }
}
fn failure(code: &'static str) -> Error {
    Error { code, status: None }
}
fn paths() -> (PathBuf, PathBuf, PathBuf) {
    (
        config().join("cortetsu/calendar-client.json"),
        config().join("cortetsu/calendar-selection.json"),
        cache().join("calendar-events.json"),
    )
}
fn normalize_client(raw: Value) -> Option<Value> {
    let mut raw = raw;
    let map = raw.as_object_mut()?;
    let client = if map.contains_key("installed") {
        map.remove("installed")?
    } else if map.contains_key("web") {
        return None;
    } else {
        raw
    };
    client
        .get("client_id")?
        .as_str()
        .filter(|s| !s.trim().is_empty())?;
    Some(client)
}
fn secret_tool() -> std::result::Result<PathBuf, Error> {
    which("secret-tool").ok_or_else(|| failure("secret_service_unavailable"))
}
fn secret_get() -> std::result::Result<Option<String>, Error> {
    let out = run(
        Command::new(secret_tool()?).args(["lookup", "service", SERVICE]),
        None,
        Duration::from_secs(10),
    )
    .map_err(|_| failure("SubprocessError"))?;
    let value = String::from_utf8(out.stdout).map_err(|_| failure("ValueError"))?;
    Ok((out.status.success() && !value.trim().is_empty()).then(|| value.trim().to_owned()))
}
fn secret_set(token: &str) -> std::result::Result<(), Error> {
    let out = run(
        Command::new(secret_tool()?).args([
            "store",
            "--label",
            "Cortetsu Google Calendar refresh token",
            "service",
            SERVICE,
        ]),
        Some(token.as_bytes()),
        Duration::from_secs(15),
    )
    .map_err(|_| failure("SubprocessError"))?;
    if !out.status.success() {
        return Err(failure("SubprocessError"));
    }
    Ok(())
}
fn secret_clear() -> std::result::Result<(), Error> {
    run(
        Command::new(secret_tool()?).args(["clear", "service", SERVICE]),
        None,
        Duration::from_secs(10),
    )
    .map_err(|_| failure("SubprocessError"))?;
    Ok(())
}
fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(20))
        .build()
}
fn token_request(data: &[(&str, &str)]) -> std::result::Result<Value, Error> {
    agent()
        .post(TOKEN_URL)
        .send_form(data)?
        .into_json()
        .map_err(|_| failure("ValueError"))
}
fn refresh(client: &Value, token: &str) -> std::result::Result<String, Error> {
    let body = token_request(&[
        ("client_id", text(&client["client_id"])),
        ("client_secret", text(&client["client_secret"])),
        ("refresh_token", token),
        ("grant_type", "refresh_token"),
    ])?;
    body["access_token"]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| failure("token_response_invalid"))
}
fn constant_equal(a: &str, b: &str) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.as_bytes()
        .iter()
        .zip(b.as_bytes())
        .fold(0u8, |v, (a, b)| v | (a ^ b))
        == 0
}
fn callback(query: &str, state: &str) -> (Option<String>, Option<&'static str>) {
    let params: Vec<_> = url::form_urlencoded::parse(query.as_bytes()).collect();
    let get = |key: &str| {
        params
            .iter()
            .find(|(k, v)| k == key && !v.is_empty())
            .map(|(_, v)| v.as_ref())
    };
    if !get("state").is_some_and(|s| constant_equal(s, state)) {
        return (None, Some("oauth_state_mismatch"));
    }
    if get("error").is_some() {
        return (None, Some("oauth_denied"));
    }
    match get("code") {
        Some(c) => (Some(c.to_owned()), None),
        None => (None, Some("oauth_code_missing")),
    }
}
fn random() -> std::result::Result<String, Error> {
    let mut b = [0u8; 32];
    File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut b))
        .map_err(|_| failure("OSError"))?;
    Ok(URL_SAFE_NO_PAD.encode(b))
}
fn authorize(client: &Value) -> std::result::Result<String, Error> {
    let verifier = random()?;
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    let expected = random()?;
    let listener = TcpListener::bind(("127.0.0.1", 0)).map_err(|_| failure("OSError"))?;
    listener
        .set_nonblocking(true)
        .map_err(|_| failure("OSError"))?;
    let redirect = format!(
        "http://127.0.0.1:{}/oauth2callback",
        listener
            .local_addr()
            .map_err(|_| failure("OSError"))?
            .port()
    );
    let query = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs([
            ("client_id", text(&client["client_id"])),
            ("redirect_uri", redirect.as_str()),
            ("response_type", "code"),
            ("scope", SCOPES.join(" ").as_str()),
            ("access_type", "offline"),
            ("prompt", "consent"),
            ("code_challenge", challenge.as_str()),
            ("code_challenge_method", "S256"),
            ("state", expected.as_str()),
        ])
        .finish();
    let auth_url = format!("https://accounts.google.com/o/oauth2/v2/auth?{query}");
    if !Command::new("xdg-open")
        .arg(&auth_url)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .is_ok()
    {
        eprintln!("Open this URL to authorize Cortetsu:\n{auth_url}");
    }
    let start = Instant::now();
    let mut result = None;
    while start.elapsed() < Duration::from_secs(300) {
        match listener.accept() {
            Ok((mut socket, _)) => {
                let _ = socket.set_read_timeout(Some(Duration::from_secs(1)));
                let _ = socket.set_write_timeout(Some(Duration::from_secs(1)));
                let mut bytes = [0u8; 8192];
                let n = socket.read(&mut bytes).unwrap_or(0);
                let request = String::from_utf8_lossy(&bytes[..n]);
                let first = request.lines().next().unwrap_or("");
                let target = first.split_whitespace().nth(1).unwrap_or("");
                let raw = target.split_once('?').map(|(_, q)| q).unwrap_or("");
                let (code, error) = callback(raw, &expected);
                let valid = code.is_some();
                let message = if valid {
                    "Cortetsu authorization received. You can close this tab."
                } else {
                    "Cortetsu could not validate the authorization response."
                };
                let response = format!(
                    "HTTP/1.1 {}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    if valid { "200 OK" } else { "400 Bad Request" },
                    message.len(),
                    message
                );
                let _ = socket.write_all(response.as_bytes());
                if error != Some("oauth_state_mismatch") {
                    result = Some((code, error));
                    break;
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(50))
            }
            Err(_) => return Err(failure("OSError")),
        }
    }
    let (code, error) = result.ok_or_else(|| failure("oauth_timeout"))?;
    if let Some(error) = error {
        return Err(failure(error));
    }
    let code = code.ok_or_else(|| failure("oauth_code_missing"))?;
    let body = token_request(&[
        ("client_id", text(&client["client_id"])),
        ("client_secret", text(&client["client_secret"])),
        ("code", &code),
        ("code_verifier", &verifier),
        ("grant_type", "authorization_code"),
        ("redirect_uri", &redirect),
    ])?;
    let access = body["access_token"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| failure("token_response_invalid"))?;
    let refresh = body["refresh_token"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| failure("refresh_token_missing"))?;
    secret_set(refresh)?;
    Ok(access.to_owned())
}
fn token(client: &Value) -> std::result::Result<String, Error> {
    if let Some(refresh_token) = secret_get()? {
        match refresh(client, &refresh_token) {
            Ok(access) => return Ok(access),
            Err(e) if matches!(e.status, Some(400 | 401)) => secret_clear()?,
            Err(e) => return Err(e),
        }
    }
    authorize(client)
}
fn api(access: &str, path: &str, params: &[(&str, String)]) -> std::result::Result<Value, Error> {
    let query = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(params.iter().map(|(k, v)| (*k, v.as_str())))
        .finish();
    agent()
        .get(&format!("{API_ROOT}{path}?{query}"))
        .set("Authorization", &format!("Bearer {access}"))
        .call()?
        .into_json()
        .map_err(|_| failure("ValueError"))
}
fn calendar_list(access: &str) -> std::result::Result<Vec<Value>, Error> {
    let mut result = Vec::new();
    let mut page = String::new();
    let mut seen = BTreeSet::new();
    loop {
        let mut params = vec![("maxResults", "250".to_owned())];
        if !page.is_empty() {
            params.push(("pageToken", page));
        }
        let data = api(access, "/users/me/calendarList", &params)?;
        for item in data["items"].as_array().unwrap_or(&Vec::new()) {
            if let Some(id) = item["id"].as_str().filter(|s| !s.is_empty()) {
                result.push(json!({"calendarId":id,"calendarName":item.get("summary").unwrap_or(&item["id"]),"calendarColor":item.get("backgroundColor").cloned().unwrap_or(json!("")),"selected":item["selected"].as_bool().unwrap_or(false),"primary":item["primary"].as_bool().unwrap_or(false)}));
            }
        }
        page = text(&data["nextPageToken"]).to_owned();
        if page.is_empty() {
            return Ok(result);
        }
        if !seen.insert(page.clone()) {
            return Err(failure("ValueError"));
        }
    }
}
fn normalize_event(item: &Value, calendar: &Value) -> Option<Value> {
    let id = item["id"].as_str()?;
    let begin = item["start"].as_object()?;
    let finish = item["end"].as_object()?;
    let start = begin
        .get("dateTime")
        .or_else(|| begin.get("date"))?
        .as_str()?;
    let end = finish
        .get("dateTime")
        .or_else(|| finish.get("date"))?
        .as_str()?;
    Some(
        json!({"calendarId":calendar["calendarId"],"calendarName":calendar["calendarName"],"calendarColor":calendar["calendarColor"],"eventId":id,"title":item.get("summary").filter(|v|!v.is_null()&&v.as_str()!=Some("")).cloned().unwrap_or(json!("(untitled)")),"start":start,"end":end,"allDay":begin.contains_key("date"),"location":item.get("location").cloned().unwrap_or(json!("")),"htmlLink":item.get("htmlLink").cloned().unwrap_or(json!(""))}),
    )
}
fn timezone() -> String {
    if let Ok(tz) = env::var("TZ")
        && !tz.trim_start_matches(':').is_empty()
    {
        return tz.trim_start_matches(':').to_owned();
    }
    fs::canonicalize("/etc/localtime")
        .ok()
        .and_then(|p| {
            p.to_str()
                .and_then(|s| s.split_once("zoneinfo/").map(|(_, tz)| tz.to_owned()))
        })
        .unwrap_or_else(|| "UTC".to_owned())
}
fn events(
    access: &str,
    calendars: &[Value],
    start: &str,
    end: &str,
    tz: &str,
) -> (Vec<Value>, Vec<Value>) {
    let mut items = Vec::new();
    let mut failures = Vec::new();
    for calendar in calendars {
        let result = (|| -> std::result::Result<(), Error> {
            let mut page = String::new();
            let mut seen = BTreeSet::new();
            loop {
                let mut params = vec![
                    ("singleEvents", "true".to_owned()),
                    ("showDeleted", "false".to_owned()),
                    ("orderBy", "startTime".to_owned()),
                    ("timeMin", start.to_owned()),
                    ("timeMax", end.to_owned()),
                    ("timeZone", tz.to_owned()),
                    ("maxResults", "2500".to_owned()),
                ];
                if !page.is_empty() {
                    params.push(("pageToken", page));
                }
                let encoded =
                    url::form_urlencoded::byte_serialize(text(&calendar["calendarId"]).as_bytes())
                        .collect::<String>()
                        .replace('+', "%20");
                let data = api(access, &format!("/calendars/{encoded}/events"), &params)?;
                if let Some(events) = data["items"].as_array() {
                    items.extend(events.iter().filter_map(|e| normalize_event(e, calendar)));
                }
                page = text(&data["nextPageToken"]).to_owned();
                if page.is_empty() {
                    return Ok(());
                }
                if !seen.insert(page.clone()) {
                    return Err(failure("ValueError"));
                }
            }
        })();
        if let Err(e) = result {
            failures.push(json!({"calendarId":calendar["calendarId"],"error":e.code}));
        }
    }
    items.sort_by(|a, b| {
        (
            text(&a["start"]),
            text(&a["calendarId"]),
            text(&a["eventId"]),
        )
            .cmp(&(
                text(&b["start"]),
                text(&b["calendarId"]),
                text(&b["eventId"]),
            ))
    });
    (items, failures)
}
struct FetchSnapshot {
    calendars: Vec<Value>,
    items: Vec<Value>,
    failures: Vec<Value>,
    start: String,
    end: String,
    tz: String,
}

fn fetch_calendar_snapshot(
    client: &Value,
    selection_path: &std::path::Path,
) -> std::result::Result<FetchSnapshot, Error> {
    let access = token(client)?;
    let calendars = calendar_list(&access)?;
    let enabled = {
        let _selection_guard = lock(
            &selection_path.with_file_name("calendar-selection.lock"),
            false,
        )
        .map_err(|_| failure("OSError"))?;
        let selection = json_load(selection_path, json!({}));
        if let Some(ids) = selection["enabled"].as_array() {
            ids.clone()
        } else {
            let ids: Vec<Value> = calendars
                .iter()
                .filter(|c| c["selected"] == true || c["primary"] == true)
                .map(|c| c["calendarId"].clone())
                .collect();
            json_save(selection_path, &json!({"enabled":ids,"initialized":true}))
                .map_err(|_| failure("OSError"))?;
            ids
        }
    };
    let chosen: Vec<Value> = calendars
        .iter()
        .filter(|c| enabled.contains(&c["calendarId"]))
        .cloned()
        .collect();
    let current = Local::now();
    let start = (current - Days::days(62)).to_rfc3339();
    let end = (current + Days::days(370)).to_rfc3339();
    let tz = timezone();
    let (items, failures) = events(&access, &chosen, &start, &end, &tz);
    Ok(FetchSnapshot {
        calendars,
        items,
        failures,
        start,
        end,
        tz,
    })
}

fn sync(force: bool) -> Result<i32> {
    let (client_path, selection_path, cache_path) = paths();
    if !client_path.exists() {
        emit(&json!({"status":"auth_required","clientPath":client_path}))?;
        return Ok(2);
    }
    let _guard = match lock(&cache_path.with_file_name("calendar-sync.lock"), true) {
        Ok(l) => l,
        Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
            emit(&json!({"status":"sync_in_progress","cache":cache_path}))?;
            return Ok(0);
        }
        Err(e) => return Err(e.into()),
    };
    let cached = json_load(&cache_path, json!({}));
    let fetched = cached.get("fetchedAt").and_then(|v| {
        v.as_f64()
            .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
    });
    if !force && fetched.is_some_and(|t| (0.0..900.0).contains(&(now() - t))) {
        emit(
            &json!({"status":"cached","cache":cache_path,"eventCount":cached["events"].as_array().map_or(0,Vec::len),"fetchedAt":cached["fetchedAt"]}),
        )?;
        return Ok(0);
    }
    let Some(client) = normalize_client(json_load(&client_path, json!({}))) else {
        emit(&json!({"status":"credential_error","clientPath":client_path}))?;
        return Ok(2);
    };
    let operation = fetch_calendar_snapshot(&client, &selection_path);
    match operation {
        Ok(FetchSnapshot {
            calendars,
            items,
            failures,
            start,
            end,
            tz,
        }) => {
            json_save(
                &cache_path,
                &json!({"schema":1,"fetchedAt":now(),"timezone":tz,"range":{"start":start,"end":end},"calendars":calendars,"events":items,"failures":failures}),
            )?;
            emit(
                &json!({"status":if failures.is_empty(){"ok"}else{"partial"},"cache":cache_path,"eventCount":items.len(),"failedCalendars":failures}),
            )?;
            Ok(if failures.is_empty() { 0 } else { 4 })
        }
        Err(e) => {
            if matches!(
                e.code,
                "HTTPError"
                    | "URLError"
                    | "OSError"
                    | "ValueError"
                    | "TypeError"
                    | "KeyError"
                    | "SubprocessError"
            ) {
                emit(&json!({"status":"error","error":e.code}))?;
            } else {
                emit(&json!({"status":e.code}))?;
            }
            Ok(3)
        }
    }
}
pub fn main(args: &[String]) -> Result<i32> {
    let a: Vec<_> = args
        .iter()
        .filter(|a| a.as_str() != "--force")
        .map(String::as_str)
        .collect();
    let (client, selection, cache) = paths();
    match a.as_slice() {
        ["scopes"] => {
            println!("{}", SCOPES.join("\n"));
            Ok(0)
        }
        ["disconnect"] => match secret_clear() {
            Ok(()) => {
                emit(&json!({"status":"disconnected"}))?;
                Ok(0)
            }
            Err(e) => {
                emit(&json!({"status":e.code}))?;
                Ok(3)
            }
        },
        ["status"] => {
            let cached = json_load(&cache, json!({}));
            let age = cached
                .get("fetchedAt")
                .and_then(|v| {
                    v.as_f64()
                        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
                })
                .filter(|t| t.is_finite())
                .map(|t| (now() - t).max(0.0) as u64);
            emit(
                &json!({"status":if client.exists(){"ready"}else{"auth_required"},"clientPath":client,"cache":cache,"cacheAgeSeconds":age,"eventCount":cached["events"].as_array().map_or(0,Vec::len)}),
            )?;
            Ok(0)
        }
        ["set-selection", id, enabled]
            if matches!(*enabled, "true" | "false") && !id.is_empty() =>
        {
            let _guard = lock(&selection.with_file_name("calendar-selection.lock"), false)?;
            let old = json_load(&selection, json!({}));
            let mut ids: BTreeSet<String> = old["enabled"]
                .as_array()
                .map(|a| {
                    a.iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default();
            if *enabled == "true" {
                ids.insert((*id).to_owned());
            } else {
                ids.remove(*id);
            }
            json_save(&selection, &json!({"enabled":ids,"initialized":true}))?;
            emit(&json!({"status":"selection_updated","enabled":ids,"initialized":true}))?;
            Ok(0)
        }
        ["sync"] => sync(args.iter().any(|a| a == "--force")),
        _ => Ok(2),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn oauth_stray_request_does_not_match() {
        assert_eq!(
            callback("state=wrong&code=secret", "right"),
            (None, Some("oauth_state_mismatch"))
        );
        assert_eq!(
            callback("state=s&error=access_denied", "s"),
            (None, Some("oauth_denied"))
        );
        assert_eq!(
            callback("state=s&code=authorization-code", "s"),
            (Some("authorization-code".to_owned()), None)
        );
    }
    #[test]
    fn google_desktop_client_and_events() {
        assert!(normalize_client(json!({"web":{"client_id":"id"}})).is_none());
        assert!(normalize_client(json!({"installed":{"client_id":"id"}})).is_some());
        let c = json!({"calendarId":"a","calendarName":"Calendar","calendarColor":"red"});
        let e = normalize_event(
            &json!({"id":"e","start":{"date":"2026-01-01"},"end":{"date":"2026-01-02"}}),
            &c,
        )
        .unwrap();
        assert_eq!(e["allDay"], true);
        assert_eq!(e["title"], "(untitled)");
    }
}
