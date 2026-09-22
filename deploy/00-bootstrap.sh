#!/usr/bin/env bash
# SN105 Beam — system bootstrap. Run as root, once.
#   sudo ./00-bootstrap.sh
set -euo pipefail

BEAM_USER=beam
INSTALL_DIR=/opt/beam
STATE_DIR=/var/lib/beam
CONF_DIR=/etc/beam
REPO=https://github.com/Beam-Network/beam.git

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root"

log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git ca-certificates openssl jq python3 python3-venv python3-pip

log "Creating user and directories"
id -u "$BEAM_USER" &>/dev/null || useradd --system --create-home --home-dir "$STATE_DIR" --shell /usr/sbin/nologin "$BEAM_USER"
mkdir -p "$INSTALL_DIR" "$STATE_DIR"/{orchestrator,worker} "$CONF_DIR"
chown -R "$BEAM_USER:$BEAM_USER" "$STATE_DIR"
# root owns it, the service group reads it. Without the chown the directory stays root:root
# and mode 750 denies the beam user *search* permission — every file inside then fails to
# open, regardless of its own mode.
chown root:"$BEAM_USER" "$CONF_DIR"
chmod 750 "$CONF_DIR"

# 01-gen-cert.sh may have run before this script created the beam user, in which case its
# own chown silently no-opped. Re-apply here, where the user is guaranteed to exist.
if [[ -f "$CONF_DIR/wcp.crt" ]]; then
  chown root:"$BEAM_USER" "$CONF_DIR/wcp.crt"
  chmod 644 "$CONF_DIR/wcp.crt"
fi
if [[ -f "$CONF_DIR/wcp.key" ]]; then
  chown root:"$BEAM_USER" "$CONF_DIR/wcp.key"
  chmod 640 "$CONF_DIR/wcp.key"
fi

log "Installing Go (1.24+ required)"
GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
[[ -n "$GO_VERSION" ]] || die "could not resolve latest Go version"
if [[ "$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}')" != "$GO_VERSION" ]]; then
  curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  rm -f /tmp/go.tgz
fi
export PATH=/usr/local/go/bin:$PATH
grep -q '/usr/local/go/bin' /etc/profile.d/go.sh 2>/dev/null || echo 'export PATH=/usr/local/go/bin:$PATH' > /etc/profile.d/go.sh
go version

log "Cloning and building Beam"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" fetch --quiet origin && git -C "$INSTALL_DIR" reset --hard --quiet origin/main
else
  git clone --quiet "$REPO" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
mkdir -p bin
go build -o bin/beam-orchestrator ./cmd/beam-orchestrator
go build -o bin/beam-worker      ./cmd/beam-worker
./bin/beam-orchestrator version || true
# Record provenance — the gateway rejects non-canonical builds with "invalid client protocol".
git rev-parse HEAD > "$INSTALL_DIR/BUILD_REVISION"
chown -R root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"/bin/*

log "Applying TCP tuning"
# 2 Gbps x 40ms RTT => ~10 MB bandwidth-delay product. Default 6 MB maxima cap a single
# stream below line rate, which costs throughput rank directly under PRISM.
cat > /etc/sysctl.d/99-beam.conf <<'SYSCTL'
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 30000
net.core.somaxconn = 8192
net.ipv4.tcp_rmem = 4096 262144 67108864
net.ipv4.tcp_wmem = 4096 262144 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 10240 65535
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 2097152
SYSCTL
modprobe tcp_bbr 2>/dev/null || true
grep -qx 'tcp_bbr' /etc/modules-load.d/bbr.conf 2>/dev/null || echo tcp_bbr > /etc/modules-load.d/bbr.conf
sysctl --quiet --system
echo "congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"

log "Capping log growth"
# Transfer payloads never touch disk (the worker streams source->destination), so the only
# things that grow here are journals. The WCP event journal has no rotation of its own, and
# an unbounded systemd journal will eventually fill the disk — a full disk means failed
# transfers, and reliability is 60% of the PRISM performance score.
sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
grep -q '^SystemMaxUse=' /etc/systemd/journald.conf || echo 'SystemMaxUse=500M' >> /etc/systemd/journald.conf
systemctl restart systemd-journald
journalctl --vacuum-size=500M >/dev/null 2>&1 || true
echo "systemd journal capped at 500M"

cat > /etc/logrotate.d/beam <<'LOGROTATE'
/var/lib/beam/orchestrator/wcp-events.jsonl {
    weekly
    rotate 2
    maxsize 500M
    compress
    missingok
    notifempty
    copytruncate
}
LOGROTATE
echo "wcp-events.jsonl rotation installed (copytruncate, keeps 2 x 500M)"

log "Installing systemd units"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/systemd" ]]; then
  install -m 644 "$SCRIPT_DIR/systemd/beam-orchestrator.service" /etc/systemd/system/
  install -m 644 "$SCRIPT_DIR/systemd/beam-worker.service"       /etc/systemd/system/
  systemctl daemon-reload
else
  echo "WARNING: systemd/ not found next to this script; copy the units manually"
fi

if [[ ! -f "$CONF_DIR/beam.env" && -f "$SCRIPT_DIR/beam.env.example" ]]; then
  install -m 600 -o root -g "$BEAM_USER" "$SCRIPT_DIR/beam.env.example" "$CONF_DIR/beam.env"
  chmod 640 "$CONF_DIR/beam.env"
  echo "created $CONF_DIR/beam.env — edit it before starting services"
fi

log "Done"
cat <<'NEXT'
Next:
  1. btcli subnets register --netuid 105 --network finney \
       --wallet-name <coldkey> --wallet-hotkey <hotkey>
  2. sudo ./01-gen-cert.sh <YOUR_PUBLIC_IP>
  3. ./03-register-orchestrator.sh <coldkey> <hotkey> <YOUR_PUBLIC_IP>
NEXT
