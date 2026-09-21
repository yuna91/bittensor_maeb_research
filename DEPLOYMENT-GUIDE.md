# Mining Bittensor Subnet 105 (Beam) — Complete Deployment Guide

**Verified 2026-09-21 against Finney block 9,117,624 and Beam's published source.**
Market context: TAO $281.40 · SN105 alpha 0.005335 TAO ≈ $1.50 · registration burn at the floor.
Prices and network state change fast — **`btcli` shows the real burn before charging; trust that
over any figure printed here.**

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

> ### ⚠ btcli does not install on native Windows
>
> `bittensor-cli` depends on `bittensor-wallet==4.1.0`, which is a **Rust** extension
> ([RaoFoundation/btwallet](https://github.com/opentensor/btwallet)) that publishes **no Windows
> wheels** — only macOS, manylinux, and a source tarball. pip therefore tries to compile it and
> fails with:
>
> ```
> ERROR: Failed building wheel for bittensor-wallet
> ```
>
> No pip flag fixes this. **Use WSL2** (Bittensor targets Linux; the manylinux wheels install
> cleanly):
>
> ```powershell
> wsl --install -d Ubuntu-24.04      # then reboot if prompted
> ```
> ```bash
> # inside WSL
> sudo apt update && sudo apt install -y python3-venv python3-pip
> python3 -m venv ~/bt && source ~/bt/bin/activate
> pip install -U bittensor-cli
> btcli --version
> ```
>
> Your wallets then live at `~/.bittensor/wallets/` inside WSL, reachable from Windows Explorer
> at `\\wsl$\Ubuntu-24.04\home\<user>\.bittensor\wallets\`. **Run every `btcli` command in this
> guide from the WSL shell**, and use plain `scp`/`ssh` there rather than the PowerShell forms.
>
> Compiling natively is possible (install Rust via `rustup` plus MSVC Build Tools with
> "Desktop development with C++"), but Bittensor does not test Windows — you would be debugging
> runtime problems alone. WSL2 is the supported path.

```bash
pip install -U bittensor-cli

btcli wallet new_coldkey --wallet-name beam_cold
btcli wallet new_hotkey  --wallet-name beam_cold --wallet-hotkey orch1
```

**Write the mnemonics on paper and store them offline. There is no recovery.**

Withdraw your TAO to the **coldkey** ss58 address (`btcli wallet list`).

### Step 3 — Register your hotkey on SN105 (on your PC / WSL)

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

#### 4a — Create your SSH key (on your Windows PC)

An SSH key is a pair of files: a **private** key you keep, and a **public** key you hand to
servers. Windows 11 includes OpenSSH, so no extra software is needed.

```powershell
# What do you already have?
Get-ChildItem $env:USERPROFILE\.ssh\*.pub
```

Reusing an existing key is perfectly valid — one key can authenticate to any number of servers.
But a **dedicated key per purpose** is better: if you ever need to revoke it, you remove one
`authorized_keys` line instead of re-keying everything. Give it its own filename with `-f`:

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519_beam" -C "beam-vps"
```

That writes two files:

| File | What it is |
|---|---|
| `C:\Users\<you>\.ssh\id_ed25519_beam` | **private key — never share, never copy to a server** |
| `C:\Users\<you>\.ssh\id_ed25519_beam.pub` | **public key — this is what you install on the VPS** |

View the public key (one line, starts with `ssh-ed25519`):

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519_beam.pub
```

#### 4a-bis — Tell SSH to use it automatically

A non-default filename means `ssh` will not find it on its own. Rather than passing
`-i <path>` to every command, add a host alias to `C:\Users\<you>\.ssh\config`:

```powershell
@"

Host beam-vps
    HostName YOUR_VPS_IP
    User ops
    IdentityFile ~/.ssh/id_ed25519_beam
    IdentitiesOnly yes
"@ | Out-File -Encoding ascii -Append "$env:USERPROFILE\.ssh\config"
```

`-Encoding ascii` matters — a UTF-8 BOM makes OpenSSH fail to parse the file.
`IdentitiesOnly yes` matters too: without it SSH offers every key you own and the server may
reject you with `Too many authentication failures` before reaching the right one.

From then on `ssh beam-vps` and `scp file beam-vps:/path` just work, with no `-i` and no IP to
remember.

#### 4b — Create the admin user and install the key

SSH into the VPS as `root` using the password PetroSky emailed you, then:

```bash
adduser ops && usermod -aG sudo ops
install -d -m 700 -o ops -g ops /home/ops/.ssh
nano /home/ops/.ssh/authorized_keys      # paste the whole ssh-ed25519 ... line, save
chown ops:ops /home/ops/.ssh/authorized_keys
chmod 600 /home/ops/.ssh/authorized_keys
```

Or push it from Windows in one command instead of pasting (Windows has no `ssh-copy-id`).
Note this connects as **root with the password**, so it does not use your new key yet:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519_beam.pub | ssh root@YOUR_VPS_IP `
  "install -d -m 700 -o ops -g ops /home/ops/.ssh && cat >> /home/ops/.ssh/authorized_keys && chown ops:ops /home/ops/.ssh/authorized_keys && chmod 600 /home/ops/.ssh/authorized_keys"
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

From the **WSL** shell, where your wallet now lives:

```bash
scp -r ~/.bittensor/wallets/beam_cold/hotkeys beam-vps:/home/ops/hk_tmp
```

> WSL has its own `~/.ssh`. Either copy `id_ed25519_beam` and your `config` into WSL, or run the
> copy from PowerShell against the WSL path instead:
> `\wsl$\Ubuntu-24.04\home\<user>\.bittensor\wallets\beam_cold\hotkeys`

```bash
mkdir -p ~/.bittensor/wallets/beam_cold/hotkeys
mv ~/hk_tmp/* ~/.bittensor/wallets/beam_cold/hotkeys/
chmod 600 ~/.bittensor/wallets/beam_cold/hotkeys/*
```

**Never copy the file named `coldkey`.** A hotkey signs work; it cannot move funds.

### Step 6 — Generate the TLS certificate (self-signed, no domain)

```bash
sudo /root/deploy/01-gen-cert.sh <YOUR_PUBLIC_IP>
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
and `keyCertSign` because the cert is its own root.

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

```bash
btcli wallet sign --wallet-name beam_cold --wallet-hotkey orch1 --use-hotkey \
  --message "<HOTKEY_SS58>:10"
```

`10` is the fee percentage you keep. **The signed message and submitted `fee_percentage` must
match.** Then on the VPS:

```bash
curl -X POST https://beamcore.b1m.ai/orchestrators/register \
  -H 'Content-Type: application/json' \
  -d '{"hotkey":"<HOTKEY_SS58>","signature":"0x...","fee_percentage":10,
       "name":"my-orch","region":"north-america",
       "url":"http://<YOUR_PUBLIC_IP>:8782","max_workers":64}'
```

Or run `./03-register-orchestrator.sh <coldkey> <hotkey> <PUBLIC_IP>`, which signs and posts in
one step.

> **Save `orchestrator_id` and `api_key` immediately — the key is returned only once.**
> 403 means your hotkey is not on the metagraph; go back to Step 3.

### Step 9 — Configure

`/etc/beam/beam.env`, mode 0640:

```bash
CORE_SERVER_URL=https://beamcore.b1m.ai
BEAM_ENV=prod
NETUID=105
SUBTENSOR_NETWORK=finney
BEAM_BITTENSOR_HOTKEY=<HOTKEY_SS58>
BEAMCORE_NATS_URL=tls://orch-gateway.b1m.ai:4222
BEAMCORE_NATS_USER=<HOTKEY_SS58>
BEAMCORE_NATS_PASSWORD=<api_key>
BEAMCORE_GATEWAY_URL=http://<YOUR_PUBLIC_IP>:8782
BEAM_WCP_LISTEN_ADDR=0.0.0.0:8782
BEAM_WCP_TLS_CERT=/etc/beam/wcp.crt
BEAM_WCP_TLS_KEY=/etc/beam/wcp.key
BEAM_ROOM_TUNNEL_COORDINATOR_URL=https://coordinator.b1m.ai
```

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
curl http://127.0.0.1:8781/health
```

### Step 11 — Register the worker

```bash
btcli wallet sign --wallet-name beam_cold --wallet-hotkey orch1 --use-hotkey \
  --message "<HOTKEY_SS58>:<VPS_IP>:9000"
```

```bash
./04-register-worker.sh <coldkey> <hotkey> <VPS_IP> 500
```

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

| Symptom | Cause and fix |
|---|---|
| `orchestrator_not_routable` | Connected to NATS before registering. Re-run Step 8, restart. |
| `403 hotkey is not registered` | Step 3 not done, or wrong netuid/network |
| `duplicate_control_session` | Two orchestrator processes on one hotkey. Run exactly one. |
| `-ERR invalid client protocol` | Non-canonical binary. Rebuild from source. |
| `x509: certificate relies on legacy Common Name field` | Cert has no SAN. Re-run Step 6. |
| Stuck in `qualifying` past 48 h | Check CPU saturation (`htop`), worker transfer errors, and that 8782 is reachable from outside |
| `readinessMultiplier` = 0 | Control plane disconnected, or cert expired |
| Rank stuck in Tier E | Usually CPU-bound during bursts. Raise worker memory/bandwidth limits, confirm BBR, then apply the day-14 rule |
| Zero incentive but delivering work | Run `./06-check-penalty.sh` — likely a zeroed penalty multiplier |

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
