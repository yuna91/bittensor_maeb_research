# Bittensor SN105 "Beam" — Mining Viability Analysis

**Date:** 2026-09-18 · **Chain snapshot:** Finney block 9,096,291 · *(burn figure refreshed 09-21 — see note)*
**Market context:** TAO $249.64 · SN105 alpha 0.005481 TAO ≈ $1.37 (−18% / 24h)

Data gathered from three independent layers: the Finney chain directly (`substrate-interface`), Beam's live BeamCore API (`beamcore.b1m.ai`), and the public repo (`Beam-Network/beam`). Figures are measured, not taken from subnet aggregator sites — several of those are AI-generated and materially wrong (see [Marketing vs. reality](#52-marketing-vs-reality)).

---

## 1. Verdict

**Can you mine it?** Yes. The barrier is genuinely low — permissionless registration for **~$0.14**, self-service API key via hotkey signature, no whitelist, no GPU, no ML competition. That combination is rare on Bittensor today.

**Will it be profitable?** Split the question:

| Framing | Assessment |
|---|---|
| **Cheap experiment** | **Worth doing.** Downside ≈ $1 registration + $40–50/mo server. You learn the full Bittensor miner lifecycle on a subnet where reaching a paying tier is actually achievable. |
| **Reliable income** | **No.** Realistic sustained-sell value is ~$10/day *if* you reach the top 30 of 230, against ~10% daily UID churn and a token depreciating ~18%/day. |
| **Token bet** | **This is the real trade.** Mining SN105 is a leveraged long on SN105 alpha. Judge it as such, not as an infrastructure business. |

**Hard requirement:** a Linux host with a public IP, open WCP port, a self-signed TLS cert (§8.2 — one `openssl` command, no domain needed), 24/7 uptime, and a **1 Gbps-class port**. A Windows desktop behind NAT will not work. Metered cloud egress (AWS/GCP at $0.08–0.12/GB) inverts the margin — use unmetered dedicated bandwidth.

---

## 2. What SN105 actually is

A decentralized **data-transfer network**, not an AI/ML subnet. No GPUs, no models, no inference.

| Role | Function |
|---|---|
| **Client** | Requests "move data A → B under these conditions" |
| **BeamCore** (team-operated, closed source) | Assigns work, tracks transfers, verifies results, computes **all** scores |
| **Orchestrator** — *this is the miner* | Holds the UID; receives chunk offers over NATS; routes them to workers |
| **Worker** | Actually moves bytes between presigned S3 / R2 / GCS URLs |
| **Validator** | Fetches BeamCore's finished weight vector and writes it on-chain |

Orchestrator and worker are Go binaries; the validator is Python. MIT licensed.

**Repo maturity:** created 2026-05-13, 72 commits, 3 stars, 6 forks, last push 2026-09-17. Actively maintained but very young relative to the subnet itself, which was registered at block 6,841,399 — **313 days ago (~November 2025)**.

---

## 3. How you get paid

Two **separate** scores. The distinction is the single most misunderstood thing about this subnet.

### 3.1 PRISM — decides how much *work* you are routed

```
throughput_score  = fleet_normalize(decayed_assignment_verified_mbps)
reliability_score = fleet_normalize(raw_reliability)

performance_score = 0.40 x throughput_score + 0.60 x reliability_score

readiness_multiplier = (ready AND connected ? 1 : 0) x active_time_ratio
penalty_multiplier   = clamp(1 - pressure, 0, 1)

prism_final_score = performance_score x readiness_multiplier x penalty_multiplier
```

- Fleet-normalized into a compressed band **[0.2, 1]** against peers in the same pool
- Evidence window **1 day**; throughput and reliability both decay on a **1-hour half-life**
- `readiness_multiplier` is linear in uptime — downtime is punished directly and immediately

### 3.2 Emission weights — decides what you are *paid*

A different formula, `formula_version: tiered_weight_verified_uploaded_mib_x_penalty_v3`:

```
base_raw_i = verified_uploaded_MiB_i x penalty_multiplier_i
```

Qualified orchestrators are ranked by `base_raw` and dropped into five **fixed-rank tiers**. Within a tier, the bucket splits proportionally to `base_raw`.

| Tier | Rank band | Documented bucket | **Measured on-chain** |
|---|---|---|---|
| A | 1–30 | 50% | **49.99%** |
| B | 31–60 | 35% | **34.90%** |
| C | 61–90 | 10% | **10.13%** |
| D | 91–120 | 4% | **4.05%** |
| E | 121+ | 1% | **0.92%** |

The documented mechanism is live and matches on-chain reality to within 0.1%.

> **The cliffs are brutal.** Rank 60 → 61 is a **3.5× pay cut**. Rank 120 → 121 is a **14× cut**. Tier position, not marginal performance, determines income.

### 3.3 The qualification gate

New miners start in a **qualifying** pool earning **nothing**:

```
confidence_score = verified_task_ratio x success_rate x maturity_factor
```

Graduation to the **qualified** pool (the only pool that receives validator weight) requires **confidence ≥ 0.9** — roughly **120 distinct verified tasks** plus **~1 day of account age**.

### 3.4 Penalties

| Kind | Coefficient | Duration |
|---|---|---|
| `fraud` | 0.1 | 168 h |
| `integrity_chunk_mismatch` | 1.0 | **permanent** |
| `sybil` | 0.5 | 168 h |

---

## 4. Live measured network state

### 4.1 On-chain (netuid 105)

| Metric | Value |
|---|---|
| UIDs | **256 / 256 — completely full** |
| Miners with non-zero incentive | 230 |
| Validators (permit) | 7 |
| **Registration burn** | 0.004498 TAO on 09-18; **decayed to the 0.0005 TAO floor ≈ $0.14 by 09-21** — dynamic, `btcli` shows the real cost |
| Immunity period | 7,500 blocks = **25.0 hours** |
| Tempo | 360 blocks = 72 min |
| Alpha price | 0.005481 TAO |
| Pool depth | 4,667 TAO ≈ $1.17M |
| Alpha in pool / outstanding | 851,517 / 2,062,153 |
| Subnet owner cut | 11,796 / 65,535 = **18%** |
| Alpha emission (out) | 1.0 alpha/block = **7,200 alpha/day** |
| **TAO inflow** (`SubnetTaoInEmission`) | 855,646 rao/block = **6.16 TAO/day ≈ $1,538/day** |

### 4.2 BeamCore API

| Metric | Value |
|---|---|
| Live orchestrators (heartbeat) | **308** |
| Registered orchestrators | 324 |
| UID slots available | 256 |

**More orchestrators are running than there are slots to hold them.**

---

## 5. Traffic profile — bursty, not steady

This is the key operational finding. Sampling `deliveryAttempts` over ~6 minutes:

| Window (UTC) | Chunks dispatched | Rate |
|---|---|---|
| 18:20:50 → 18:23:20 | 0 | **idle** |
| 18:23:20 → 18:25:51 | 5,824 | ~39/s |
| 18:25:51 → 18:26:08 | 1,637 | **~96/s** |

The pattern: **~10-minute lulls punctuated by bursts** that dispatch 6,000–7,500 chunks (≈230–290 GiB of work) in a couple of minutes.

| Aggregate | Value |
|---|---|
| Lifetime (this BeamCore process) | 533,720 chunk-tasks, 652 client transfers |
| Network throughput | **~20 TiB/day ≈ 2 Gb/s average** |
| Client transfers | **~670/day** (one every ~2 min) |
| Peak *dispatch* rate | ~96 chunks/s ≈ 30 Gb/s of work handed out |
| Per-miner average (230 miners) | ~91 GiB/day ≈ **8.8 Mbps** |

### 5.1 Why "8.8 Mbps average" is a trap

Average volume is trivial — ~2.7 TB/month, comfortably inside any unmetered plan. **But you are not scored on average volume.**

PRISM scores `transfer_mbps` — *measured speed during a transfer*, fleet-normalized against every other orchestrator, on a 1-hour half-life. Emissions then rank you by `verified_uploaded_MiB`. **Both metrics are won or lost inside the bursts.**

A 100 Mbps link will move its 91 GiB/day without breaking a sweat and still rank near the bottom, because during a burst it posts a low `transfer_mbps` and claims fewer chunks than the miner next to it on a 10 Gbps port.

> **Size the box for burst headroom, not transfer allowance.**
> A dedicated server with a 1 Gbps unmetered port (~€40–50/mo, Hetzner/OVH class) is close to ideal: high peak, low fixed cost, no egress metering. A cheap 100 Mbps VPS is not competitive.

### 5.2 Marketing vs. reality

| Claim (aggregator sites) | Measured |
|---|---|
| "847 Gb/s aggregate bandwidth" | ~2 Gb/s average, ~30 Gb/s peak dispatch |
| "1,247 active miner nodes" | 256 UIDs max, 230 earning; 308 live orchestrators |
| "2.4 PB moved" | ~20 TiB observed on the current process |

The 847 Gb/s figure is advertised worker *capacity*, not utilization. **The network runs at roughly 0.24% of its claimed capacity on average.**

---

## 6. Economics

### 6.1 Nominal emissions

7,200 alpha/day → 18% owner cut → 5,904 alpha/day split 50/50 → **2,952 alpha/day to miners** (≈ 16.2 TAO ≈ **$4,039/day** across all miners at spot).

| Tier | Rank | alpha/day | **$/day** | **$/month** |
|---|---|---|---|---|
| A | 1–30 | 49.2 | **$67** | $2,020 |
| B | 31–60 | 34.4 | **$47** | $1,414 |
| C | 61–90 | 9.8 | **$13.50** | $404 |
| D | 91–120 | 3.9 | **$5.40** | $162 |
| E | 121–230 | 0.27 | **$0.37** | $11 |

### 6.2 Why those numbers are inflated ~4×

`SubnetTaoInEmission` = 6.16 TAO/day ≈ **$1,538/day** is the **entire real TAO inflow** into SN105. But 7,200 alpha/day is handed out, nominally worth 39.5 TAO.

If every recipient sold immediately, miners' 41% share of genuine inflow is **~$630/day across all 230 miners** — putting **Tier A at ~$10.50/day, not $67**.

Alpha is **down 18% in 24h**, which is precisely what that arithmetic predicts. **You are paid in a token whose emission rate exceeds its capital inflow by roughly 4×.** The $67/day is only realisable if you hold and alpha appreciates — a speculative position, not mining revenue.

### 6.3 Cost side

| Item | Cost |
|---|---|
| Registration burn | ~$0.14 one-off (floor; dynamic) |
| Server (1 Gbps unmetered dedicated) | ~$40–50/mo |
| Bandwidth consumed | ~2.7 TB/mo — free on unmetered |
| Metered cloud egress (**avoid**) | ~$250–320/mo at $0.09–0.12/GB |

Bandwidth **cost** is negligible. Bandwidth **capacity** is what you are competing on.

---

## 7. Risks

1. **~10% daily UID churn.** 25 UIDs registered in the last 24h; 42 in 3d; 79 in 7d; 138 in 30d; 250 in 90d. Only **6 of 256** UIDs are older than 90 days. The subnet is full, so every registration evicts someone.

2. **The immunity squeeze.** Immunity is 25h. PRISM graduation needs ~24h + 120 verified tasks. You exit immunity *precisely* as you graduate into Tier E with near-zero `base_raw` — i.e. as the prime eviction candidate. Expected Tier-E tenure ≈ 110 UIDs ÷ 25 evictions/day ≈ **4.4 days**. You must climb to Tier C or better within days.

3. **Total scoring centralization.** The docs are explicit that the validator *"does not compute PRISM locally for the production path"* — it fetches BeamCore's materialized vector and relays it on-chain. The team controls routing, verification, scoring and weights. `GET /orchestrators/prism-scores/{uid}` requires authentication, so **scores are not publicly auditable**. If your routing is throttled you have no recourse and no evidence.

4. **Validator concentration.** UID 0 takes 2,633 of 2,952 validator alpha/day — **89%**.

5. **Loose operator quality.** 6 of 50 entries in the public routing table advertise `127.0.0.1`; one has a malformed URL. Easy to out-compete, but it signals a loose operation.

6. **Third-party ratings mixed to negative.** ICM Analytics 43/100 ("avoid"); SubnetRadar 50–62/100 ("fair"), flagging low development activity.

---

## 8. Setup requirements

### 8.1 Infrastructure

- Linux host, public IP, 24/7 uptime (uptime multiplies your score linearly)
- **1 Gbps-class unmetered port** — burst capacity is the competitive variable
- Open inbound WCP port (orchestrator listens on `0.0.0.0:8782`)
- Outbound access to BeamCore, Core NATS, Bittensor, and task storage URLs
- Go 1.24+ to build; Python 3.10–3.12 only if also running a validator

**One VPS is sufficient for the whole stack.** Orchestrator and workers are designed to
co-locate — the worker guide's own membership example posts to `http://127.0.0.1:8781`. Default
ports do not collide:

| Process | Port | Scope |
|---|---|---|
| Worker control API | `127.0.0.1:8780` | local only |
| Orchestrator control API | `127.0.0.1:8781` | local only |
| Orchestrator WCP listener | `0.0.0.0:8782` | **inbound, public** |

### 8.2 The WCP TLS certificate — self-signed, 30 seconds

`BEAM_WCP_TLS_CERT` / `BEAM_WCP_TLS_KEY` secure the **orchestrator ↔ worker** link only. This is
a private channel where you control both ends, so **no public CA, no domain, and no Let's Encrypt
is needed or even useful.**

The worker builds its trust store from an *empty* pool
([cmd/beam-worker/main.go:335](https://github.com/Beam-Network/beam/blob/main/cmd/beam-worker/main.go#L335)):

```go
roots := x509.NewCertPool()          // empty — never SystemCertPool()
roots.AppendCertsFromPEM(caBytes)    // populated only from BEAM_WCP_CA
TLSConfig: &tls.Config{MinVersion: tls.VersionTLS13, RootCAs: roots, ServerName: *wcpServerName}
```

It trusts exactly one thing: the file you pass as `BEAM_WCP_CA`. The server side loads the keypair
with no `ClientAuth`, so there is no mutual TLS to arrange either.

```bash
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout wcp.key -out wcp.crt \
  -subj "/CN=beam-orch" \
  -addext "subjectAltName=DNS:beam-orch,DNS:localhost,IP:127.0.0.1,IP:YOUR.PUBLIC.IP" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign"
```

Wire the same file into both sides:

| Side | Variable | Value |
|---|---|---|
| Orchestrator | `BEAM_WCP_TLS_CERT` | `/path/wcp.crt` |
| Orchestrator | `BEAM_WCP_TLS_KEY` | `/path/wcp.key` |
| Worker | `BEAM_WCP_CA` | `/path/wcp.crt` (same file) |
| Worker | `BEAM_WCP_SERVER_NAME` | `beam-orch` |
| Worker | `BEAM_WCP_ADDRESS` | `127.0.0.1:8782` (co-located) |

Gotchas:

- **SAN is mandatory.** Go ignores the legacy Common Name field; a cert without
  `subjectAltName` fails with `x509: certificate relies on legacy Common Name field`.
- `BEAM_WCP_SERVER_NAME` must exactly match a SAN entry, but **need not be a real DNS name** —
  the dial address and the verified name are independent, so `beam-orch` is fine.
- `CA:TRUE` + `keyCertSign` are required because the cert acts as its own root.
- 10-year expiry is deliberate: you control both ends, so there is no renewal treadmill.
- EC is a faster alternative: `-newkey ec -pkeyopt ec_paramgen_curve:P-256`.

**No certificate is needed for** `tls://orch-gateway.b1m.ai:4222` (Beam's own cert, validated
against the OS trust store) or for `BEAMCORE_GATEWAY_URL` (an advertised address — 36 of 50
orchestrators in the live routing table use plain `http://`).

### 8.3 Worker topology and sizing

Worker runtime defaults (`cmd/beam-worker/main.go`):

| Flag | Default | Meaning |
|---|---|---|
| `--bandwidth-mbps` | 100 | reservable bandwidth advertised upstream |
| `--memory-bytes` | 512 MiB | reservable memory — caps concurrent chunks |
| `--scratch-bytes` | 10 GiB | reservable scratch space — **accounting only**; the worker streams source→destination via `io.TeeReader` and writes no payload to disk |

At the documented 40 MiB chunk size, the 512 MiB default bounds a worker to roughly **13
concurrent chunk transfers**. That, not the worker count, is usually the first ceiling you hit.

**Start with 1–2 workers and raise their limits; do not scale by worker count.** Workers on one
box share one NIC — ten workers on a 1 Gbps port still yield 1 Gbps, just with more context
switching. Add workers for parallelism headroom and failure isolation, not for capacity.

**Do not over-claim `claimed_bandwidth_mbps` or `--bandwidth-mbps`.** PRISM scores
*provider-verified* throughput, so inflated claims win nothing — but they pull in more chunks than
you can deliver, and failures plus reassignments feed the reliability signal, which is **60% of
`performance_score`**. Orchestrators are also evaluated at pool level, so one weak worker drags
down the whole UID. Under-promise.

> **Open item:** `docs/worker.md` lists "Bittensor worker hotkey registered on subnet 105" as a
> requirement, but the worker runtime accepts **no hotkey or wallet argument** — the hotkey only
> signs the one-time `POST /workers/register`; runtime identity is `worker_id` + Ed25519 node key
> + membership. Each worker needing its own UID is also arithmetically impossible (256 slots, 308
> live orchestrators). Reusing the orchestrator hotkey to sign worker registration should
> therefore work, but this was **not verified against the live API** — confirm on first run. If it
> is rejected, each worker costs an extra UID and the economics change materially.

### 8.4 Registration sequence

1. `btcli subnets register --netuid 105 --network finney` (~$0.14 burn)
2. Sign `{hotkey}:{fee_percentage}` with the hotkey
3. `POST https://beamcore.b1m.ai/orchestrators/register`
4. **Save the returned `api_key` — it is shown exactly once and is not retrievable**
5. Sign `{worker_hotkey}:{public_ip}:9000` → `POST /workers/register` → save `worker_id`
6. `./bin/beam-worker node-id --node-key data/worker/node.key`
7. `POST http://127.0.0.1:8781/v1/orchestrator/memberships` to bind worker → orchestrator
8. Start orchestrator, then worker (`fee_percentage` is moot when you pay yourself)

Registration **must** precede the NATS connection, or you get `orchestrator_not_routable`.

### 8.5 Mainnet config

```bash
export CORE_SERVER_URL=https://beamcore.b1m.ai
export BEAM_ENV=prod
export BEAMCORE_NATS_URL=tls://orch-gateway.b1m.ai:4222
export BEAMCORE_NATS_USER=<orchestrator_hotkey_ss58>
export BEAMCORE_NATS_PASSWORD=<orchestrator_api_key>
export BEAMCORE_GATEWAY_URL=http://<YOUR_PUBLIC_IP>:8782
export BEAM_WCP_LISTEN_ADDR=0.0.0.0:8782
export BEAM_WCP_TLS_CERT=/path/wcp.crt
export BEAM_WCP_TLS_KEY=/path/wcp.key
export SUBTENSOR_NETWORK=finney
export NETUID=105
```

### 8.6 Failure modes to avoid

- **`BEAMCORE_GATEWAY_URL` set to `127.0.0.1`** — you will never receive work. Six of the 50
  orchestrators in the live routing table have made exactly this mistake. Note the asymmetry:
  `BEAM_WCP_ADDRESS=127.0.0.1:8782` (worker → orchestrator, internal) is correct and expected;
  `BEAMCORE_GATEWAY_URL` must be your **public** IP.
- Registering with BeamCore *after* connecting to NATS → `orchestrator_not_routable`
- Running two orchestrator processes on one hotkey → `duplicate_control_session`
- Building from a non-canonical source → `-ERR invalid client protocol` (the gateway speaks NATS
  protocol 1; rebuild from the official repo rather than downgrading anything)
- Any downtime — `readiness_multiplier` is linear in `active_time_ratio`

---

## 9. Methodology and caveats

- **Chunk size:** volume figures assume the 40 MiB chunk size from the documented offer example (`chunk_size: 41943040`). If real chunks are smaller, actual throughput is **lower** than stated, not higher.
- **Process uptime:** derived from NATS heartbeat rate, which is unstable (measured 54/s and 101/s in different windows because task results inflate it during bursts). Uptime is somewhere in **23–43h**, so lifetime volume figures carry roughly **±2× uncertainty**.
- **Peak dispatch rate** (~30 Gb/s) is work being *handed out*, which the fleet then executes over the following minutes — not sustained wire speed.
- **`/routing/orchestrators`** returns a fixed 50 entries regardless of pagination parameters, so it is a capped sample, not the full qualified set. The 230 figure comes from the chain.
- Incentive vectors update only at epoch boundaries (tempo = 72 min).

---

## 10. Sources

- [taostats — SN105](https://taostats.io/subnets/105/chart)
- [Beam-Network/beam (GitHub)](https://github.com/Beam-Network/beam)
- [PRISM scoring spec](https://github.com/Beam-Network/beam/blob/main/guide/prism.md)
- [Weights formula](https://github.com/Beam-Network/beam/blob/main/guide/weights.md)
- [Orchestrator guide](https://github.com/Beam-Network/beam/blob/main/guide/orchestrators.md)
- [Validator guide](https://github.com/Beam-Network/beam/blob/main/guide/validators.md)
- [BeamCore OpenAPI](https://beamcore.b1m.ai/openapi.json)
- [SubnetRadar — SN105](https://subnetradar.com/subnet/105)
- [Wu-Tao — SN105](https://wutao.app/subnet/sn105)
- [ICM Analytics — SN105](https://icm-analytics.com/bittensor/subnets/105/)
- [CoinGecko — TAO](https://www.coingecko.com/en/coins/bittensor)
