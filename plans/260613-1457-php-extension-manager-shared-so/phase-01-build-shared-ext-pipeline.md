---
phase: 1
title: "Build pipeline — shared-ext artifacts"
status: done
priority: P1
effort: "4-5h"
dependencies: []
---

## Implementation status

### 8.4 verified live (2026-06-13) — 5/6 exts pass
| ext | build .so | otool gate | php load | directive |
|-----|:-:|:-:|:-:|-----------|
| apcu | ✓ 135K | ✓ clean | ✓ `php -m` | extension |
| imagick | ✓ 22M | ✓ clean | ✓ `php -m` | extension |
| xdebug | ✓ 560K | ✓ clean | ✓ `php -v` (abs path) | zend_extension |
| grpc | ✓ | ✓ clean | ✓ `php -m` | extension |
| swoole | ✓ 18M | ✓ clean | ✓ `php -m` | extension |
| enchant | ✗ | — | — | — |

- **enchant does NOT build shared via spc**: `phpize` runs in `source/php-src` but enchant is a
  core-bundled ext (no standalone `config.m4` there) — spc has no build-shared recipe for it. Same
  "deferred / not spc-buildable" bucket as yaf/ioncube. → DROP from the spc shared set; revisit as a
  special-case track if needed.
- **Phase 3 finding:** `zend_extension=` needs an ABSOLUTE path in `conf.d/xdebug.ini`
  (`zend_extension=/abs/.../xdebug.so`) — it does NOT resolve via `extension_dir` like `extension=`.
### Full matrix verified live (2026-06-13) — 14 artifacts
| ext | 8.4 | 8.3 | 8.1 | directive |
|-----|:-:|:-:|:-:|-----------|
| apcu | ✓ | ✓ | ✓ | extension |
| imagick | ✓ | ✓ | ✓ | extension |
| xdebug | ✓ | ✓ | ✓ | zend_extension |
| grpc | ✓ | ✓ | ✓ | extension |
| swoole | ✓ | ✓ | ✗ | extension (CLI runtime) |

- **swoole does NOT build on PHP 8.1** (Swoole 6.x compile failure in ext/swoole) — real ecosystem
  constraint, not a pipeline bug. Catalog is per-(ext,version), so swoole is simply absent for 8.1.
- Every produced `.so` passed: build → otool relocatability gate → `php -m`/`php -v` load.
- Transient note: an `spc download` mirror hiccup (libtiff metadata) aborted 8.1's first run; a plain
  re-run resolved it. Reported as `8.1:BASE-BUILD` though the base php had already built — the failure
  was actually the shared-ext deps download (a label nuance, harmless).
- Pending: cross-patch ABI verify (H3, needs a published 8.4.y artifact), publish the 14 artifacts.

### Pipeline hardening (during 8.4 verify)
Three `set -e`/spc interaction bugs found + fixed: (1) a single combined `--build-shared=<all>` aborts
the whole batch on the first unbuildable ext → split into combined fast-path + per-ext retry; (2) each
retry's `make clean` wipes `buildroot/modules` → `harvest_modules()` copies each `.so` to `ext-collect/`
right after it builds; (3) `harvest_modules` returned the last test's exit code → added `return 0`. A
per-ext failure now writes a sentinel and leaves the base build exit 0; only the ext wrapper turns a
sentinel into a non-zero verdict.
- `scripts/lib-relocatable.sh` — added `package_extension` (top dir `<ext>/` holding `<ext>.so` →
  `php-ext-<ext>-<ver>-<arch>.tar.gz` + `.sha256`).
- `scripts/build-php-static.sh` — `SHARED_EXTENSIONS` (default `apcu,imagick,xdebug,enchant,grpc,swoole`),
  downloads shared-ext deps, `spc build … --build-shared` AFTER base packaging, per-ext otool gate +
  ad-hoc sign + package + JSONL manifest fragment; exits non-zero if any ext fails (base + passing
  exts still produced).
- `scripts/release/build-php-extensions.sh` — matrix wrapper (default 8.4/8.3/8.1), tolerates
  per-version failure, aggregates fragments → `php-ext-manifest.json`, prints publish hint.

Run to verify: `scripts/release/build-php-extensions.sh` then
`scripts/release/publish-artifacts.sh binaries-v1 <php-ext-*.tar.gz…>`.

# Phase 1: Build pipeline — shared-extension artifacts

## Overview
Produce one relocatable, ad-hoc-signed `.so` per optional extension per PHP version via
static-php-cli `--build-shared`, packaged as a downloadable artifact (`.so` + `.sha256`) and published
to the GitHub Release. This is the data layer the app's catalog (Phase 2) points at.

## Verified (spike)
- `spc build "<static-set>" --build-shared=<ext>` emits `buildroot/modules/<ext>.so`.
- imagick.so 22 MB, `otool -L` → only `/usr/lib/*` (portable); loads on the installed php (cross-build ABI).
- Build cost: heavy ext (imagick) ~10 min deps download + ~4 min compile per version (`--prefer-pre-built`).

## Decisions to lock
- **Shared set (spc `--build-shared`):** `apcu, imagick, xdebug, grpc, swoole` — all 5 VERIFIED on 8.4
  (build + otool gate + `php -m` load). enchant dropped (core-bundled, no spc build-shared recipe).
  - `grpc` is heavy (grpc+openssl+cares) — large `.so`, longer build; confirmed relocatable.
  - `swoole` (Swoole 6): async runtime used via CLI, NOT php-fpm — catalog it as a CLI-runtime ext
    (label accordingly in UI); still ships as a loadable `.so`.
- **Deferred / not in this pipeline:** `yaf` (no spc recipe — add custom ext or defer), `ioncube` +
  `sg16` (proprietary, vendor `.so` per exact PHP patch, redistribution license — separate later track).
- **Versions:** 8.4, 8.3, 8.1 (match the runtime manifest).
- **Artifact name:** `php-ext-<ext>-<phpver>-arm64.tar.gz` (top dir `<ext>/` containing `<ext>.so`),
  consistent with the runtime artifact convention so `RuntimeDownloader` can reuse the extract path.

## Related files
- Modify: `scripts/build-php-static.sh` (add `SHARED_EXTENSIONS` var + `--build-shared` + package each `.so`)
- Modify: `scripts/build-php-versions.sh` (loop already exists)
- Reuse: `scripts/lib-relocatable.sh` (`package_dir`), `scripts/release/publish-artifacts.sh`
- Create: `scripts/release/build-php-extensions.sh` (optional thin wrapper to build the shared set per version)

## Implementation steps
1. Add `SHARED_EXTENSIONS="${SHARED_EXTENSIONS:-imagick,xdebug,apcu}"` to `build-php-static.sh`.
2. After the main build, run `spc ... --build-shared=$SHARED_EXTENSIONS`; for each produced
   `buildroot/modules/<ext>.so`: run the **otool relocatability gate** (reuse the existing gate loop),
   `codesign --force --sign -`, then `package_dir` into `php-ext-<ext>-<ver>-arm64.tar.gz` + sha256.
3. Build all 3 versions × shared set; collect sha256 per (ext, version).
4. Publish via `publish-artifacts.sh binaries-v1 php-ext-imagick-8.4-arm64.tar.gz …` (clobber).
5. Emit a machine-readable manifest fragment (ext, version, url, sha256, loadDirective) to paste into
   the Swift catalog (Phase 2) — e.g. a small `jq`-friendly summary printed at the end.

## Success criteria
- [ ] Each shared `.so` (imagick/xdebug/apcu × 8.4/8.3/8.1) passes the otool gate (only `/usr/lib`,
  `/System`, `@rpath` refs)
- [ ] `.so` loads on the installed relocatable php (`php -d extension=… -m` shows it)
- [ ] **Cross-patch ABI verify (H3):** a `.so` built on 8.4.x loads into the PUBLISHED 8.4.y runtime
  artifact (different patch, same minor) → `php -m` lists it. Document: minor bump ⇒ rebuild exts; patch
  bump within a minor ⇒ no ext rebuild needed (same `ZEND_MODULE_API_NO`).
- [ ] Artifacts + sha256 published; URLs resolve; downloaded hash == emitted sha256

## Risks
- **ioncube** is proprietary (no spc recipe) — needs the vendor's prebuilt loader `.so` for the exact
  PHP version; verify it's relocatable + ABI-matching, else defer.
- **xdebug** is a Zend extension → `zend_extension=`; confirm spc builds it shared cleanly.
- Build time/space: full matrix re-downloads codec deps once per version (cached after).

## Next steps
Phase 2 turns the emitted (ext, version, url, sha256) into the Swift catalog.
