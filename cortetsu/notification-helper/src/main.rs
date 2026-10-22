use cortetsu_notifications_rs::{run, state_home};
use std::env;
use std::io::{self, Read};
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    match state_home().and_then(|root| {
        if args == ["merge"] {
            let mut bytes = Vec::new();
            io::stdin()
                .take(1024 * 1024 + 1)
                .read_to_end(&mut bytes)
                .map_err(|_| cortetsu_notifications_rs::Failure {
                    code: 2,
                    message: "INVALID_REQUEST".into(),
                })?;
            cortetsu_notifications_rs::owner::merge(&root, &bytes).map(|v| v.to_string())
        } else {
            run(&args, &root)
        }
    }) {
        Ok(output) => {
            println!("{output}");
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("{}", err.message);
            ExitCode::from(err.code)
        }
    }
}
