#!/usr/bin/env python3
"""Cancelling a polkit dialog and pam_faillock, checked on a private PAM stack.

Every run uses pam_start_confdir() with copies of the stack and
`pam_faillock dir=<tmp>`: it never reads a password and never writes
/run/faillock. The cancel leg runs the real pam_unix (a failed conversation
returns before any password check); legs that type a password swap pam_unix
for pam_exec with a test password.

  default  checks the committed fixtures (Arch/CachyOS system-auth) and the
           optional override cortetsu/system/pam/polkit-1
  --live   reports whether the installed polkit-1 stack counts a cancel
"""
import os, pwd, re, shutil, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "scripts/features/fixtures/pam"
OVERRIDE = REPO / "cortetsu/system/pam/polkit-1"
UNIX_LINE = re.compile(r"^(auth\s+\[[^\]]*\]\s+)pam_unix\.so.*$", re.M)
PAM_SUCCESS, PAM_AUTH_ERR = 0, 7


class Probe:
    def __init__(self, tmp: Path):
        self.tmp = tmp
        self.bin = tmp / "probe"
        subprocess.run(["cc", "-o", str(self.bin), str(REPO / "scripts/features/pam-cancel-probe.c"), "-lpam"], check=True)
        self.tally = tmp / "tally"
        self.check = tmp / "check.sh"
        self.check.write_text('#!/bin/sh\nread -r p; [ "$p" = realm-ok ]\n')
        self.check.chmod(0o755)
        # pam_faillock never denies root; probe as an unprivileged account then.
        self.user = "nobody" if os.geteuid() == 0 else pwd.getpwuid(os.getuid()).pw_name

    def stack(self, name: str, files: dict, test_password: bool) -> Path:
        conf = self.tmp / name
        conf.mkdir()
        for file, text in files.items():
            text = text.replace("pam_faillock.so", f"pam_faillock.so dir={self.tally}")
            if test_password:
                text = UNIX_LINE.sub(lambda m: f"{m.group(1)}pam_exec.so expose_authtok quiet {self.check}", text)
            (conf / file).write_text(text)
        return conf

    def run(self, conf: Path, mode: str) -> tuple[int, int]:
        out = subprocess.run([str(self.bin), str(conf), "polkit-1", self.user, mode],
                             capture_output=True, text=True, check=True).stdout
        rc = int(re.search(r"pam_authenticate=(\d+)", out).group(1))
        tally = subprocess.run(["faillock", "--dir", str(self.tally), "--user", self.user],
                               capture_output=True, text=True).stdout
        return rc, len([l for l in tally.splitlines()[2:] if l.strip()])

    def reset(self):
        shutil.rmtree(self.tally, ignore_errors=True)
        self.tally.mkdir()


def files_for(system_auth: str, polkit: str) -> dict:
    return {"system-auth": system_auth, "polkit-1": polkit}


def auth_modules(text: str) -> list:
    """The auth lines with control fields blanked, to compare two stacks."""
    return [re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]", "[]", line)).strip()
            for line in text.splitlines() if line.startswith(("auth", "-auth"))]


def live_files() -> tuple[dict, str]:
    polkit = next(p for p in (Path("/etc/pam.d/polkit-1"), Path("/usr/lib/pam.d/polkit-1")) if p.exists())
    return files_for(Path("/etc/pam.d/system-auth").read_text(), polkit.read_text()), str(polkit)


def cancels_counted(probe: Probe, files: dict, name: str) -> int:
    probe.reset()
    conf = probe.stack(name, files, test_password=False)
    return probe.run(conf, "cancel")[1]


def main() -> int:
    for tool in ("cc", "faillock"):
        if not shutil.which(tool):
            print(f"SKIP: {tool} not installed")
            return 0
    failures = []

    def expect(label, got, want):
        ok = got == want
        print(f"{'PASS' if ok else 'FAIL'} {label}: {got}" + ("" if ok else f" (want {want})"))
        if not ok:
            failures.append(label)

    with tempfile.TemporaryDirectory() as tmp:
        probe = Probe(Path(tmp))
        if "--live" in sys.argv:
            files, source = live_files()
            n = cancels_counted(probe, files, "live")
            print(f"installed stack ({source}): a cancel {'COUNTS' if n else 'does not count'} for pam_faillock")
            if auth_modules(OVERRIDE.read_text()) != auth_modules(files["system-auth"]):
                print("WARN: /etc/pam.d/system-auth changed; review cortetsu/system/pam/polkit-1 before using it")
            return 0

        stock = files_for((FIXTURES / "system-auth").read_text(), (FIXTURES / "polkit-1").read_text())
        fixed = dict(stock, **{"polkit-1": OVERRIDE.read_text()})

        # The documented defect: the stock stack counts a cancel.
        expect("stock: one cancel adds one failure", cancels_counted(probe, stock, "stock"), 1)

        probe.reset()
        conf = probe.stack("fixed-unix", fixed, test_password=False)
        expect("override, real pam_unix: three cancels", [probe.run(conf, "cancel")[1] for _ in range(3)], [0, 0, 0])

        probe.reset()
        conf = probe.stack("fixed-test", fixed, test_password=True)
        expect("override: cancel then wrong password", [probe.run(conf, m)[1] for m in ("cancel", "answer:wrong")], [0, 1])
        expect("override: right password succeeds and resets", probe.run(conf, "answer:realm-ok"), (PAM_SUCCESS, 0))
        tallies = [probe.run(conf, "answer:wrong")[1] for _ in range(3)]
        expect("override: three wrong passwords still count", tallies, [1, 2, 3])
        expect("override: locked account refuses the right password", probe.run(conf, "answer:realm-ok")[0], PAM_AUTH_ERR)

        # The override copies system-auth's auth section; flag drift.
        expect("override auth modules match system-auth",
               auth_modules(OVERRIDE.read_text()), auth_modules(stock["system-auth"]))

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
