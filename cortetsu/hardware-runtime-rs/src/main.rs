mod display;
mod gamemode;
mod hardware;
mod nvibrant;
mod owner;
mod power;
mod util;
fn main() {
    if let Err(error) = util::init_signals() {
        eprintln!("{error}");
        std::process::exit(1)
    }
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    let Some(command) = args.first() else {
        eprintln!("usage: cortetsu-hardware-runtime COMMAND [ARGS...]");
        std::process::exit(2)
    };
    let args = &args[1..];
    let (value, code) = match command.as_str() {
        "exec" => (owner::exec(), 0),
        "cortetsu-display-probe" => (display::probe(), 0),
        "cortetsu-display-plan" => display::planner(args),
        "cortetsu-display-transaction"
            if args.first().is_some_and(|a| {
                ["preview", "confirm", "revert", "recover"].contains(&a.as_str())
            }) =>
        {
            owner::manual_cli("display", || display::transaction(args))
        }
        "cortetsu-display-transaction" => display::transaction(args),
        "cortetsu-display-persist" if args.first().is_some_and(|a| a == "persist") => {
            owner::manual_cli("display", || display::persist(args))
        }
        "cortetsu-display-persist" => display::persist(args),
        "cortetsu-display-workspaces" if args.first().is_some_and(|a| a == "sync") => {
            owner::manual_cli("display", || display::workspaces(args))
        }
        "cortetsu-display-workspaces" => display::workspaces(args),
        "cortetsu-gamemode"
            if args
                .iter()
                .any(|a| ["enable", "disable", "recover"].contains(&a.as_str())) =>
        {
            owner::manual_cli("gamemode", || gamemode::main(args))
        }
        "cortetsu-gamemode" => gamemode::main(args),
        "cortetsu-nvibrant" => nvibrant::main(args),
        "cortetsu-hardware-probe" => hardware::main(args),
        "cortetsu-hardware-power" if args.first().is_some_and(|a| a == "set-profile") => {
            owner::manual_cli("power", || power::hardware(args))
        }
        "cortetsu-hardware-power" => power::hardware(args),
        "cortetsu-power-auto-control" => power::control(args),
        "cortetsu-power-auto" => power::watcher(args),
        _ => util::json_error(format!("unknown command: {command}")),
    };
    if !value.is_null() {
        println!("{value}");
    }
    std::process::exit(if util::cancelled() { 130 } else { code });
}
