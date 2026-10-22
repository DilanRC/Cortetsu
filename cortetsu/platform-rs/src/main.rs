mod doctor;
mod dotfiles;
mod gc;
mod imports;
mod install;
mod metadata;
mod migrations;
mod runtime;
mod system;
mod theme;
mod transforms;
mod util;
use util::*;
fn run() -> Result<i32> {
    let raw: Vec<String> = std::env::args().skip(1).collect();
    let cmd = raw
        .first()
        .ok_or("usage: cortetsu-platform <command> [args]")?
        .trim_end_matches(".py");
    let args = Args::parse(&raw[1..])?;
    match cmd {
        "seal-runtime" | "validate-runtime" => runtime::run(cmd, &args),
        "metadata" | "build-metadata" | "show-generation" | "verify-shell-metadata" => {
            metadata::run(cmd, &args)
        }
        "install-transaction" => install::run(&args),
        "dotfiles" => dotfiles::run(&args),
        "system" => system::run(&args),
        "generation_gc" | "gc" => gc::run(&args),
        "doctor" => doctor::run(&args),
        "theme" => theme::run(&args),
        "migrate_config" => migrations::config(&args),
        "shell_lifecycle" => migrations::lifecycle(&args),
        "migrate_legacy_processes" => migrations::legacy(&args),
        "import_desktop" => imports::run("desktop", &args),
        "import_fish" => imports::run("fish", &args),
        "import_hyprland" => imports::run("hyprland", &args),
        "normalize-shell-24"
        | "normalize-contentwindow-overview-24"
        | "compose-panels"
        | "migrate-bottom-hub-from-main"
        | "check-bottom-hub-target"
        | "wire_sad_shell"
        | "retire_legacy_theme" => transforms::run(cmd, &args),
        _ => fail(format!("unknown platform command: {cmd}")),
    }
}
fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("ERROR: {e}");
            std::process::exit(1)
        }
    }
}
