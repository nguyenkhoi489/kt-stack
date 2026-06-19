# KTStack

Native macOS local development environment for PHP and Node.js.

Run local websites with trusted HTTPS, automatic `.test` domains, databases, mail testing, logs, and public sharing — all from a native SwiftUI application.

> Open-source alternative to Laravel Herd, Valet and Laragon for macOS.

![KTStack Sites dashboard](assets/readme/dashboard-sites.png)

## Features

* ✅ Automatic `.test` domains
* ✅ Trusted local HTTPS
* ✅ Nginx + PHP-FPM management
* ✅ PHP 8.1 / 8.3 / 8.4
* ✅ Node.js runtimes
* ✅ MySQL, PostgreSQL, Redis and MongoDB
* ✅ Built-in Mailpit
* ✅ Per-site log viewer
* ✅ Cloudflare Tunnel sharing
* ✅ Native SwiftUI interface
* ❌ No Docker required

---

## Why KTStack?

Setting up a local development environment on macOS often means combining multiple tools:

* Web server
* PHP runtime manager
* Database services
* Local HTTPS certificates
* DNS configuration
* Mail testing
* Public preview links

KTStack brings all of those pieces together into a single native application.

Create a site and instantly access:

```text
https://my-project.test
```

with HTTPS, databases, logs, and mail testing already configured.

---

## Screenshots

### Sites

![Sites dashboard](assets/readme/dashboard-sites.png)

### Services

![Services dashboard](assets/readme/dashboard-services.png)

### Runtimes

![Runtimes dashboard](assets/readme/dashboard-runtimes.png)

### Menu Bar

![Menu bar dropdown](assets/readme/menubar-dropdown.png)

---

## Current Feature Set

| Area           | Status                                                              |
| -------------- | ------------------------------------------------------------------- |
| Native app     | Menu-bar SwiftUI app                                                |
| Local sites    | Park/import sites with automatic `.test` domains                    |
| HTTPS          | Trusted local TLS certificates                                      |
| Web server     | Nginx virtual hosts and PHP-FPM pools                               |
| PHP            | On-demand PHP 8.1 / 8.3 / 8.4                                       |
| Other runtimes | Node.js                                                             |
| Services       | Nginx, PHP-FPM, dnsmasq, MySQL, PostgreSQL, Redis, MongoDB, Mailpit |
| Database UI    | MySQL, PostgreSQL, SQLite, MongoDB                                  |
| Mail           | Mailpit integration                                                 |
| Logs           | Per-service and per-site log viewer                                 |
| Sharing        | Cloudflare Tunnel public links                                      |
| Updates        | Sparkle auto-update support                                         |

---

## Cloudflare Tunnel Sharing

KTStack can expose a local site through a temporary `trycloudflare.com` URL.

Useful for:

* Client reviews
* Mobile device testing
* QA verification
* Temporary demos

KTStack automatically creates a dedicated tunnel vhost and forwards the correct host and HTTPS metadata so frameworks like Laravel and WordPress behave correctly behind the tunnel.

---

## Architecture

Application data is stored under:

```text
~/Library/Application Support/KDWarm/
```

Core components:

| Component    | Purpose                  |
| ------------ | ------------------------ |
| KTStack.app  | Native macOS application |
| KDWarmKit    | Core framework           |
| KDWarmHelper | Privileged helper        |
| project.yml  | XcodeGen source of truth |

---

## Local Development

Requirements:

* macOS 13+
* Xcode
* XcodeGen

Install XcodeGen:

```bash
brew install xcodegen
```

Generate project:

```bash
xcodegen generate
```

Run tests:

```bash
xcodebuild \
  -project KDWarm.xcodeproj \
  -scheme KDWarmKit-Tests \
  -destination 'platform=macOS' \
  test
```

Build:

```bash
xcodebuild \
  -project KDWarm.xcodeproj \
  -scheme KDWarm \
  -destination 'platform=macOS' \
  -configuration Release \
  build
```

---

## Build DMG

```bash
scripts/release/build-dmg.sh \
  ~/Library/Developer/Xcode/DerivedData/KDWarm-*/Build/Products/Release/KTStack.app \
  ./KTStack.dmg
```

Release signing and notarization playbook:
`docs/signing-and-notarization-guide.md`

---

## Repository Layout

```text
KDWarm/                 Application target
KDWarmKit/Sources/      Core framework
KDWarmHelper/           Privileged helper
KDWarmKitTests/         Unit tests
scripts/                Build & release scripts
spikes/                 Experiments
assets/readme/          README assets
```

---

## Notes

* macOS only
* Runtime downloads are checksum verified
* MongoDB is installed on demand
* Generated projects and local artifacts are ignored

---

## Project Status

KTStack is an active side project built to explore Swift, SwiftUI, macOS development, local infrastructure tooling, and developer experience.

Feedback, issues, and pull requests are welcome.

⭐ If KTStack helps your workflow, consider starring the repository.
