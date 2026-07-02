#!/usr/bin/env bash
# Generate NOTICES.txt: attribution + license identifiers for every redistributed component, plus a
# written offer of source for the copyleft ones (GPL/SSPL). KTStack is distributed free / open-source,
# so GPL/SSPL redistribution is compatible — this file satisfies the attribution + source-offer
# obligation. Runnable now (does not need signing). Edit the table below as the bundled set changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/NOTICES.txt}"

# component | license (SPDX-ish) | upstream source
COMPONENTS=(
  "nginx|BSD-2-Clause|https://nginx.org/en/download.html"
  "PHP (7.4/8.0/8.1/8.2/8.3/8.4, php/php-fpm — shivammathur/php bottle, relocated)|PHP-3.01|https://www.php.net/downloads"
  "dnsmasq|GPL-2.0-or-later|https://thekelleys.org.uk/dnsmasq/"
  "mkcert|BSD-3-Clause|https://github.com/FiloSottile/mkcert"
  "Mailpit|MIT|https://github.com/axllent/mailpit"
  "MySQL (mysqld)|GPL-2.0-only|https://dev.mysql.com/downloads/mysql/"
  "PostgreSQL|PostgreSQL|https://www.postgresql.org/ftp/source/"
  "Redis (>=7)|SSPL-1.0 / RSALv2|https://github.com/redis/redis"
  "Node.js|MIT (+deps)|https://nodejs.org/dist/"
  "Go (on-demand)|BSD-3-Clause|https://go.dev/dl/"
  "Sparkle|MIT|https://github.com/sparkle-project/Sparkle"
  "OpenSSL (libssl/libcrypto)|Apache-2.0|https://www.openssl.org/source/"
  "ICU (libicu*)|Unicode-3.0|https://github.com/unicode-org/icu"
  "curl (libcurl)|curl (MIT-like)|https://curl.se/download.html"
  "nghttp2/nghttp3 (libnghttp*)|MIT|https://nghttp2.org/"
  "ngtcp2 (libngtcp2*)|MIT|https://github.com/ngtcp2/ngtcp2"
  "libssh2|BSD-3-Clause|https://libssh2.org/"
  "brotli (libbrotli*)|MIT|https://github.com/google/brotli"
  "zstd (libzstd)|BSD-3-Clause OR GPL-2.0|https://github.com/facebook/zstd"
  "zlib (libz)|Zlib|https://zlib.net/"
  "xz/lzma (liblzma)|0BSD|https://tukaani.org/xz/"
  "PostgreSQL client (libpq)|PostgreSQL|https://www.postgresql.org/ftp/source/"
  "SQLite (libsqlite3)|blessing (public domain)|https://www.sqlite.org/download.html"
  "libsodium|ISC|https://github.com/jedisct1/libsodium"
  "argon2 (libargon2)|CC0-1.0 OR Apache-2.0|https://github.com/P-H-C/phc-winner-argon2"
  "oniguruma (libonig)|BSD-2-Clause|https://github.com/kkos/oniguruma"
  "PCRE2 (libpcre2)|BSD-3-Clause|https://github.com/PCRE2Project/pcre2"
  "libzip|BSD-3-Clause|https://libzip.org/"
  "MIT Kerberos (libkrb5/libk5crypto/libcom_err/libgssapi_krb5/libkrb5support)|MIT|https://web.mit.edu/kerberos/"
  "OpenLDAP (libldap/liblber)|OLDAP-2.8|https://www.openldap.org/software/download/"
  "libffi|MIT|https://github.com/libffi/libffi"
  "GD (libgd)|BSD-like|https://libgd.github.io/"
  "FreeType (libfreetype)|FTL OR GPL-2.0|https://freetype.org/"
  "fontconfig (libfontconfig)|MIT|https://www.freedesktop.org/wiki/Software/fontconfig/"
  "libpng|PNG-2.0|http://www.libpng.org/pub/png/libpng.html"
  "libjpeg-turbo (libjpeg)|IJG OR BSD-3-Clause|https://libjpeg-turbo.org/"
  "libtiff|libtiff (BSD-like)|https://libtiff.gitlab.io/libtiff/"
  "libwebp/sharpyuv|BSD-3-Clause|https://github.com/webmproject/libwebp"
  "aom (libaom)|BSD-2-Clause|https://aomedia.googlesource.com/aom/"
  "dav1d (libdav1d)|BSD-2-Clause|https://code.videolan.org/videolan/dav1d"
  "libavif|BSD-2-Clause|https://github.com/AOMediaCodec/libavif"
  "libvmaf|BSD-2-Clause-Patent|https://github.com/Netflix/vmaf"
  "tidy-html5 (libtidy)|W3C (MIT-like)|https://github.com/htacg/tidy-html5"
  "unixODBC (libodbc)|LGPL-2.1-or-later|https://www.unixodbc.org/"
  "FreeTDS (libsybdb)|LGPL-2.0-or-later|https://www.freetds.org/"
  "GMP (libgmp)|LGPL-3.0-or-later OR GPL-2.0|https://gmplib.org/"
  "GNU gettext (libintl)|LGPL-2.1-or-later|https://www.gnu.org/software/gettext/"
  "GNU Aspell (libaspell/libpspell)|LGPL-2.1-or-later|http://aspell.net/"
  "GNU libtool (libltdl)|LGPL-2.1-or-later|https://www.gnu.org/software/libtool/"
  "ImageMagick (libMagickCore/libMagickWand — imagick ext)|ImageMagick (Apache-2.0-like)|https://imagemagick.org/"
  "Little CMS (liblcms2 — imagick ext)|MIT|https://www.littlecms.com/"
  "libmemcached (memcached ext)|BSD-3-Clause|https://libmemcached.org/"
  "libevent (event ext)|BSD-3-Clause|https://libevent.org/"
  "net-snmp (libnetsnmp — snmp ext)|net-snmp (BSD-like)|https://www.net-snmp.org/"
)
# Copyleft components that require a written offer of source.
SOURCE_OFFER=(
  "dnsmasq" "MySQL (mysqld)" "Redis (>=7)"
  "unixODBC (libodbc)" "FreeTDS (libsybdb)" "GMP (libgmp)"
  "GNU gettext (libintl)" "GNU Aspell (libaspell/libpspell)" "GNU libtool (libltdl)"
)

{
  echo "KTStack — Third-Party Notices"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "KTStack is distributed free of charge as open-source software."
  echo
  echo "== Redistributed components =="
  for row in "${COMPONENTS[@]}"; do
    IFS='|' read -r name lic src <<< "$row"
    printf -- "- %s\n    License: %s\n    Source:  %s\n" "$name" "$lic" "$src"
  done
  echo
  echo "== Written offer of source (GPL / SSPL components) =="
  echo "For the following components, KTStack provides the complete corresponding source code."
  echo "The exact upstream version + build recipe for each is in scripts/build-*-relocatable.sh and"
  echo "scripts/build-php-versions.sh; request a copy at the project repository or the contact below."
  for c in "${SOURCE_OFFER[@]}"; do echo "  - $c"; done
  echo
  echo "Contact: https://github.com/KTStackAPP/KTStack"
  echo
  echo "Full license texts for each component are available at the Source URLs above and are included"
  echo "with the corresponding upstream distributions."
} > "$OUT"

echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
