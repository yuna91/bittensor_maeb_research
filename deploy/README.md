# SN105 Beam — Deployment Kit

Single-VPS deployment: one orchestrator (holds the UID, earns emissions) plus one worker
(moves the bytes) on the same Linux host.

Target: Debian 12 / Ubuntu 22.04+ with a public IPv4 and root access.
Reference host: PetroSky Quebec City, 2 vCPU / 4 GB / 40 GB, 2 Gbps port.

---

## Run order

Order matters. BeamCore registration **must** happen before the orchestrator connects to NATS,
and the membership call requires the orchestrator to already be running.

| # | Step | Script | Notes |
|---|---|---|---|
| 0 | System prep, Go, build, TCP tuning | `00-bootstrap.sh` | run as root, once |
| 1 | Register hotkey on subnet 105 | *manual* `btcli` | ~0.0005 TAO (~$0.14) |
| 2 | Generate WCP TLS cert | `01-gen-cert.sh` | self-signed, no domain needed |
| 3 | Register orchestrator with BeamCore | `03-register-orchestrator.sh` | **saves the one-time api_key** |
| 4 | Start orchestrator | `systemctl start beam-orchestrator` | |
| 5 | Register worker + bind membership | `04-register-worker.sh` | needs orchestrator running |
| 6 | Start worker | `systemctl start beam-worker` | |
| 7 | Verify | `99-healthcheck.sh` | run after every change |

Step 1 is deliberately manual — it spends real TAO and needs your coldkey password:

```bash
btcli subnets register --netuid 105 --network finney \
  --wallet-name <coldkey> --wallet-hotkey <hotkey>
```

---

## What gets created

```
/opt/beam/               repo + built binaries (beam user, read-only at runtime)
/var/lib/beam/           durable state: registry.json, node.key, journals
/etc/beam/beam.env       env file, mode 0600 — holds your API keys
/etc/beam/wcp.crt|.key   WCP TLS material
```

Two systemd units, both `Restart=always`. Uptime is not optional — `readiness_multiplier` in
PRISM is linear in `active_time_ratio`, so every minute down scales your score down.

---

## The two addresses you must not confuse

This is the single most common misconfiguration. Six of the 50 orchestrators in Beam's live
routing table have it wrong and receive no work at all.

| Variable | Correct value | Direction |
|---|---|---|
| `BEAM_WCP_ADDRESS` | `127.0.0.1:8782` | worker → orchestrator, **internal** — loopback is right |
| `BEAMCORE_GATEWAY_URL` | `http://<PUBLIC_IP>:8782` | advertised to BeamCore — **must be public** |

`99-healthcheck.sh` checks this explicitly.

---

## Firewall

Two inbound ports:

```bash
ufw allow 22/tcp
ufw allow 8782/tcp    # WCP listener
ufw allow 9470/tcp    # worker room transfers — extra uploaded MiB, i.e. extra rank
ufw enable
```

Ports 8780 (worker control) and 8781 (orchestrator control) bind to loopback only — do not
expose them.

---

## Tuning notes

`00-bootstrap.sh` applies TCP tuning that matters more than it looks. On a 2 Gbps link with
~40 ms RTT to us-east-1, the bandwidth-delay product is ~10 MB. Default `tcp_rmem` maxima of
~6 MB will cap a single stream well below line rate — and since PRISM scores `transfer_mbps`
fleet-normalised against competitors, that cap directly costs you rank. The script raises
buffers to 64 MB and switches to BBR.

Worker resource flags are set in `beam.env`:

| Flag | Kit default | Why |
|---|---|---|
| `BEAM_WORKER_MEMORY_BYTES` | 2 GiB | caps concurrent chunks (~50 at 40 MiB) |
| `BEAM_WORKER_SCRATCH_BYTES` | 16 GiB | admission accounting only — `transfer.multipart` streams and consumes no disk |
| `BEAM_WORKER_BANDWIDTH_MBPS` | 500 | **start conservative** |

**Do not inflate bandwidth.** PRISM scores *provider-verified* throughput, so over-claiming wins
nothing — but it pulls in more chunks than you can deliver, and the resulting failures and
reassignments feed reliability, which is **60% of `performance_score`**. Raise it only after
`99-healthcheck.sh` shows you are consistently saturating the current figure.

---

## Unverified assumption

`docs/worker.md` lists "Bittensor worker hotkey registered on subnet 105" as a requirement, but
the worker runtime accepts no hotkey argument — the hotkey only signs the one-time
`POST /workers/register`. `04-register-worker.sh` therefore **reuses the orchestrator hotkey**.

This was not verified against the live API. If registration returns
`403 hotkey is not registered on this subnet`, the reuse is rejected and each worker needs its
own registered UID — which changes the economics materially. Check the script's output.
