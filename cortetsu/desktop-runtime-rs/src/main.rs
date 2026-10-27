mod calendar;
mod common;
mod connectivity;
mod palette;
mod pomodoro;
mod quantizer;
mod recorder;
mod sharepicker;
mod startup;
mod utilities;

fn main() {
    let mut args = std::env::args().skip(1);
    let helper = args.next().unwrap_or_default();
    let args: Vec<String> = args.collect();
    let result = match helper.as_str() {
        "cortetsu-pomodoro" => pomodoro::main(&args),
        "cortetsu-calendar" => calendar::main(&args),
        "cortetsu-scheme" => palette::scheme(&args),
        "cortetsu-scheme-posthook" => palette::posthook(),
        "cortetsu-wallpaper-colours" => palette::wallpaper_colours(&args),
        "cortetsu-wallpaper-color-daemon" => palette::wallpaper_daemon(&args),
        "cortetsu-emoji" => utilities::emoji(&args),
        "cortetsu-area-capture" => utilities::area(&args),
        "cortetsu-connectivity-secret" | "ConnectivitySecret.py" => connectivity::main(&args),
        "cortetsu-startup" => startup::main(&args),
        "cortetsu-record" => recorder::main(&args),
        "cortetsu-share-picker" => sharepicker::main(&args),
        _ => {
            eprintln!("unknown desktop helper: {helper}");
            Ok(2)
        }
    };
    let code = match result {
        Ok(code) => code,
        Err(e) => {
            if e.downcast_ref::<std::io::Error>()
                .is_some_and(|e| e.kind() == std::io::ErrorKind::BrokenPipe)
            {
                0
            } else {
                eprintln!("{helper}: {e}");
                1
            }
        }
    };
    std::process::exit(code);
}
