use serde_json::{Value, json};
use std::{
    fs,
    io::Write,
    process::{Command, Stdio},
};

#[test]
fn typed_dnd_cross_language_cas_and_replay() {
    let root = std::env::temp_dir().join(format!("cortetsu-exec-dnd-{}", std::process::id()));
    fs::create_dir_all(&root).unwrap();
    let invoke = |request: &Value| -> Value {
        let mut child = Command::new(env!("CARGO_BIN_EXE_cortetsu-rescue"))
            .env("HOME", &root)
            .env("XDG_STATE_HOME", root.join("state"))
            .arg("exec")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(request.to_string().as_bytes())
            .unwrap();
        serde_json::from_slice(&child.wait_with_output().unwrap().stdout).unwrap()
    };
    let request: Value = serde_json::from_slice(include_bytes!(
        "../../contracts/exec/v1/fixtures/notifications-dnd-set.json"
    ))
    .unwrap();
    let applied = invoke(&request);
    assert_eq!(applied["outcome"], "applied", "{applied}");
    assert_eq!(applied["body"], json!({"dnd":true,"revision":1}));
    assert_eq!(invoke(&request)["body"]["revision"], 1);
    let mut stale = request.clone();
    stale["idempotency_key"] = json!("00000000-0000-4000-8000-000000000003");
    stale["arguments"]["enabled"] = json!(false);
    assert_eq!(invoke(&stale)["error"]["code"], "STATE_STALE");
    fs::remove_dir_all(root).unwrap();
}
