#!/usr/bin/env bash
# SN105 Beam — register the worker with BeamCore and bind it to the local orchestrator.
#   ./04-register-worker.sh <coldkey> <hotkey> <PUBLIC_IP> [claimed_bandwidth_mbps]
#
# Run AFTER the orchestrator service is up: the membership call targets the orchestrator's
# owner-local API on 127.0.0.1:8781.
#
# NOTE: this reuses the ORCHESTRATOR hotkey. docs/worker.md asks for a hotkey "registered on
# subnet 105", but the worker runtime accepts no hotkey argument at all — the hotkey only signs
# this one-time request. If BeamCore rejects the reuse with 403, each worker needs its own UID.
set -euo pipefail

COLDKEY="${1:-}"; HOTKEY_NAME="${2:-}"; PUBLIC_IP="${3:-}"; CLAIMED_MBPS="${4:-500}"

CORE_SERVER_URL="${CORE_SERVER_URL:-https://beamcore.b1m.ai}"
ORCH_API="${ORCH_API:-http://127.0.0.1:8781}"
WORKER_PORT=9000
CONF_DIR=/etc/beam
STATE_DIR=/var/lib/beam
NODE_KEY="$STATE_DIR/worker/node.key"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ -n "$COLDKEY" && -n "$HOTKEY_NAME" && -n "$PUBLIC_IP" ]] \
  || die "usage: $0 <coldkey> <hotkey> <PUBLIC_IP> [claimed_bandwidth_mbps]"
command -v jq >/dev/null || die "jq not installed (run 00-bootstrap.sh)"
# orchestrator.creds is written by 03-register-orchestrator.sh. Registering by hand (btcli sign
# + curl, as the guide also documents) never creates it — but beam.env holds the same values, so
# fall back to that rather than making the user redo a registration that already succeeded.
if [[ -f "$CONF_DIR/orchestrator.creds" ]]; then
  # shellcheck disable=SC1091
  source "$CONF_DIR/orchestrator.creds"
elif [[ -f "$CONF_DIR/beam.env" ]]; then
  # shellcheck disable=SC1091
  source "$CONF_DIR/beam.env"
  ORCHESTRATOR_ID="${ORCHESTRATOR_ID:-${BEAM_ORCHESTRATOR_ID:-}}"
  ORCHESTRATOR_API_KEY="${ORCHESTRATOR_API_KEY:-${BEAMCORE_NATS_PASSWORD:-}}"
  if [[ -n "$ORCHESTRATOR_ID" ]]; then
    echo "no orchestrator.creds — using BEAM_ORCHESTRATOR_ID from beam.env"
    umask 077
    printf 'ORCHESTRATOR_ID=%s\nORCHESTRATOR_API_KEY=%s\nHOTKEY_SS58=%s\n' \
      "$ORCHESTRATOR_ID" "$ORCHESTRATOR_API_KEY" "${BEAM_BITTENSOR_HOTKEY:-}" \
      > "$CONF_DIR/orchestrator.creds"
    chmod 600 "$CONF_DIR/orchestrator.creds"
    echo "wrote $CONF_DIR/orchestrator.creds for 99-healthcheck.sh and 06-check-penalty.sh"
  fi
else
  die "neither $CONF_DIR/orchestrator.creds nor $CONF_DIR/beam.env exists - run step 8 first"
fi
[[ -n "${ORCHESTRATOR_ID:-}" ]] || die "ORCHESTRATOR_ID not set in orchestrator.creds"

log "Checking orchestrator is running"
# The health route is GET /healthz at the ROOT (verified against the compiled route table);
# the docs claim /v1/orchestrator/health, which 404s. With curl -f a 404 is indistinguishable
# from the process being down, which used to abort this script against a healthy orchestrator.
# Accept ANY HTTP response as proof of life; fail only on a connection error.
HTTP_CODE="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
              "$ORCH_API/healthz" 2>/dev/null || echo 000)"
if [[ "$HTTP_CODE" == "000" ]]; then
  HTTP_CODE="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "$ORCH_API/" 2>/dev/null || echo 000)"
fi
if [[ "$HTTP_CODE" == "000" ]]; then
  die "orchestrator API unreachable at $ORCH_API - start beam-orchestrator first"
fi
echo "orchestrator API responding (HTTP $HTTP_CODE)"

log "Resolving keys"
# Signing normally happens here via 02-sign.py, which needs bittensor_wallet plus the wallet
# directory (including coldkeypub.txt). Neither belongs on the VPS: Step 5 copies only the
# hotkey, and sudo resets HOME to /root so the wallet would not be found anyway.
#
# So: if HOTKEY_SS58, COLDKEY_SS58 and SIG are supplied in the environment, use them and never
# touch a wallet here. Produce them on your workstation with btcli:
#
#   btcli wallet list                       # read both ss58 addresses
#   btcli wallet sign --wallet-name <cold> --wallet-hotkey <hot> --use-hotkey \
#     --message "<HOTKEY_SS58>:<PUBLIC_IP>:9000"
#
# then on the VPS:
#
#   sudo HOTKEY_SS58=5... COLDKEY_SS58=5... SIG=0x... \
#     /root/deploy/04-register-worker.sh <cold> <hot> <PUBLIC_IP> 500
if [[ -n "${HOTKEY_SS58:-}" && -n "${COLDKEY_SS58:-}" && -n "${SIG:-}" ]]; then
  echo "using pre-signed values from the environment (no wallet needed on this host)"
else
  [[ -x "$SCRIPT_DIR/02-sign.py" ]] \
    || die "02-sign.py not executable, and HOTKEY_SS58/COLDKEY_SS58/SIG were not supplied"
  python3 -c 'import bittensor_wallet' 2>/dev/null || python3 -c 'import bittensor' 2>/dev/null \
    || die "no bittensor wallet library on this host. Sign on your workstation instead, then:
  sudo env HOTKEY_SS58=... COLDKEY_SS58=... SIG=0x... $0 $*"
  HOTKEY_SS58="$("$SCRIPT_DIR/02-sign.py" --wallet "$COLDKEY" --hotkey "$HOTKEY_NAME" --ss58-only)"
  COLDKEY_SS58="$("$SCRIPT_DIR/02-sign.py" --wallet "$COLDKEY" --hotkey "$HOTKEY_NAME" --coldkeypub-only)"
  log "Signing '${HOTKEY_SS58}:${PUBLIC_IP}:${WORKER_PORT}'"
  SIG="$("$SCRIPT_DIR/02-sign.py" --wallet "$COLDKEY" --hotkey "$HOTKEY_NAME" \
          --message "${HOTKEY_SS58}:${PUBLIC_IP}:${WORKER_PORT}")"
fi
echo "hotkey:  $HOTKEY_SS58"
echo "coldkey: $COLDKEY_SS58"
echo "message: ${HOTKEY_SS58}:${PUBLIC_IP}:${WORKER_PORT}"

log "POST ${CORE_SERVER_URL}/workers/register"
# claimed_bandwidth_mbps is a claim, not a measurement. PRISM scores provider-VERIFIED
# throughput, so inflating this wins nothing and risks accepting work you cannot deliver —
# failures feed reliability, which is 60% of performance_score.
BODY="$(jq -n \
  --arg hk "$HOTKEY_SS58" --arg ck "$COLDKEY_SS58" --arg ip "$PUBLIC_IP" --arg sig "$SIG" \
  --argjson port "$WORKER_PORT" --argjson bw "$CLAIMED_MBPS" \
  '{hotkey:$hk, coldkey:$ck, ip:$ip, port:$port, claimed_bandwidth_mbps:$bw, signature:$sig}')"

RESP="$(curl -sS --max-time 45 -X POST "${CORE_SERVER_URL}/workers/register" \
         -H 'Content-Type: application/json' -d "$BODY" -w '\n%{http_code}')"
CODE="$(tail -n1 <<<"$RESP")"; JSON="$(sed '$d' <<<"$RESP")"
echo "HTTP $CODE"; echo "$JSON" | jq . 2>/dev/null || echo "$JSON"

if [[ "$CODE" == "403" ]]; then
  cat <<'WARN' >&2

403 — the orchestrator hotkey was rejected for worker registration.
This is the unverified assumption in the README: the worker apparently needs its OWN hotkey
registered on subnet 105, meaning an extra UID and an extra ~0.0005 TAO burn per worker.
Register a second hotkey and re-run this script with it.
WARN
  exit 1
fi
[[ "$CODE" =~ ^2 ]] || die "worker registration failed"

WORKER_ID="$(jq -r '.worker_id // empty' <<<"$JSON")"
WORKER_KEY="$(jq -r '.api_key // empty'  <<<"$JSON")"
[[ -n "$WORKER_ID" ]] || die "no worker_id returned"

umask 077
printf 'WORKER_ID=%s\nWORKER_API_KEY=%s\n' "$WORKER_ID" "$WORKER_KEY" > "$CONF_DIR/worker.creds"
chmod 600 "$CONF_DIR/worker.creds"
log "Saved $CONF_DIR/worker.creds"

log "Creating BeamLink node identity"
install -d -o beam -g beam "$STATE_DIR/worker"
NODE_ID="$(sudo -u beam /opt/beam/bin/beam-worker node-id --node-key "$NODE_KEY" | tr -d '[:space:]')"
[[ -n "$NODE_ID" ]] || die "could not derive node id"
echo "node id: $NODE_ID"

log "Binding worker membership on the orchestrator"
MRESP="$(curl -sS --max-time 20 -X POST "$ORCH_API/v1/orchestrator/memberships" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg o "$ORCHESTRATOR_ID" --arg w "$WORKER_ID" --arg n "$NODE_ID" \
        '{OrchestratorID:$o, WorkerID:$w, NodeID:$n, Status:"active"}')" \
  -w '\n%{http_code}')"
MCODE="$(tail -n1 <<<"$MRESP")"; MJSON="$(sed '$d' <<<"$MRESP")"
echo "HTTP $MCODE"; echo "$MJSON" | jq . 2>/dev/null || echo "$MJSON"
[[ "$MCODE" =~ ^2 ]] || die "membership binding failed"

cat <<EOF

Set in $CONF_DIR/beam.env:
  BEAM_WORKER_ID=$WORKER_ID
  BEAM_ORCHESTRATOR_ID=$ORCHESTRATOR_ID

If the membership response contained a delegation value, also set:
  BEAM_ORCHESTRATOR_DELEGATION=<base64url value>

Then:
  sudo systemctl enable --now beam-worker
  ./99-healthcheck.sh
EOF
