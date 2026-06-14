---
phase: 5
title: "Signing / notarization + docs"
status: done
priority: P2
effort: "2h"
dependencies: [1, 3]
---

# Phase 5: Signing / notarization + docs

## Overview
Make the `.so` extension layer correct under macOS code-signing: ad-hoc for the dev build (works today
per spike), Developer-ID-signed + notarized per `.so` for Phase-9 production. Document the whole flow.

## Verified (spike) — the constraint
A hardened-runtime php-fpm REJECTS a foreign-team `.so` ("different Team IDs", Library Validation). So:
- **Dev build (today):** php-fpm is ad-hoc, not hardened → loads ad-hoc `.so`. No action needed beyond
  the build script's existing `codesign --force --sign -` on each `.so`.
- **Phase-9 (notarized, hardened php-fpm):** each `.so` MUST be Developer-ID-signed with the **same
  Team ID as php-fpm** → Library Validation passes naturally. Do NOT grant php-fpm
  `disable-library-validation` (it is the JIT runtime — preserve its posture).

## Related files
- Modify: `scripts/build-php-static.sh` (already ad-hoc signs each `.so` — Phase 1)
- Modify: `scripts/release/sign-all-binaries.sh` (extend to Developer-ID sign ext `.so` with
  `jit-runtime`/base entitlements as appropriate, inside-out)
- Modify: `scripts/release/notarize.sh` usage (notarize each ext `.so` artifact — bare `.so` → zip →
  notarytool submit; cannot staple a loose `.so`, Gatekeeper checks online first run, like the runtime
  artifacts)
- Modify: `docs/signing-and-notarization-guide.md` (new section: signing + notarizing extension `.so`;
  add to the §0.5 go-live gate that ext `.so` join the notarization matrix)
- Modify: `KDWarmKit/Sources/Runtimes/RuntimeCatalog.swift`-style manifest: bump `.so` sha256 after
  re-signing (re-sign changes the hash → must update the extension manifest, like the PHP artifacts)

## Implementation steps
1. Dev path: confirm Phase-1 ad-hoc `.so` load through php-fpm end-to-end (covered by Phase 3 verify).
2. Phase-9 path (when Team ID exists): Developer-ID sign each ext `.so` (same identity as php-fpm),
   notarize the `.so` artifacts, **bump sha256** in the extension manifest, rebuild app.
3. Docs: extend the signing guide + the §0.5 security go-live gate to include ext `.so`.

## Success criteria
- [ ] Dev: ad-hoc `.so` loads under the (ad-hoc) php-fpm via the manager (Phase 3/4)
- [ ] Phase-9 recipe documented: Developer-ID + notarize per `.so`, same team as php-fpm, sha256 bump
- [ ] `docs/signing-and-notarization-guide.md` updated; §0.5 gate references ext `.so`
- [ ] No use of `disable-library-validation` on php-fpm

## Threat model (red-team L3)
Installing a `.so` = downloading + loading NATIVE code into php-fpm (the JIT runtime). Transit integrity
is covered (`RuntimeDownloader.requireHTTPS` + `ChecksumVerifier`, pinned to YOUR sha256). Same-team
Developer-ID signing (this phase) makes Library Validation reject a FOREIGN `.so` (real defense vs a
third party dropping a `.so`), NOT just Gatekeeper theater. The residual NEW surface is
release-pipeline compromise × N more signed artifacts — same trust class as the already-signed
php-fpm/redis/etc., just more of them. Mitigation = the same notarization-matrix discipline; do NOT
grant php-fpm `disable-library-validation`.

## Risks
- Re-signing changes `.so` sha256 → the extension manifest must be re-bumped + app rebuilt (same gotcha
  as the runtime artifacts; document loudly).
- Notarizing many `.so` (N ext × M version) inflates the release pipeline — script the loop.

## Implementation status — DONE (2026-06-14)
- **Dev path (criterion 1): confirmed** — each ext `.so` is ad-hoc signed by build-php-static.sh
  (`Signature=adhoc`) and loads under the ad-hoc php-fpm (proven live in Phase 3). No action needed.
- **Production recipe (criteria 2-3): scripted + documented.**
  - `scripts/release/sign-extensions.sh` (new) — Developer-ID sign each `.so` (same Team as php-fpm,
    `--options runtime --timestamp`, NO entitlements — ignored for a loaded library), re-`package_dir`,
    re-emit the manifest with new sha256, print notarize/publish hints. Decision: NOT added to
    `sign-all-binaries.sh` (that signs only the .app bundle; on-demand artifacts sign at publish time —
    matches the existing runtime-artifact convention, doc §4).
  - `docs/signing-and-notarization-guide.md`: §0 table + new §4.1 (ext `.so` recipe) + §6 checklist +
    references. Key gotcha documented: ext sha256 bumps into **PHPExtensionManifest.swift** (not
    RuntimeCatalog), and `RuntimeDownloader.installSharedObject` verifies it before placing the `.so`.
- **Criterion 4: verified** — no `disable-library-validation` in `entitlements/` or `project.yml`;
  jit-runtime carries only `allow-jit`. Same-Team signing is the defense (red-team L3).
- Note: actual Developer-ID signing not run here — the machine lacks the private key (guide "Trạng thái
  hiện tại"); the recipe is ready for go-live once the `.p12` is imported.

## Next steps
Feature complete. Future: trim compiled-in base into the shared layer; ini-toggle for built-ins
(opcache.enable, xdebug.mode); per-extension version pinning if ever needed.
