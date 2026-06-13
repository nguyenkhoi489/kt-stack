---
phase: 3
title: "ExtensionInstaller + php-fpm wiring (Kit)"
status: done
priority: P1
effort: "6-8h"
dependencies: [2]
---

# Phase 3: ExtensionInstaller + php-fpm wiring

## Overview
Lifecycle: download an extension `.so` → place under the version's managed modules dir → write its
`conf.d/<ext>.ini` → restart the version's php-fpm pool so the extension loads. Uninstall reverses it.
Drive loading via `PHP_INI_SCAN_DIR` + an `extension_dir` scan-dir ini (NOT pool `php_admin_value`).

## Verified (spike + red-team, on the INSTALLED 8.4 binary)
- Static core dlopen of a `--build-shared` `.so` works; cross-build ABI OK.
- `PHP_INI_SCAN_DIR=<dir>` overrides the compiled (nonexistent) scan dir AND coexists with the existing
  `-c <php.ini>` (both parsed; scan-dir wins precedence) → the per-version php.ini is unaffected.
- `extension_dir` set in a LOW-numbered scan-dir ini correctly resolves `extension=` in a higher-numbered
  ini — **no `php_admin_value[extension_dir]` needed** (it's ineffective: modules load at MINIT before
  pool values apply).
- A failed/missing/ABI-mismatched `.so` → **non-fatal startup Warning**, process continues, `php -m`
  simply omits it (basis for the silent-fail handling below).

## STILL UNPROVEN (Phase-3 hard gate)
The launchd → FPM env hop: does `PHP_INI_SCAN_DIR` survive `launchctl bootstrap gui/<uid>` →
`EnvironmentVariables` → `php-fpm -F`? CLI is proven; FPM-under-launchd is not. **Plan B (pre-committed):**
if the env hop fails, append `-d extension_dir=<modules>` + `-d extension=<ext>.so` per installed ext to
`programArguments` (the spike's proven `-d` path). Step 4 is go/no-go.

## Architecture
- Per-version managed dirs (new): `runtimes/php/<v>/modules/` (the `.so`) + `runtimes/php/<v>/conf.d/`
  (extension inis). Add `AppSupportPaths.phpModulesDir(version:)` + reuse/extend `phpIniDir(version:)`.
- **`installSharedObject` (NEW — do NOT reuse `installArchive`)**: `installArchive`
  (`RuntimeDownloader.swift:76`) hard-requires an EXECUTABLE marker and rolls back if absent → a `.so`
  (not +x) is rejected; and its `moveItem` removes an existing `dest` first → would WIPE sibling exts.
  New method reuses download → `ChecksumVerifier.verify` → extract, then places the single `<ext>.so`
  into the shared `modules/` dir WITHOUT touching siblings, no marker check.
- `PHPExtensionInstaller` (Kit, `Sendable`):
  - `install(_ ext:_ phpVersion:)`: `installSharedObject` → write `conf.d/20-<ext>.ini`
    (`extension=<ext>.so` or `zend_extension=<ext>.so`) → caller RESTARTS the pool → **verify load**.
  - `uninstall(_ ext:_ phpVersion:)`: remove `conf.d/20-<ext>.ini` (+ `modules/<ext>.so`) → caller
    **RESTARTS** the pool (a `dlopen`'d `.so` stays loaded until restart; reload is insufficient).
  - **Load verification (silent-fail, H2):** after restart, re-probe `php -m` AND capture php startup
    stderr (run `php -d extension_dir=… -d extension=<so> -m` capturing stderr). If the ext is absent
    OR a load Warning was emitted → return `.installedButFailedToLoad` (ABI/signature) + offer rollback.
    Note `PHPModules.probe` currently discards stderr (`PHPModules.swift:42`) — the installer needs its
    own stderr-capturing probe.
- **php-fpm wiring** (scan-dir, NOT pool php_admin_value):
  - Write `conf.d/00-extension-dir.ini` containing `extension_dir = <v>/modules` (loaded before the
    `20-<ext>.ini` files).
  - Launch php-fpm with `PHP_INI_SCAN_DIR=<v>/conf.d` via `LaunchAgentSpec.environment`
    (`PHPFPMController.spec()` currently passes none → add it). Coexists with the existing `-c` php.ini.
  - opcache is COMPILED-IN (no `.so`, no ordering ini needed); xdebug's `zend_extension=xdebug.so` loads
    after the built-in opcache automatically. Verify xdebug+opcache coexist (xdebug disabling JIT is
    expected, not a bug).

## Related files
- Create: `KDWarmKit/Sources/Runtimes/PHPExtensionInstaller.swift`
- Modify: `KDWarmKit/Sources/Runtimes/RuntimeDownloader.swift` (add `installSharedObject` — C1)
- Modify: `KDWarmKit/Sources/Process/AppSupportPaths.swift` (`phpModulesDir(version:)`, `phpExtConfDir(version:)`)
- Modify: `KDWarmKit/Sources/Services/PHPFPMController.swift` (spec `environment["PHP_INI_SCAN_DIR"]`;
  Plan-B `-d` args if the env hop fails) — NOT `PHPFPMPoolWriter` (no `extension_dir` there, C2)
- Modify: `KDWarmKit/Sources/Runtimes/PHPModules.swift` (a stderr-capturing probe variant for load-verify)
- Read ref: `RuntimeDownloader.swift:76` (the marker check to avoid), `ChecksumVerifier.swift`
- Modify: tests (`PHPExtensionInstallerTests.swift`)

## Implementation steps (TDD)
1. Tests first:
   - `testIniGenerationExtensionVsZend`: imagick → `extension=imagick.so`; xdebug → `zend_extension=xdebug.so`.
   - `testInstallPlacesSoKeepsSiblings`: installing ext B does NOT remove ext A's `.so` (guards the C1
     sibling-wipe); `conf.d/20-<ext>.ini` + `modules/<ext>.so` present.
   - `testUninstallRemovesIniAndSo`.
   - `testExtensionDirIniWritten`: `conf.d/00-extension-dir.ini` contains `extension_dir = <modules>`.
   - `testSpecCarriesIniScanDirEnv`: php-fpm spec `environment["PHP_INI_SCAN_DIR"] == <conf.d>`.
2. Implement `installSharedObject` (C1) + paths helpers + `PHPExtensionInstaller` (ini write/remove,
   load-verify probe).
3. Wire spec `PHP_INI_SCAN_DIR` env; ensure existing pools still start (regression). Call
   `PHPModules.invalidate(version:)` after install/uninstall (L2) before re-reading status.
4. **HARD GATE — verify live under FPM/launchd (H1):** install imagick on an installed 8.4, RESTART the
   pool, confirm `php -m` (via the running pool, e.g. a script through that pool) shows imagick + a site
   using Imagick renders. If the `PHP_INI_SCAN_DIR` env did NOT propagate, switch to Plan B (`-d`
   programArguments) and re-verify. Do not mark done until a real Imagick request works.
5. Silent-fail (H2): force an ABI-mismatched `.so`, confirm the installer returns
   `.installedButFailedToLoad` (not a false success).

## Success criteria
- [ ] Tests written first, fail before implement
- [ ] install → `.so` in modules/ (siblings intact), ini written, pool RESTART loads it (`php -m`)
- [ ] uninstall → ini + .so gone, pool RESTART unloads it
- [ ] Load driven by `PHP_INI_SCAN_DIR` + `00-extension-dir.ini` (or Plan-B `-d`); existing pools/php.ini unaffected
- [ ] Failed load surfaces `.installedButFailedToLoad`, not silent success
- [ ] M2 launch signature check still passes (`.so` ad-hoc signed; gate is on the php-fpm binary)

## Risks
- **H1 — launchd→FPM env hop unproven** (the one load-bearing unknown). Step 4 is go/no-go; Plan B
  (`-d extension=` args) is pre-committed and proven at CLI level.
- **Reload ≠ unload:** uninstall (and a failed install retry) RESTART the pool, not reload.
- Uninstalling an ext a site depends on → runtime error in that site (destructive confirm in UI, Phase 4).
- Version-uninstall must tear down `modules/` + `conf.d/` (verify the existing PHP-version-uninstall path
  removes the whole `runtimes/php/<v>/` tree — M3).

## Implementation status — DONE (2026-06-13)
- `AppSupportPaths`: `phpModulesDir(version:)` (`runtimes/php/<v>/modules`) + `phpExtConfDir(version:)`
  (`runtimes/php/<v>/conf.d`) — inside the runtime tree so version-uninstall tears them down (M3).
- `RuntimeDownloader.installSharedObject` (C1): download → verify → extract → place ONLY `<ext>.so`
  into the shared modules dir, replacing just that file (no sibling wipe, no executable-marker check).
- `PHPExtensionInstaller`: `iniContent` (extension= / absolute zend_extension=), `writeExtensionDirIni`
  (`00-extension-dir.ini`), `placeSharedObject` (no sibling wipe), `finishInstall` (`20-<ext>.ini`),
  `install` (download→ini→verify), `uninstall` (ini+.so removal + `PHPModules.invalidate`), `verifyLoad`
  (stderr+stdout capture → `.installedButFailedToLoad` on silent fail, H2).
- `PHPFPMController.spec`: now sets `environment["PHP_INI_SCAN_DIR"] = phpExtConfDir(version)` (C2 — NOT
  pool `php_admin_value`); `-c php.ini` unchanged.
- Tests: `PHPExtensionInstallerTests.swift` (5, written first). **Full KDWarmKit suite green: 153 tests.**

### Hard gates — empirically PROVEN (live, build-cache 8.4 fpm)
- **H1 (launchd→FPM env hop): PROVEN.** Bootstrapped php-fpm via `launchctl` with plist
  `EnvironmentVariables[PHP_INI_SCAN_DIR]` (the exact `spec()` mechanism) → `php-fpm -m` lists imagick;
  baseline without the env omits it. → **Plan B (`-d` programArguments) NOT needed.**
- Scan-dir load: `00-extension-dir.ini` (`extension_dir`) + `20-imagick.ini` (`extension=`) loads under
  php-fpm with no startup warning.
- **H2 (silent fail): PROVEN.** A garbage `.so` → non-fatal "Unable to load dynamic library" warning,
  `php -m` omits it → `verifyLoad` returns `.installedButFailedToLoad` + the captured warning.
- xdebug (`zend_extension`, absolute path) + compiled-in opcache coexist (verified Phase 1 `php -v`).

### Note for Phase 4
The UI must RESTART the pool after install/uninstall — `PHPFPMController.reload()` (`launchctl kickstart -k`)
is a full process re-exec, which loads/unloads the `.so` (a graceful config-reload would not).

## Next steps
Phase 4 puts the manager UI on top of install/uninstall + status.
