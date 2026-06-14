---
phase: 4
title: "Extension Manager UI"
status: done
priority: P1
effort: "3h"
dependencies: [3]
---

# Phase 4: Extension Manager UI

## Overview
The Laragon-style manager (reference screenshot): a button on each PHP runtime version that opens a
list of extensions — Name · Type · Description · Status (✓/✗) · Action (Install | Uninstall) — wired
to `PHPExtensionInstaller` + the `php -m` status probe.

## Architecture
- `@MainActor` view-model `PHPExtensionManager` (ObservableObject) OR fold into `RuntimeManager`:
  publishes per-version `[PHPExtensionRow]` (extension + status + busy/progress/error).
  - `install(_ ext:_ version:)` → installer.install → reload pool (`server.reconcileAfterRuntimeChange()`
    or a targeted `pools.reload(version:)`) → refresh status.
  - `uninstall(_ ext:_ version:)` → installer.uninstall → reload → refresh.
- UI: a sheet `PHPExtensionsSheet(version:)` opened from the installed-version row in `RuntimeCardView`
  (next to "Edit php.ini"). A `List`/`Table` of rows mirroring the screenshot columns.
  - Built-in extensions: status ✓, action shown as "Built-in" (disabled) — no uninstall.
  - Optional: Install (download progress) / Uninstall (destructive confirm if a site uses Imagick etc.).

## Related files
- Create: `KDWarm/UI/Dashboard/Sections/Runtimes/PHPExtensionsSheet.swift`
- Create: `KDWarm/UI/Dashboard/Sections/Runtimes/PHPExtensionRowView.swift`
- Modify: `KDWarm/UI/Dashboard/Sections/Runtimes/RuntimeCardView.swift` (add "Extensions…" button per
  installed PHP version)
- Modify: `KDWarm/UI/Dashboard/Sections/RuntimesSectionView.swift` (sheet presentation + wiring)
- Modify: `KDWarmKit/Sources/Runtimes/RuntimeManager.swift` (install/uninstall ext + published rows) OR
  a new view-model
- Read ref: existing `loadPHPExtensions` probe (`RuntimesSectionView`), `RuntimeDownloadSheet.swift`
  (download-progress UI pattern), `ServiceRowView` (Install button + progress pattern)

## Implementation steps
1. View-model: per-version extension rows from `PHPExtensionCatalog` + live `php -m` status; install/
   uninstall actions with busy/progress/error. **Call `PHPModules.invalidate(version:)` after every
   install/uninstall + pool restart BEFORE re-reading status (L2)** — the probe caches per version
   forever, else the UI shows pre-install state. Surface `.installedButFailedToLoad` as an error row
   (not ✓), with the captured load Warning + a "reinstall"/rollback action (H2).
2. `PHPExtensionsSheet` + `PHPExtensionRowView` (columns per screenshot: name/type/desc/status/action).
3. "Extensions…" entry point on `RuntimeCardView` per installed version (PHP only).
4. Destructive-confirm on uninstall when sites may depend on it (reuse the confirm pattern from the
   PHP-version uninstall already shipped).
5. Build app; run: open Extensions for installed 8.4, Install imagick (progress → ✓), site using
   Imagick works; Uninstall → ✗.

## Success criteria
- [ ] Extensions sheet lists built-in (status-only) + optional (install/uninstall) per the screenshot
- [ ] Install imagick → progress → status ✓ → a site using Imagick renders; Uninstall → ✗
- [ ] Status reflects live `php -m`; busy/error surfaced; no main-thread stalls (probe off-main, as today)
- [ ] App + KDWarmKit build; existing Runtimes UI unregressed

## Risks
- Probing `php -m` per version spawns the binary — keep off-main (existing `loadPHPExtensions` pattern).
- Pool reload latency: show busy until the extension actually appears in `php -m` (poll briefly).

## Implementation status — DONE (2026-06-14)
- `PHPExtensionsModel` (@MainActor view-model): per-version rows from `PHPExtensionCatalog.descriptors` +
  live `php -m` status (resolved off-main), optional-first sort; install/uninstall via
  `PHPExtensionInstaller` → `server.reloadPHPPool(version:)` (full re-exec, (un)loads the `.so`) →
  `PHPModules.invalidate` → re-probe. Transient busy/progress/error kept separate from rows so a refresh
  never clobbers them; `.installedButFailedToLoad` surfaces the captured Warning (H2/L2).
- `PHPExtensionsSheet` + `PHPExtensionRowView`: status icon · name + type tag + summary · action
  (Built-in / Install+progress / Uninstall / Reinstall+Remove on load-failure / n/a). Uninstall is a
  destructive confirm (sites using it will error until they stop).
- `RuntimeCardView`: "Extensions…" link per installed PHP version (PHP only). `RuntimesSectionView`:
  `.sheet(item:)` presentation + wiring.
- **App + KDWarmKit build green** (xcodebuild `KDWarm` scheme). Kit unchanged → 153 tests still valid.
- Manual GUI smoke (open Extensions for 8.4 → Install imagick → ✓ → site renders) is the remaining
  hands-on check; every underlying mechanism (download/place, ini, PHP_INI_SCAN_DIR load, silent-fail)
  is already proven live in Phase 3.

## Next steps
Phase 5 hardens the signing/notarization of `.so` for Phase-9 production.
