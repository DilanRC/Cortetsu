# Desktop runtime

`cortetsu-desktop-runtime <helper> <arguments...>` provides the native runtime for:

- `cortetsu-calendar`: status, events, calendar selection and desktop OAuth.
- `cortetsu-pomodoro`: state, configuration, controls and the session-owned daemon.
- `cortetsu-emoji`: picker, dump and Unicode catalog download.
- `cortetsu-startup`: process/XDG/systemd inventory and explicit startup controls.
- `cortetsu-area-capture` and `cortetsu-record`: capture and recorder lifecycle.
- `cortetsu-scheme`, `cortetsu-scheme-posthook`, `cortetsu-wallpaper-colours`
  and `cortetsu-wallpaper-color-daemon`: schemes and wallpaper colors.
- `cortetsu-connectivity-secret` (also accepts `ConnectivitySecret.py` as a
  dispatch name): persist and verify a WPA-PSK/SAE secret through NetworkManager.

No operation starts Python or loads a Python interpreter. The old source remains
only as a development reference. External programs remain domain owners: e.g.
ImageMagick converts wallpaper pixels, gpu-screen-recorder records video,
secret-tool accesses Secret Service, and systemctl manages user units. The NM
credential path uses native zbus directly; credentials enter on stdin and are
never put in process arguments or error messages. `CREDENTIAL_SAVED` is emitted
only after persistent settings and secret readback both match.

## Generation resources

Installed launchers set `CORTETSU_RESOURCE_ROOT` to the paired immutable shell
generation. Schemes and the bundled emoji catalog are read there. Source tools
can explicitly set `CORTETSU_REPO_ROOT` to a checkout; installed binaries never
embed or automatically discover the build checkout. The remaining fallback is
`CORTETSU_RUNTIME_ROOT/current`, canonicalized to the selected shell generation.
Missing/unreadable scheme catalogs fail rather than silently crossing generations.
A downloaded emoji catalog is saved in the user's cache, never in a generation.

State follows XDG locations. State replacement uses same-directory temporary
files, rename, file/parent fsync and private modes; state locks reject symlinks.
Pomodoro serializes phase transitions and sleeps until a deadline or signal.
Recorder controls verify PID start time and process identity before signalling;
a live or unrelated process cannot be mistaken for a completed recording. XDG
startup edits retain backups and check the resulting enabled/disabled state.

## Verification

Run `cargo test --locked` and `cargo clippy --all-targets --locked -- -D warnings`.
Tests use temporary XDG directories, fixture executables, a private D-Bus daemon
and no desktop session or real Google account. Integration tests require
`dbus-daemon`, normal `/proc` PID visibility and Unix-domain sockets. The secret
fixture checks preservation of unrelated NM settings, permanent PSK flags,
readback failure and refusal to overwrite enterprise credentials.

Standalone fixtures compare 1,152 Material roles across 16 seed/mode combinations
against the former Python helper. Six pixel datasets also compare Wu clusters,
all quantized colors/populations and selected source colors against the legacy
C++ extension. This includes the Linux RNG seed, convergence limit and integer
truncation at its delta-E threshold. No Python packages are needed to run these
Rust tests. `src/quantizer.rs` adapts the Google Material Color Utilities algorithm
under Apache-2.0; its license and the materialyoucolor binding's MIT notice are
included alongside this file.

OAuth server calls are bounded and access is read-only. Unit and fixture tests
cover validation, normalization, cache retention and secret handling; they do
not authenticate a real Google account or mutate a running NetworkManager.
