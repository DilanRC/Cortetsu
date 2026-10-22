use cortetsu_display_presets_rs::{Paths, run};
use std::env;
use std::process::ExitCode;
fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let paths = match Paths::from_env(&env::current_exe().unwrap_or_default()) {
        Ok(paths) => paths,
        Err(err) => {
            println!("{}", serde_json::json!({"ok":false,"error":err.0}));
            return ExitCode::from(2);
        }
    };
    let (body, code) = run(&args, &paths);
    println!("{body}");
    ExitCode::from(code)
}
