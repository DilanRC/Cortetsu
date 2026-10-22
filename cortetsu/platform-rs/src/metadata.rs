use crate::util::*;
use serde_json::json;
use std::path::Path;
pub fn run(command: &str, a: &Args) -> Result<i32> {
    a.check(&[])?;
    match command {
        "build-metadata" => {
            if a.positional.len() != 3 {
                return fail("usage: build-metadata <path> <build-id> <revision>");
            }
            write_json(
                Path::new(&a.positional[0]),
                &json!({"schema":1,"sourceProject":"Cortetsu","buildId":a.positional[1],"builtAt":timestamp(),"repositoryRevision":a.positional[2]}),
            )?;
        }
        "metadata" => {
            let p = Path::new(a.positional.first().ok_or("metadata path required")?);
            let data = json(p)?;
            if a.positional.len() == 1 {
                println!("{}", serde_json::to_string(&data)?);
            } else {
                for field in &a.positional[1..] {
                    let mut v = &data;
                    for part in field.split('.') {
                        v = &v[part];
                    }
                    println!(
                        "{}",
                        if v.is_null() {
                            "unknown".into()
                        } else {
                            v.as_str()
                                .map(str::to_owned)
                                .unwrap_or_else(|| v.to_string())
                        }
                    );
                }
            }
        }
        "show-generation" => {
            if a.positional.len() != 2 {
                return fail("usage: show-generation <label> <BUILD.json>");
            }
            let label = &a.positional[0];
            match json(Path::new(&a.positional[1])) {
                Ok(v) => {
                    println!(
                        "  {label}_source={}@{}\n  {label}_revision={}",
                        v["sourceProject"].as_str().unwrap_or("unknown"),
                        v["repositoryRevision"].as_str().unwrap_or("unknown"),
                        v["repositoryRevision"].as_str().unwrap_or("unknown")
                    );
                }
                Err(_) => println!("  {label}_metadata=invalid"),
            }
        }
        "verify-shell-metadata" => {
            let v = json(Path::new(
                a.positional.first().ok_or("BUILD.json path required")?,
            ))?;
            if v["schema"] != 1
                || v["sourceProject"] != "Cortetsu"
                || !v["repositoryRevision"]
                    .as_str()
                    .is_some_and(|x| !x.is_empty())
            {
                return fail("invalid Cortetsu BUILD.json");
            }
        }
        _ => return fail("unknown metadata command"),
    };
    Ok(0)
}
