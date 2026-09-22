# Mining Bittensor Subnet 105 (Beam) — Deployment Guide

**For operators whose everyday computer runs Linux.** Your Linux PC holds the wallet and signs
things; a rented Linux VPS does the mining. No prior Bittensor experience assumed.

> Verified against Finney block 9,117,624 and Beam build `8be314b`. Every command below was run
> on a real deployment (UID 92) on 2026-09-22; the scoring figures in §10 are that node's live
> values, and they reproduce Beam's published formulas exactly.
>
> Using Windows? [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) is the same deployment with a WSL2
> control machine. This one is simpler — on Linux you get `btcli` natively, `ssh-copy-id`, and
> one `~/.ssh` instead of two.

---

## How to read this guide

Every command block says **where to run it**. Mixing them up is the most common way to waste an
hour:

| Badge | Machine |
|---|---|
| **PC** | your own Linux computer — holds the wallet, never exposed |
| **VPS** | the rented server — runs the miner, never holds your coldkey |

Placeholders, each meaning exactly one thing:

| Placeholder | Value | Where to get it |
|---|---|---|
| `<PUBLIC_IP>` | the **VPS's** public IPv4 | your provider, or `curl -4 -s ifconfig.me` on the VPS |
| `<HOTKEY_SS58>` | the **hotkey** address | `btcli wallet list`, the `Hotkey` row |
| `<COLDKEY_SS58>` | the **coldkey** address | `btcli wallet list`, the `Coldkey` row |
| `<UID>` | your slot number | `btcli wallet overview --netuid 105` |

Both addresses start with `5` and look alike. The coldkey is used **once**, to receive TAO, and
appears in no config file. Confusing them produces `403 hotkey is not registered`.

---

## Table of contents

**Decide**

1. [What this is and what it pays](#1-what-this-is-and-what-it-pays)
2. [Vocabulary in 60 seconds](#2-vocabulary-in-60-seconds)
3. [Before you spend anything](#3-before-you-spend-anything)

**Build** — about 90 minutes

4. [Part 1 — Your Linux PC](#4-part-1--your-linux-pc)
5. [Part 2 — The VPS](#5-part-2--the-vps)
6. [Part 3 — Joining Beam](#6-part-3--joining-beam)
7. [Part 4 — Verify](#7-part-4--verify)

**Run**

8. [Part 5 — Operating it](#8-part-5--operating-it)
9. [Part 6 — When things break](#9-part-6--when-things-break)

**Reference**

10. [How scoring actually works](#10-how-scoring-actually-works)
11. [Troubleshooting index](#11-troubleshooting-index)
12. [Reference and sources](#12-reference-and-sources)  — glossary is in §2

---

## 1. What this is and what it pays

Beam (SN105) is a **data-transfer subnet**. No AI, no GPU. Your server moves data between cloud
storage endpoints and is paid for verified bytes delivered.

Pay comes in **five fixed tiers by rank**, and the cliffs between them are brutal:

| Your rank | Nominal/month | **Realistic/month** | Verdict |
|---|---|---|---|
| 1–30 | ~$2,216 | **~$358** | strongly profitable |
| 31–60 | ~$1,551 | **~$250** | strongly profitable |
| 61–90 | ~$443 | **~$72** | profitable |
| 91–120 | ~$177 | **~$29** | break-even |
| **121+** (~89 miners) | ~$15 | **~$2** | **loss** |

Ranks 1–120 share **99%** of miner emissions; rank 121+ shares **1%**. Rank 60→61 is a 3.5× pay
cut; 120→121 is 14×.

"Realistic" is what you actually bank if you convert alpha to TAO as you earn it. The gap is
structural — see §12. Costs: **~$0.14** once, **~$16/month** thereafter.

**Three facts that decide whether to bother:**

1. **There are zero free slots.** The subnet is at 256/256. Registering **evicts someone**, and
   you get 25 hours of immunity before the same happens to you.
2. **Registration is trivially cheap** — ~$0.14, not hundreds of dollars. The experiment is
   low-risk; the monthly server bill is the real cost.
3. **Your server choice barely matters.** One tier of rank is worth ~$150/month; the spread
   between sensible VPS plans is ~$25/month. **Where you rank is everything.**

A positive-expected-value bet with high variance. Not passive income.

---

## 2. Vocabulary in 60 seconds

| Term | What it means for you |
|---|---|
| **TAO** | Bittensor's main token (~$281) |
| **Alpha** | SN105's own token (~$1.50). **You are paid in alpha, not TAO** |
| **Coldkey** | Controls your money. Stays on your PC. Never on the VPS |
| **Hotkey** | Signs work. Safe on the VPS. **Cannot move funds** |
| **netuid** | Subnet number. Beam is **105** |
| **UID** | Your numbered slot. There are 256 and all are taken |
| **Orchestrator** | The miner process. Holds the UID, earns emissions |
| **Worker** | The process that moves the bytes. Runs beside the orchestrator |
| **BeamCore** | Beam's central coordinator. Closed-source; computes all scores |
| **PRISM** | Beam's scoring system. Decides how much work you are sent |
| **Immunity** | 25-hour grace period after registering, during which you cannot be evicted |
| **Tempo** | How often weights and payouts update: 360 blocks, ~72 minutes |

**You need one UID, not two.** Verified 2026-09-22: registering the worker with the
*orchestrator's* hotkey is accepted, and BeamCore returns `worker_id == orchestrator_id`. Beam's
own `docs/worker.md` implies a second registration is required. It is not.

---

## 3. Before you spend anything

Both of these are free, and either can invalidate the plan.

**Get your provider's bandwidth answer in writing.** You will move 3–5 TB/month in bursts.
PetroSky's current terms do not prohibit crypto mining — but "fair use" is undefined and they
reserve the right to cancel any service at any time. Email `support@petrosky.io`:

> I plan to run a bandwidth-relay node moving roughly 3–5 TB/month sustained, in bursts.
> Is this acceptable under your fair-use policy?

**Accept that you are joining a queue, not filling a vacancy.** Registration evicts the
lowest-scoring non-immune miner, and ~25 UIDs turn over daily. Budget for two or three
re-registrations while you tune; at $0.14 each that is affordable.

### What you will spend

| Item | Cost |
|---|---|
| ~0.1 TAO for registration and fees | ~$28 (you keep the change) |
| SN105 registration burn | **0.0005 TAO ≈ $0.14** — dynamic; `btcli` shows the real figure before charging |
| VPS: 2 vCPU / 4 GB / 40 GB | **€14.39/month** |
| Second hotkey for the worker | **$0 — not needed** (see §2) |
| Domain and TLS certificate | **$0 — not needed** (see Step 2.5) |

### Which VPS, and why

**PetroSky Quebec City, Standard 2 vCPU / 4 GB / 40 GB, Ubuntu 24.04.** No 10 Gbps upgrade, no
extra storage, no backups — everything here is reproducible.

- **Not 1 vCPU / 2 GB.** 2 GB cannot hold the worker's 2 GiB reservation plus the orchestrator
  and OS. An OOM kill destroys reliability, which carries 60% of your score.
- **Not bigger.** Measured load is ~91 GiB/day (~8.8 Mbps average); the entire subnet moves
  ~2 Gb/s. You will not be CPU-bound, and the cheap plan breaks even a full tier lower.
- **Quebec, not Paris.** Beam's routing is US-dominated. Quebec→us-east-1 is ~40 ms, Paris ~80 ms,
  and throughput is scored *relative to* those US competitors.
- **40 GB is plenty.** Transferred data never touches disk — the worker streams source to
  destination in a single pipe, computing SHA-256 in flight. Disk goes to Ubuntu, the Go
  toolchain, and logs.

> `--scratch-bytes` (default 10 GiB) is an **accounting figure** the worker reserves against when
> deciding how much work to accept. It is not disk usage. Do not size your disk around it.

**Upgrade only on evidence.** Run `vmstat 1 10` during a burst: CPU steal above 5% with a poor
rank justifies a dedicated instance; `us+sy` pinned at 100% justifies more vCPU. Neither, but
stuck in the bottom tier, means the problem is your network path or config — more CPU will not
fix it.

---

## 4. Part 1 — Your Linux PC

### Step 1.1 — Install `btcli`

**PC**

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y python3-venv python3-pip pipx
# Fedora:  sudo dnf install -y python3-pip python3-virtualenv pipx
# Arch:    sudo pacman -S --needed python python-pip python-pipx
```

Modern distros refuse `pip install` into the system Python (PEP 668 —
`error: externally-managed-environment`). Do **not** reach for `--break-system-packages`: `btcli`
pins exact dependency versions and will fight your distro's packages. Pick one:

```bash
pipx install bittensor-cli        # recommended — always on PATH, isolated
```

```bash
python3 -m venv ~/bt              # alternative — must be activated each session
source ~/bt/bin/activate
pip install -U bittensor-cli
```

```bash
btcli --version
```

> **`btcli: command not found` tomorrow?** You used the venv and opened a fresh shell. Either
> `source ~/bt/bin/activate` or switch to `pipx`.
>
> **`Conflict detected: 'scalecodec' is installed`?** Two SCALE codecs in one environment. Fix
> with `pip uninstall scalecodec substrate-interface -y` then
> `pip install --force-reinstall bittensor-cli`. Never install `substrate-interface` alongside
> `btcli` — `bittensor-cli` already ships `async-substrate-interface`.

### Step 1.2 — Create your wallet

**PC**

```bash
btcli wallet new_coldkey --wallet-name beam_cold
btcli wallet new_hotkey  --wallet-name beam_cold --wallet-hotkey orch1
```

**Write both mnemonics on paper and store them offline. There is no recovery.**

Then lock the directory down — your home is a normal multi-user directory:

```bash
chmod 700 ~/.bittensor ~/.bittensor/wallets ~/.bittensor/wallets/beam_cold
find ~/.bittensor/wallets -type f -exec chmod 600 {} +
```

> If this machine is shared, has an unencrypted home directory, or syncs `~` to cloud storage,
> keep the coldkey elsewhere — a LUKS volume or an offline machine — and leave only the hotkey.

### Step 1.3 — Buy and deposit TAO

**PC**

```bash
btcli wallet list                                   # note the COLDKEY address
```

Buy ~0.1 TAO on any exchange supporting Bittensor withdrawals (Kraken, Binance, KuCoin, MEXC)
and withdraw to that **coldkey** address. Confirm arrival:

```bash
btcli wallet balance --wallet-name beam_cold
```

### Step 1.4 — Register on subnet 105

**PC** — this spends real TAO.

```bash
btcli subnets register --netuid 105 --network finney \
  --wallet-name beam_cold --wallet-hotkey orch1
```

`btcli` shows the burn before charging. Expect ~0.0005 TAO; if it has spiked to several TAO,
wait — it decays with a 360-block half-life.

Confirm, and **write down your UID**:

```bash
btcli wallet overview --netuid 105 --wallet-name beam_cold
```

> **That table looks alarming and is fine.** `ACTIVE: False` and `AXON: none` are normal for a
> Beam miner — see §8 for why. The column that matters is `INCENTIVE`, and it stays `0.00` for at
> least a day.

### Step 1.5 — Create an SSH key

**PC**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_beam -C "beam-vps"
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_beam
```

A dedicated key per purpose is better than reusing one: revoking it later means deleting one
line, not re-keying everything.

Add a host alias so you never type the IP or `-i` again:

```bash
cat >> ~/.ssh/config <<'EOF'

Host beam-vps
    HostName <PUBLIC_IP>
    User ops
    IdentityFile ~/.ssh/id_ed25519_beam
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 6
EOF
chmod 600 ~/.ssh/config
```

Each line earns its place: `IdentitiesOnly yes` stops SSH offering every key you own and being
rejected with `Too many authentication failures`; `chmod 600` is mandatory, since OpenSSH refuses
a group-readable config (`Bad owner or permissions`); the `ServerAlive*` pair stops a NAT timeout
killing long builds and `journalctl -f` sessions.

---

## 5. Part 2 — The VPS

Order the server (§3) with **Ubuntu 24.04**. The provider emails you a root password.

> ⚠ **Do not name your login user `beam`.** Bootstrap creates `beam` as a *system* account with
> no shell, to run the services under. If a login user called `beam` already exists, bootstrap
> skips creating it and your miner ends up running as a sudo-capable account. Use `ops`.

### Step 2.1 — Create your login user

**VPS** — SSH in as `root` with the emailed password:

```bash
adduser ops && usermod -aG sudo ops
```

**PC** — install your key. No copy-pasting required on Linux:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_beam.pub ops@<PUBLIC_IP>
ssh beam-vps 'whoami'            # must print "ops" with no password prompt
```

> `cannot create .ssh/authorized_keys: Permission denied` means `/home/ops/.ssh` exists but is
> root-owned. From root: `chown -R ops:ops /home/ops && chmod 700 /home/ops/.ssh`, then re-run.

### Step 2.2 — Harden

> **First, in a second terminal, confirm `ssh beam-vps` logs you in without a password.** If you
> disable password login while your key is misconfigured, only the provider's web console can
> recover the machine.

**VPS**

```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

sudo apt update && sudo apt install -y ufw fail2ban
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 8782/tcp    # orchestrator — must be public
sudo ufw allow 9470/tcp    # room transfers — extra earnings
sudo ufw enable
```

Ports **8780** and **8781** are internal control APIs bound to `127.0.0.1`. Never open them.

### Step 2.3 — Copy the kit and your hotkey

**PC**, from the directory containing [deploy/](deploy/):

```bash
scp -r deploy beam-vps:/home/ops/deploy-new
scp -r ~/.bittensor/wallets/beam_cold/hotkeys beam-vps:/home/ops/hk_tmp
```

> **Copy `hotkeys/`, not `beam_cold/`.** `coldkey` and `coldkeypub.txt` live one level up, and
> that one-word difference is what keeps your funds off a public server.

**VPS**

```bash
sudo install -d -m 700 /root/deploy
sudo cp -r /home/ops/deploy-new/. /root/deploy/
sudo find /root/deploy -name '*.sh' -exec chmod +x {} +
rm -rf /home/ops/deploy-new
sudo ls -l /root/deploy                            # seven .sh files plus systemd/

mkdir -p ~/.bittensor/wallets/beam_cold/hotkeys
mv ~/hk_tmp/* ~/.bittensor/wallets/beam_cold/hotkeys/
chmod 600 ~/.bittensor/wallets/beam_cold/hotkeys/*
ls -l ~/.bittensor/wallets/beam_cold/hotkeys       # nothing called coldkey
```

> **Why `find` instead of `chmod +x /root/deploy/*.sh`?** Your shell expands the glob as `ops`
> *before* `sudo` runs, and `/root` is mode 700 — so it matches nothing and `chmod` reports
> `cannot access '/root/deploy/*.sh': No such file or directory`. Any wildcard inside a root-only
> path has to be expanded by root.
>
> **Updating a script later?** Run the remote half with `ssh -t`, or `sudo` aborts with *"a
> terminal is required to read the password"* — a command passed to `ssh` gets no TTY:
> ```bash
> scp deploy/99-healthcheck.sh beam-vps:/home/ops/
> ssh -t beam-vps 'sudo cp /home/ops/99-healthcheck.sh /root/deploy/ \
>   && sudo chmod +x /root/deploy/99-healthcheck.sh && rm /home/ops/99-healthcheck.sh'
> ```

### Step 2.4 — Build

**VPS** — takes several minutes. Run it inside `tmux` so a dropped connection cannot interrupt
the build:

```bash
tmux new -As beam
sudo /root/deploy/00-bootstrap.sh
```

Six things happen, only one of which is the build: packages; the `beam` system account; Go;
`beam-orchestrator` and `beam-worker` built from canonical source with `-trimpath`; TCP/BBR
tuning; log-growth caps; and installation of the two systemd units plus `/etc/beam/beam.env`.

**The TCP tuning is not cosmetic.** On a 2 Gbps link at ~40 ms RTT the bandwidth-delay product is
~10 MB, and stock kernel buffers cap a single stream well below line rate. PRISM scores your
throughput *relative to competitors*, so an untuned kernel costs you rank directly — for two
commands. Confirm it took:

```bash
sysctl -n net.ipv4.tcp_congestion_control          # must print: bbr
```

> **Always build from source.** `-ERR invalid client protocol` at runtime means a non-canonical
> binary.

### Step 2.5 — Generate the TLS certificate

**VPS** — run this *after* bootstrap, so the `beam` account exists and ownership lands right:

```bash
sudo /root/deploy/01-gen-cert.sh <PUBLIC_IP>
```

That is the **VPS's** public IPv4, never your PC's. The script writes it into the certificate's
SAN, and workers verify the address they dialled against it. Check the printed SAN block contains
`IP Address:<PUBLIC_IP>`.

> **No domain or Let's Encrypt needed.** The worker builds its trust store from an *empty* pool
> (`x509.NewCertPool()`, never `SystemCertPool()`) and trusts only the file you hand it, so a
> public CA certificate would be ignored. Self-signed with a 10-year expiry also removes the
> 90-day renewal failure mode, which would otherwise zero your readiness multiplier if it lapsed.

Check ownership before continuing — this is the most common cause of a restart-looping
orchestrator:

```bash
sudo ls -ld /etc/beam
sudo -u beam cat /etc/beam/wcp.crt > /dev/null && echo "beam can read the cert"
sudo -u beam cat /etc/beam/wcp.key > /dev/null && echo "beam can read the key"
```

`/etc/beam` must be `root:beam` mode 750. If it is `root:root`, the `beam` user has no *search*
permission and every file inside fails to open whatever its own mode says:

```bash
sudo chown root:beam /etc/beam /etc/beam/wcp.crt /etc/beam/wcp.key /etc/beam/beam.env
sudo chmod 750 /etc/beam
sudo chmod 644 /etc/beam/wcp.crt
sudo chmod 640 /etc/beam/wcp.key /etc/beam/beam.env
```

---

## 6. Part 3 — Joining Beam

Order matters. BeamCore registration **must** happen before the orchestrator connects, and the
worker's membership binding requires the orchestrator to already be running.

### Step 3.1 — Register the orchestrator with BeamCore

**PC** — sign the message. `10` is your fee percentage, baked into the signature:

```bash
btcli wallet sign --wallet-name beam_cold --wallet-hotkey orch1 --use-hotkey \
  --message "<HOTKEY_SS58>:10"
```

> **What the fee is, and why 10.** It is the cut your orchestrator keeps from workers registered
> under it — Beam lets third parties attach their workers to yours. **If you own both ends the
> number is irrelevant**: emissions land on the hotkey holding the UID either way. It matters
> only if you later host other people's workers, where a low fee recruits and a high one deters.
> 10 is the kit's default. Treat it as sticky.

**VPS** — post it:

```bash
curl -X POST https://beamcore.b1m.ai/orchestrators/register \
  -H 'Content-Type: application/json' \
  -d '{"hotkey":"<HOTKEY_SS58>","signature":"0x...","fee_percentage":10,
       "name":"my-orch","region":"north-america",
       "url":"http://<PUBLIC_IP>:8782","max_workers":64}'
```

> **Save `orchestrator_id` and `api_key` immediately, somewhere off the VPS. The key is returned
> exactly once.** A `403` means your hotkey is not on the metagraph — go back to Step 1.4.

**VPS** — record them where the monitoring scripts look. Do this even though `beam.env` holds the
same values: `99-healthcheck.sh` and `06-check-penalty.sh` read this file and silently skip their
PRISM queries without it.

```bash
sudo sh -c 'umask 077
cat > /etc/beam/orchestrator.creds <<EOF
ORCHESTRATOR_ID=<orchestrator_id>
ORCHESTRATOR_API_KEY=<api_key>
HOTKEY_SS58=<HOTKEY_SS58>
EOF
chmod 600 /etc/beam/orchestrator.creds'
```

### Step 3.2 — Fill in the configuration

**VPS.** Bootstrap already installed `/etc/beam/beam.env` from
[deploy/beam.env.example](deploy/beam.env.example), mode 0640, `root:beam`. **Do not write this
file from scratch** — the systemd units interpolate a dozen variables from it, and a hand-written
subset produces a malformed command line.

```bash
sudo grep -n REPLACE_ /etc/beam/beam.env          # shows exactly what is left
sudoedit /etc/beam/beam.env
```

| Placeholder | Value | From |
|---|---|---|
| `REPLACE_hotkey_ss58` (×2) | `<HOTKEY_SS58>` | Step 1.2 |
| `REPLACE_orchestrator_id` | the `orchestrator_id` | Step 3.1 |
| `REPLACE_orchestrator_api_key` | the `api_key` | Step 3.1 |
| `REPLACE_PUBLIC_IP` (×2) | `<PUBLIC_IP>` | your provider |
| `REPLACE_uid` | `<UID>` | Step 1.4 |
| `REPLACE_worker_id` | the `worker_id` | Step 3.4 — leave for now |

> ### ⚠ The mistake that silently kills miners
>
> Two addresses, and **only one may be loopback**:
>
> | Variable | Correct value | Why |
> |---|---|---|
> | `BEAMCORE_GATEWAY_URL` | `http://<PUBLIC_IP>:8782` | **must be public** — this is how work reaches you |
> | `BEAM_WCP_ADDRESS` | `127.0.0.1:8782` | internal worker to orchestrator hop; loopback is right |
>
> Six of the 50 orchestrators in Beam's live routing table have `127.0.0.1` in the first one.
> They receive no work and probably do not know why.

The certificate paths printed by `01-gen-cert.sh` are **already correct in the template**. That
closing message is generic advice for a hand-built config; ignore it.

### Step 3.3 — Start the orchestrator

**VPS**

```bash
sudo systemctl enable --now beam-orchestrator
sudo journalctl -u beam-orchestrator -f
```

A healthy start is three lines in the journal, then silence:

```
starting beam-orchestrator-beamcore NATS connector
Beam Orchestrator WCP listening on 0.0.0.0:8782 (TLS 1.3)
Beam Orchestrator 0.2.0 orchestrator_id=<uuid> listening on 127.0.0.1:8781
```

`(TLS 1.3)` proves the cert **and** key loaded; `0.0.0.0` proves the listener is public; the
`orchestrator_id` proves it read your registration. Any `Main process exited` after those means
it is still failing — read the line above it.

Then check over HTTP — this is a separate thing from the journal, and answers in JSON:

```bash
curl -s http://127.0.0.1:8781/healthz; echo
```

```json
{"orchestrator_id":"fb58b7d8-...","status":"ok"}
```

> **The health route is `GET /healthz`, at the root.** Beam's published `docs/orchestrator.md`
> documents `/v1/orchestrator/health`; that route does not exist and returns `404 page not
> found`. Verified against the compiled route table in `internal/orchestrator/server/server.go`.
> A 404 still proves the server is up — `Connection refused` is the reply that means it is down.
> Port 8782 speaks TLS, so `curl http://…:8782` returning nothing is also expected.

### Step 3.4 — Register the worker

This step spans both machines: signing needs your wallet, which is deliberately not on the VPS,
while the script needs root, the orchestrator's loopback API, and `orchestrator.creds`.

**PC** — the port in this message is **9000** (registration), not 9470 (room transfers):

```bash
btcli wallet sign --wallet-name beam_cold --wallet-hotkey orch1 --use-hotkey \
  --message "<HOTKEY_SS58>:<PUBLIC_IP>:9000"
btcli wallet list                                  # read both ss58 addresses
```

**VPS** — hand the script the pre-signed values, so no wallet tooling is needed on the server:

```bash
sudo env HOTKEY_SS58=<HOTKEY_SS58> COLDKEY_SS58=<COLDKEY_SS58> SIG=0x<signature> \
  /root/deploy/04-register-worker.sh beam_cold orch1 <PUBLIC_IP> 500
```

Use `sudo env VAR=...`, not `sudo VAR=...` — with the default `env_reset` in sudoers the latter
is rejected. The script echoes the message it will use; check it matches what you signed.

> **Be honest with the bandwidth claim** (the `500`). PRISM scores *provider-verified*
> throughput, so overclaiming gains nothing — but it pulls in work you cannot deliver, and those
> failures hit your success rate, the one number that can lock you out of emissions permanently.
> See §10.

It registers with BeamCore, writes `/etc/beam/worker.creds`, derives the node identity and binds
the membership. Copy the id into `beam.env`:

```bash
sudo grep '^WORKER_ID' /etc/beam/worker.creds
sudoedit /etc/beam/beam.env                        # set BEAM_WORKER_ID
```

> `worker_id` being identical to `orchestrator_id` is **correct** — BeamCore keys both records to
> the same hotkey. See §2.

### Step 3.5 — Room transfers, then start the worker

Room transfers are extra uploaded MiB, and uploaded MiB is what sets your rank. Three conditions
must hold and **the kit already satisfies all three** — do not edit the unit file. Only one value
is yours:

```bash
sudo grep -E 'BEAM_WORKER_CAPABILITIES|BEAM_ROOM_TRANSFER' /etc/beam/beam.env
```

| Variable | Required | State |
|---|---|---|
| `BEAM_WORKER_CAPABILITIES` | includes `room.transfer.direct.v1` **and** `room.transfer.e2ee.v2` | already correct |
| `BEAM_ROOM_TRANSFER_LISTEN_ADDR` | `0.0.0.0:9470` | already correct |
| `BEAM_ROOM_TRANSFER_ADVERTISE_URL` | `https://<PUBLIC_IP>:9470` | **yours to fill** |

The third condition, `--allow-public-network-listeners`, defaults to **false** and gates the room
handler entirely. It appears in neither Beam's docs nor most guides, and is hardcoded in
[deploy/systemd/beam-worker.service](deploy/systemd/beam-worker.service).

**VPS**

```bash
sudo systemctl enable --now beam-worker
sudo journalctl -u beam-worker -n 20 --no-pager
```

Editing `beam.env` needs no `daemon-reload` — systemd re-reads `EnvironmentFile` at service
start. Only a change to the `.service` file itself would.

> **Nothing will be listening on 9470, and that is correct.** With `room.transfer.direct.v1` the
> listener is created **on demand**, when a room workload actually runs; `cmd/beam-worker` binds
> eagerly only on the hybrid `room.transfer.storage.v2` path. An idle worker has 9470 closed, and
> `nc` from outside reports `Connection refused`. Verify the *capabilities* instead — §7 does.

---

## 7. Part 4 — Verify

Run all of these once. Each catches a different class of failure.

### On the VPS

```bash
sudo /root/deploy/99-healthcheck.sh
```

Checks services, ports, the two-address trap, certificate SAN, the BeamCore session, PRISM pool
and your on-chain position. It exits non-zero only on **FAIL**; `WARN` lines are informational.

> **One warning is expected:** *"no substrate client found — skipping chain check"*. The VPS
> deliberately has no Bittensor tooling. Read rank from your PC instead.

```bash
WID=$(sudo sed -n 's/^WORKER_ID=//p' /etc/beam/worker.creds)
sudo -u beam /opt/beam/bin/beam-worker doctor --worker-id "$WID"
```

> `$BEAM_WORKER_ID` lives in `beam.env`, which your login shell never sources — hence reading it
> from `worker.creds` first.

Then confirm work is actually arriving, which is the real test:

```bash
curl -s http://127.0.0.1:8781/v1/orchestrator/tasks | jq 'length'     # chunks assigned to you
curl -s http://127.0.0.1:8781/v1/orchestrator/manifest | jq .
```

The manifest's `Capabilities` must list all five entries including both room ones. It can only
advertise what a *member* worker offers, so that list is proof your worker membership bound
correctly.

Reading the rest of the manifest without alarm:

| Field | Expected | Why |
|---|---|---|
| `Available` == `Total` | normal | nothing in flight at that instant |
| `cpu_millis: 1000` | fixed | hardcoded in the binary; no flag exists. `connections`/`streams` at 1024 likewise |
| `Gateways: null` | normal | the handler passes `nil` for that argument — an artifact of this endpoint |
| `ExpiresAt` a minute out | normal | short TTL, rebuilt continuously |

Only `--memory-bytes`, `--scratch-bytes` and `--bandwidth-mbps` are tunable, and `beam.env`
already sets all three well above the binary's defaults.

### On your PC

```bash
nc -vz <PUBLIC_IP> 8782        # MUST succeed
btcli wallet overview --netuid 105 --wallet-name beam_cold
```

Reachability has to be tested from outside. Run it on the VPS and it passes over loopback even
with the firewall shut — the exact false positive that leaves an orchestrator silently earning
nothing. A timeout means `ufw`, or a listener bound to `127.0.0.1` instead of `0.0.0.0`.

**Do not test 9470 this way** — see Step 3.5. `Connection refused` there is correct for an idle
worker, and incidentally proves the firewall is open, since a `ufw` block would time out instead.

### The full PRISM breakdown

This is the most informative single command you have, and nothing else exposes these numbers:

```bash
sudo sh -c '. /etc/beam/orchestrator.creds
curl -sS -H "x-api-key: $ORCHESTRATOR_API_KEY" \
  https://beamcore.b1m.ai/orchestrators/prism-scores/<UID> | jq .'
```

§10 explains every field and which ones can hurt you.

---

## 8. Part 5 — Operating it

### What to expect, and when

**You earn nothing on day one. This is normal.**

| Time | What happens |
|---|---|
| 0 h | Registered. Pool is `qualifying`. Earnings **zero** |
| 0–24 h | Equal-share rotation builds your evidence |
| ~24 h | Confidence reaches 0.9 → **qualified** |
| **25 h** | **Immunity ends — you can now be evicted** |
| 24 h+ | Production work; incentive starts appearing on chain |
| 3–7 days | Tier stabilises |

Graduation lands almost exactly when immunity expires, and you enter at the bottom of the ranking
while ~25 UIDs are evicted daily. **This is the squeeze.** Survive it and you are fine. If you do
not, §9 makes recovery cheap — it is not a ban.

> Note two different clocks. `age_days` in the PRISM response counts from your **BeamCore**
> registration (Step 3.1). The 7,500-block immunity window counts from your **on-chain**
> registration (Step 1.4). They differ by however long you took in between.

### The three numbers that decide your income

```bash
sudo /root/deploy/99-healthcheck.sh | grep -iA3 "prism\|pool"
```

1. **Pool** — must flip `qualifying` → `qualified` within a few days
2. **Rank** — ≤120 you are earning, 121+ you are not
3. **`success_rate`** — must stay **above 0.90**, for the reason in §10

### Reading `btcli wallet overview` without panicking

| Column | Typical | Meaning |
|---|---|---|
| `ACTIVE` | **False** | tracks recent **weight-setting**. Only validators set weights, so nearly every miner reads False. Not a health signal |
| `AXON` | **none** | Beam does not use Bittensor's axon transport. Your endpoint is the WCP listener plus the NATS session, neither published on chain |
| `INCENTIVE` | 0.00 at first | the real signal. Appears only after graduation, and moves one tempo (~72 min) at a time |
| `UPDATED` | blocks since registration | miners never set weights, so it counts up from registration. At ~7,500 you become evictable |

### Keep it alive

`readinessMultiplier` is **linear in uptime**, and a dropped control-plane connection sets it to
**zero**. Uptime is the cheapest score you can buy.

- Set a free UptimeRobot monitor against `<PUBLIC_IP>:8782`
- Both units already carry `Restart=always`
- Automate the checks:

```bash
sudo crontab -e
```

```cron
0 * * * * /root/deploy/99-healthcheck.sh > /var/log/beam-health.log 2>&1 || logger -t beam-health "healthcheck FAILED"
30 6 * * * /root/deploy/06-check-penalty.sh > /var/log/beam-penalty.log 2>&1
```

- Rebuild weekly:

```bash
cd /opt/beam && sudo git pull --ff-only && sudo go clean -cache
sudo go build -trimpath -o bin/beam-orchestrator ./cmd/beam-orchestrator
sudo go build -trimpath -o bin/beam-worker       ./cmd/beam-worker
sudo systemctl restart beam-orchestrator beam-worker
```

### The penalty that ends a hotkey

`integrity_chunk_mismatch` has coefficient **1.0 and never expires** — one event zeroes that
hotkey forever. Any `etag`, `integrity` or `checksum` line in the worker log is an early warning.

Because **no data touches disk**, a failing disk cannot cause it. The real vectors are RAM
corruption (ECC memory genuinely helps), a middlebox mangling the stream (never put a proxy or
caching layer between the worker and object storage), and a modified or stale build (always
`-trimpath` from canonical source).

### Day-14 decision checkpoint

Be disciplined about this.

| Result | Action |
|---|---|
| Rank ≤ 120, stable | Working. Consider a bandwidth upgrade **only** if genuinely bandwidth-bound |
| Rank 121+, not improving | Earning ~$2/month against a ~$16 bill. **Shut it down** |

The registration burn is sunk; the monthly bill is not. Do not run a bottom-tier node for months
hoping the tier structure changes.

### Converting alpha to TAO

```bash
btcli stake remove --netuid 105 --wallet-name beam_cold --wallet-hotkey orch1
```

> Pool depth is only ~4,600 TAO. **Unstake in small tranches**, or you eat the slippage yourself.

---

## 9. Part 6 — When things break

### If you are deregistered (the likely outcome at least once)

This is **not a ban** and nothing is blacklisted. Re-register the **same hotkey**:

```bash
btcli subnets register --netuid 105 --network finney \
  --wallet-name beam_cold --wallet-hotkey orch1
```

Your BeamCore record is keyed to the hotkey, so **qualified pool status persists** — you skip the
24-hour dead period and start inside a fresh 25-hour immunity window. Reuse the same VPS, same
IP, same install. Cost: ~$0.14.

**Do not "start fresh" with a new hotkey. It is strictly worse.**

### If you are penalised

| Penalty | Coefficient | Events to zero you | Expires |
|---|---|---|---|
| `fraud` | 0.1 | 10 | 168 h |
| `sybil` | 0.5 | 2 | 168 h |
| `integrity_chunk_mismatch` | **1.0** | **1** | **never** |

Classify by time: if the zero survives 168 clean hours, it is the permanent one. A sudden drop
from 1.0 straight to 0.0 is the integrity signature; fraud degrades gradually.

Fraud penalties can be cleared self-service, at the cost of demotion back to `qualifying`:

```bash
curl -X DELETE https://beamcore.b1m.ai/orchestrators/history \
  -H "Authorization: Bearer <api_key>" -H 'Content-Type: application/json' -d '{"confirm":true}'
```

**If integrity is confirmed, that hotkey is finished.** You need a new hotkey — and because
`SybilViolationType` includes `SAME_IP`, a new IP alongside it.

---

## 10. How scoring actually works

Two separate scores. Confusing them is the most common analytical mistake.

### Stage A — how much work you are sent (PRISM)

```
performance = 0.4 × throughput_score + 0.6 × reliability_score
final       = performance × readiness_multiplier × penalty_multiplier
```

| Constant | Value |
|---|---|
| Throughput weight | 0.4 |
| Reliability weight | 0.6 |
| Fleet normalization floor | 0.2 |
| Evidence lookback | 1 day |
| Reliability half-life | 1 hour |
| Graduation confidence | 0.9 |
| Target verified tasks | 120 (`verified_task_count`) |

Three consequences, all favourable to a careful small operator:

1. **Reliability outweighs throughput, 0.6 to 0.4.** A small flawless node beats a big flaky one.
2. **Normalization floors at 0.2**, so work allocation spreads only ~5× between best and worst.
3. **Readiness is linear in uptime.** 90% uptime costs 10% of your score; a dropped control-plane
   connection sets it to **zero**.

### Stage B — graduating out of the zero-emission pool

```
confidence = min(1, verified_task_count/120) × success_rate × (0.8 + 0.2 × age_ratio)
```

> **It is `verified_task_count`, not `verified_transfer_count`.** The PRISM response carries both
> and they differ by an order of magnitude — transfers are the multipart operations, tasks are
> the chunks inside them (roughly 20+ tasks per transfer). Only `verified_task_count` reproduces
> the reported `confidence_score`. Watching the wrong counter makes graduation look impossibly
> far away.

New orchestrators start in `qualifying` and **earn nothing**, receiving randomized equal-share
work so everyone can build evidence. Graduate at **confidence ≥ 0.9**.

> ### The success-rate ceiling — the trap in this formula
>
> Past 120 tasks and 1 day of age, both other terms saturate at 1.0, so the formula collapses to:
>
> ```
> confidence_max = success_rate
> ```
>
> **A success rate below 0.90 makes graduation arithmetically impossible**, however many tasks
> you complete. Tasks and age are only a matter of waiting. Success rate is the one term that can
> permanently lock you out of emissions, and the only lever on it is not accepting work you
> cannot deliver — which is why Step 3.4 insists on an honest bandwidth claim.
>
> If it drifts toward 0.90, cut `BEAM_WORKER_BANDWIDTH_MBPS` toward your measured
> `verified_bandwidth_mbps` and restart the worker. `throughput_score` is fleet-normalised and
> saturates at 1.0, so a lower honest claim usually costs nothing.

### Stage C — converting to emissions (the cliff)

```
raw = verified_uploaded_mib × penalty_multiplier
TIER_SHARES = { A: 0.50, B: 0.35, C: 0.10, D: 0.04, E: 0.01 }
```

- **PRISM score** decides how much work you get (~5× spread)
- **Verified uploaded MiB** decides your rank
- **Rank** drops you into a tier (~50× spread)

That mismatch is the cliff. Ties break by rawScore → prismFinalScore → uploadedMiB → **lower UID
wins**.

### Verified against a live node

UID 92, 2026-09-22, ~18 hours old. The published constants reproduce exactly:

```
throughput 1 · reliability 0.82502  →  0.4(1) + 0.6(0.82502) = 0.89501    (reported 0.89501)
performance 0.89501 × readiness 0.99687 × penalty 1          = 0.89221    (reported 0.89221)
tasks 60/120 × success 0.9156 × (0.8 + 0.2 × age 0.74)       = 0.4340     (reported 0.4343)
```

Read that as: throughput maxed against the fleet, uptime 99.7%, no penalties, and graduation
gated on task count — but with only 1.7% of headroom above the success-rate floor.

An hour later, same node, showing what healthy progress looks like:

```
tasks 88/120 × success 0.9483 × (0.8 + 0.2 × age 0.78) = 0.6648    (reported 0.6654)
0.4(1) + 0.6(0.90993) = 0.94596 → × 0.99705 = 0.94316              (reported 0.94316)
```

Tasks arrived at ~28/hour, success rate climbed 0.9156 → 0.9483, and headroom above the 0.90
floor widened from 1.7% to 4.8%. Note the threshold does not require `age_ratio` to reach 1.0:
at 120 tasks and a 0.9483 success rate, confidence is 0.9066 — over the line at age 0.78. Solve
`success_rate × (0.8 + 0.2 × age) >= 0.9` to see when your own node qualifies.

---

## 11. Troubleshooting index

### On your PC

| Symptom | Cause and fix |
|---|---|
| `error: externally-managed-environment` | PEP 668. Use `pipx` or a venv (Step 1.1), never `--break-system-packages` |
| `btcli: command not found` in a new shell | venv not activated. `source ~/bt/bin/activate`, or use `pipx` |
| `Conflict detected: 'scalecodec' is installed` | Two SCALE codecs. See Step 1.1 |
| `Bad owner or permissions on ~/.ssh/config` | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/config` |
| `Permissions 0644 for 'id_ed25519_beam' are too open` | `chmod 600 ~/.ssh/id_ed25519_beam` |
| `Too many authentication failures` | Add `IdentitiesOnly yes` to the host block (Step 1.5) |
| `sudo: a terminal is required to read the password` | A command passed to `ssh` has no TTY. Use `ssh -t host 'sudo …'` |

### On the VPS

| Symptom | Cause and fix |
|---|---|
| `cannot create .ssh/authorized_keys: Permission denied` | `/home/ops/.ssh` is root-owned. `chown -R ops:ops /home/ops` from root |
| `chmod: cannot access '/root/deploy/*.sh'` | Your shell expanded the glob as `ops`. Use `sudo sh -c 'chmod +x /root/deploy/*.sh'` |
| `open /etc/beam/wcp.crt: permission denied`, restart loop | `/etc/beam` is `root:root` 750 — no search permission for `beam`. See Step 2.5 |
| `404 page not found` from `127.0.0.1:8781` | Wrong path, not a broken service. Health is `GET /healthz` |
| `missing /etc/beam/orchestrator.creds` | You registered by hand; create it from Step 3.1. Do **not** re-register |
| `BEAM_WORKER_ID or --worker-id is required` | That variable is in `beam.env`, not your shell. Read it from `worker.creds` (§7) |
| `nc` to 9470 refused | **Expected.** The room listener binds on demand (Step 3.5) |
| `orchestrator_not_routable` | Connected to NATS before registering. Redo Step 3.1, restart |
| `403 hotkey is not registered` | Step 1.4 not done, wrong netuid/network, or you used the **coldkey** address |
| `duplicate_control_session` | Two orchestrator processes on one hotkey. Run exactly one |
| `-ERR invalid client protocol` | Non-canonical binary. Rebuild from source |
| `x509: certificate relies on legacy Common Name field` | Cert has no SAN. Re-run Step 2.5 |
| Stuck in `qualifying` past 48 h | Check `success_rate` first (§10), then CPU saturation and that 8782 is reachable from outside |
| `readinessMultiplier` = 0 | Control plane disconnected, or certificate expired |
| Rank stuck in the bottom tier | Usually CPU-bound during bursts. Confirm BBR, raise worker limits, then apply the day-14 rule |
| Zero incentive but delivering work | Run `06-check-penalty.sh` — likely a zeroed penalty multiplier |

---

## 12. Reference and sources

### Live network state (block 9,117,624 — 2026-09-21)

- **256 / 256 UIDs — completely full.** 249 miners + 7 validators. Zero free slots
- **209** miners with non-zero incentive; 324 orchestrators registered, 308 live
- Alpha 0.005335 TAO (~$1.50) · pool depth ~4,622 TAO · burn at the MinBurn floor
- Churn: 18 UIDs in 24h, 90 in 7 days · traffic ~20 TiB/day, ~2 Gb/s average

### Why the nominal numbers are ~7× too high

SN105 emits 2,952 alpha/day to miners — nominally $4,432/day at spot. But actual new TAO flowing
into the subnet, read from the chain, is `SubnetTaoInEmission[105] ≈ 6.20 TAO/day ≈ $1,744/day`.
Miners' 41% share is **~$715/day of hard-backed value** against **$4,432/day of alpha issued** —
about **1:6.2**. If everyone converted as they earned, price would settle near that ratio. Alpha
fell 18% in a single day during research; that is the arithmetic playing out.

### Corrected here against Beam's own published material

| Claim | Correction |
|---|---|
| Orchestrator health at `/v1/orchestrator/health` | **Wrong.** The route is `GET /healthz`. Verified in the compiled route table |
| Worker needs its own UID "per the docs" | **No.** One hotkey serves both; BeamCore returns `worker_id == orchestrator_id` |
| "249 of 256 filled — 7 free slots" | **Zero free slots.** The 7 are validator UIDs |
| TAO inflow "17.6 TAO/day" | **~6.2 TAO/day**, read from `SubnetTaoInEmission` |
| "Budget ~1 TAO for registration" | Actual burn **0.0005 TAO ≈ $0.14** |
| Domain + Let's Encrypt required | **Not required.** Self-signed works — the worker trusts only your file |
| Room listener should be bound at startup | **On-demand** for `room.transfer.direct.v1`. An idle 9470 is correct |

### Added here, found nowhere else

`--allow-public-network-listeners` (defaults false, gates room listeners entirely) · the
two-address trap · TCP/BBR tuning with the BDP rationale · penalty classification and permanence
· re-registration preserving qualified status · `SAME_IP` sybil risk · the `/etc/beam` ownership
trap · the success-rate ceiling in §10.

### Sources

- [Beam-Network/beam](https://github.com/Beam-Network/beam) — orchestrator, worker, validator guides
- [Beam-Network/beam-core-public](https://github.com/Beam-Network/beam-core-public) — PRISM and tier logic
- Beam build `8be314b`, read directly for route tables and listener behaviour
- [BeamCore OpenAPI](https://beamcore.b1m.ai/openapi.json) · [dashboard](https://data.b1m.ai/)
- [taostats SN105](https://taostats.io/subnets/105/metagraph) · [PetroSky pricing](https://petrosky.io/pricing/pro)
- Deployment kit: [deploy/](deploy/) · full analysis: [SN105-Beam-mining-analysis.md](SN105-Beam-mining-analysis.md)

---

*Not financial advice. Figures verified 2026-09-22 and will change. Re-verify before committing
funds.*
