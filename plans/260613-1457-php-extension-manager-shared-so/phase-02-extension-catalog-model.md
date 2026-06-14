---
phase: 2
title: "Extension catalog model (Kit)"
status: done
priority: P1
effort: "2.5h"
dependencies: [1]
---

# Phase 2: Extension catalog model (Kit)

## Overview
Model the optional-extension layer: a descriptor per extension + a manifest of downloadable `.so`
(ext × php-version → url + sha256), plus installed-state resolution from `php -m`. Pure data/logic,
no lifecycle (Phase 3).

## Architecture
- `PHPExtension` (struct): `id` ("imagick"), `displayName`, `type` (cache/buffer/graphics/debugger/…),
  `summary`, `loadDirective` (`.extension` | `.zendExtension`), `isBuiltIn` (compiled into base →
  status-only, no install/uninstall).
- `PHPExtensionRelease` (struct): `extID`, `phpVersion`, `url`, `sha256`. `id = "<ext>-<phpver>"`.
- `PHPExtensionCatalog`: static `descriptors: [PHPExtension]` (built-in + optional) + static
  `manifest: [PHPExtensionRelease]` (from Phase 1). Methods:
  - `optional() -> [PHPExtension]` (installable shared set)
  - `release(_ extID:_ phpVersion:) -> PHPExtensionRelease?`
  - `installedExtensions(_ phpVersion:) -> Set<String>` via the existing `php -m` probe (reuse
    `PHPModules.list`).
  - `status(_ ext:_ phpVersion:) -> .builtIn | .installed | .installedButFailedToLoad | .available | .unavailable`.
    `.installedButFailedToLoad` = the ini + `.so` are on disk but `php -m` omits it (ABI/signature load
    failure) — distinguishes a real install from a silent no-op (red-team H2). The catalog reports the
    on-disk vs `php -m` discrepancy; the installer (Phase 3) captures the startup Warning detail.

## Related files
- Create: `KDWarmKit/Sources/Runtimes/PHPExtensionCatalog.swift`
- Read ref: `KDWarmKit/Sources/Runtimes/PHPModules.swift` (the `php -m` probe), `RuntimeCatalog.swift`
  (manifest pattern), `ServiceBinaryCatalog.swift` (release + sha256 pattern)
- Modify: `KDWarmKitTests/RuntimeManagementTests.swift` or new `PHPExtensionCatalogTests.swift`

## Implementation steps (TDD)
1. Tests first:
   - `testManifestWellFormed`: every release sha256 64-hex, url https, suffix matches `<ext>-<ver>`.
   - `testStatusBuiltInVsOptional`: a built-in (redis) → `.builtIn`; an optional with `php -m` present
     → `.installed`; optional absent but manifest has a release → `.available`; no release → `.unavailable`.
   - `testInstalledExtensionsParsesPhpM`: feed a fixture `php -m` output → resolves the installed set.
2. Implement `PHPExtension`, `PHPExtensionRelease`, `PHPExtensionCatalog` with the Phase-1 manifest data.
3. Wire `installedExtensions` to `PHPModules.list(version:paths:)` (already probes `php -m`).

## Success criteria
- [ ] Tests written first, fail before implement
- [ ] Catalog resolves built-in/installed/available/unavailable correctly
- [ ] Manifest entries well-formed (https, 64-hex sha256), URLs match Phase-1 artifacts
- [ ] KDWarmKit builds + tests green

## Risks
- Built-in list must match what's actually compiled in (drift if the base build changes) — derive the
  "built-in" flag from a fixed list documented next to the base EXTENSIONS in the build script.
- `php -m` reports module names that differ from the catalog id (e.g. "Zend OPcache") — normalize.

## Implementation status — DONE (2026-06-13)
- `KDWarmKit/Sources/Runtimes/PHPExtensionCatalog.swift` — `PHPExtension`, `PHPExtensionRelease`,
  `PHPExtensionLoadDirective` (`.module`=`extension` / `.zendExtension`), `PHPExtensionType`,
  `PHPExtensionStatus`, and `PHPExtensionCatalog` (optional/descriptor/release lookups,
  `installedExtensions` via `PHPModules.list`, pure + live `status(...)`, `sharedObjectExists`).
- `KDWarmKit/Sources/Runtimes/PHPExtensionManifest.swift` — 5 optional + 24 built-in descriptors,
  14-entry manifest (apcu/imagick/xdebug/grpc/swoole × versions; swoole has no 8.1).
- Tests: `KDWarmKitTests/PHPExtensionCatalogTests.swift` (9 tests, written first). Status logic uses an
  injectable `status(_:phpVersion:installed:soOnDisk:)` so it is tested without a real PHP binary.
- New files added to the KDWarmKit / KDWarmKitTests Xcode targets (project uses explicit refs).
- **Full KDWarmKit suite green: 148 tests, 0 failures.**
- Note for Phase 3: `.zendExtension` (xdebug) ini must use an ABSOLUTE `.so` path; `sharedObjectExists`
  already encodes the `runtimes/php/<v>/modules/<ext>.so` install layout the installer must write.

## Next steps
Phase 3 consumes the catalog to download + install/uninstall a release.
