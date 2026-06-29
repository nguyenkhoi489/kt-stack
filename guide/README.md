# KTStack User Guide

KTStack is a native macOS menu-bar app for running a local web development environment — your own open-source alternative to Herd, Valet, and Laragon. It serves your projects at `https://<name>.test` with trusted HTTPS, multiple PHP and Node versions, bundled databases, email testing, log viewing, and public sharing through Cloudflare Tunnel. No Docker required. macOS 13 or later.

This guide is written for **people who use the app**, not for developers of KTStack. Each topic is a separate page so you can jump straight to what you need.

## How to read this guide

If you are brand new, read pages `00` through `06` in order — that takes you from install to your first running site. After that, open any topic on demand.

## Table of contents

### Getting started
- [00 — Introduction](00-introduction.md) — what KTStack does and core concepts
- [01 — Install & first run](01-install-and-first-run.md) — install, onboarding, helper approval, enabling DNS
- [02 — Interface overview](02-interface-overview.md) — menu bar and dashboard layout

### Working with sites
- [03 — Managing sites](03-managing-sites.md) — create, import, edit, and remove sites
- [04 — PHP & runtimes](04-php-and-runtimes.md) — install PHP/Node versions, set defaults, per-project versions
- [05 — HTTPS & certificates](05-https-and-certificates.md) — secure sites with local TLS and trust the CA

### Services & data
- [06 — Services](06-services.md) — start/stop/restart, install, reset service data
- [07 — Database basics](07-database-basics.md) — connect, create databases, browse and edit tables
- [08 — Database query & ER diagram](08-database-query-and-er-diagram.md) — SQL editor, history, schema diagram
- [09 — Database backup & restore](09-database-backup-and-restore.md) — backups, restore, import/export

### Testing & debugging
- [10 — Email testing with Mailpit](10-email-testing-mailpit.md) — capture and inspect outgoing mail
- [11 — Logs & dumps](11-logs-and-dumps.md) — live log tailing and capturing `dump()` / `dd()`
- [12 — API Tester](12-api-tester.md) — send requests and inspect responses inside the app
- [14 — Xdebug & debugging](14-xdebug-and-debugging.md) — enable Xdebug and configure your editor

### Sharing & terminal
- [13 — Sharing with Cloudflare Tunnel](13-sharing-cloudflare-tunnel.md) — expose a site publicly with a QR code
- [15 — Shell integration](15-shell-integration.md) — use per-project PHP/Node versions from the terminal

### Configuration & maintenance
- [16 — Settings & preferences](16-settings-and-preferences.md) — TLD, sites root, update channel
- [17 — Uninstall & reset](17-uninstall-and-reset.md) — remove KTStack cleanly
- [18 — Troubleshooting & FAQ](18-troubleshooting-and-faq.md) — common problems and fixes

## A note on terms

- **Site** — a local project served at `https://<name>.test`.
- **TLD** — the domain suffix for local sites (default `.test`).
- **Service** — a background process KTStack manages (Nginx, PHP-FPM, MySQL, and so on).
- **Runtime** — a language version you can install and switch between (PHP, Node).
