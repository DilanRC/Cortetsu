mod common;
use common::*;
use serde_json::{Value, json};
use std::{fs, process::Command};

// Processes: RSS travels as exact bytes, and the smaps breakdown is read
// only for the PID and start time asked for. A reused PID, an ended process
// and an unreadable smaps_rollup never turn into numbers.
#[test]
fn process_memory_is_exact_bytes_and_detail_is_identity_checked() {
    let t = setup();
    let proc = t.path().join("proc");
    fs::create_dir_all(&proc).unwrap();
    fs::write(
        proc.join("meminfo"),
        "MemTotal: 15571296 kB\nMemAvailable: 6000000 kB\n",
    )
    .unwrap();
    fs::write(proc.join("uptime"), "90000.00 1.00\n").unwrap();
    fs::write(proc.join("stat"), "cpu 1 0 1 100 0 0 0 0 0 0\n").unwrap();
    let process = |pid: &str, rss_pages: u64, smaps: Option<&str>| {
        let dir = proc.join(pid);
        fs::create_dir_all(&dir).unwrap();
        let fields = format!(
            "{pid} (qs worker) S 1 {pid} {pid} 0 -1 0 0 0 0 0 10 5 0 0 20 0 49 0 7777 0 {rss_pages} 0"
        );
        fs::write(dir.join("stat"), fields).unwrap();
        fs::write(dir.join("comm"), "qs\n").unwrap();
        // stat's rss drifts; statm is the exact count the table must use.
        fs::write(
            dir.join("statm"),
            format!("900000 {} 5000 10 0 80000 0\n", rss_pages - 256),
        )
        .unwrap();
        fs::write(dir.join("cmdline"), "qs\0-n\0").unwrap();
        fs::write(
            dir.join("status"),
            "Name:\tqs\nVmRSS:\t  481928 kB\nVmSwap:\t   44278 kB\n",
        )
        .unwrap();
        if let Some(s) = smaps {
            fs::write(dir.join("smaps_rollup"), s).unwrap();
        }
    };
    // The rollup differs from status (it adds swapped shared memory to
    // Swap) so the test proves Rss and Swap come from the same rollup read.
    let rollup = "55d0-7ffd ---p 00000000 00:00 0 [rollup]\nRss:  481936 kB\nPss:  356853 kB\nPss_Anon:  300186 kB\nPss_File:   56668 kB\nPss_Shmem:  0 kB\nShared_Clean: 60000 kB\nPrivate_Clean:  1000 kB\nPrivate_Dirty:  299000 kB\nSwap:  44285 kB\nSwapPss:  44270 kB\nAnonHugePages:  45056 kB\n";
    process("4242", 120482, Some(rollup));
    process("4343", 1000, None);
    let probe = |args: &[&str]| {
        let mut all = vec!["cortetsu-hardware-probe"];
        all.extend_from_slice(args);
        output(
            Command::new(env!("CARGO_BIN_EXE_cortetsu-hardware-runtime"))
                .args(&all)
                .env("XDG_RUNTIME_DIR", t.path().join("run"))
                .env("CORTETSU_SYSFS_ROOT", t.path().join("sys"))
                .env("CORTETSU_PROCFS_ROOT", &proc)
                .env(
                    "PATH",
                    format!("{}:/usr/bin:/bin", t.path().join("bin").display()),
                )
                .output()
                .unwrap(),
        )
    };
    let p = probe(&["--process-detail", "4242:7777"]);
    let row = p["processes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["pid"] == 4242)
        .unwrap()
        .clone();
    let page = nix::unistd::sysconf(nix::unistd::SysconfVar::PAGE_SIZE)
        .unwrap()
        .unwrap() as u64;
    assert_eq!(row["rss_bytes"], json!((120482 - 256) * page));
    assert_eq!(row["start_ticks"], 7777);
    assert_eq!(row["name"], "qs");
    let d = &p["process_detail"];
    assert_eq!(d["status"], "ok");
    assert_eq!(d["smaps"], "ok");
    assert_eq!(d["pss_bytes"], json!(356853_u64 * 1024));
    assert_eq!(d["pss_anon_bytes"], json!(300186_u64 * 1024));
    assert_eq!(d["private_bytes"], json!(300000_u64 * 1024));
    assert_eq!(d["rss_bytes"], json!(481936_u64 * 1024));
    assert_eq!(d["swap_bytes"], json!(44285_u64 * 1024));
    assert_eq!(d["swap_pss_bytes"], json!(44270_u64 * 1024));
    assert_eq!(d["anon_huge_bytes"], json!(45056_u64 * 1024));

    // Without smaps_rollup: RSS and swap from status, the rest unknown.
    let d =
        probe(&["--process-detail", "4343:7777", "--top-processes", "1"])["process_detail"].clone();
    assert_eq!(d["status"], "ok");
    assert_eq!(d["smaps"], "unavailable");
    assert_eq!(d["pss_bytes"], Value::Null);
    assert_eq!(d["anon_huge_bytes"], Value::Null);
    assert_eq!(d["rss_bytes"], json!(481928_u64 * 1024));
    assert_eq!(d["swap_bytes"], json!(44278_u64 * 1024));

    // Same PID, another start time: a different process.
    let d = probe(&["--process-detail", "4242:1"])["process_detail"].clone();
    assert_eq!(d, json!({"pid":4242,"start_ticks":1,"status":"replaced"}));
    let d = probe(&["--process-detail", "999:7777"])["process_detail"].clone();
    assert_eq!(d["status"], "gone");
    assert_eq!(probe(&[])["process_detail"], Value::Null);
    let bad = run(&t, &["cortetsu-hardware-probe", "--process-detail", "0:5"]);
    assert_eq!(bad.status.code(), Some(2));

    // A reused PID is a new process: its CPU share starts from its own ticks,
    // never from the counters of the process that held the PID before.
    fs::write(
        proc.join("4242/stat"),
        "4242 (qs worker) S 1 4242 4242 0 -1 0 0 0 0 0 900000 5 0 0 20 0 49 0 9999 0 1000 0",
    )
    .unwrap();
    let reused = probe(&[])["processes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["pid"] == 4242)
        .unwrap()
        .clone();
    assert_eq!(reused["start_ticks"], 9999);
    assert_eq!(reused["cpu"], 0.0, "{reused}");
}
