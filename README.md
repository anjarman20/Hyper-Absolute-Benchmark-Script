# HABS — Hyper Absolute Benchmark Script

<p align="center">
  <img src="https://img.shields.io/badge/version-2.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-WTFPL-brightgreen.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-linux-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/bash-4.0%2B-black.svg" alt="Bash">
</p>

**HABS** is a professional Bash-based Linux benchmarking suite combining the functionality of [YABS](https://github.com/masonr/yet-another-bench-script) and [byte-unixbench](https://github.com/kdlucas/byte-unixbench). It provides comprehensive system information alongside **12 benchmark categories** including sysbench, fio, Geekbench 6, stress-ng, y-cruncher, UnixBench, iperf3, and more. Clean modern output, JSON export, ARM64 and x86_64 support, and automatic dependency handling.

---

## Quick Start

```bash
# Run directly
curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh | bash

# Or download and run
curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh -o habs.sh
chmod +x habs.sh
./habs.sh
```

> Running `./habs.sh` without flags runs **all 12 benchmark categories**.

---

## Usage

```
Usage:  bash habs.sh [options]
```

### Options

| Option                | Description                                    |
|-----------------------|------------------------------------------------|
| `-h`, `--help`        | Show help message                              |
| `--version`           | Print version                                  |
| `--skip-cpu`          | Skip sysbench CPU benchmarks                   |
| `--skip-memory`       | Skip sysbench memory benchmarks                |
| `--skip-disk`         | Skip dd disk benchmarks                        |
| `--skip-network`      | Skip network benchmarks (curl + iperf3)        |
| `--skip-geekbench`    | Skip Geekbench 6                               |
| `--skip-advanced`     | Skip all advanced benchmarks (stress-ng, fio, multi-block mem, advanced net) |
| `--skip-y-cruncher`   | Skip y-cruncher Pi calculation                 |
| `--skip-unixbench`    | Skip UnixBench (byte-unixbench compilation)    |
| `--quick`, `-q`       | Quick mode — shorter tests, less data          |
| `--full`, `-f`        | Full mode — comprehensive tests                |
| `--json`              | Output results as JSON to stdout               |
| `--output FILE`       | Save results to file                           |
| `--no-color`          | Disable colored terminal output                |
| `--verbose`, `-v`     | Enable verbose/debug output                    |

### Examples

```bash
# Full benchmark suite (all 12 categories)
./habs.sh

# Quick overview
./habs.sh --quick

# Skip network tests on headless servers
./habs.sh --skip-network

# CPU + disk only
./habs.sh --skip-memory --skip-network --skip-geekbench --skip-advanced

# Export results as JSON
./habs.sh --json --output results.json

# Silent JSON generation
./habs.sh --skip-cpu --skip-memory --skip-disk --skip-network --skip-advanced --json 2>/dev/null | jq .
```

---

## Benchmarks

All benchmarks run by default. Use `--skip-*` to exclude categories.

### Standard Benchmarks

| Benchmark    | Tool       | Configuration                         | Mode       |
|-------------|------------|---------------------------------------|------------|
| CPU Single  | sysbench   | 1 thread, max-prime 10k/20k/50k       | quick/std/full |
| CPU Multi   | sysbench   | N threads, max-prime 10k/20k/50k      | quick/std/full |
| Scaling     | —          | Multi ÷ Single ratio                  | —          |
| Memory Read | sysbench   | 1M blocks, 2G/10G/20G                | quick/std/full |
| Memory Write| sysbench   | 1M blocks, 2G/10G/20G                | quick/std/full |
| Disk 1M Seq | dd         | Direct I/O, 1M blocks                 | —          |
| Disk 4K Rand| dd         | Direct I/O, 4K blocks, IOPS           | —          |
| Network DL  | curl       | Multi-CDN (Cloudflare, CacheFly, OVH, Tele2) | —    |
| Network UL  | iperf3     | iperf.he.net, iperf.online.net, iperf.scottlinux.com | — |
| Latency     | ping       | 1.1.1.1, 8.8.8.8, cloudflare.com     | —          |

### Geekbench 6

Downloads the official Geekbench 6 CLI from `cdn.geekbench.com` and runs the full benchmark suite:

| Metric       | Description                                    |
|-------------|------------------------------------------------|
| Single-Core | 25+ real-world workloads (AES, LZMA, JPEG, HTML5, SQLite, PDF, etc.) |
| Multi-Core  | Same workloads, all cores simultaneously       |

- Duration: **5–10 minutes**
- Architecture: x86_64 and ARM64
- Binary auto-cleaned after completion

### Advanced Benchmarks

| Benchmark       | Tool       | Test                                    | Mode          |
|----------------|------------|-----------------------------------------|---------------|
| CPU Matrix     | stress-ng  | Matrix multiplication (256×256)         | 10s/20s/40s   |
| CPU FPU        | stress-ng  | Floating-point operations               | 10s/20s/40s   |
| CPU Crypto     | stress-ng  | SHA256 / AES operations                 | 10s/20s/40s   |
| CPU Cache      | stress-ng  | Cache thrashing                         | 10s/20s/40s   |
| Memory 256B    | sysbench   | L1 cache bandwidth                      | —             |
| Memory 4K      | sysbench   | L2/L3 cache bandwidth                   | —             |
| Memory 64K     | sysbench   | Cache-to-RAM bandwidth                  | —             |
| Memory 1M      | sysbench   | Main memory bandwidth                   | —             |
| Disk 4K Rand   | fio        | QD=32, 70/30 R/W mix, io_uring/libaio/psync auto-detect | — |
| Disk Latency   | ioping     | Actual disk response time               | —             |
| IPv6 Download  | curl       | Cloudflare IPv6 endpoint                | —             |
| Packet Loss    | ping       | 1.1.1.1, configurable count             | —             |
| Traceroute     | traceroute | Hop count to 1.1.1.1                    | —             |

### y-cruncher

Pi calculation benchmark for CPU stability:

| Config     | Digits     | Duration     |
|-----------|-----------|--------------|
| Quick      | 500M     | ~30-60s      |
| Standard   | 1000M    | ~1-3m        |
| Full        | 5000M    | ~5-20m       |

- Binary auto-downloaded per architecture
- Cleaned up after completion

### UnixBench (byte-unixbench)

Combined system index score from the classic UnixBench suite:

- Tests: Dhrystone, Whetstone, Execl, Pipe, Context Switching, Shell Scripts, System Call
- Compiles from source (requires gcc, make, perl)
- Reports single **System Benchmarks Index Score**

---

## Scoring

Weighted 100-point scale with letter grades:

| Category      | Weight | Baseline                |
|---------------|--------|-------------------------|
| CPU           | 25 pts | 100 events/s single     |
| Memory        | 25 pts | 2000 MiB/s read         |
| Disk          | 25 pts | 500 MB/s avg (1M r/w)  |
| Network       | 25 pts | 500 Mbps download       |
| Geekbench 6   | 25 pts | 500 single-core score   |

Each category capped at 25 pts. Total normalized to 100.

### Letter Grades

| Score    | Grade |
|----------|-------|
| 97–100   | A+    |
| 90–96    | A     |
| 80–89    | A-    |
| 70–79    | B+    |
| 60–69    | B     |
| 50–59    | B-    |
| 40–49    | C+    |
| 30–39    | C     |
| 20–29    | D     |
| 0–19     | F     |

---

## Output

### Terminal

```
  ┌─ System Information ────────────────────────────────────┐
   Hostname          : server-01
   OS                : Ubuntu 24.04 LTS (x86_64)
   ...
  └──────────────────────────────────────────────────────────┘

  ┌─ CPU Benchmark ─────────────────────────────────────────┐
   Single:   1234.56 events/s
   Multi:    4567.89 events/s
   Scaling:  3.70x (ideal: 4x)
  └──────────────────────────────────────────────────────────┘
```

### JSON

Full structured JSON with all benchmark results, scores, and system information. Example:

```json
{
  "tool": "HABS",
  "version": "2.0.0",
  "system": { "...": "..." },
  "benchmarks": {
    "cpu": { "single_events_per_sec": 1234.56 },
    "memory": { "read_mib_per_sec": 1095.67 },
    "disk": { "1m_read_mb_per_sec": 1234.5 },
    "network": { "download_mbps": 456.78 },
    "geekbench_6": { "single_core_score": 1234, "multi_core_score": 5678 },
    "advanced_cpu": { "matrix_bogo_ops": 1234.56 },
    "advanced_memory": { "256b_read_mib_per_sec": 12345 },
    "advanced_disk": { "fio_random_4k_read_iops": 45678 },
    "advanced_network": { "ipv6_download_mbps": 456.78 },
    "y_cruncher": { "compute_time_sec": 12.345 },
    "unixbench": { "index_score": 1234.5 }
  },
  "scores": { "total": 88, "grade": "A-" }
}
```

---

## Requirements

| Tool      | Required | Used For                          | Auto-Install |
|-----------|----------|-----------------------------------|--------------|
| sysbench  | Yes      | CPU, memory, advanced memory      | ✅           |
| curl      | Yes      | Network download, Geekbench DL    | ❌ (pre-installed) |
| dd        | Yes      | Disk I/O                          | ❌ (coreutils) |
| ping      | Yes      | Network latency, packet loss      | ❌ (pre-installed) |
| python3   | Yes      | JSON parsing (fio, iperf3, geekbench) | ❌ (pre-installed) |
| bc        | Yes      | Arithmetic in calculations        | ❌ (pre-installed) |
| stress-ng | Yes*      | Advanced CPU (matrix, FPU, crypto, cache) | ✅    |
| fio       | Yes*      | Advanced disk (random 4K QD=32)  | ✅           |
| ioping    | No        | Disk latency                      | ✅           |
| iperf3    | No        | Upload speed test                 | ✅           |
| traceroute | No       | Hop count                         | ✅           |
| gcc/make/perl | No | UnixBench compilation             | ❌ (apt/yum) |

`*` Part of advanced benchmarks (skippable via `--skip-advanced`)

---

## Installation

### One-liner

```bash
bash <(curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh)
```

### Manual

```bash
git clone https://github.com/anjarman20/Hyper-Absolute-Benchmark-Script.git
cd Hyper-Absolute-Benchmark-Script
chmod +x habs.sh
./habs.sh
```

---

## Comparison with YABS

| Feature                     | YABS              | HABS v2.0             |
|-----------------------------|-------------------|-----------------------|
| System Information          | Basic             | Comprehensive (+ cache, flags, virt) |
| CPU Benchmark               | sysbench          | sysbench + stress-ng (4 tests) |
| Memory Benchmark            | ❌                | sysbench (1M) + multi-block |
| Disk Benchmark              | dd (4K + 1M)     | dd + fio (QD=32, engine auto-detect) + ioping |
| Network Benchmark           | speedtest-cli     | curl multi-CDN + iperf3 + IPv6 + loss + traceroute |
| Geekbench 6                 | ❌                | ✅ Auto-download + run |
| y-cruncher                  | ❌                | ✅ Pi calculation     |
| UnixBench                   | ❌                | ✅ Compile + run (combined index score) |
| Scoring                     | Basic numeric     | Weighted 100-pt + letter grades |
| JSON Output                 | Limited           | Full structured (all 12 categories) |
| Quick / Full Modes          | ❌                | ✅                    |
| Box-drawing Terminal UI     | ❌                | ✅                    |
| File Output                 | ❌                | ✅ `--output FILE`   |
| Auto-Install Dependencies   | ❌                | ✅ (sysbench, stress-ng, fio, ioping, iperf3, traceroute) |
| Line Count                  | ~500-600          | ~2069                 |

---

## License

```
            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
                    Version 2, December 2004

 Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>

 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. You just DO WHAT THE FUCK YOU WANT TO.
```
