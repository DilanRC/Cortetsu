# Estado vigente (2026-11-06)

La auditoría Task 22 que sigue es una instantánea histórica del 2026-09-05,
no un inventario del código activo. Desde entonces el runtime Python de
migración se retiró y sus oráculos quedaron bajo
`tests/reference/python-runtime/`. El staging de Cortetsu copia `base/`,
`modules/`, `components/`, `utils/` y servicios propios; no instala ni ejecuta
los migradores archivados.

El contrato actual `cortetsu/contracts/patch-debt.tsv` solo conserva su
encabezado: no hay parches upstream activos que registrar. Las referencias del
texto histórico a `cortetsu/bin/check-bottom-hub-target.py` y a que
`test-patch-debt-audit.py` forma parte de `scripts/cortetsu test` ya no son
ciertas. Las pruebas que necesitan aquel checker lo cargan desde el archivo de
referencia. `scripts/features/test-patch-debt-audit.py` se ejecuta de forma
independiente; no forma parte del comando normal de tests.

No se eliminó nada por esta actualización: se corrigieron las referencias de
las pruebas para que siguieran apuntando a los oráculos congelados y se
verificó que el runtime generado no depende de ellos.

---

# Patch debt status (Task 22 audit)

Audited 2026-09-05. Scope: the 10 patches originally owned by this session. Every other
patch in `caelestia/patches/` (Notifications, CoreConfig, Network/BT/Power/Tray,
Regional, Launcher, Screenshot/Record, Overlay-host) is being worked by parallel
sessions and was left untouched here.

## Method

For each patch:

1. Read the diff and its target path in `caelestia/patches/MANIFEST.tsv`.
2. `grep -rn` for the component/property the patch introduces across
   `cortetsu/modules/` and the shell composition scripts.
3. Cross-checked against `cortetsu/bin/check-bottom-hub-target.py` (the
   Bottom Hub v4 migration's semantic contract checker) and
   `scripts/features/test-bottom-hub-v4.py`, which assert on these exact
   patches' content and on their presence in `MANIFEST.tsv`.

## Result: 5 remain ACTIVE

The working hypothesis going in was that some of these patches might be dead,
superseded by the Bottom Hub v4 migration. The evidence points the other way:
six of the ten patches (`Shortcuts`, `sidebar/Wrapper`, `bar/BarWrapper`,
`bar/popouts/Wrapper`, `bar/popouts/ClipWrapper`, `utilities/Wrapper`) are not
legacy scaffolding *superseded by* Bottom Hub v4 -- they are the mechanism
*that implements* Bottom Hub v4: they retire the old top bar's visuals
(`disabled: true`, `shouldBeVisible: false`, `implicitWidth: 0`) and re-anchor
sidebar/utilities/popouts to the bottom edge instead. Deleting any of them
would break the shell (bar would reappear) and fail
`scripts/features/test-bottom-hub-v4.py` immediately (it reads several of
these patch files directly and asserts on their content, and asserts
`modules__bar__BarWrapper.qml.patch` stays listed in `MANIFEST.tsv`).

The remaining base infrastructure is now first-party (`shell.qml`, `Hypr`, and
`Paths`); only seven Bottom Hub patches remain active.

| Patch | Capability | Active consumers | Replacement | Status |
|---|---|---|---|---|
| `shell.qml.patch` | Retired: `cortetsu/shell.qml` now owns the composition root and the build copies it directly | `cortetsu/shell.qml`, `build-runtime.sh` | first-party shell composition | **RETIRED** |
| `components__misc__CustomShortcut.qml.patch` | Retired: `cortetsu/components/misc/CustomShortcut.qml` now owns the `cortetsu` app id directly | `scripts/features/test-shortcut-namespace.py` | none | **RETIRED** |
| `services__Hypr.qml.patch` | Retired: `cortetsu/services/Hypr.qml` now owns the compatibility surface and delegates to `CortetsuHypr` | `cortetsu/services/Hypr.qml` | first-party Hypr service | **RETIRED** |
| `utils__Paths__Config.qml.patch` | Retired: `cortetsu/utils/Paths.qml` now owns all XDG paths | `cortetsu/utils/Paths.qml` | first-party Paths utility | **RETIRED** |
| `modules__Shortcuts.qml.patch` | Super key -> IPC `customDock launcher` (native launcher toggle) instead of the old `ShellState.forActive().launcher` toggle; Super+N opens sidebar+utilities together | `check_shortcuts()` in `check-bottom-hub-target.py`, asserted verbatim in `test-bottom-hub-v4.py` line 51-53 | replaces old in-process `ShellState` toggle -- this patch **is** the replacement | **ACTIVE** (Bottom Hub v4 engine) |
| `modules__sidebar__Wrapper.qml.patch` | Re-anchors the sidebar to the bottom edge (`anchors.fill`, capped `520x430` card) instead of the old right-edge slide-in; tags `objectName: "cortetsuBottomNotificationCenter"` | `check_sidebar()` in `check-bottom-hub-target.py` | replaces the old right-edge `Tokens.sizes.sidebar`-driven layout -- this patch **is** the replacement | **ACTIVE** (Bottom Hub v4 engine) |
| `modules__bar__BarWrapper.qml.patch` | Forces the legacy top bar fully invisible and zero-width (`disabled: true`, `exclusiveZone: 0`, `shouldBeVisible: false`, `implicitWidth: 0`) | `check_bar()` in `check-bottom-hub-target.py`; `test-bottom-hub-v4.py` line 47 asserts this patch stays in `MANIFEST.tsv` ("retiro de barra nativa") | Bottom Hub itself is the replacement UI; this patch is the retirement switch, not dead code | **ACTIVE** (Bottom Hub v4 engine -- retires the old bar) |
| `modules__bar__popouts__Wrapper.qml.patch` | Adds `bottomAttached`/`bottomOffset`/`bottomAnchorCenter` state so popouts (volume/network/etc) can dock under the Bottom Hub instead of the old top bar | `check_popout_wrapper()` in `check-bottom-hub-target.py` | none, extends the same file | **ACTIVE** (Bottom Hub v4 engine) |
| `modules__bar__popouts__ClipWrapper.qml.patch` | Positions the popout clip against `bottomAnchorCenter` and drops the old horizontal/vertical slide `Behavior` animations (popups now anchor instantly under the hub button that opened them) | `check_popout_clip()` in `check-bottom-hub-target.py`; `test-bottom-hub-v4.py` reads this patch directly (lines 15, 55, 57) | replaces old top-bar-relative positioning | **ACTIVE** (Bottom Hub v4 engine) |
| `modules__utilities__Wrapper.qml.patch` | Drops the old sidebar-adjacency layout (`horizontalStretch`, `sidebarLerp`, `attachedToSidebar` state) in favor of a bottom-anchored independent panel | `check_utilities()` in `check-bottom-hub-target.py` | replaces old sidebar-relative layout | **ACTIVE** (Bottom Hub v4 engine) |

## Deletions made

None. All 10 patches audited are active; zero patches or MANIFEST.tsv lines
were removed.

## Regression gate

`scripts/features/test-patch-debt-audit.py` (wired into `scripts/cortetsu
test`) pins this result: it asserts each of the 10 patches stays in
`MANIFEST.tsv`, has a grep-able real consumer, and that
`check-bottom-hub-target.py` keeps validating the six Bottom-Hub-engine
patches. If a future cleanup pass wants to remove one of these, this test
will need to be updated deliberately -- it will not fail silently.

---

# Design system reduction status (Task 8 audit)

Audited 2026-09-05, same session.

## Baseline count

```
grep -rn 'Colours\.\|Tokens\.\|StyledRect\|StyledText\|MaterialIcon' cortetsu/modules/ caelestia/patches/*.patch | wc -l
# => 99
```

Breaking that down:

```
grep -rn 'Colours\.\|Tokens\.\|StyledRect\|StyledText\|MaterialIcon' cortetsu/modules/ | wc -l
# => 0
grep -rln 'Colours\.\|Tokens\.\|StyledRect\|StyledText\|MaterialIcon' caelestia/patches/*.patch
# => modules__launcher__ContentList.qml.patch, modules__drawers__ContentWindow.qml.patch,
#    modules__launcher__AppList.qml.patch, modules__sidebar__Wrapper.qml.patch,
#    modules__launcher__Content.qml.patch, modules__utilities__Wrapper.qml.patch,
#    modules__launcher__Wrapper.qml.patch, modules__drawers__Panels.qml.patch,
#    modules__drawers__Panels__cortetsu-shell-state.qml.patch
```

All 99 hits are in `caelestia/patches/*.patch` -- diffs against the upstream
`caelestia-shell` tree (launcher, drawers, sidebar/utilities wrappers), which
is explicitly out of scope for this pass (launcher and drawers are large /
owned by other sessions per the task brief; sidebar/utilities patch context
lines still show unchanged upstream `Tokens.*` references around the hunks
this session did touch, but the patch's own added/changed lines carry no
legacy token -- confirmed above by direct read).

**`cortetsu/modules/` -- the actual scope for Task 8 -- has zero occurrences.**
Every one of the 38 files there that touches design tokens already goes
through `CortetsuDesign.js` via the first-party primitives:

- `cortetsu/modules/CortetsuSurface.qml`
- `cortetsu/modules/CortetsuText.qml`
- `cortetsu/modules/CortetsuIcon.qml`

These already exist (checked before creating anything new) and are consumed
by 38 files under `cortetsu/modules/`.

## Conclusion

No migration work was done because there is nothing left to migrate in
`cortetsu/modules/`. Forcing a migration here would mean inventing a task
that doesn't exist, which the brief explicitly says not to do. This is
consistent with the repo's own history: Task 8-style reduction already
happened as part of the Bottom Hub v4 first-party rewrite (the same rewrite
audited in Task 22 above) -- `cortetsu/modules/` was rebuilt clean and never
picked the legacy tokens back up.

## Regression gate

`scripts/features/test-design-system-migration-status.py` (wired into
`scripts/cortetsu test`) pins this: it fails if any file under
`cortetsu/modules/` reintroduces `Colours.`, `Tokens.`, `StyledRect`,
`StyledText`, or `MaterialIcon`, and fails if any of the three first-party
primitives goes missing.
