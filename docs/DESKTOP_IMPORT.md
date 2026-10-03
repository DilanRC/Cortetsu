# Desktop import

Cortetsu can snapshot the active user configuration for Kitty, Zsh, GTK and Qt into the repository without adopting whole configuration directories as opaque symlinks.

The importer is intentionally conservative:

- only regular UTF-8 files up to 2 MiB are imported;
- backups, temporary files, logs and symlinks are skipped;
- files that look like they contain passwords, API keys, tokens, client secrets or private keys block `apply`;
- missing applications are not an error when at least one selected group has importable configuration;
- generated files live under `dotfiles/imported/desktop/home/` so a new snapshot can replace the previous one atomically;
- `~/.config/kdeglobals` is reported as user-owned and skipped so KDE can keep writing application preferences to a regular file;
- only `dotfiles/manifest.toml` and `dotfiles/imported/desktop/` are staged by `--commit`; unrelated worktree changes remain untouched.

## Groups

- `kitty` -> tag `terminal`
- `zsh` -> tag `user-shell`
- `gtk` -> tag `toolkit`
- `qt` -> tag `toolkit`

The `personal` profile enables all three tags.

## Usage

Preview all groups:

```bash
cortetsu-import-desktop plan
```

Preview one or more groups:

```bash
cortetsu-import-desktop plan --group kitty --group zsh
```

Create the repository snapshot and a local commit:

```bash
cortetsu-import-desktop apply --commit
```

After reviewing and pushing the commit, a normal `cortetsu install` adopts the imported files into the immutable dotfiles generation with the same backup-before-adopt behavior as the rest of Cortetsu.

The generated manifest block is delimited by `BEGIN/END CORTETSU DESKTOP IMPORT`. Re-run the importer instead of editing that block manually.
