#!/usr/bin/env bash
# SN105 Beam — detect and classify PRISM penalties, especially the permanent one.
#   ./06-check-penalty.sh
#
# Background:
#   penalty_multiplier = clamp(1 - pressure, 0, 1),  pressure += coefficient x active_rows
#
#     fraud                     0.1  per row   expires after 168h  -> needs 10 rows to zero you
#     sybil                     0.5  per row   expires after 168h  -> needs  2 rows to zero you
#     integrity_chunk_mismatch  1.0  per row   PERMANENT           -> ONE row zeroes you forever
#
#   base_raw = verified_uploaded_MiB x penalty_multiplier, and zero-raw orchestrators never
#   receive positive weight. So a zeroed penalty multiplier means zero earnings, permanently
#   if the cause was integrity.
#
# Run daily from cron; it keeps state so the 7-day expiry test resolves automatically.
set -uo pipefail

CONF_DIR=/etc/beam
STATE_FILE=/var/lib/beam/penalty-watch.state
CORE_SERVER_URL="${CORE_SERVER_URL:-https://beamcore.b1m.ai}"

pass() { printf '  \033[1;32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[1;33mWARN\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[1;31mALERT\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

[[ -f "$CONF_DIR/beam.env" ]] && { set -a; # shellcheck disable=SC1091
  source "$CONF_DIR/beam.env"; set +a; }
[[ -f "$CONF_DIR/orchestrator.creds" ]] && { # shellcheck disable=SC1091
  source "$CONF_DIR/orchestrator.creds"; }

NOW=$(date +%s)
PENALISED=0

# ---------------------------------------------------------------------------
section "1. PRISM breakdown (authoritative)"
# ---------------------------------------------------------------------------
# BeamCore is the only authority on penalties; the validator repo only caches them locally.
if [[ -n "${ORCHESTRATOR_API_KEY:-}" ]]; then
  for path in "/orchestrators/prism-scores/${BEAM_UID:-}" "/orchestrators/${ORCHESTRATOR_ID:-}"; do
    [[ "$path" == */ ]] && continue
    RESP="$(curl -fsS --max-time 25 -H "x-api-key: $ORCHESTRATOR_API_KEY" \
            "${CORE_SERVER_URL}${path}" 2>/dev/null || true)"
    [[ -z "$RESP" ]] && continue
    echo "  --- ${path} ---"
    echo "$RESP" | jq . 2>/dev/null | sed 's/^/  /' | head -n 60 || echo "  $RESP" | head -c 600
    # Field names are not published, so match on pattern rather than assume a schema.
    HITS="$(echo "$RESP" | grep -oiE '"[a-z_]*penalt[a-z_]*"[[:space:]]*:[[:space:]]*[^,}]*' || true)"
    [[ -n "$HITS" ]] && { echo "  penalty-related fields:"; sed 's/^/    /' <<<"$HITS"; }
    if grep -qi 'integrity_chunk_mismatch' <<<"$RESP"; then
      bad "integrity_chunk_mismatch present in the response — PERMANENT penalty"
      PENALISED=2
    fi
    PM="$(jq -r '.. | .penalty_multiplier? // empty' <<<"$RESP" 2>/dev/null | head -n1)"
    if [[ -n "$PM" ]]; then
      if awk "BEGIN{exit !($PM <= 0)}"; then bad "penalty_multiplier = $PM (score forced to zero)"; PENALISED=${PENALISED:-1}
      elif awk "BEGIN{exit !($PM < 1)}"; then warn "penalty_multiplier = $PM (degraded, not zero)"; PENALISED=1
      else pass "penalty_multiplier = $PM (clean)"; fi
    fi
  done
else
  warn "ORCHESTRATOR_API_KEY unknown — cannot query PRISM directly. Falling back to symptoms."
fi

# ---------------------------------------------------------------------------
section "2. On-chain symptom (no credentials needed)"
# ---------------------------------------------------------------------------
# If you are qualified, connected and delivering work but incentive is 0, penalty_multiplier
# is almost certainly 0 — because base_raw = uploaded_MiB x penalty.
CHAIN_ZERO=0
# See 99-healthcheck.sh: prefer async_substrate_interface; substrate-interface pulls
# scalecodec, which collides with cyscale and breaks btcli.
if python3 -c 'import async_substrate_interface' 2>/dev/null \
   || python3 -c 'import substrateinterface' 2>/dev/null && [[ -n "${BEAM_BITTENSOR_HOTKEY:-}" ]]; then
  OUT="$(python3 - "$BEAM_BITTENSOR_HOTKEY" <<'PY' 2>/dev/null
import sys, warnings
warnings.filterwarnings("ignore")
try:
    from async_substrate_interface import SubstrateInterface   # preferred
except ImportError:
    from substrateinterface import SubstrateInterface          # legacy fallback
hk = sys.argv[1]
s = SubstrateInterface(url="wss://entrypoint-finney.opentensor.ai:443")
uid = s.query("SubtensorModule", "Uids", [105, hk]).value
if uid is None:
    print("NOUID"); raise SystemExit
inc = s.query("SubtensorModule", "Incentive", [105]).value
rank = sum(1 for x in inc if x > inc[uid]) + 1
print(f"{uid} {inc[uid]} {rank} {sum(1 for x in inc if x>0)}")
PY
)"
  if [[ "$OUT" == "NOUID" ]]; then
    warn "hotkey not registered on subnet 105 (deregistered?) — penalties are a separate question"
  elif [[ -n "$OUT" ]]; then
    read -r UID INC RANK ACTIVE <<<"$OUT"
    echo "  UID $UID  incentive $INC  rank ~$RANK / $ACTIVE active"
    if [[ "$INC" -eq 0 ]]; then
      CHAIN_ZERO=1
      warn "incentive is ZERO — either still qualifying, receiving no work, or penalised"
    else
      pass "incentive is non-zero — you are NOT fully penalised"
    fi
  fi
else
  warn "no substrate client or hotkey unset — skipping chain check"
fi

# ---------------------------------------------------------------------------
section "3. Is work actually being delivered?"
# ---------------------------------------------------------------------------
# Distinguishes "penalised" from "simply idle". Successful results with zero incentive is the
# signature of a zeroed penalty multiplier.
OKC=$(journalctl -u beam-worker --since '24 hours ago' --no-pager -q 2>/dev/null | grep -ci 'state=completed\|success' || echo 0)
ERRC=$(journalctl -u beam-worker --since '24 hours ago' --no-pager -q 2>/dev/null | grep -ciE 'etag|integrity|mismatch|checksum' || echo 0)
echo "  last 24h: ~$OKC successful results, ~$ERRC integrity/etag related log lines"
[[ "$ERRC" -gt 0 ]] && bad "integrity/etag errors in worker log — these are what trigger the permanent penalty" \
                    || pass "no integrity/etag errors logged"
if [[ "$CHAIN_ZERO" -eq 1 && "$OKC" -gt 0 ]]; then
  bad "delivering work successfully but earning zero — consistent with penalty_multiplier = 0"
  PENALISED=${PENALISED:-1}
fi

# ---------------------------------------------------------------------------
section "4. The 168-hour expiry test (tells fraud/sybil from integrity)"
# ---------------------------------------------------------------------------
# fraud and sybil expire after 168h; integrity_chunk_mismatch never does. If the zero state
# survives 7+ clean days, the cause is permanent.
if [[ "${PENALISED:-0}" -ge 1 ]]; then
  if [[ -f "$STATE_FILE" ]]; then
    FIRST=$(cat "$STATE_FILE")
    ELAPSED=$(( (NOW - FIRST) / 3600 ))
    echo "  first observed penalised: $(date -d "@$FIRST" 2>/dev/null || echo "$FIRST")  (${ELAPSED}h ago)"
    if [[ "$ELAPSED" -gt 168 ]]; then
      bad "still penalised after ${ELAPSED}h > 168h — fraud and sybil would have expired."
      bad "VERDICT: permanent integrity_chunk_mismatch. This hotkey will never earn again."
      echo
      echo "  Recovery: register a NEW hotkey. Because SybilViolationType includes SAME_IP,"
      echo "  move to a different IP as well, or the new hotkey risks a sybil flag."
    else
      warn "penalised for ${ELAPSED}h. If fraud/sybil, it expires at 168h ($(( 168 - ELAPSED ))h left)."
      echo "  Re-run daily. Survival past 168h means it is the permanent one."
    fi
  else
    echo "$NOW" > "$STATE_FILE" 2>/dev/null || true
    warn "first penalised observation recorded. Re-run daily to resolve the 168h test."
  fi
else
  [[ -f "$STATE_FILE" ]] && { rm -f "$STATE_FILE"; pass "previously-penalised state cleared"; }
  pass "no penalty indicators"
fi

# ---------------------------------------------------------------------------
section "5. Root-cause hunt (public audit route, no auth needed)"
# ---------------------------------------------------------------------------
cat <<EOF
  To find the transfer that caused it, pull the raw rows for a suspect transfer:

    curl -s "https://data.b1m.ai/api/audit/orchestrator/\${BEAM_BITTENSOR_HOTKEY}/transfers/<TRANSFER_UUID>" | jq .

  Returns: transfer_assignment_plans, task_offer_batches, tasks, task_attempts,
           task_results, overseer_interventions.
  Look in task_results / overseer_interventions for etag or integrity failures.
  The route is public — the orchestrator id may be a UUID, UID, or hotkey.
EOF

section "Summary"
case "${PENALISED:-0}" in
  0) printf '  \033[1;32mNo penalty detected.\033[0m\n' ;;
  1) printf '  \033[1;33mPenalty indicators present — re-run daily to classify.\033[0m\n' ;;
  2) printf '  \033[1;31mPERMANENT integrity penalty confirmed. New hotkey + new IP required.\033[0m\n' ;;
esac
exit 0
