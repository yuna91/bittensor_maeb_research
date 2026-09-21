#!/usr/bin/env bash
# SN105 Beam — generate the self-signed WCP TLS certificate.
#   sudo ./01-gen-cert.sh <PUBLIC_IP>
#
# This secures the orchestrator <-> worker link only. You control both ends, so no public CA
# and no domain are involved: the worker builds its trust store from an EMPTY pool
# (x509.NewCertPool, never SystemCertPool) and trusts only the file passed as BEAM_WCP_CA.
set -euo pipefail

PUBLIC_IP="${1:-}"
CONF_DIR=/etc/beam
SERVER_NAME=beam-orch
DAYS=3650

die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root"
[[ -n "$PUBLIC_IP" ]] || die "usage: $0 <PUBLIC_IP>"
[[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'$PUBLIC_IP' is not an IPv4 address"
[[ "$PUBLIC_IP" != "127.0.0.1" ]] || die "that is loopback, not your public IP"

mkdir -p "$CONF_DIR"

if [[ -f "$CONF_DIR/wcp.crt" ]]; then
  read -r -p "$CONF_DIR/wcp.crt exists. Overwrite? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] || { echo "keeping existing cert"; exit 0; }
fi

# SAN is mandatory: Go ignores the legacy Common Name field entirely and fails with
# "x509: certificate relies on legacy Common Name field" if subjectAltName is absent.
# CA:TRUE + keyCertSign are required because this cert acts as its own root.
openssl req -x509 -newkey rsa:4096 -sha256 -days "$DAYS" -nodes \
  -keyout "$CONF_DIR/wcp.key" -out "$CONF_DIR/wcp.crt" \
  -subj "/CN=${SERVER_NAME}" \
  -addext "subjectAltName=DNS:${SERVER_NAME},DNS:localhost,IP:127.0.0.1,IP:${PUBLIC_IP}" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign" 2>/dev/null

chown root:beam "$CONF_DIR/wcp.crt" "$CONF_DIR/wcp.key" 2>/dev/null || true
chmod 644 "$CONF_DIR/wcp.crt"
chmod 640 "$CONF_DIR/wcp.key"

echo "Wrote $CONF_DIR/wcp.crt and $CONF_DIR/wcp.key"
echo
openssl x509 -in "$CONF_DIR/wcp.crt" -noout -subject -dates -ext subjectAltName,basicConstraints

cat <<EOF

Set in /etc/beam/beam.env:
  BEAM_WCP_TLS_CERT=$CONF_DIR/wcp.crt     (orchestrator)
  BEAM_WCP_TLS_KEY=$CONF_DIR/wcp.key      (orchestrator)
  BEAM_WCP_CA=$CONF_DIR/wcp.crt           (worker — same file)
  BEAM_WCP_SERVER_NAME=$SERVER_NAME       (worker — must match a SAN entry)
EOF
