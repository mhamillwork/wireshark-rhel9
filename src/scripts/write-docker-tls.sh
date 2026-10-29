#!/usr/bin/env bash
# Write the dockerd server certificate and the client certificate the GitLab
# jobs use. DOCKER_TLS_DIR defaults to /etc/docker/tls. The client files are
# ca.pem, cert.pem, and key.pem. The server files are server-cert.pem and
# server-key.pem. Re-running leaves an existing set in place.
set -euo pipefail

dir="${DOCKER_TLS_DIR:-/etc/docker/tls}"
mkdir -p "$dir"
if [ -f "$dir/ca.pem" ] && [ -f "$dir/server-cert.pem" ] && [ -f "$dir/server-key.pem" ] && [ -f "$dir/cert.pem" ] && [ -f "$dir/key.pem" ]; then
  echo "docker tls: certificates already present in ${dir}"
  exit 0
fi
command -v openssl >/dev/null 2>&1 || { echo "docker tls: openssl is required" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$dir/ca-key.pem" -out "$dir/ca.pem" \
  -subj "/CN=wireshark-docker-ca"

cat > "$tmp/server.ext" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:wireshark-docker,DNS:wireshark-docker.gitlab,DNS:wireshark-docker.gitlab.svc,DNS:wireshark-docker.gitlab.svc.cluster.local,DNS:localhost,IP:127.0.0.1
EOF
openssl req -newkey rsa:2048 -nodes \
  -keyout "$dir/server-key.pem" -out "$tmp/server.csr" \
  -subj "/CN=wireshark-docker"
openssl x509 -req -in "$tmp/server.csr" \
  -CA "$dir/ca.pem" -CAkey "$dir/ca-key.pem" -CAserial "$tmp/ca.srl" -CAcreateserial \
  -out "$dir/server-cert.pem" -days 3650 -extfile "$tmp/server.ext"

cat > "$tmp/client.ext" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF
openssl req -newkey rsa:2048 -nodes \
  -keyout "$dir/key.pem" -out "$tmp/client.csr" \
  -subj "/CN=wireshark-docker-client"
openssl x509 -req -in "$tmp/client.csr" \
  -CA "$dir/ca.pem" -CAkey "$dir/ca-key.pem" -CAserial "$tmp/ca.srl" \
  -out "$dir/cert.pem" -days 3650 -extfile "$tmp/client.ext"

chmod 600 "$dir/ca-key.pem" "$dir/server-key.pem" "$dir/key.pem"
chmod 644 "$dir/ca.pem" "$dir/server-cert.pem" "$dir/cert.pem"
echo "docker tls: wrote certificates in ${dir}"
