#!/usr/bin/env bash
# S4 runner — proves vendored mkcert can mint a *.test leaf that the macOS system trust
# store trusts (the green-lock signal Safari + Chrome consume; both read the System
# keychain). Firefox uses its own NSS store — verify there too IF Firefox is installed,
# else Safari is the accepted fallback (owner decision).
#
# Authoritative automated check: serve the leaf over TLS and connect with curl using the
# SYSTEM trust store (NO -k). ssl_verify_result == 0 == trusted chain + SAN match.
#
# Prereq (one-time, interactive admin auth): ./bin/mkcert -install   (installs the local CA)
set -euo pipefail
cd "$(dirname "$0")"
export CAROOT="$PWD/caroot"
PORT="${1:-8443}"
HOST="demo.test"

[[ -x ./bin/mkcert ]] || { echo "vendored mkcert missing at ./bin/mkcert" >&2; exit 2; }
[[ -f "$CAROOT/rootCA.pem" ]] || { echo "CA not installed — run: CAROOT=$CAROOT ./bin/mkcert -install" >&2; exit 2; }

# Mint (idempotent — re-mints the leaf).
./bin/mkcert "$HOST" >/dev/null 2>&1
openssl verify -CAfile "$CAROOT/rootCA.pem" "$HOST.pem" >/dev/null

# Serve + verify against the system trust store.
openssl s_server -accept "$PORT" -cert "$HOST.pem" -key "$HOST-key.pem" -quiet -WWW >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
# Wait for the listener (no fixed sleep).
for _ in $(seq 1 50); do lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && break; done

RES=$(curl -sS --resolve "$HOST:$PORT:127.0.0.1" "https://$HOST:$PORT/$HOST.pem" \
        -o /dev/null -w "%{ssl_verify_result}" 2>&1 || true)

if [[ "$RES" == "0" ]]; then
    echo "S4 PASS — system trust store trusts the mkcert *.test leaf (ssl_verify_result=0)."
    echo "  Browser visual green-lock needs $HOST to resolve (dnsmasq/resolver — S2/Phase 4) or a temp hosts entry."
    [[ -d "/Applications/Firefox.app" ]] && echo "  Firefox present — also verify in Firefox NSS." || echo "  Firefox absent — Safari is the accepted fallback browser."
    exit 0
else
    echo "S4 FAIL — ssl_verify_result=$RES (expected 0)."
    exit 1
fi
