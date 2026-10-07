# NInfer-3090 Setup for AnkiTov — Synthesis (2026-08-23)

> **⚠️ 2026-08-25 DEPRECATION NOTE (user decision):** NInfer-3090 is deprecated in favor of
> **`syv-ai/qwen38-27b-rtx3090`** — a vLLM-based serving build for Qwen3.8-27B on a single
> RTX 3090 (OpenAI-compatible API on **port 18020**, `--profile single` for chat ~120-133 tok/s
> / `--profile batch` for ~1,035 tok/s at 64 concurrent; 64k-150k+ context; lossless).
> Switch instructions below remain valid with: port 8080 → 18020, and clone
> `https://github.com/syv-ai/qwen38-27b-rtx3090` instead of `Don-Chad/ninfer-3090`.
> See `workspace/Hive/STATUS.md` decision #3 for the current recommendation.


## Architecture

```
Mac M4 (arm64)                              Intel Ubuntu (x86_64)
┌──────────────────────────┐       LAN       ┌───────────────────────────┐
│ Goose GUI                │                 │ NInfer-3090               │
│   ↓                      │                 │                           │
│ Headroom Proxy :8787     │  ──────────→    │ ninfer-serve :8080        │
│   compress + shape output│  ←──────────    │ Qwen3.8-27B .ninfer       │
│   upstream→ OpenRouter*  │                 │ RTX 3090 (24GB, SM86)     │
└──────────────────────────┘                 └───────────────────────────┘
* Currently OpenRouter (deepseek-v4-pro). Switch to NInfer by changing
  OPENAI_TARGET_API_URL to http://<ubuntu-ip>:8080/v1 and model to qwen3.8-27b.
```

## Why NInfer-3090 (not SGLang/llama.cpp/vLLM)

NInfer-3090 is purpose-built C++20/CUDA engine for exactly our setup:
Qwen3.8-27B on one RTX 3090. Key advantages over general-purpose stacks:

| Concern | General-purpose | NInfer-3090 |
|---|---|---|
| Engine | SGLang/llama.cpp (heavy) | Native SM86 binary, C++/CUDA |
| Quantization | Q4 GGUF (~14-17GB) | Custom .ninfer artifact (16.96 GiB) |
| Speculative decode | Needs external drafter | MTP3 built-in, 56-61% acceptance |
| Context ceiling | ~13K tokens (SGLang Q4) | **171K tokens** INT8 (64K C1 sweet spot) |
| Overthinking | Model switch / prompt hack | `--reasoning-effort low` (first-class) |
| Memory | Variable | C1: 19,641 MiB peak (4.3 GiB free) |

MTP3 is the mature speculative decoder for Qwen3.8-27B — benchmarked at
56-96% acceptance. DFlash 2 only serves the 35B-A3B artifact, irrelevant.

## Ubuntu Build

**Docker (recommended — v0.6.1 validated 245 compile/link steps):**

```bash
git clone https://github.com/Don-Chad/ninfer-3090.git
cd ninfer-3090 && git checkout release/v0.6.0-rtx3090

# Verify GPU
docker run --rm --gpus all nvidia/cuda:13.1.2-runtime-ubuntu24.04 nvidia-smi

# Build (Ubuntu 24.04, CUDA 13.1, GCC 13, Ninja)
docker build --tag ninfer-3090:sm86 .

# Download artifact (NOT GGUF)
mkdir -p models
# → https://huggingface.co/neroued/Qwen3.8-27B-NInfer
# save as models/qwen3_8_27b.ninfer (16.96 GiB)
```

**Caveats:** No prebuilt Linux archive. Linux is untested delivery path —
all qualified performance results are Windows. Docker build is safest.

## Launch Command (annotated)

```bash
docker run --rm --gpus all \
  --publish 8080:8080 \
  --volume "$PWD/models:/workspace/models:ro" \
  ninfer-3090:sm86 \
  ninfer-serve models/qwen3_8_27b.ninfer \
  --host 0.0.0.0 --port 8080 \
  --max-context 65536 --kv-capacity auto \
  --max-concurrency 1 --max-pending-requests 16 \
  --prefill-chunk 1024 --kv-dtype int8 \
  --spec mtp --draft-tokens 3 --lm-head-draft \
  --reasoning-effort low
```

| Flag | Why |
|---|---|
| `--host 0.0.0.0` | Reachable from Mac over LAN |
| `--max-context 65536` | C1 sweet spot; Goose needs large codebase context |
| `--kv-capacity auto` | Maximizes remaining VRAM (~171K INT8 ceiling) |
| `--kv-dtype int8` | Quality-default. NEVER use `rk8v4` (lossy, wrong answers) |
| `--spec mtp --draft-tokens 3` | MTP3 speculative decode, 56-61% acceptance |
| `--max-concurrency 1` | Single agent (Goose). Block Buzz agents queue |
| `--reasoning-effort low` | Kill Qwen 3.8 overthinking at source |
| `--prefill-chunk 1024` | Tuned for 3090 memory bandwidth |

## Expected Performance (C1 mode, from project's Windows-qualified benchmarks)

| Metric | Value |
|---|---|
| Decode throughput | ~70 tok/s |
| Prefill (4K prompt) | ~862 tok/s |
| TTFT (1K-token prompt) | ~149 ms |
| Peak VRAM | ~19,641 MiB |

## Ubuntu Box Optimizations

1. **Run headless** — disable GDM/lightdm (`systemctl set-default multi-user.target`).
   Recovers 1-2GB VRAM.
2. **GPU persistence** — `nvidia-smi -pm 1` (survives driver unload).
3. **Lock GPU clocks** — `nvidia-smi -lgc 1500,1900` (RTX 3090 sweet spot).
4. **CPU governor** — `performance` governor during inference.
5. **Cooling** — 3090 throttles at high temps. NInfer's C1 profile is ~175W,
   lighter than gaming, but sustained.

## Mac: Headroom Proxy Config (already deployed)

File: `~/.local/bin/headroom-proxy-start.sh`

```bash
#!/bin/bash
export OPENROUTER_API_KEY=$(security find-generic-password -a "ybg" -s "OpenRouter_API_Key" -w)
export OPENAI_TARGET_API_URL="https://openrouter.ai/api/v1"
export OPENAI_API_KEY=$OPENROUTER_API_KEY
export HEADROOM_OUTPUT_SHAPER=1
export HEADROOM_VERBOSITY_LEVEL=2
export HEADROOM_OUTPUT_HOLDOUT=20

headroom proxy --code-aware --port 8787 --memory --mode token \
  --log-messages --backend openrouter
```

Status (2026-08-23):
- Input compression: ~4.6% savings, working
- Output shaping: Verbosity L2 active, holdout=20% A/B measuring
- `headroom learn --verbosity` is Claude-only — doesn't work with Goose
- Holdout CI: -4.7% to +117.9% — not yet statistically significant

## Mac: Config Fix Applied

Template: `/Volumes/YBG1TB4Mac/AnkiTov-goose/config/global-config.yaml`
- Line 173: `OPENROUTER_HOST: http://localhost:8787` (was `https`)
- File is gitignored (machine-specific), no commit needed
- Reran `bootstrap.sh` to regenerate live symlink

Live config verified: `~/.config/goose/config.yaml` → temp file with fix.

## How to Switch to NInfer (when ready)

In `global-config.yaml`:

```yaml
# Change:
OPENAI_TARGET_API_URL: https://openrouter.ai/api/v1
# To:
OPENAI_TARGET_API_URL: http://<ubuntu-ip>:8080/v1

# And model:
providers:
  openai:
    model: qwen3.8-27b                    # was: deepseek/deepseek-v4-pro
```

Then rerun bootstrap. Headroom continues compressing and shaping transparently —
doesn't care which backend model is behind it.

## Risks / Open Questions

1. **Linux uncertified** — all NInfer performance data is Windows. Expect
   debugging. Docker build validated to compile; runtime behavior unknown.
2. **Qwen3.8 vs DeepSeek v4 Pro** — benchmark on representative Goose turns
   before committing. Keep OpenRouter fallback if Qwen can't match on
   complex Rust tasks.
3. **One model at a time** — NInfer is single-model, single-GPU. Block Buzz's
   7 concurrent agents would need a second 3090 or the Ubuntu box to run two
   instances. C8 mode gives 2.3× throughput but drops context to 8K — unusable
   for codebase-scale Goose sessions.
4. **WAN latency** — Mac → Ubuntu LAN is ~1-5ms. If the Ubuntu box is ever
   remote (Tailscale/WireGuard), add 10-50ms.

## Decision: Holdout Measurement

Keep `HEADROOM_OUTPUT_HOLDOUT=20` running. Only trust the number when
the entire confidence band (ci_low to ci_high) sits above zero. Current
point estimate (56.6%) is not reliable. Remove `--log-messages` when
done inspecting (saves memory, `output-savings` ledger is separate).
