#!/usr/bin/env bash
# Generate NOTICES.txt: attribution + license identifiers for every redistributed component, plus a
# written offer of source for the copyleft ones (GPL/SSPL). KDWarm is distributed free / open-source,
# so GPL/SSPL redistribution is compatible — this file satisfies the attribution + source-offer
# obligation. Runnable now (does not need signing). Edit the table below as the bundled set changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/NOTICES.txt}"

# component | license (SPDX-ish) | upstream source
COMPONENTS=(
  "nginx|BSD-2-Clause|https://nginx.org/en/download.html"
  "PHP (7.4/8.1/8.3/8.4, php-fpm)|PHP-3.01|https://www.php.net/downloads"
  "dnsmasq|GPL-2.0-or-later|https://thekelleys.org.uk/dnsmasq/"
  "mkcert|BSD-3-Clause|https://github.com/FiloSottile/mkcert"
  "Mailpit|MIT|https://github.com/axllent/mailpit"
  "MySQL (mysqld)|GPL-2.0-only|https://dev.mysql.com/downloads/mysql/"
  "PostgreSQL|PostgreSQL|https://www.postgresql.org/ftp/source/"
  "Redis (>=7)|SSPL-1.0 / RSALv2|https://github.com/redis/redis"
  "Node.js|MIT (+deps)|https://nodejs.org/dist/"
  "Go (on-demand)|BSD-3-Clause|https://go.dev/dl/"
  "Sparkle|MIT|https://github.com/sparkle-project/Sparkle"
)
# Copyleft components that require a written offer of source.
SOURCE_OFFER=("dnsmasq" "MySQL (mysqld)" "Redis (>=7)")

{
  echo "KDWarm — Third-Party Notices"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "KDWarm is distributed free of charge as open-source software."
  echo
  echo "== Redistributed components =="
  for row in "${COMPONENTS[@]}"; do
    IFS='|' read -r name lic src <<< "$row"
    printf -- "- %s\n    License: %s\n    Source:  %s\n" "$name" "$lic" "$src"
  done
  echo
  echo "== Written offer of source (GPL / SSPL components) =="
  echo "For the following components, KDWarm provides the complete corresponding source code."
  echo "The exact upstream version + build recipe for each is in scripts/build-*-relocatable.sh and"
  echo "scripts/build-php-versions.sh; request a copy at the project repository or the contact below."
  for c in "${SOURCE_OFFER[@]}"; do echo "  - $c"; done
  echo
  echo "Contact: <set release contact / repository URL here>"
  echo
  echo "Full license texts for each component are available at the Source URLs above and are included"
  echo "with the corresponding upstream distributions."
} > "$OUT"

echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
