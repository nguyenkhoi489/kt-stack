---
title: "PHP Extension Manager (shared .so, Laragon-style)"
description: "Install/uninstall PHP extensions on-demand as shared .so over the static base — no variants, no version-identity change"
status: done
priority: P2
created: 2026-06-13
mode: tdd
source: plans/reports/spike-php-shared-extensions-260613-1423-feasibility-report.md
---

# PHP Extension Manager (shared .so)

## Overview
A Laragon/aaPanel-style per-extension Install/Uninstall manager. Extensions are an **independent `.so`
layer** over a fixed static base PHP; the PHP version identity ("8.4") is unchanged — no variants, no
DB/site migration. Feasibility proven end-to-end by the spike (apcu + imagick: load, extension_dir
override, portable `.so`, cross-build ABI; imagick.so 22 MB self-contained, zero Homebrew leak).

**Non-breaking choice:** keep the current compiled-in extensions as **built-in (status-only)** in the
manager; ADD the optional ones (imagick, xdebug, apcu, ioncube, …) as install/uninstall shared `.so`.
Trimming the base into shared is a later optimization, out of scope.

## Mechanism (verified by spike)
- Per-version layout: `runtimes/php/<v>/modules/<ext>.so` + `runtimes/php/<v>/conf.d/<ext>.ini`.
- php-fpm launched with `PHP_INI_SCAN_DIR=<v>/conf.d` (`LaunchAgentSpec.environment`) + `extension_dir`
  pointed at `<v>/modules` (a managed base ini). Each `conf.d/<ext>.ini` carries `extension=<ext>.so`
  (or `zend_extension=` for xdebug/ioncube).
- Status (✓/✗) from `php -m` (the Runtimes card already probes this).
- Phase-9: each `.so` Developer-ID-signed (same team as php-fpm) + notarized → Library Validation
  passes (spike showed a hardened php rejects a foreign-team `.so`).

## Phases
| Phase | Name | Status |
|-------|------|--------|
| 1 | [Build pipeline — shared-ext artifacts](./phase-01-build-shared-ext-pipeline.md) | Done (14 artifacts published) |
| 2 | [Extension catalog model (Kit)](./phase-02-extension-catalog-model.md) | Done (148 tests green) |
| 3 | [ExtensionInstaller + php-fpm wiring (Kit)](./phase-03-extension-installer.md) | Done (H1 proven, 153 tests) |
| 4 | [Extension Manager UI](./phase-04-extension-manager-ui.md) | Done (app builds) |
| 5 | [Signing / notarization + docs](./phase-05-signing-notarization-docs.md) | Done (dev ad-hoc verified; prod recipe scripted) |

## Key dependencies
- P2 (catalog) needs P1's published `.so` URLs + sha256.
- P3 (installer) needs P2 (catalog) + the php-fpm ini/scan-dir wiring.
- P4 (UI) needs P3 (installer) + the `php -m` probe (exists).
- P5 (signing) gates Phase-9 production; dev build uses ad-hoc `.so` (works today per spike).

## Extension catalog (user-confirmed set, categorized vs base + spc)

**Built-in (status-only ✓ — already compiled into base, no install/uninstall):**
fileinfo, opcache, memcached, redis, exif, intl, xsl, mbstring, xlswriter, pgsql, ssh2, xhprof,
protobuf, pdo_pgsql, readline, snmp, ldap, bz2, sysvshm, calendar, gmp, sysvmsg, zstd, event.

**Shared `.so` (install/uninstall — spc `--build-shared`, all VERIFIED on 8.4 2026-06-13):**
- `apcu` ✓, `imagick` ✓, `xdebug` ✓ (zend_extension, needs ABSOLUTE path in its ini), `grpc` ✓ (heavy:
  grpc+openssl+cares), `swoole` ✓ (Swoole 6 — ⚠️ async runtime, used via CLI `php server.php`, NOT under
  php-fpm; loads as an ext but the manager should label it "CLI runtime", not a per-site fpm ext).
- Each passed: build `.so` → otool relocatability gate (only /usr/lib /System @rpath) → `php -m` load.

**Special-case / deferred (not spc-buildable):**
- `enchant` — core-bundled in php-src (no standalone config.m4); spc has no build-shared recipe →
  dropped from the spc set (empirically verified 2026-06-13). Revisit as a special-case track if needed.
- `yaf` — open-source but no spc recipe → either add a custom ext to spc (extra work) or defer.
- `ioncube`, `sg16` (SourceGuardian) — proprietary loaders, vendor `.so` keyed to the EXACT PHP patch,
  redistribution license. Special-cased vendor artifacts (own patch-keyed catalog + license check),
  NOT in the spc pipeline. Defer to a follow-up phase.

Phasing: P1 builds the 5 verified spc-shared exts × {8.4,8.3,8.1}. enchant/yaf/ioncube/sg16 = separate later track.

## Red Team Review — 2026-06-13
Adversarial review (empirical — load path tested live on the installed 8.4 binary). Verdict:
**GO-WITH-CHANGES.** The core load path is PROVEN stronger than the spike: `PHP_INI_SCAN_DIR` +
`extension_dir` in a scan-dir ini + `extension=` works on the installed php AND coexists with the
existing `-c` php.ini. Findings applied to phases:

| # | Sev | Finding | Disposition |
|---|-----|---------|-------------|
| C1 | Critical | `RuntimeDownloader.installArchive` rejects a `.so` (executable-marker check) + `moveItem` would WIPE sibling exts | Ph3: new `installSharedObject` (no marker check, no sibling-wipe) |
| C2 | Critical | `php_admin_value[extension_dir]` is ineffective (modules load at MINIT before pool values) + unnecessary | Ph3: drop it → `extension_dir` in a `00-extension-dir.ini` scan-dir file |
| H1 | High | launchd→FPM `PHP_INI_SCAN_DIR` env hop UNPROVEN (only CLI tested) | Ph3: pre-commit the proven `-d extension=` programArguments fallback as Plan B; live FPM test = hard gate |
| H2 | High | `php -m` omission ≠ "not installed" → silent load failure looks like no-op | Ph2/Ph3: add `installedButFailedToLoad` status + capture startup Warning |
| H3 | High | cross-PATCH ABI load asserted, not proven | Ph1: add a build-on-8.4.x → load-into-published-8.4.y verify |
| M1 | Med | ioncube doesn't fit | CUT from scope (above) |
| M2 | Med | `10-opcache.ini` ordering is fictional (opcache compiled-in, no `.so`) | Ph3: removed |
| M3 | Med | uninstall must RESTART (not reload) to unload; version-uninstall must clear ext dirs | Ph3: restart on uninstall + ext-dir teardown |
| L1 | Low | effort optimistic | Ph1 4–5h, Ph3 6–8h |
| L2 | Low | `PHPModules` cache stale after install | Ph4: `invalidate(version:)` after every change |
| L3 | Low | new native-code surface = release-pipeline compromise × N artifacts | Ph5: document; keep no `disable-library-validation` |

**Top 3 before Phase 1:** C1+C2 redesign install path · H1 pre-commit `-d` fallback · H2 silent-fail status.

## Code review (2026-06-14) — findings fixed
Evidence-based review of P1–P4. Fixes applied + re-verified (153 Kit tests, app builds):
- **C1 (Critical):** `installedExtensions` used a BARE `php -m` (compiled scan dir, which the relocatable
  build lacks) → every installed optional ext mis-resolved to `.installedButFailedToLoad`. Fixed:
  `PHPModules.loadedModules(version:scanDir:)` runs `php -m` with `PHP_INI_SCAN_DIR` = the ext conf.d;
  catalog uses it; the sheet probes once per refresh + the pure status overload. Proven live (bare
  `php -m` omits imagick; with the scan dir it appears).
- **H2 (High):** `reloadPHPPool` = `kickstart -k` keeps the old job definition → a pool bootstrapped
  before the `PHP_INI_SCAN_DIR` env never loads exts. Fixed: `restartPHPPool` (bootout + re-bootstrap,
  full master re-exec) on the install/uninstall path.
- **M2:** modules/ + conf.d/ now created `0700` (matches the app-support tree invariant).
- **M3:** load-failure detection also matches "Failed loading" (Zend extension), not only "Unable to load".
- **L1:** the "n/a" tooltip is version-agnostic (no hard-coded 8.1).
- Accepted as-is: H1 (post-C1 `refresh()` recomputes the correct status; the captured Warning is still
  surfaced), M1 (`verifyLoad` reads stdout-then-stderr — safe for tiny `php -m` output), shell manifest
  aggregation is intentionally cumulative across versions.

## Out of scope
- Trimming the compiled-in base into shared (non-breaking now; optimize later).
- Per-extension version pinning (ext `.so` is ABI-locked to its PHP minor — one `.so` per ext×version).
- Windows/x86_64 (arm64 only, consistent with the rest).

## TDD note
P2/P3 (Kit logic — catalog resolution, ini generation, install/uninstall file ops, extension_dir
wiring) are TDD. P1 (build script) + P4 (UI) verified by build/run, not unit tests.
