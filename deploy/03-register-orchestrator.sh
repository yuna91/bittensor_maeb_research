#!/usr/bin/env bash
# SN105 Beam — register the orchestrator with BeamCore.
#   ./03-register-orchestrator.sh <coldkey> <hotkey> <PUBLIC_IP> [fee_percentage] [region]
#
# MUST run BEFORE the orchestrator connects to NATS. The NATS "register" message only declares
# your live gateway and readiness; it cannot create the record. Connecting without this step
# is rejected with `orchestrator_not_routable`.
#
# The api_key is returned ONLY on first registration and is not retrievable afterwards.
set -euo pipefail

COLDKEY="${1:-}"; HOTKEY_NAME="${2:-}"; PUBLIC_IP="${3:-}"
FEE_PCT="${4:-10}"; REGION="${5:-north-america}"

CORE_SERVER_URL="${CORE_SERVER_URL:-https://beamcore.b1m.ai}"
CONF_DIR=/etc/beam
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ -n "$COLDKEY" && -n "$HOTKEY_NAME" && -n "$PUBLIC_IP" ]] \
  || die "usage: $0 <coldkey> <hotkey> <PUBLIC_IP> [fee_percentage] [region]"
[[ "$PUBLIC_IP" != "127.0.0.1" ]] || die "gateway URL must be your PUBLIC ip, not loopback"
command -v jq >/dev/null || die "jq not installed (run 00-bootstrap.sh)"

log "Resolving hotkey ss58"
HOTKEY_SS58="$("$SCRIPT_DIR/02-sign.py" --wallet "$COLDKEY" --hotkey "$HOTKEY_NAME" --ss58-only)"
[[ -n "$HOTKEY_SS58" ]] || die "could not resolve hotkey ss58"
echo "hotkey: $HOTKEY_SS58"

log "Signing '${HOTKEY_SS58}:${FEE_PCT}'"
# The signed message and the submitted fee_percentage must agree, or the signature check fails.
SIG="$("$SCRIPT_DIR/02-sign.py" --wallet "$COLDKEY" --hotkey "$HOTKEY_NAME" \
        --message "${HOTKEY_SS58}:${FEE_PCT}")"

GATEWAY_URL="http://${PUBLIC_IP}:8782"

log "POST ${CORE_SERVER_URL}/orchestrators/register"
BODY="$(jq -n \
  --arg hk "$HOTKEY_SS58" --arg sig "$SIG" --arg url "$GATEWAY_URL" \
  --arg name "beam-$(hostname -s)" --arg region "$REGION" \
  --argjson fee "$FEE_PCT" --argjson maxw 64 \
  '{hotkey:$hk, signature:$sig, fee_percentage:$fee, name:$name, region:$region, url:$url, max_workers:$maxw}')"

RESP="$(curl -sS --max-time 45 -X POST "${CORE_SERVER_URL}/orchestrators/register" \
         -H 'Content-Type: application/json' -d "$BODY" -w '\n%{http_code}')"
CODE="$(tail -n1 <<<"$RESP")"; JSON="$(sed '$d' <<<"$RESP")"

echo "HTTP $CODE"
echo "$JSON" | jq . 2>/dev/null || echo "$JSON"

if [[ "$CODE" == "403" ]]; then
  die "hotkey is not registered on subnet 105. Run:
  btcli subnets register --netuid 105 --network finney --wallet-name $COLDKEY --wallet-hotkey $HOTKEY_NAME"
fi
[[ "$CODE" =~ ^2 ]] || die "registration failed"

ORCH_ID="$(jq -r '.orchestrator_id // empty' <<<"$JSON")"
API_KEY="$(jq -r '.api_key // empty'         <<<"$JSON")"

if [[ -z "$API_KEY" ]]; then
  cat <<'WARN'

NOTE: no api_key in the response. That field is returned ONLY on first registration, so this
was almost certainly a metadata update on an existing record. Reuse the key you saved earlier.
WARN
else
  umask 077
  printf 'ORCHESTRATOR_ID=%s\nORCHESTRATOR_API_KEY=%s\nHOTKEY_SS58=%s\n' \
    "$ORCH_ID" "$API_KEY" "$HOTKEY_SS58" > "$CONF_DIR/orchestrator.creds"
  chmod 600 "$CONF_DIR/orchestrator.creds"
  log "Saved credentials to $CONF_DIR/orchestrator.creds (mode 0600)"
fi

cat <<EOF

Now set these in $CONF_DIR/beam.env:

  BEAM_BITTENSOR_HOTKEY=$HOTKEY_SS58
  BEAMCORE_NATS_USER=$HOTKEY_SS58
  BEAMCORE_NATS_PASSWORD=${API_KEY:-<your saved api_key>}
  BEAMCORE_GATEWAY_URL=$GATEWAY_URL
  BEAM_ORCHESTRATOR_ID=${ORCH_ID:-<your orchestrator_id>}

Then:
  sudo systemctl enable --now beam-orchestrator
  sudo journalctl -u beam-orchestrator -f
EOF
