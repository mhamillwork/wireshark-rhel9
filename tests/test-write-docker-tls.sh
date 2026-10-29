#!/usr/bin/env bash
# The TLS writer produces a server certificate for wireshark-docker and a
# client certificate the job can present. This does not start dockerd.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || fail "openssl is required"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

DOCKER_TLS_DIR="$tmp/tls" bash "$root/src/scripts/write-docker-tls.sh" >/dev/null
for name in ca.pem server-cert.pem server-key.pem cert.pem key.pem; do
  [ -f "$tmp/tls/$name" ] || fail "missing $name"
done
openssl verify -CAfile "$tmp/tls/ca.pem" "$tmp/tls/server-cert.pem" >/dev/null || fail "server certificate does not chain to the CA"
openssl verify -CAfile "$tmp/tls/ca.pem" "$tmp/tls/cert.pem" >/dev/null || fail "client certificate does not chain to the CA"
san="$(openssl x509 -in "$tmp/tls/server-cert.pem" -noout -ext subjectAltName)"
grep -F 'DNS:wireshark-docker' <<<"$san" >/dev/null || fail "server certificate SAN was: $san"
mode="$(stat -c '%a' "$tmp/tls/key.pem")"
[ "$mode" = 600 ] || fail "client key mode was $mode"

DOCKER_TLS_DIR="$tmp/tls" bash "$root/src/scripts/write-docker-tls.sh" | grep -F 'already present' >/dev/null || fail "second run rewrote the certificates"

echo "docker tls certificates passed"
