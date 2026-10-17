//! `watch` reports a hotplug and leaves nothing behind when it is killed.
//!
//! A fake udevadm stands in for the real one: it records its pid, waits for
//! the test to plug a keyboard into a fake sysfs, prints one udev line and
//! then blocks like the real monitor does.

use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

fn write(path: &Path, contents: &str) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, contents).unwrap();
}

fn plug(sys: &Path, port: &str, event: &str) {
    let input = sys.join(format!("devices/pci0000:00/usb1/{port}/{port}:1.0/0003:1A2C:2124.0001/input/input9"));
    write(&sys.join(format!("devices/pci0000:00/usb1/{port}/idVendor")), "1a2c\n");
    write(&input.join("name"), "SEMICO USB Keyboard\n");
    write(&input.join("phys"), "usb-0000:00:14.0-2/input0\n");
    write(&input.join("id/bustype"), "0003\n");
    write(&input.join("id/vendor"), "1a2c\n");
    write(&input.join("id/product"), "2124\n");
    write(&input.join("capabilities/ev"), "120013\n");
    write(&input.join("capabilities/key"), "fffffffe\n");
    fs::create_dir_all(input.join(event)).unwrap();
    std::os::unix::fs::symlink(input.join(event), sys.join("class/input").join(event)).unwrap();
}

fn alive(pid: &str) -> bool {
    // A zombie has exited; only a running or sleeping process counts.
    fs::read_to_string(format!("/proc/{pid}/stat"))
        .map(|stat| !stat.split_whitespace().nth(2).is_some_and(|state| state == "Z"))
        .unwrap_or(false)
}

#[test]
fn hotplug_is_reported_and_udevadm_dies_with_the_watcher() {
    let base = std::env::temp_dir().join(format!("cortetsu-watch-{}", std::process::id()));
    let _ = fs::remove_dir_all(&base);
    let sys = base.join("sys");
    fs::create_dir_all(sys.join("class/input")).unwrap();
    let go = base.join("go");
    let pidfile = base.join("udevadm.pid");
    let fake = base.join("udevadm");
    write(
        &fake,
        &format!(
            "#!/bin/sh\necho $$ > {pid}\nwhile [ ! -e {go} ]; do sleep 0.05; done\n\
             echo 'UDEV  [1.0] add      /devices/pci0000:00/usb1/1-2 (input)'\nexec sleep 60\n",
            pid = pidfile.display(),
            go = go.display()
        ),
    );
    Command::new("chmod").arg("+x").arg(&fake).status().unwrap();

    let mut watcher = Command::new(env!("CARGO_BIN_EXE_cortetsu-keybinds"))
        .arg("watch")
        .env("CORTETSU_SYSFS", &sys)
        .env("CORTETSU_UDEV_DATA", base.join("udev"))
        .env("CORTETSU_UDEVADM", &fake)
        .env("CORTETSU_HYPRCTL", "false")
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut lines = BufReader::new(watcher.stdout.take().unwrap()).lines();
    let initial: serde_json::Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    assert_eq!((initial["protocol"].as_u64(), initial["event"].as_str()), (Some(2), Some("initial")));
    assert_eq!(initial["keyboards"].as_array().unwrap().len(), 0);

    let started = Instant::now();
    plug(&sys, "1-2", "event9");
    write(&go, "");
    let changed: serde_json::Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    let latency = started.elapsed();
    assert_eq!(changed["event"], "changed");
    assert_eq!(changed["keyboards"][0]["kind"], "usb");
    assert!(latency < Duration::from_secs(2), "hotplug took {latency:?}");
    eprintln!("hotplug latency: {latency:?}");

    let udevadm = fs::read_to_string(&pidfile).unwrap().trim().to_owned();
    assert!(alive(&udevadm));
    // SIGKILL: no handler runs, only the kernel's parent-death signal.
    watcher.kill().unwrap();
    watcher.wait().unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    while alive(&udevadm) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(20));
    }
    assert!(!alive(&udevadm), "udevadm {udevadm} outlived the watcher");
    let _ = fs::remove_dir_all(PathBuf::from(&base));
}
