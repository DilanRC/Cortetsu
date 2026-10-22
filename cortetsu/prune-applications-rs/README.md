# F5 Rust parity candidate: cortetsu-prune-applications

Opt-in Rust implementation of the first-party Python desktop-file quarantiner.
It is **not installed** or used by the shell. Accepts only `--dry-run` or no
arguments, and considers only `XDG_DATA_HOME/applications/*.desktop`. Quarantine
is under `XDG_DATA_HOME/cortetsu/quarantine/applications`; no application
packages or system `.desktop` directories are touched. No shell is executed.

Cloud CI verifies the Rust binary against the original Python command using
two independent disposable XDG home directories, including invalid `Exec`
fields, `Type=Link`, duplicate `Exec` keys, and a full quarantine operation.

Known compatibility limits before cutover: nonstandard INI multiline parsing,
platform-dependent `shlex` quoting, symlinked desktop entries, files changing
mid-operation, and error messages outside the normal command contract. No
live owner replacement is authorized until these and physical QA pass.
