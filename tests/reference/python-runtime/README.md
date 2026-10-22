# Python compatibility oracles

These are frozen test inputs from commit `ce9523ea8a403ba106162cd8118b264897104db8`.
`MANIFEST.json` records the original paths and exact SHA-256 digests. The files
are not launchers, installed helpers, build dependencies, or a runtime fallback.

Native differential tests may execute these references in disposable homes.
The historical integration scripts are retained so developer-only regression
tests can reproduce the old installation in a temporary copy. The production
installer and all first-party runtime entry points use Rust/Go owners.

Behavior intentionally tightened by the native transaction contracts (for
example refusing corrupt DND state instead of resetting it) is tested as an
explicit safety change, separately from unchanged CLI/output parity.
