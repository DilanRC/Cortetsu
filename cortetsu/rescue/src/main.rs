use cortetsu_rescue::{
    Roots, current, plan_rollback, previous,
    transaction::{recover, rollback_pointers},
};
use cortetsu_rescue::{exec_read, helper_bundle};
use serde_json::json;
use std::env;
use std::io::{self, Read};
use std::path::Path;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<_> = env::args().collect();
    let is_explicit_rollback =
        args.len() == 3 && args[1] == "rollback" && args[2] == "--acknowledge-unmanaged-helpers";
    let is_helper_stage =
        args.len() == 4 && args[1] == "helpers-stage" && args[2] == "--experimental";
    let is_helper_verify = args.len() == 3 && args[1] == "helpers-verify";
    if !is_explicit_rollback
        && !is_helper_stage
        && !is_helper_verify
        && (args.len() != 2
            || !matches!(
                args[1].as_str(),
                "verify" | "status" | "plan-rollback" | "recover" | "exec"
            ))
    {
        eprintln!(
            "usage: cortetsu-rescue verify|status|plan-rollback|recover|exec|rollback --acknowledge-unmanaged-helpers|helpers-stage --experimental ABSOLUTE_SOURCE|helpers-verify BUILD_ID"
        );
        return ExitCode::from(2);
    }
    let roots = match Roots::from_env() {
        Ok(roots) => roots,
        Err(e) => {
            eprintln!("ERROR: {e}");
            return ExitCode::from(1);
        }
    };
    if args[1] == "exec" {
        let mut bytes = Vec::new();
        let read = io::stdin().take(65537).read_to_end(&mut bytes);
        if read.is_err() {
            eprintln!("ERROR: invalid stdin");
            return ExitCode::from(1);
        }
        let response = exec_read::handle(&bytes, &roots);
        println!("{response}");
        return if response["verified"] == true {
            ExitCode::SUCCESS
        } else {
            ExitCode::from(1)
        };
    }
    let result = match args[1].as_str() {
        "verify" => current(&roots).map(|snapshot| json!({"verified":true,"current":snapshot})),
        "status" => current(&roots).map(|snapshot| {
            let older = previous(&roots).ok();
            json!({"verified":true,"current":snapshot,"previous":older})
        }),
        "plan-rollback" => plan_rollback(&roots).map(|(now,target)| {
            json!({"operation":"ROLLBACK_PLAN_ONLY","current":now,"target":target,"applied":false})
        }),
        "recover" => recover(&roots).map(|receipt| json!({"verified":true,"recovery":receipt})),
        "rollback" => rollback_pointers(&roots, is_explicit_rollback).map(|receipt| json!({"verified":true,"result":receipt,"helpers_restored":false})),
        "helpers-stage" => helper_bundle::stage(&roots, Path::new(&args[3]))
            .map(|bundle| json!({"verified":true,"bundle":bundle,"activated":false})),
        "helpers-verify" => helper_bundle::verify(&roots, &args[2])
            .map(|bundle| json!({"verified":true,"bundle":bundle,"activated":false})),
        _ => unreachable!(),
    };
    match result {
        Ok(value) => {
            println!("{value}");
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("ERROR: {e}");
            ExitCode::from(1)
        }
    }
}
