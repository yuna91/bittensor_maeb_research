#!/usr/bin/env bash
# SN105 Beam — post-deployment verification.
#   ./99-healthcheck.sh
# Exits non-zero if any FAIL check trips. Safe to run repeatedly / from cron.
set -uo pipefail

CONF_DIR=/etc/beam
CORE_SERVER_URL="${CORE_SERVER_URL:-https://beamcore.b1m.ai}"
FAILED=0

pass() { printf '  \033[1;32mPASS\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33mWARN\033[0m  %s\n' "$*"; }
fail() { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; FAILED=1; }
section() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

[[ -f "$CONF_DIR/beam.env" ]] && { set -a; # shellcheck disable=SC1091
  source "$CONF_DIR/beam.env"; set +a; }
[[ -f "$CONF_DIR/orchestrator.creds" ]] && { # shellcheck disable=SC1091
  source "$CONF_DIR/orchestrator.creds"; }

section "Services"
for u in beam-orchestrator beam-worker; do
  if systemctl is-active --quiet "$u"; then
    since="$(systemctl show -p ActiveEnterTimestamp --value "$u")"
    nrestart="$(systemctl show -p NRestarts --value "$u")"
    pass "$u active since $since (restarts: $nrestart)"
    [[ "${nrestart:-0}" -gt 5 ]] && warn "$u has restarted $nrestart times — check journal for crash loops"
  else
    fail "$u is NOT active  (journalctl -u $u -n 50)"
  fi
done

section "Listening sockets"
if ss -lnt 2>/dev/null | grep -q ':8782'; then pass "WCP listener on 8782"
else fail "nothing listening on 8782 — workers cannot connect"; fi
# Room transfers are extra uploaded MiB, which is what sets your rank. The listener defaults
# to loopback and also needs --allow-public-network-listeners on the worker.
if ss -lnt 2>/dev/null | grep -qE "0\.0\.0\.0:9470|\*:9470"; then
  pass "room-transfer listener public on 9470"
elif ss -lnt 2>/dev/null | grep -q ':9470'; then
  warn "9470 is bound but not publicly — check BEAM_ROOM_TRANSFER_LISTEN_ADDR=0.0.0.0:9470"
else
  warn "no room-transfer listener on 9470 — you are forfeiting Room work (extra rank)"
fi
for p in 8780 8781; do
  if ss -lnt 2>/dev/null | grep -qE "127\.0\.0\.1:$p"; then pass "control API $p bound to loopback"
  elif ss -lnt 2>/dev/null | grep -q ":$p"; then fail "port $p is NOT loopback-only — do not expose it"
  else warn "nothing listening on $p"; fi
done

section "The two-address trap"
# BEAMCORE_GATEWAY_URL must be public; BEAM_WCP_ADDRESS should be loopback. Six of the 50
# orchestrators in Beam's live routing table get this backwards and receive no work.
if [[ "${BEAMCORE_GATEWAY_URL:-}" =~ 127\.0\.0\.1|localhost ]]; then
  fail "BEAMCORE_GATEWAY_URL is loopback (${BEAMCORE_GATEWAY_URL}) — you will never receive work"
elif [[ -n "${BEAMCORE_GATEWAY_URL:-}" ]]; then
  pass "BEAMCORE_GATEWAY_URL = ${BEAMCORE_GATEWAY_URL}"
  MY_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  if [[ -n "$MY_IP" ]]; then
    if [[ "$BEAMCORE_GATEWAY_URL" == *"$MY_IP"* ]]; then pass "gateway URL matches detected public IP $MY_IP"
    else warn "gateway URL does not contain detected public IP $MY_IP"; fi
  fi
else
  fail "BEAMCORE_GATEWAY_URL is unset"
fi
[[ "${BEAM_WCP_ADDRESS:-}" =~ 127\.0\.0\.1 ]] \
  && pass "BEAM_WCP_ADDRESS = ${BEAM_WCP_ADDRESS} (loopback is correct here)" \
  || warn "BEAM_WCP_ADDRESS = ${BEAM_WCP_ADDRESS:-unset} — expected 127.0.0.1:8782 when co-located"

section "External reachability of 8782"
if [[ -n "${MY_IP:-}" ]]; then
  if timeout 8 bash -c "echo > /dev/tcp/$MY_IP/8782" 2>/dev/null; then
    pass "8782 reachable via public IP"
  else
    warn "could not reach $MY_IP:8782 from this host (hairpin NAT can cause a false negative; verify the firewall allows 8782/tcp)"
  fi
fi

section "TLS certificate"
if [[ -f "$CONF_DIR/wcp.crt" ]]; then
  if openssl x509 -in "$CONF_DIR/wcp.crt" -noout -checkend 2592000 >/dev/null 2>&1; then
    pass "cert valid for at least 30 more days"
  else fail "cert expires within 30 days (or is invalid) — regenerate with 01-gen-cert.sh"; fi
  SAN="$(openssl x509 -in "$CONF_DIR/wcp.crt" -noout -ext subjectAltName 2>/dev/null | tail -n1 | tr -d ' ')"
  if [[ -n "$SAN" ]]; then
    pass "SAN: $SAN"
    # Go rejects CN-only certs outright; BEAM_WCP_SERVER_NAME must appear in the SAN.
    [[ "$SAN" == *"${BEAM_WCP_SERVER_NAME:-beam-orch}"* ]] \
      && pass "BEAM_WCP_SERVER_NAME '${BEAM_WCP_SERVER_NAME:-beam-orch}' present in SAN" \
      || fail "BEAM_WCP_SERVER_NAME '${BEAM_WCP_SERVER_NAME:-beam-orch}' NOT in SAN — TLS will fail"
  else
    fail "cert has no subjectAltName — Go will reject it (legacy Common Name is ignored)"
  fi
else
  fail "missing $CONF_DIR/wcp.crt"
fi

section "BeamCore control plane"
RELAYS="$(curl -fsS --max-time 20 "$CORE_SERVER_URL/status/orchestrator-relays" 2>/dev/null || true)"
if [[ -n "$RELAYS" && -n "${HOTKEY_SS58:-}" ]]; then
  if grep -q "$HOTKEY_SS58" <<<"$RELAYS"; then
    pass "hotkey present in live relay set (control session established)"
  else
    fail "hotkey NOT in relay set — orchestrator is not connected/ready to BeamCore"
  fi
  TOTAL="$(jq -r '.hotkeys | length' <<<"$RELAYS" 2>/dev/null || echo '?')"
  echo "         live orchestrators fleet-wide: $TOTAL"
else
  warn "could not query relay status (or HOTKEY_SS58 unknown)"
fi

if [[ -n "${ORCHESTRATOR_API_KEY:-}" ]]; then
  PRISM="$(curl -fsS --max-time 20 -H "x-api-key: $ORCHESTRATOR_API_KEY" \
           "$CORE_SERVER_URL/orchestrators/${ORCHESTRATOR_ID:-}" 2>/dev/null || true)"
  if [[ -n "$PRISM" ]]; then
    echo "$PRISM" | jq '{pool, ready, status, confidence_score, prism_final_score}' 2>/dev/null \
      || echo "$PRISM" | head -c 400
    POOL="$(jq -r '.pool // empty' <<<"$PRISM" 2>/dev/null)"
    case "$POOL" in
      qualified)  pass "pool = qualified (earning validator weight)" ;;
      qualifying) warn "pool = qualifying — NOT yet earning. Needs ~120 verified tasks + ~1 day age for confidence 0.9" ;;
      *)          warn "pool unknown" ;;
    esac
  fi
else
  warn "ORCHESTRATOR_API_KEY unknown — skipping PRISM check"
fi

section "On-chain position"
# Prefer async_substrate_interface (ships with bittensor-cli, uses cyscale). The older
# substrate-interface pulls scalecodec, which collides with cyscale's namespace and makes
# btcli refuse to start. Never install both in one environment.
if python3 -c 'import async_substrate_interface' 2>/dev/null \
   || python3 -c 'import substrateinterface' 2>/dev/null && [[ -n "${HOTKEY_SS58:-}" ]]; then
  python3 - "$HOTKEY_SS58" <<'PY' 2>/dev/null || warn "chain query failed"
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
    print("  \033[1;31mFAIL\033[0m  hotkey is NOT registered on subnet 105"); raise SystemExit
inc = s.query("SubtensorModule", "Incentive", [105]).value
emi = s.query("SubtensorModule", "Emission", [105]).value
mine = inc[uid]
rank = sum(1 for x in inc if x > mine) + 1
alpha_day = emi[uid] / 1e9 * 20          # Emission is per-tempo; 20 tempos/day
tier = ("A", "B", "C", "D", "E")[min(4, (rank - 1) // 30)] if mine > 0 else "-"
print(f"  \033[1;32mPASS\033[0m  UID {uid}  incentive {mine}  rank ~{rank}/{sum(1 for x in inc if x>0)}")
print(f"         tier {tier}   ~{alpha_day:.2f} alpha/day")
if mine == 0:
    print("  \033[1;33mWARN\033[0m  zero incentive — still qualifying, or receiving no routed work")
PY
else
  warn "no substrate client found — skipping chain check (pip install -U bittensor-cli provides async-substrate-interface; do NOT pip install substrate-interface, it conflicts)"
fi

section "Host tuning"
CC="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
[[ "$CC" == "bbr" ]] && pass "congestion control = bbr" || warn "congestion control = $CC (bbr recommended for high-BDP paths)"
RMAX="$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)"
[[ "$RMAX" -ge 33554432 ]] && pass "rmem_max = $RMAX" \
  || warn "rmem_max = $RMAX — too small for a 2 Gbps x 40ms path (~10 MB BDP); re-run 00-bootstrap.sh"
df -h /var/lib/beam | awk 'NR==2 {print "         disk: "$4" free of "$2" ("$5" used)"}'
free -m | awk 'NR==2 {print "         mem:  "$7" MiB available of "$2" MiB"}'

section "Recent errors"
journalctl -u beam-orchestrator -u beam-worker --since '30 min ago' -p err --no-pager -q 2>/dev/null | tail -n 15 \
  || echo "  (none)"
for pat in orchestrator_not_routable duplicate_control_session "invalid client protocol"; do
  if journalctl -u beam-orchestrator --since '1 hour ago' --no-pager -q 2>/dev/null | grep -q "$pat"; then
    fail "saw '$pat' in the last hour"
  fi
done

echo
[[ $FAILED -eq 0 ]] && printf '\033[1;32mAll critical checks passed.\033[0m\n' \
                    || printf '\033[1;31mOne or more critical checks FAILED.\033[0m\n'
exit $FAILED
