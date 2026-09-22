# Mining Bittensor Subnet 105 (Beam) — Complete Deployment Guide (Linux workstation)

**Verified 2026-09-21 against Finney block 9,117,624 and Beam's published source.**
Market context: TAO $281.40 · SN105 alpha 0.005335 TAO ≈ $1.50 · registration burn at the floor.
Prices and network state change fast — **`btcli` shows the real burn before charging; trust that
over any figure printed here.**

> **Which guide is this?** The variant for operators whose everyday computer runs **Linux**.
> Your Linux PC is the *control machine*: it holds the coldkey, runs `btcli`, signs the
> registration messages, and SSHes into the VPS. [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) is
> the same document with a Windows + WSL2 control machine. Only Steps 2–5 differ; everything
> from Step 6 onward runs on the VPS and is byte-identical in both.
>
> **This is the easier path.** WSL2 appears in the other guide purely to supply a Linux shell for
> `btcli`, which has no native Windows build. On Linux you already have one — plus `ssh-copy-id`,
> a single `~/.ssh` instead of two, and no Windows↔WSL filesystem boundary to drag wallets
> across. Any modern distro works; commands are given for Debian/Ubuntu, Fedora and Arch where
> they differ.

This guide merges two independent research passes and resolves where they disagreed by
querying the chain directly. Section 11 lists what changed and why.

---

## Table of contents

1. [Read this first](#1-read-this-first)
2. [What you are signing up for](#2-what-you-are-signing-up-for)
3. [How you get paid](#3-how-you-get-paid)
4. [Cost and realistic returns](#4-cost-and-realistic-returns)
5. [Step 0 — Before you spend anything](#5-step-0--before-you-spend-anything)
6. [Setup, steps 1–14](#6-setup)
7. [Running it](#7-running-it)
8. [Recovery — deregistration and penalties](#8-recovery)
9. [Troubleshooting](#9-troubleshooting)
10. [Glossary](#10-glossary)
11. [Corrections and sources](#11-corrections-and-sources)

---

## 1. Read this first

Beam pays in five fixed tiers. **Ranks 1–120 share 99% of miner emissions. Rank 121+ shares 1%.**
With ~209 earning miners, you must finish in roughly the top half to earn anything real.

| If you land at | Nominal/month | **Realistic/month** | Verdict |
|---|---|---|---|
| Tier A (rank 1–30) | ~$2,216 | **~$358** | Strongly profitable |
| Tier B (31–60) | ~$1,551 | **~$250** | Strongly profitable |
| Tier C (61–90) | ~$443 | **~$72** | Profitable |
| Tier D (91–120) | ~$177 | **~$29** | Break-even |
| **Tier E (121+, ~89 miners)** | ~$15 | **~$2** | **Loss** |

"Realistic" is what you bank if you convert alpha to TAO as you earn it. See §4 for the maths —
the gap is large and it is structural, not pessimism.

**Three facts that decide whether this is worth doing:**

1. **There are zero free UID slots.** The subnet is at 256/256. Registering **evicts someone**,
   and you get 25 hours of immunity before the same can happen to you.
2. **Registration is cheap — ~$0.14**, not hundreds of dollars. The experiment is low-risk.
3. **Your server choice barely matters.** One tier of rank is worth ~$150/month; the spread
   between sensible VPS plans is ~$25/month. **Where you rank is everything.**

This is a positive-expected-value bet with high variance, not passive income.

---

## 2. What you are signing up for

Beam (SN105) is a **decentralized data-transfer subnet** — not AI, not GPU. Miners move data
chunks between cloud storage endpoints and are paid for verified bytes delivered.

| Role | What it does | Needs a UID? |
|---|---|---|
| **Orchestrator** | The miner. Receives chunk offers, routes them to workers. **Earns emissions.** | **Yes** |
| **Worker** | Executes the byte transfers, returns signed results | **Unresolved — see below** |
| **Validator** | Relays BeamCore's weight vector on-chain | Yes — not your path |

> **Open question: does the worker need its own UID?**
> `docs/worker.md` says "Bittensor worker hotkey registered on subnet 105" and shows a
> `btcli subnets register` call. But the worker runtime accepts **no hotkey or wallet argument
> at all** — the hotkey only signs the one-time `POST /workers/register`; runtime identity is
> `worker_id` + Ed25519 node key + membership.
>
> **Resolve it cheaply:** register one hotkey, then try the worker registration with that same
> hotkey (Step 11). If it returns 403, register a second hotkey for ~$0.14 more. Do not
> pre-emptively buy two UIDs, and do not assume you only need one.

### Live network state (block 9,117,624 — 2026-09-21)

- **256 / 256 UIDs — completely full.** 249 miners + 7 validators. **Zero free slots.**
- **209** miners with non-zero incentive (down from 230 on 09-18 — 47 UIDs now earn nothing)
- **324 orchestrators registered, 308 live** — more running than there are slots
- Alpha: 0.005335 TAO (~$1.50) · pool depth ~4,622 TAO
- **Registration burn: 0.0005 TAO ≈ $0.14 — at the MinBurn floor**
- Churn: 18 UIDs registered in the last 24h, 90 in 7 days
- Network traffic: **~20 TiB/day, ~2 Gb/s average**, in ~10-minute lulls punctuated by bursts

---

## 3. How you get paid

Two separate scores. Confusing them is the most common mistake.

Source: [beam-core-public](https://github.com/Beam-Network/beam-core-public) — Beam's own
published scoring code, which I verified matches on-chain reality to within 0.1%.

### Stage A — Getting work assigned (PRISM)

```
performanceScore  = 0.4 × throughputScore + 0.6 × reliabilityScore
prismFinalScore   = performanceScore × readinessMultiplier × penaltyMultiplier
```

Confirmed constants from `prism/scoring.ts`:

| Constant | Value |
|---|---|
| Throughput weight | **0.4** |
| Reliability weight | **0.6** |
| Fleet normalization floor | **0.2** |
| Evidence lookback | 1 day |
| Reliability half-life | 1 hour |
| Graduation confidence | 0.9 |
| Target verified tasks | 120 |

Three consequences, all favourable to a careful small operator:

1. **Reliability outweighs throughput, 0.6 to 0.4.** A small flawless node beats a big flaky one.
2. **Normalization floors at 0.2**, so work allocation spreads only ~5× between best and worst.
3. **`readinessMultiplier` is linear in uptime.** 90% uptime costs you 10% of your score.
   A dropped control-plane connection sets it to **zero**.

From `assignment-engine.ts`, chunks are allocated **proportional to `prismFinalScore`**
(`allocationRule: "prism_final_score_desc"`), with ties broken by cryptographic shuffle.

### Stage B — Graduating out of the zero-emission pool

New orchestrators start in the **qualifying** pool and **earn nothing**. They receive
`qualifying_equal_share_rotation` work — randomized equal shares, so everyone gets a fair
shot at building evidence.

```
confidence = min(1, verifiedTasks/120) × successRate × (0.8 + 0.2 × ageRatio)
```

Graduate at **confidence ≥ 0.9**: ~120 verified tasks, near-perfect success rate, 24h+ of age.

### Stage C — Converting to emissions (the cliff)

```js
raw_i = verified_uploaded_mib_i × penalty_multiplier_i
const TIER_SHARES = { A: 0.5, B: 0.35, C: 0.1, D: 0.04, E: 0.01 };
```

- **PRISM score** decides how much work you get (~5× spread)
- **Verified uploaded MiB** decides your rank
- **Rank** drops you into a tier (~50× spread)

That mismatch is the cliff. Rank 60 → 61 is a **3.5× pay cut**; rank 120 → 121 is **14×**.

Ties break by rawScore → prismFinalScore → uploadedMiB → **lower UID wins**.

---

## 4. Cost and realistic returns

### Why the nominal numbers are ~7× too high

SN105 emits **2,952 alpha/day to miners** — nominally $4,432/day at spot. But the actual new TAO
flowing into the subnet, read straight from the chain, is:

```
SubnetTaoInEmission[105] = 861,000 rao/block ≈ 6.20 TAO/day ≈ $1,744/day
```

Miners' 41% share of that is **~$715/day of hard-backed value** against **$4,432/day of alpha
issued** — a ratio of about **1:6.2**. If everyone converted as they earned, the price would
settle near that ratio. Alpha fell 18% in a single day during research — that arithmetic
playing out.

Reality sits between the two columns in §1. Plan on the realistic column; treat nominal as upside.

### VPS sizing — the honest disagreement

Two defensible positions, and the evidence cuts both ways:

- **Measured average load is tiny.** ~91 GiB/day per miner ≈ **8.8 Mbps**. On average, 2 vCPU is
  ample.
- **But scoring happens in bursts.** Beam is TLS in + TLS out plus chunk hashing, so at burst
  rates it is genuinely CPU-bound, and `transfer_mbps` is measured *during* those bursts.

**The decisive number: the entire SN105 network moves ~2 Gb/s.** A single 2 Gbps port — standard
on every PetroSky plan — could carry the whole subnet. Per miner that is ~91 GiB/day average
(~8.8 Mbps), bursting to perhaps 70–350 Mbps. TLS both ways at 350 Mbps is ~88 MB/s of AES-GCM,
which AES-NI handles in under 10% of one core. **Hardware is not the binding constraint; work
allocation is.**

| Plan | Spec | €/mo | Break-even | Verdict |
|---|---|---|---|---|
| Standard | 1 vCPU / 2 GB / 20 GB | 6.99 | — | **No** — 2 GB RAM cannot hold the 2 GiB worker reservation alongside the orchestrator and OS, and 20 GB is tight for OS + Go toolchain + growing journals. OOM or disk-full destroys reliability (60% of score) |
| **Standard** | **2 vCPU / 4 GB / 40 GB** | **14.39** | **Tier D** | **Buy this** |
| Standard | 4 vCPU / 8 GB | 26.39 | Tier C | CPU you will not use |
| Dedicated | 2 vCPU / 4 GB | 30.92 | Tier C | Only if you measure CPU steal — see triggers |
| Dedicated | 4 vCPU / 8 GB | 42.92 | Tier C | Not justified by measured load |

The €14.39 plan **breaks even one full tier lower** than the dedicated options. Since this is an
uncertain bet, the lowest break-even threshold wins; the expensive box needs you to succeed
*more* just to pay for itself.

### Storage: you need almost none

**Transferred data is never stored.** The worker streams source → destination in a single pipe
(`internal/workload/handlers/transfer/handler.go`):

```go
sourceResponse, _ := h.client.Do(sourceRequest)                  // GET source
source  := io.LimitReader(sourceResponse.Body, part.Length)
counter := &countingReader{reader: io.TeeReader(source, hash)}   // SHA-256 computed in flight
destinationRequest, _ := http.NewRequestWithContext(ctx, method, part.Destination.URL, counter)
h.client.Do(destinationRequest)                                  // PUT destination
```

The source body becomes the destination request body directly. No temp file, no buffer
accumulating the chunk. A 40 MiB chunk never exists as 40 MiB anywhere — per concurrent transfer
the real memory cost is tens of KB of HTTP/TLS buffers. Room transfers behave the same way.

> `--scratch-bytes` (default 10 GiB) is an **admission-control accounting figure** the worker
> advertises and reserves against when deciding how much work to accept. `transfer.multipart`
> does not consume it. Do not size your disk around it.

What actually uses disk: Ubuntu (~3–5 GB), the Go toolchain and build cache (~1.5–2.5 GB), the
repo and binaries (~300 MB), and **journals that grow without bound** — `wcp-events.jsonl`,
`tasks.json`, receipts, payment evidence, plus the systemd journal. `00-bootstrap.sh` caps the
systemd journal at 500 MB and installs logrotate for the WCP journal.

**40 GB is comfortable.**

**Upgrade triggers — measure, don't guess.** Run `vmstat 1 10` during a burst:

- CPU steal (`st`) consistently >5% **and** rank below Tier C → Dedicated 2 vCPU
- `us + sy` pinned near 100% during bursts → more vCPU genuinely helps
- Neither, but stuck in Tier E → the problem is your network path or config. More CPU will not
  fix it; apply the day-14 rule.

**Location: Quebec City, not Paris.** Beam's routing table is US-dominated (~21 of 50 entries are
US/Virginia). Quebec→us-east-1 is ~40 ms; Paris is ~80 ms. Throughput is fleet-normalized against
those US competitors.

**Skip the €39.99 10 Gbps upgrade** initially — it costs more than the server and you will not be
bandwidth-bound at the start.

### One-time costs

| Item | Cost |
|---|---|
| SN105 registration burn | **0.0005 TAO ≈ $0.14** — currently at the MinBurn floor; dynamic |
| Second hotkey, if the worker needs one | ~$0.14 |
| Domain + TLS certificate | **$0 — not required** (see Step 6) |

Hold ~0.05 TAO for burn plus fees. Budgeting a whole TAO is unnecessary.

---

## 5. Step 0 — Before you spend anything

All three are free and any one can invalidate the plan.

### 0.1 — Ask the Beam Discord one question

Join via [b1m.ai](https://b1m.ai/):

> Does a solo operator need two SN105 registrations (orchestrator hotkey + worker hotkey), or can
> one hotkey serve both roles?

This is the genuine open question in §2 and it doubles your UID cost if the answer is "two".

### 0.2 — Get PetroSky's bandwidth answer in writing

Email `support@petrosky.io`:

> I plan to run a bandwidth-relay node moving roughly 3–5 TB/month sustained, in bursts.
> Is this acceptable under your fair-use policy?

Their current published Terms do **not** prohibit crypto mining — I checked the live page, and
the six-item prohibited list has no mining clause. (Search engines still surface an older version
that did; ignore it.) But they **do** ban Tor nodes, the list is explicitly non-exhaustive, and
"fair use" is undefined while reserving the right to "suspend or cancel any service at any time".
Their customer base is Forex/RDP/emulator users — you will be a significant outlier. Get it in
writing.

### 0.3 — Accept that there are no free slots

The subnet is at **256/256**. Registration evicts the lowest-scoring non-immune miner, and ~25
UIDs turn over daily. You are joining a queue, not filling a vacancy. Budget for two or three
re-registrations while you tune.

---

## 6. Setup

Scripts referenced below are in [deploy/](deploy/). You can run them or follow the commands by
hand — both are equivalent.

### Step 1 — Acquire TAO

Buy ~0.1 TAO on any exchange supporting Bittensor withdrawals (Kraken, Binance, KuCoin, MEXC).
Do not withdraw until you have a wallet address (Step 2).

### Step 2 — Create your wallet on your PC, never the VPS

> **Your coldkey controls your funds. It must never touch the VPS.**

Your Linux box is already the platform Bittensor targets: `bittensor-wallet` publishes manylinux
wheels, so there is nothing to compile and no WSL to install. Two things to get right first.

**1. Install the Python prerequisites.**

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y python3-venv python3-pip pipx

# Fedora / RHEL
sudo dnf install -y python3-pip python3-virtualenv pipx

# Arch
sudo pacman -S --needed python python-pip python-pipx
```

**2. Do not install into the system Python.**

Debian 12+, Ubuntu 23.04+, Fedora 38+ and Arch mark the system interpreter *externally managed*
(PEP 668), so a bare `pip install` aborts with:

```
error: externally-managed-environment
```

`--break-system-packages` is exactly as bad as it sounds here — btcli pins exact dependency
versions (see the `cyscale` note in Step 3) and will fight your distro's packages for them.
Use a virtualenv:

```bash
python3 -m venv ~/bt
source ~/bt/bin/activate
pip install -U bittensor-cli
btcli --version
```

or, if you would rather have `btcli` permanently on `PATH` without activating anything:

```bash
pipx install bittensor-cli      # isolated venv, shimmed into ~/.local/bin
```

> **Every `btcli` command in this guide runs on your Linux PC, never on the VPS.** If you chose
> the venv, activate it first (`source ~/bt/bin/activate`); the usual cause of "command not
> found" two days later is a fresh shell with the venv unactivated. `pipx` sidesteps that.

Your wallets live at `~/.bittensor/wallets/`. Create them:

```bash
btcli wallet new_coldkey --wallet-name beam_cold
btcli wallet new_hotkey  --wallet-name beam_cold --wallet-hotkey orch1
```

> **Lock the wallet directory down.** btcli sets sane modes, but confirm them — a coldkey
> readable by another local account is the one irreversible mistake available at this step:
> ```bash
> chmod 700 ~/.bittensor ~/.bittensor/wallets ~/.bittensor/wallets/beam_cold
> find ~/.bittensor/wallets -type f -exec chmod 600 {} +
> ls -lR ~/.bittensor/wallets/beam_cold
> ```
> If this machine is shared, has an unencrypted home directory, or syncs `~` to cloud storage,
> keep the coldkey elsewhere — a LUKS volume or an offline machine — and leave only the hotkey
> here. Only the hotkey is needed for day-to-day operation.

**Write the mnemonics on paper and store them offline. There is no recovery.**

Withdraw your TAO to the **coldkey** ss58 address (`btcli wallet list`).

### Step 3 — Register your hotkey on SN105 (on your Linux PC)

```bash
btcli subnets register --netuid 105 --network finney \
  --wallet-name beam_cold --wallet-hotkey orch1
```

btcli shows the burn cost before charging. Expect ~0.0005 TAO (the floor). If it has spiked to several TAO,
wait — it decays with a 360-block half-life.

> **btcli version note.** Use the newest `bittensor-cli` (9.23.x); do not pin an old one.
> Verified against btcli source: `--network` / `--subtensor.network` and
> `--wallet-name` / `--wallet.name` / `--wallet-hotkey` / `--wallet.hotkey` are all accepted
> aliases, and `subnet` is an alias for `subnets`. The dotted forms still work — the canonical
> dashed spellings are used here.
>
> **There is no `-w` short flag.** The wallet-name aliases are `--wallet-name`, `--name`,
> `--wallet_name`, `--wallet.name`. (`-H` is a valid short form for the hotkey.)
>
> btcli 9.x adds interactive prompts this command did not previously have — it asks about
> **safe registration** and **rate tolerance**. For scripted runs:
> `--unsafe` (or `--safe` plus `--tolerance 0.05`), `--json-output`, and `-y` / `--no-prompt`.
>
> btcli ships in the **`bittensor-cli`** package, not `bittensor` (which is the SDK). If the
> command is missing or behaves oddly, run `pip install -U bittensor-cli` and check
> `btcli --version`.

> ### ⚠ `scalecodec` / `cyscale` conflict
>
> If btcli aborts on startup with
> `Conflict detected: 'scalecodec' (py-scale-codec) is installed`, you have two SCALE codecs
> claiming the same namespace. `async-substrate-interface` (a btcli dependency) hard-fails at
> import when it sees `scalecodec`.
>
> **Cause:** the old **`substrate-interface`** package depends on `scalecodec<1.3`, while
> `bittensor-cli` depends on `cyscale`. Installing both breaks btcli.
>
> **Fix:**
> ```bash
> pip uninstall scalecodec cyscale -y
> pip install "cyscale==0.5.0" --force-reinstall   # match bittensor-cli's exact pin
> pip check                                        # should report no conflicts
> btcli --version                                  # confirm it starts
> ```
>
> **Do not follow the error message's own advice verbatim.** It says
> `pip install cyscale --force-reinstall`, which installs the newest cyscale (0.8.0) — but
> `bittensor-cli` 9.23.2 pins **`cyscale==0.5.0`** exactly, so that leaves you with:
> `bittensor-cli 9.23.2 requires cyscale==0.5.0, but you have cyscale 0.8.0`.
> Pin the version to whatever your btcli requires:
> ```bash
> pip show bittensor-cli | grep -i requires      # or check the pin directly
> ```
> If the set is still inconsistent, let pip resolve it wholesale:
> ```bash
> pip install --force-reinstall "bittensor-cli==9.23.2"
> ```
> If `substrate-interface` is also present, remove it too — it will drag `scalecodec` back in:
> ```bash
> pip uninstall substrate-interface -y
> ```
>
> **Do not `pip install substrate-interface` in the same environment as btcli.** You do not need
> it: `bittensor-cli` already ships `async-substrate-interface`, which exposes a drop-in sync
> `SubstrateInterface` with an identical `query()` and constructor. The scripts in
> [deploy/](deploy/) import it preferentially and only fall back to the legacy package.
>
> Use a clean virtualenv per role if you must keep both:
> ```bash
> python3 -m venv ~/bt_venv && source ~/bt_venv/bin/activate
> pip install -U bittensor-cli
> ```

Verify: `btcli wallet overview --netuid 105 --wallet-name beam_cold` should show a UID.

### Step 4 — Order and secure the VPS

Order: **PetroSky Quebec City — Standard 2 vCPU / 4 GB / 40 GB (€14.39), Ubuntu 24.04.**
No 10 Gbps upgrade, no extra storage, no backups (everything here is reproducible; back up your
hotkey and `api_key` yourself). See §4 for why this plan and not a larger one.

> ⚠ **Do not name your login user `beam`.** `00-bootstrap.sh` creates `beam` as a *system*
> account with `--shell /usr/sbin/nologin` to run the services under. If a login user called
> `beam` already exists, bootstrap silently skips creating it and your miner ends up running as
> a sudo-capable account — a needless privilege escalation. Pick any other name; `ops` is used
> below.

#### 4a — Create your SSH key (on your Linux PC)

An SSH key is a pair of files: a **private** key you keep, and a **public** key you hand to
servers. OpenSSH ships with every mainstream distro — `ssh -V` confirms it; if it is somehow
missing, `sudo apt install openssh-client` (or `openssh-clients` / `openssh` on Fedora / Arch).

```bash
# What do you already have?
ls -l ~/.ssh/*.pub 2>/dev/null
```

Reusing an existing key is perfectly valid — one key can authenticate to any number of servers.
But a **dedicated key per purpose** is better: if you ever need to revoke it, you remove one
`authorized_keys` line instead of re-keying everything. Give it its own filename with `-f`:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_beam -C "beam-vps"
```

That writes two files:

| File | What it is |
|---|---|
| `~/.ssh/id_ed25519_beam` | **private key — never share, never copy to a server** |
| `~/.ssh/id_ed25519_beam.pub` | **public key — this is what you install on the VPS** |

Set a passphrase. `ssh-agent` then asks for it once per desktop session rather than once per
connection:

```bash
eval "$(ssh-agent -s)"          # most desktop sessions already run one
ssh-add ~/.ssh/id_ed25519_beam
```

View the public key (one line, starts with `ssh-ed25519`):

```bash
cat ~/.ssh/id_ed25519_beam.pub
```

#### 4a-bis — Tell SSH to use it automatically

A non-default filename means `ssh` will not find it on its own. Rather than passing `-i <path>`
to every command, add a host alias to `~/.ssh/config`:

```bash
cat >> ~/.ssh/config <<'EOF'

Host beam-vps
    HostName YOUR_VPS_IP
    User ops
    IdentityFile ~/.ssh/id_ed25519_beam
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 6
EOF
chmod 600 ~/.ssh/config
```

`IdentitiesOnly yes` matters: without it SSH offers every key you own and the server may reject
you with `Too many authentication failures` before it reaches the right one. The `chmod` matters
too — OpenSSH refuses to use a config or private key that is group- or world-readable, with
`Bad owner or permissions on /home/<you>/.ssh/config`. The two `ServerAlive*` lines stop a NAT
or firewall idle-timeout from dropping long `journalctl -f` sessions and the Step 7 build.

From then on `ssh beam-vps` and `scp file beam-vps:/path` just work, with no `-i` and no IP to
remember.

> **Use `tmux` on the VPS for anything long-running.** `ssh beam-vps -t tmux new -As beam` gives
> you a session that survives a dropped link; the Go build in Step 7 takes several minutes and
> a disconnect mid-build leaves you guessing at what completed.

#### 4b — Create the admin user and install the key

SSH into the VPS as `root` using the password PetroSky emailed you, then:

```bash
adduser ops && usermod -aG sudo ops
```

Now — the part that is genuinely simpler from Linux — push the key with `ssh-copy-id` instead of
pasting it. Run this on your **Linux PC**, authenticating with the password you just set for
`ops`:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_beam.pub ops@YOUR_VPS_IP
```

It creates `/home/ops/.ssh` with the correct modes, appends the key to `authorized_keys`, and
skips keys that are already installed. Verify:

```bash
ssh -i ~/.ssh/id_ed25519_beam ops@YOUR_VPS_IP 'ls -ld ~/.ssh && cat ~/.ssh/authorized_keys'
```

> **`cannot create .ssh/authorized_keys: Permission denied`** means `/home/ops/.ssh` already
> exists and is owned by `root` — the usual result of creating it with a bare `mkdir` while
> logged in as root. `ssh-copy-id` cannot recover from that because it connects as `ops`. Repair
> ownership from root, then re-run it:
> ```bash
> ssh root@YOUR_VPS_IP 'chown -R ops:ops /home/ops && chmod 700 /home/ops/.ssh'
> ```

If `ssh-copy-id` is unavailable, install the key through root instead — note the
`-o ops -g ops`, which is what keeps the directory writable by `ops`:

```bash
install -d -m 700 -o ops -g ops /home/ops/.ssh
nano /home/ops/.ssh/authorized_keys      # paste the whole ssh-ed25519 ... line, save
chown ops:ops /home/ops/.ssh/authorized_keys
chmod 600 /home/ops/.ssh/authorized_keys
```

#### 4c — Test, then harden

> **Open a second terminal and confirm `ssh beam-vps` logs you in without a password before
> running the next block.** If you disable password login while your key is misconfigured, you
> are locked out of the server permanently and PetroSky's web console is the only way back.
>
> Debug with `ssh -v beam-vps` — the verbose output names which key file it offered.

```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

```bash
sudo apt update && sudo apt install -y ufw fail2ban
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 8782/tcp    # orchestrator WCP — must be public
sudo ufw allow 9470/tcp    # worker room transfers — extra earnings, see Step 12
sudo ufw enable
```

Ports **8780** and **8781** stay on `127.0.0.1`. Never expose them.

### Step 5 — Copy the hotkey to the VPS

Your wallet sits on the same filesystem as your SSH config — no WSL boundary, no path
translation, no second `~/.ssh`. From your **Linux PC**:

```bash
scp -r ~/.bittensor/wallets/beam_cold/hotkeys beam-vps:/home/ops/hk_tmp
```

> **Copy the `hotkeys/` subdirectory, not `beam_cold/`.** `coldkey` and `coldkeypub.txt` live one
> level up, and that one-word difference is what keeps your funds off a public server. Check both
> ends before and after:
> ```bash
> ls ~/.bittensor/wallets/beam_cold/hotkeys      # should list only hotkey names, e.g. orch1
> ssh beam-vps 'ls -l /home/ops/hk_tmp'          # same, and nothing called coldkey
> ```

Then **on the VPS**:

```bash
mkdir -p ~/.bittensor/wallets/beam_cold/hotkeys
mv ~/hk_tmp/* ~/.bittensor/wallets/beam_cold/hotkeys/
chmod 600 ~/.bittensor/wallets/beam_cold/hotkeys/*
```

**Never copy the file named `coldkey`.** A hotkey signs work; it cannot move funds.

### Step 5b — Put the deploy kit on the VPS

Steps 6–14 call scripts by absolute path (`/root/deploy/...`), so the [deploy/](deploy/)
directory has to get there first. From your **Linux PC**, in the directory holding this guide:

```bash
# from your Linux PC
scp -r deploy beam-vps:/home/ops/deploy

# then on the VPS
sudo install -d -m 700 /root/deploy
sudo cp -r /home/ops/deploy/. /root/deploy/
sudo find /root/deploy -name '*.sh' -exec chmod +x {} +
rm -rf /home/ops/deploy
sudo ls -l /root/deploy
```

`rsync -av --delete deploy/ beam-vps:/home/ops/deploy/` is the better form once you start
iterating on the scripts — it re-sends only what changed.

> **Re-syncing a script later?** Run the remote half with `ssh -t`, or `sudo` aborts with
> *"a terminal is required to read the password"* — a command passed to `ssh` gets no TTY, so
> `sudo` has nowhere to prompt:
> ```bash
> scp deploy/00-bootstrap.sh beam-vps:/home/ops/
> ssh -t beam-vps 'sudo cp /home/ops/00-bootstrap.sh /root/deploy/ >   && sudo find /root/deploy -name "*.sh" -exec chmod +x {} + >   && rm /home/ops/00-bootstrap.sh'
> ```

> **Why `find` and not `chmod +x /root/deploy/*.sh`?** Your shell expands the glob as `ops`
> *before* `sudo` runs, and `/root` is mode 700 — so it matches nothing and `chmod` is handed the
> literal string, giving `cannot access '/root/deploy/*.sh': No such file or directory`. The
> files are fine. Any wildcard inside a root-only path needs to be expanded by root:
> `sudo sh -c 'chmod +x /root/deploy/*.sh'` works too.

> Scripts that read `/etc/beam/beam.env` (`99-healthcheck.sh`, `06-check-penalty.sh`) need root
> or membership of a group you grant read access; run them with `sudo`.

### Step 6 — Generate the TLS certificate (self-signed, no domain)

> **`<YOUR_PUBLIC_IP>`, `<PUBLIC_IP>` and `<VPS_IP>` all mean one thing: the VPS's own public
> IPv4** — never your workstation's, which nothing ever dials and which is usually dynamic and
> behind NAT. The same value goes into Steps 6, 8, 9, 11, 12 and 14. Read it off the VPS once:
> ```bash
> curl -4 -s ifconfig.me; echo
> ip -4 addr show scope global | grep inet     # cross-check — PetroSky gives a dedicated IPv4
> ```
> `YOUR_VPS_IP` in Step 4 is the same address too; from Step 5 onward the `beam-vps` SSH alias
> stands in for it.

```bash
sudo /root/deploy/01-gen-cert.sh <YOUR_PUBLIC_IP>     # the VPS's public IPv4
```

> **You do not need a domain or Let's Encrypt.** The worker builds its trust store from an
> *empty* pool and trusts only the file you hand it:
> ```go
> roots := x509.NewCertPool()          // empty — never SystemCertPool()
> roots.AppendCertsFromPEM(caBytes)    // only BEAM_WCP_CA
> ```
> A public CA certificate would be ignored unless you placed it in that same file. Self-signed
> with a 10-year expiry also removes the 90-day renewal failure mode, which would otherwise zero
> your readiness multiplier if it ever lapsed.

Requirements the script handles: **SAN is mandatory** (Go ignores Common Name), plus `CA:TRUE`
and `keyCertSign` because the cert is its own root. The IP you pass is written into the SAN as
`IP:<PUBLIC_IP>`, and workers verify the address they dialled against it — a workstation IP
there produces a certificate that fails verification for everyone. The script prints the SAN
block when it finishes; confirm your VPS IP is in it.

> **Ownership is fixed up in Step 7, not here.** This script chowns the cert and key to
> `root:beam`, but at this point Step 7 has not created the `beam` account yet, so that chown
> silently no-ops and both files stay `root:root` — the failure surfaces much later as
> `open /etc/beam/wcp.crt: permission denied` in the orchestrator log. `00-bootstrap.sh`
> re-applies the ownership for exactly this reason. If you ever regenerate the cert *after*
> bootstrap has run, the script gets it right on its own.

### Step 7 — Install Go and build Beam

```bash
sudo /root/deploy/00-bootstrap.sh
```

#### Or the full manual equivalent

Building by hand is fine, but the script does **six** things and only one of them is the build.
Skipping the rest costs you rank. Run all of this as root:

```bash
# 1. Packages
apt-get update && apt-get install -y curl git ca-certificates openssl jq \
  python3 python3-venv python3-pip logrotate

# 2. Service account — nologin, NOT your SSH login user
useradd --system --create-home --home-dir /var/lib/beam --shell /usr/sbin/nologin beam
mkdir -p /opt/beam /var/lib/beam/orchestrator /var/lib/beam/worker /etc/beam
chown -R beam:beam /var/lib/beam
# The chown is not optional. root:root + 750 denies `beam` SEARCH permission on the directory,
# and every file inside then fails to open however permissive its own mode is.
chown root:beam /etc/beam
chmod 750 /etc/beam

# 3. Go (latest stable)
cd /tmp && curl -fsSLO "https://go.dev/dl/$(curl -fsSL 'https://go.dev/VERSION?m=text'|head -1).linux-amd64.tar.gz"
rm -rf /usr/local/go && tar -C /usr/local -xzf go*.linux-amd64.tar.gz
echo 'export PATH=/usr/local/go/bin:$PATH' > /etc/profile.d/go.sh
export PATH=/usr/local/go/bin:$PATH

# 4. Build from canonical source
git clone https://github.com/Beam-Network/beam.git /opt/beam
cd /opt/beam && mkdir -p bin
go build -trimpath -o bin/beam-orchestrator ./cmd/beam-orchestrator
go build -trimpath -o bin/beam-worker       ./cmd/beam-worker
git rev-parse HEAD > /opt/beam/BUILD_REVISION

# 5. TCP tuning — this one directly affects your rank
cat > /etc/sysctl.d/99-beam.conf <<'SYSCTL'
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 30000
net.core.somaxconn = 8192
net.ipv4.tcp_rmem = 4096 262144 67108864
net.ipv4.tcp_wmem = 4096 262144 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.ip_local_port_range = 10240 65535
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 2097152
SYSCTL
modprobe tcp_bbr; echo tcp_bbr > /etc/modules-load.d/bbr.conf
sysctl --system
sysctl -n net.ipv4.tcp_congestion_control    # must print: bbr

# 6. Cap log growth (nothing rotates these by default)
sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
systemctl restart systemd-journald
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
```

Then install the two unit files from [deploy/systemd/](deploy/systemd/) into
`/etc/systemd/system/` and run `systemctl daemon-reload`.

> **Build from source. Never use a downloaded binary.** `-ERR invalid client protocol` means a
> non-canonical build.

**Why step 5 is not optional:** on a 2 Gbps link at ~40 ms RTT the bandwidth-delay product is
~10 MB, and stock `tcp_rmem` maxima of ~6 MB cap a single stream below line rate. PRISM scores
`transfer_mbps` fleet-normalised against competitors, so an untuned kernel costs you rank
directly — for two commands.

### Step 8 — Register the orchestrator with BeamCore

Sign on your PC (safer — the official CLI, no custom tooling):

> **`<HOTKEY_SS58>` is the *hotkey's* ss58 address**, from the `Hotkey` row of
> `btcli wallet list` — not the coldkey's, which appears directly above it and also starts with
> `5`. The coldkey address is used once, to receive your TAO in Step 2, and never appears in a
> config file or API call. Swapping them yields `403 hotkey is not registered`, because a
> coldkey is not a neuron. Confirm the right one carries your UID first:
> ```bash
> btcli wallet overview --netuid 105 --wallet-name beam_cold
> ```
> Using the scripts avoids the question — they resolve the ss58 from the wallet name.

```bash
btcli wallet sign --wallet-name beam_cold --wallet-hotkey orch1 --use-hotkey \
  --message "<HOTKEY_SS58>:10"
```

`10` is the fee percentage you keep. **The signed message and submitted `fee_percentage` must
match**, or the signature check fails.

> **What the fee is, and why 10.** It is the cut your orchestrator keeps from workers registered
> under it — Beam allows third parties to attach their workers to your orchestrator, and this
> sets the split. **If you own both the orchestrator and its only worker, the value is
> irrelevant**: emissions land on the hotkey holding the UID either way, so the fee just moves
> value between your own pockets. 10 is nothing more than the default in
> [03-register-orchestrator.sh](deploy/03-register-orchestrator.sh); leave it there.
>
> It starts mattering only if you later host other people's workers. More workers means more
> capacity and more verified uploaded MiB, which is what sets your rank — so a low fee recruits,
> a high one deters. 10% is conventional and puts nobody off.
>
> Treat the value as sticky. Re-registering appears to update an existing record rather than
> create one (the script warns when no `api_key` comes back for exactly this reason), so a later
> change is probably possible — but the kit does not confirm it.

Then on the VPS:

```bash
curl -X POST https://beamcore.b1m.ai/orchestrators/register \
  -H 'Content-Type: application/json' \
  -d '{"hotkey":"<HOTKEY_SS58>","signature":"0x...","fee_percentage":10,
       "name":"my-orch","region":"north-america",
       "url":"http://<YOUR_PUBLIC_IP>:8782","max_workers":64}'
```

**Prefer the script.** `sudo /root/deploy/03-register-orchestrator.sh <coldkey> <hotkey> <PUBLIC_IP>`
signs and posts in one step, taking the fee from a single variable so the message and the body
cannot drift apart — the one mistake that reliably breaks this call. A different fee goes in the
optional 4th argument (`... <PUBLIC_IP> 5`), never by editing one of the two places by hand.

> **Save `orchestrator_id` and `api_key` immediately — the key is returned only once.**
> 403 means your hotkey is not on the metagraph; go back to Step 3.

> **If you registered by hand rather than with the script, also write
> `/etc/beam/orchestrator.creds`.** Only `03-register-orchestrator.sh` creates it, and
> Steps 11 and 14 plus `06-check-penalty.sh` read it — without it the health and penalty checks
> silently skip their PRISM queries. Once `beam.env` is filled in (Step 9), derive it:
> ```bash
> sudo sh -c '. /etc/beam/beam.env
> umask 077
> printf "ORCHESTRATOR_ID=%s
ORCHESTRATOR_API_KEY=%s
HOTKEY_SS58=%s
" >   "$BEAM_ORCHESTRATOR_ID" "$BEAMCORE_NATS_PASSWORD" "$BEAM_BITTENSOR_HOTKEY" >   > /etc/beam/orchestrator.creds
> chmod 600 /etc/beam/orchestrator.creds'
> ```

### Step 9 — Configure

**The file already exists — do not write it from scratch.** Step 7's `00-bootstrap.sh` installed
`/etc/beam/beam.env` from [deploy/beam.env.example](deploy/beam.env.example) at mode 0640,
owner `root`, group `beam`. Your job here is to replace the five `REPLACE_*` placeholders:

```bash
sudo grep -n REPLACE_ /etc/beam/beam.env      # shows exactly what is left to fill
sudoedit /etc/beam/beam.env
```

| Placeholder | Value | Available from |
|---|---|---|
| `REPLACE_hotkey_ss58` (×2) | your hotkey ss58 | Step 2 — `btcli wallet list` |
| `REPLACE_orchestrator_api_key` | the one-time `api_key` | **Step 8 — shown once, never again** |
| `REPLACE_orchestrator_id` | the `orchestrator_id` | Step 8 |
| `REPLACE_PUBLIC_IP` (×2) | the VPS's public IPv4 | Step 6 |
| `REPLACE_worker_id` | the `worker_id` | Step 11 — leave until then |

`03-register-orchestrator.sh` and `04-register-worker.sh` print the values they obtain but do
**not** write them into the file; that edit is yours. Re-run the `grep` afterwards — a leftover
`REPLACE_` is a service that starts and then fails to authenticate.

> **Why not just type out the variables you see referenced in this guide?** Because the worker
> unit interpolates `${BEAM_WORKER_CAPABILITIES}`, `${BEAM_WORKER_MEMORY_BYTES}`,
> `${BEAM_WORKER_SCRATCH_BYTES}`, `${BEAM_WORKER_BANDWIDTH_MBPS}` and the two
> `${BEAM_ROOM_TRANSFER_*}` values straight into its `ExecStart`
> ([beam-worker.service](deploy/systemd/beam-worker.service)). A hand-written subset produces a
> malformed command line, and omitting `BEAM_WCP_CA` / `BEAM_WCP_SERVER_NAME` leaves the worker
> unable to verify TLS against your own orchestrator. Edit the installed template; do not
> replace it.

The cert paths `01-gen-cert.sh` printed at the end of Step 6 — `BEAM_WCP_TLS_CERT`,
`BEAM_WCP_TLS_KEY`, `BEAM_WCP_CA`, `BEAM_WCP_SERVER_NAME=beam-orch` — are **already correct in
the template**. That message is generic advice for a hand-built config; you can ignore it.

### ⚠ The mistake that silently kills your miner

Two addresses. **Only one may be loopback.**

| Variable | Correct value | Direction |
|---|---|---|
| `BEAMCORE_GATEWAY_URL` | `http://<PUBLIC_IP>:8782` | **must be public** |
| `BEAM_WCP_ADDRESS` | `127.0.0.1:8782` | internal; loopback is correct |

Six of the 50 orchestrators in Beam's live routing table have `127.0.0.1` in the first one. They
receive no work and likely don't know why.

### Step 10 — Start the orchestrator

```bash
sudo systemctl enable --now beam-orchestrator
sudo journalctl -u beam-orchestrator -f
curl -s http://127.0.0.1:8781/healthz; echo
```

A healthy start looks like this in the **journal** (`journalctl -u beam-orchestrator`) —
three lines, then silence:

```
starting beam-orchestrator-beamcore NATS connector
Beam Orchestrator WCP listening on 0.0.0.0:8782 (TLS 1.3)
Beam Orchestrator 0.2.0 orchestrator_id=<uuid> listening on 127.0.0.1:8781
```

`(TLS 1.3)` means the cert **and** key loaded; `0.0.0.0` means the WCP listener is public, not
loopback; the `orchestrator_id` means it read your Step 8 registration out of `beam.env`. Any
`Main process exited` line after them means it is still failing - read the line above it.

`/healthz` answers separately, as JSON — this is what success looks like:

```json
{"orchestrator_id":"fb58b7d8-75bf-42f8-b281-2c8ee01d952c","status":"ok"}
```

The id there must match the one in the log and the one BeamCore returned in Step 8.

> **The health route is `GET /healthz`, at the root.** Beam's published `docs/orchestrator.md`
> documents `/v1/orchestrator/health`; that route does not exist and returns
> `404 page not found`. Verified against the compiled route table in
> `internal/orchestrator/server/server.go` at build revision `8be314b`. A 404 is still proof the
> HTTP server is up — `Connection refused` is the answer that means the process is down. Note
> also that port 8782 speaks TLS, so `curl http://...:8782` returns nothing; that is expected.
>
> The other routes on 8781, all `/v1/orchestrator/`-prefixed: `manifest`, `memberships` (used by
> Step 11), `observations`, `placements`, `workloads/{offers,commits,cancel}`,
> `circuits[/revoke]`, `transfers/{plan,dispatch}`, `network/links`, `tasks`, `task-events`.

Local success is not the same as reachable. Confirm from **your Linux PC**, not the VPS:

```bash
nc -vz <YOUR_PUBLIC_IP> 8782
```

A timeout here is almost always `ufw` — `sudo ufw status` should list `8782/tcp` and `9470/tcp`.
An orchestrator that looks healthy in its own log and is unreachable from outside receives no
work at all.

### Step 11 — Register the worker

This step spans both machines. **Sign on your Linux PC; run the script on the VPS.** The script
needs root, the orchestrator's loopback API and `/etc/beam/orchestrator.creds`, so it cannot run
from your workstation — but signing needs your wallet, which is deliberately not on the VPS.

**On your Linux PC**, sign the worker message. Note the port in the message is **9000**, which is
the registration port, not the 9470 room-transfer port:

```bash
btcli wallet sign --wallet-name beam_cold --wallet-hotkey orch1 --use-hotkey   --message "<HOTKEY_SS58>:<YOUR_PUBLIC_IP>:9000"
btcli wallet list        # read both ss58 addresses off this
```

**On the VPS**, pass the three values in and run the script:

```bash
sudo env HOTKEY_SS58=<hotkey ss58> COLDKEY_SS58=<coldkey ss58> SIG=0x<signature>   /root/deploy/04-register-worker.sh beam_cold orch1 <YOUR_PUBLIC_IP> 500
```

With those set, the script skips `02-sign.py` entirely and no wallet tooling is needed on the
server. It echoes the message it will use — check it matches what you signed, character for
character, before it posts.

> **Why not let the script sign on the VPS?** It would need `bittensor_wallet` installed there,
> plus `coldkeypub.txt`, which Step 5 intentionally leaves behind — and `sudo` resets `HOME` to
> `/root`, so the hotkey you copied to `/home/ops/.bittensor` would not be found anyway. Keeping
> the wallet off the server is the point, so signing stays on your PC.
>
> Use `sudo env VAR=...`, not `sudo VAR=...`. With the default `env_reset` in sudoers the latter
> is rejected with *"not allowed to set the following environment variables"*.

> **Be honest with `claimed_bandwidth_mbps`.** PRISM scores *provider-verified* throughput, so
> overclaiming gains nothing — but it pulls in work you cannot deliver, and failures hit
> reliability, which carries **60%** of your performance score.

> **A 403 here answers the §2 open question.** It means the worker needs its own registered
> hotkey. Register a second one and re-run.

### Step 12 — Enable room transfers (extra earnings, easily missed)

Room transfers are additional volume — additional uploaded MiB, which is what sets your rank.
Three conditions must all hold:

1. The worker advertises **both** `room.transfer.direct.v1` and `room.transfer.e2ee.v2`
2. The room listener binds publicly: `--room-transfer-addr 0.0.0.0:9470` (default is
   `127.0.0.1:0` — loopback, unusable)
3. **`--allow-public-network-listeners`** is set — it defaults to **false** and gates the room
   handler entirely

That third flag appears in neither Beam's docs nor the reference guide, and without it the public
room listener will not serve.

```bash
ExecStart=/opt/beam/bin/beam-worker serve \
  --capabilities transfer.multipart,transfer.multipart.fanout.v1,room.transfer,room.transfer.direct.v1,room.transfer.e2ee.v2 \
  --allow-public-network-listeners \
  --room-transfer-addr 0.0.0.0:9470 \
  --room-transfer-advertise-url https://<YOUR_PUBLIC_IP>:9470
```

### Step 13 — Start the worker

```bash
sudo systemctl enable --now beam-worker
```

### Step 14 — Verify

```bash
./99-healthcheck.sh
```

Checks services, ports, the two-address trap, certificate SAN, BeamCore control session, PRISM
pool, and your live on-chain rank and tier. Also:

```bash
/opt/beam/bin/beam-worker doctor --worker-id "$BEAM_WORKER_ID"
nc -vz <YOUR_PUBLIC_IP> 8782     # from OUTSIDE the VPS
```

---

## 7. Running it

### What to expect, and when

**You earn nothing on day one.** This is normal.

| Time | What happens |
|---|---|
| 0 h | Registered. Pool = `qualifying`. Earnings **zero** |
| 0–24 h | Equal-share rotation builds your confidence score |
| ~24 h | Confidence hits 0.9 → **qualified** |
| **25 h** | **Immunity ends — you can now be evicted** |
| 24 h+ | Production work; incentive appears on chain |
| 3–7 days | Tier stabilises |

Graduation lands almost exactly when immunity expires, and you enter at the bottom of the
ranking while ~25 UIDs are evicted daily. This is the squeeze — survive it and you are fine.

### The two numbers that decide your income

```bash
./99-healthcheck.sh | grep -A3 "On-chain position"
```

1. **Pool** — must flip `qualifying` → `qualified` within a few days
2. **Rank** — ≤120 you are earning; 121+ you are not

Alongside those, the orchestrator's own control API tells you whether work is actually arriving
— more directly than the log does:

```bash
curl -s http://127.0.0.1:8781/v1/orchestrator/tasks | jq 'length'   # chunks assigned to you
curl -s http://127.0.0.1:8781/v1/orchestrator/manifest | jq .       # what you advertise
```

During the qualifying period a rising task count is the earliest sign PRISM is routing to you.
A flat zero after a few hours, with the service healthy, points at reachability — re-check
`nc -vz <YOUR_PUBLIC_IP> 8782` from off the box.

### Uptime alerting

Every minute offline scales `readinessMultiplier` down linearly; a dropped control-plane
connection sets it to zero. Set a free UptimeRobot monitor, keep `Restart=always`, rotate logs so
the disk never fills, and rebuild weekly:

```bash
cd /opt/beam && git pull --ff-only && go clean -cache
go build -trimpath -o bin/beam-orchestrator ./cmd/beam-orchestrator
go build -trimpath -o bin/beam-worker       ./cmd/beam-worker
sudo systemctl restart beam-orchestrator beam-worker
```

### Watch for the permanent penalty

```bash
./06-check-penalty.sh      # run daily from cron
```

`integrity_chunk_mismatch` has coefficient **1.0 and never expires** — one event zeroes that
hotkey forever. Any `etag`/`integrity`/`checksum` line in the worker log is an early warning.

**What causes it, and what doesn't.** The worker computes SHA-256 in flight and compares against
`expected_sha256`, so corruption is caught mid-transfer. Because **no data touches disk**, a
failing disk is not a realistic cause. The actual vectors are:

- **RAM corruption** — PetroSky's ECC memory genuinely helps here
- **A middlebox mangling the stream** — never put a transparent proxy or caching layer between
  the worker and object storage
- **A modified or stale build** — always build from canonical source with `-trimpath`

### Day-14 decision checkpoint

Be disciplined.

| Result | Action |
|---|---|
| Rank ≤ 120, stable | Working. Consider the 10 Gbps upgrade **only** if genuinely bandwidth-bound |
| Rank 121+, not improving | Earning ~$1.60/mo against a ~$36 bill. **Shut it down.** |

The registration burn is sunk. The monthly bill is not. Do not run a Tier E node for months
hoping the tier structure changes.

### Converting alpha to TAO

```bash
btcli stake remove --netuid 105 --wallet-name beam_cold --wallet-hotkey orch1
```

> Pool depth is only ~4,667 TAO. **Unstake in small tranches**, not one lump, or you eat the
> slippage yourself.

---

## 8. Recovery

### If you are deregistered (the likely outcome)

This is **not a ban**. Nothing is blacklisted. Re-register with the **same hotkey** — your
BeamCore record is keyed to the hotkey, so your **qualified pool status persists** and you skip
the 24-hour dead period, starting inside a fresh 25-hour immunity window.

**Do not "start fresh" with a new hotkey after a deregistration — it is strictly worse.**

Reuse the same VPS, same IP, same install. Cost: ~$0.14.

### If you are penalised

| Penalty | Coefficient | Rows to zero you | Expires |
|---|---|---|---|
| `fraud` | 0.1 | 10 | 168 h |
| `sybil` | 0.5 | 2 | 168 h |
| `integrity_chunk_mismatch` | **1.0** | **1** | **never** |

Classify by time: if the zero survives 168 clean hours, it is the permanent one. A sudden drop
from 1.0 straight to 0.0 is the integrity signature; fraud degrades gradually.

Fraud penalties can be cleared self-service, at the cost of demotion to `qualifying`:

```bash
curl -X DELETE https://beamcore.b1m.ai/orchestrators/history \
  -H "Authorization: Bearer <api-key>" -H 'Content-Type: application/json' -d '{"confirm":true}'
```

**If integrity is confirmed, that hotkey is finished.** You need a new hotkey — and because
`SybilViolationType` includes `SAME_IP`, a new IP alongside it.

---

## 9. Troubleshooting

### On the VPS

| Symptom | Cause and fix |
|---|---|
| `orchestrator_not_routable` | Connected to NATS before registering. Re-run Step 8, restart. |
| `403 hotkey is not registered` | Step 3 not done, or wrong netuid/network |
| `missing /etc/beam/orchestrator.creds — run 03 first` | You registered in Step 8 by hand; only the script writes that file. Derive it from `beam.env` (see Step 8) — do not re-register |
| `duplicate_control_session` | Two orchestrator processes on one hotkey. Run exactly one. |
| `-ERR invalid client protocol` | Non-canonical binary. Rebuild from source. |
| `x509: certificate relies on legacy Common Name field` | Cert has no SAN. Re-run Step 6. |
| Stuck in `qualifying` past 48 h | Check CPU saturation (`htop`), worker transfer errors, and that 8782 is reachable from outside |
| `readinessMultiplier` = 0 | Control plane disconnected, or cert expired |
| `404 page not found` from `127.0.0.1:8781` | Wrong path, not a broken service. Health is `GET /healthz`, not `/v1/orchestrator/health` (the published docs are wrong). A 404 proves the server is up |
| `open /etc/beam/wcp.crt: permission denied`, service restart-looping | `/etc/beam` is `root:root` mode 750, so the `beam` user cannot search it; the cert files may also still be `root:root`. Fix: `sudo chown root:beam /etc/beam /etc/beam/wcp.crt /etc/beam/wcp.key /etc/beam/beam.env`, then `sudo chmod 750 /etc/beam; sudo chmod 644 /etc/beam/wcp.crt; sudo chmod 640 /etc/beam/wcp.key /etc/beam/beam.env`. Verify with `sudo -u beam cat /etc/beam/wcp.key > /dev/null` before restarting |
| Rank stuck in Tier E | Usually CPU-bound during bursts. Raise worker memory/bandwidth limits, confirm BBR, then apply the day-14 rule |
| Zero incentive but delivering work | Run `./06-check-penalty.sh` — likely a zeroed penalty multiplier |

### On your Linux PC (control machine)

| Symptom | Cause and fix |
|---|---|
| `error: externally-managed-environment` | PEP 668 — your distro protects the system Python. Use the venv or `pipx` from Step 2, not `--break-system-packages` |
| `btcli: command not found` in a new shell | The venv is not activated. `source ~/bt/bin/activate`, or install with `pipx` so the shim is always on `PATH` |
| `Conflict detected: 'scalecodec' is installed` | Two SCALE codecs in one environment — see the callout in Step 3 |
| `Bad owner or permissions on /home/<you>/.ssh/config` | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/config` |
| `Permissions 0644 for 'id_ed25519_beam' are too open` | `chmod 600 ~/.ssh/id_ed25519_beam` |
| `Too many authentication failures` | SSH offered every key you own before the right one. Add `IdentitiesOnly yes` to the host block (Step 4a-bis) |
| `ssh-copy-id: ERROR: No identities found` | Name the key explicitly: `ssh-copy-id -i ~/.ssh/id_ed25519_beam.pub ops@IP` |
| `sudo: a terminal is required to read the password` | A command passed to `ssh` has no TTY. Use `ssh -t host 'sudo ...'` |
| `sh: 1: cannot create .ssh/authorized_keys: Permission denied` | `/home/ops/.ssh` exists but is root-owned — it was made with a plain `mkdir` as root. Fix from root: `chown -R ops:ops /home/ops && chmod 700 /home/ops/.ssh`, then re-run `ssh-copy-id`. If `/home/ops` is missing entirely (`useradd` without `-m`), create it first: `install -d -m 750 -o ops -g ops /home/ops` |
| `chmod: cannot access '/root/deploy/*.sh': No such file or directory` | The glob is expanded by your shell as `ops`, which cannot read mode-700 `/root`. Let root expand it: `sudo sh -c 'chmod +x /root/deploy/*.sh'`. Confirm the files arrived with `sudo ls -l /root/deploy` |
| SSH drops during the Step 7 build | Idle timeout. The `ServerAlive*` lines in Step 4a-bis, plus `tmux` on the VPS |
| `btcli` hangs on `finney` | Public endpoint congestion, not your machine. Retry; `--network finney` has no local dependency |

---

## 10. Glossary

| Term | Meaning |
|---|---|
| **TAO** | Bittensor's main token (~$250) |
| **Alpha** | A subnet's own token. You are paid in SN105 alpha (~$1.50), not TAO |
| **netuid** | Subnet ID. Beam is 105 |
| **UID** | Your slot. SN105 has 256, all taken |
| **Coldkey** | Controls funds. Never on the VPS |
| **Hotkey** | Signs work. Safe on the VPS. Cannot move funds |
| **finney** | Bittensor mainnet |
| **Immunity period** | Grace window before eviction. SN105: 7,500 blocks ≈ 25 h |
| **Tempo** | Weight-setting interval. SN105: 360 blocks ≈ 72 min |
| **PRISM** | Beam's scoring system — decides how much work you are routed |
| **WCP** | Beam's worker control protocol (TLS 1.3, port 8782) |
| **BeamCore** | Beam's central coordinator. Closed; computes all scores |

---

## 11. Corrections and sources

This guide reconciles two independent research passes. Where they disagreed, I queried the chain.

**Corrected from the reference guide:**

| Claim | Correction |
|---|---|
| "249 of 256 filled — **7 free slots**, you can register now" | **Zero free slots.** `SubnetworkN = MaxAllowedUids = 256`. The 7 are validator UIDs. Registering evicts someone. |
| TAO inflow "0.49% × 3,600 = 17.6 TAO/day" | **5.81 TAO/day**, read directly from `SubnetTaoInEmission`. The 0.49% share was right; the 3,600 TAO/day base was not — the on-chain sum across 87 subnets is ~1,206 TAO/day. |
| "Assume 30–50% less than nominal" | Structural ratio is **~1:6.8**, i.e. ~85% less if fully converting |
| "Budget ~1 TAO (~$240)" for registration | Actual burn **0.0005 TAO ≈ $0.14** at the floor |
| Domain + Let's Encrypt required | **Not required.** Self-signed works — proven from `beam-worker`'s use of `x509.NewCertPool()` |
| Worker needs a UID "per the docs" | **Genuinely unresolved.** Runtime takes no hotkey. Test for ~$0.14 rather than assuming |

**Adopted from the reference guide** (it was right and I had missed these): the Step 0 pre-flight
discipline, VPS hardening, `btcli wallet sign` instead of custom tooling, `-trimpath` builds,
**room transfers on port 9470**, the day-14 decision checkpoint, unstaking slippage, and — most
valuably — the existence of
[beam-core-public](https://github.com/Beam-Network/beam-core-public), which let both passes verify
the scoring logic against Beam's own source rather than inferring it.

**Corrected against the compiled binary (build `8be314b`):** Beam's `docs/orchestrator.md` and
the reference guide both document the orchestrator health endpoint as
`GET /v1/orchestrator/health`. That route does not exist — `internal/orchestrator/server`
registers `GET /healthz` at the root. Everything else in that namespace, `memberships` included,
matches the docs. Trust the route table over the documentation.

**Added here:** `--allow-public-network-listeners` (defaults false, gates room listeners), the
two-address trap, TCP/BBR tuning with BDP rationale, penalty classification and permanence,
re-registration keeping qualified status, and `SAME_IP` sybil risk.

### Sources

- [Beam-Network/beam](https://github.com/Beam-Network/beam) — orchestrator/worker/validator guides
- [Beam-Network/beam-core-public](https://github.com/Beam-Network/beam-core-public) — PRISM and tier logic
- Finney chain via `substrate-interface`, block 9,099,090
- [BeamCore OpenAPI](https://beamcore.b1m.ai/openapi.json) · [dashboard](https://data.b1m.ai/)
- [taostats SN105](https://taostats.io/subnets/105/metagraph) · [PetroSky pricing](https://petrosky.io/pricing/pro)
- Full analysis: [SN105-Beam-mining-analysis.md](SN105-Beam-mining-analysis.md)

---

*Not financial advice. Figures verified 2026-09-18 and will change. Re-verify before committing funds.*
