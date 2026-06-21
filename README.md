# HABS — Hyper Absolute Benchmark Script

<p align="center">
  <img src="https://img.shields.io/badge/version-2.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-linux-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/bash-4.0%2B-black.svg" alt="Bash">
</p>

**HABS** is a modern, all-in-one Linux benchmark tool inspired by YABS (Yet Another Benchmark Script). It provides comprehensive system information gathering alongside **10 benchmark categories** — including **Geekbench 6**, **stress-ng**, **fio**, and **ioping** — all enabled by default. Delivers clean, structured output suitable for VPS, dedicated servers, and cloud infrastructure evaluation.

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Options](#options)
  - [Examples](#examples)
- [Benchmarks](#benchmarks)
  - [Standard](#standard)
  - [Geekbench 6](#geekbench-6)
  - [Advanced CPU](#advanced-cpu)
  - [Advanced Memory](#advanced-memory)
  - [Advanced Disk](#advanced-disk)
  - [Advanced Network](#advanced-network)
- [Scoring](#scoring)
- [Output](#output)
  - [Terminal](#terminal)
  - [JSON](#json)
- [Requirements](#requirements)
- [Installation](#installation)
- [Comparison with YABS](#comparison-with-yabs)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **System Information** — OS, kernel, CPU model/cache/frequency/flags, RAM, swap, disk, filesystem, virtualization, load averages
- **Geekbench 6** — Single-core & multi-core scores via 25+ real-world workloads (AES, LZMA, JPEG, HTML5, SQLite, PDF, text processing)
- **CPU Benchmark** — Single & multi-threaded via sysbench with scaling ratio
- **Advanced CPU** — Matrix ops, FPU, crypto, and cache thrashing via stress-ng
- **Memory Benchmark** — Sequential 1M read/write via sysbench
- **Advanced Memory** — Multi-block read (256B/4K/64K/1M) + cache hierarchy
- **Disk Benchmark** — 1M sequential & 4K random via dd with IOPS & auto-scaling
- **Advanced Disk** — Random 4K QD=32 mixed via fio + latency via ioping
- **Network Benchmark** — Multi-CDN download, iperf3 upload, ping latency
- **Advanced Network** — IPv6 download, packet loss, traceroute
- **Scoring System** — 100-point weighted score across 5 categories with letter grades (A+ through F)
- **Flexible Output** — Clean box-drawing terminal UI + full JSON export + file output
- **Quick & Full Modes** — Adjustable test duration
- **All benchmarks enabled by default** — No flags needed. Use `--skip-*` to exclude.

---

## Quick Start

```bash
# Run directly (one-liner)
bash <(curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh)

# Or download and run
curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh -o habs.sh
chmod +x habs.sh
./habs.sh
```

> Running `./habs.sh` without any flags executes **all 10 benchmark categories**.

---

## Usage

```
Usage:  bash habs.sh [options]
```

### Options

| Option              | Description                                    |
|---------------------|------------------------------------------------|
| `-h`, `--help`      | Show help message                              |
| `--version`         | Print version                                  |
| `--skip-cpu`        | Skip CPU benchmarks (standard + advanced)      |
| `--skip-memory`     | Skip memory benchmarks (standard + advanced)   |
| `--skip-disk`       | Skip disk benchmarks (standard + advanced)     |
| `--skip-network`    | Skip network benchmarks (standard + advanced)  |
| `--quick`, `-q`     | Quick mode — shorter tests, less data          |
| `--full`, `-f`      | Full mode — comprehensive tests, more data     |
| `--json`            | Output results as JSON to stdout               |
| `--output FILE`     | Save results to file                           |
| `--no-color`        | Disable colored terminal output                |
| `--verbose`, `-v`   | Enable verbose/debug output                    |

> **Geekbench 6** and **Advanced benchmarks** run automatically.  
> No extra flags needed. Use `--skip-*` to exclude specific categories.

### Examples

```bash
# Full benchmark suite (all 10 categories)
./habs.sh

# Quick run for a fast overview
./habs.sh --quick

# Skip network tests on headless servers
./habs.sh --skip-network

# CPU + memory + Geekbench only
./habs.sh --skip-disk --skip-network

# Export results as JSON for dashboards
./habs.sh --json --output results.json

# Silent JSON generation (suppress terminal output)
./habs.sh --skip-cpu --skip-memory --skip-disk --skip-network --json
```

---

## Benchmarks

All benchmarks run by default. Use `--skip-*` flags to exclude.

### Standard

#### CPU
Uses **sysbench** to calculate events per second for prime number computation:

| Mode            | Configuration                        | Duration    |
|-----------------|--------------------------------------|-------------|
| Quick (`-q`)    | 1 thread + N threads, max-prime=10k  | ~15–30s     |
| Default         | 1 thread + N threads, max-prime=20k  | ~30–60s     |
| Full (`-f`)     | 1 thread + N threads, max-prime=50k  | ~60–120s    |

Scaling ratio (multi ÷ single) indicates how well the CPU utilizes multiple cores.

#### Memory
Sequential read and write throughput in MiB/s via sysbench (1M blocks):

| Mode            | Total Size                            |
|-----------------|---------------------------------------|
| Quick (`-q`)    | 2 GB                                  |
| Default         | 10 GB                                 |
| Full (`-f`)     | 20 GB                                 |

#### Disk
**dd** with direct I/O, bypassing caching:

| Test                  | Block Size | Default Size     |
|-----------------------|------------|------------------|
| Sequential Write      | 1 MiB      | 1 GB             |
| Sequential Read       | 1 MiB      | 1 GB             |
| 4K Write              | 4 KiB      | ~1 GB            |
| 4K Read               | 4 KiB      | ~1 GB            |

Auto-scales down when disk space is limited.

#### Network
Downloads from four global CDN locations, reporting the best speed:

| Server                          | Provider     |
|---------------------------------|--------------|
| `speed.cloudflare.com`          | Cloudflare   |
| `cachefly.cachefly.net`         | CacheFly     |
| `proof.ovh.net`                 | OVH          |
| `speedtest.tele2.net`           | Tele2        |

- **Upload**: iperf3 to `iperf.he.net` / `iperf.online.net` (optional)
- **Latency**: ICMP ping to `1.1.1.1`, `8.8.8.8`, `cloudflare.com`

### Geekbench 6

Downloads the official Geekbench 6 CLI (~100 MB) from `cdn.geekbench.com` and runs the full benchmark suite:

| Metric          | Description                                    |
|-----------------|------------------------------------------------|
| Single-Core     | 25+ real-world workloads (AES, LZMA, JPEG, HTML5, SQLite, PDF, text processing, etc.) |
| Multi-Core      | Same workloads, all cores simultaneously       |

- Duration: **5–10 minutes**
- Results are parsed from JSON output and cached
- Binary is auto-cleaned after completion

### Advanced CPU

Uses **stress-ng** to measure bogo operations per second:

| Test       | Workload                     | Duration (default) |
|------------|------------------------------|--------------------|
| Matrix     | Matrix multiplication (256x256) | 20s             |
| FPU        | Floating-point operations    | 20s               |
| Crypto     | SHA256 / AES operations      | 20s               |
| Cache      | Cache thrashing              | 20s               |

### Advanced Memory

Multi-block-size read test via sysbench:

| Block Size | Purpose                        |
|------------|--------------------------------|
| 256B       | L1 cache bandwidth             |
| 4K         | L2/L3 cache bandwidth          |
| 64K        | Cache-to-RAM bandwidth         |
| 1M         | Main memory bandwidth          |

Plus cache hierarchy detection via lscpu (L1d, L1i, L2, L3 sizes).

### Advanced Disk

#### fio — Random 4K Mixed
Queue depth 32, 70/30 read/write mix, direct I/O:

| Metric              | Description                      |
|---------------------|----------------------------------|
| Read IOPS           | Random 4K read operations/sec    |
| Write IOPS          | Random 4K write operations/sec   |
| Read Latency        | Average read latency (µs)        |
| Write Latency       | Average write latency (µs)       |

#### ioping — Disk Latency
Measures actual disk response time in milliseconds.

### Advanced Network

| Test          | Method                                   |
|---------------|------------------------------------------|
| IPv6 Download | curl via IPv6 to Cloudflare              |
| Packet Loss   | 10 × ICMP ping to `1.1.1.1`             |
| Traceroute    | Hop count to `1.1.1.1` (traceroute/mtr) |

---

## Scoring

Scores are calculated on a **100-point scale** with five categories:

| Category      | Weight | Normalization Baseline     |
|---------------|--------|----------------------------|
| CPU           | 25 pts | 100 events/s single-thread  |
| Memory        | 25 pts | 2000 MiB/s read             |
| Disk          | 25 pts | 500 MB/s avg (1M r/w)       |
| Network       | 25 pts | 500 Mbps download            |
| Geekbench 6   | 25 pts | 500 single-core score        |

Each category is capped at 25 points. Total maximum is 125, normalized to 100.

### Letter Grades

| Score Range | Grade |
|-------------|-------|
| 97–100      | A+    |
| 90–96       | A     |
| 80–89       | A–    |
| 70–79       | B+    |
| 60–69       | B     |
| 50–59       | B–    |
| 40–49       | C+    |
| 30–39       | C     |
| 20–29       | D     |
| 0–19        | F     |

> Scoring is designed for relative comparison. Most meaningful when comparing similar system types.

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

  ┌─ Geekbench 6 ───────────────────────────────────────────┐
   Single-Core: 1234
   Multi-Core:  5678
  └──────────────────────────────────────────────────────────┘

  ┌─ Advanced CPU (stress-ng) ──────────────────────────────┐
   Matrix:   1234.56 bogo ops/s
   FPU:      567.89 bogo ops/s
   Crypto:   901.23 bogo ops/s
   Cache:    3456.78 bogo ops/s
  └──────────────────────────────────────────────────────────┘

  ┌─ Results ───────────────────────────────────────────────┐
   CPU Score         : 25/25
   Memory Score      : 20/25
   Disk Score        : 18/25
   Network Score     : 22/25
   Geekbench Score   : 21/25

   Total Score       : 88/100
   Grade             : A-

   Benchmark completed in 12m 34s
  └──────────────────────────────────────────────────────────┘
```

### JSON

```json
{
  "tool": "HABS",
  "version": "2.0.0",
  "timestamp": "2026-06-21T12:00:00Z",
  "duration_seconds": 754,
  "system": { ... },
  "benchmarks": {
    "cpu": {
      "single_events_per_sec": 1234.56,
      "multi_events_per_sec": 4567.89
    },
    "memory": {
      "read_mib_per_sec": 1095.67,
      "write_mib_per_sec": 576.89
    },
    "disk": {
      "4k_write_mb_per_sec": 228.9,
      "4k_read_mb_per_sec": 456.7,
      "1m_write_mb_per_sec": 870.1,
      "1m_read_mb_per_sec": 1234.5
    },
    "network": {
      "download_mbps": 456.78,
      "upload_mbps": 123.45,
      "avg_latency_ms": 12.34
    },
    "geekbench_6": {
      "single_core_score": 1234,
      "multi_core_score": 5678
    },
    "advanced": {
      "cpu": {
        "matrix_bogo_ops": 1234.56,
        "fpu_bogo_ops": 567.89,
        "crypto_bogo_ops": 901.23,
        "cache_bogo_ops": 3456.78
      },
      "memory": {
        "256b_read_mib_per_sec": 12345,
        "4k_read_mib_per_sec": 23456,
        "64k_read_mib_per_sec": 34567,
        "1m_read_mib_per_sec": 45678
      },
      "disk": {
        "fio_random_4k_read_iops": 45678,
        "fio_random_4k_write_iops": 12345,
        "fio_random_4k_read_lat_us": 450,
        "fio_random_4k_write_lat_us": 680,
        "ioping_latency_ms": 0.42
      },
      "network": {
        "ipv6_download_mbps": 456.78,
        "packet_loss_pct": 0,
        "traceroute_hops": 14
      }
    }
  },
  "scores": {
    "cpu": 25,
    "memory": 20,
    "disk": 18,
    "network": 22,
    "geekbench": 21,
    "total": 88,
    "max": 100,
    "grade": "A-"
  }
}
```

---

## Requirements

| Tool       | Required | Used For                              | Auto-Install |
|------------|----------|---------------------------------------|--------------|
| `sysbench` | Yes      | CPU, memory, advanced memory          | ✅           |
| `curl`     | Yes      | Network download, Geekbench download  | ❌ (pre-installed) |
| `dd`       | Yes      | Disk I/O benchmarks                   | ❌ (coreutils) |
| `ping`     | Yes      | Network latency, packet loss          | ❌ (pre-installed) |
| `stress-ng` | Yes    | Advanced CPU (matrix, FPU, crypto, cache) | ✅        |
| `fio`      | Yes      | Advanced disk (random 4K QD=32)       | ✅           |
| `ioping`   | No       | Disk latency (advanced disk)          | ❌ (apt/yum) |
| `iperf3`   | No       | Upload speed test                     | ❌ (apt/yum) |
| `python3`  | No       | JSON parsing for fio & iperf3         | ❌ (pre-installed) |
| `traceroute` | No     | Hop count (advanced network)          | ❌ (apt/yum) |

HABS auto-installs missing dependencies (`sysbench`, `stress-ng`, `fio`) via the system package manager.

---

## Installation

### One-liner (recommended)

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

### As a system command

```bash
sudo curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh -o /usr/local/bin/habs.sh
sudo chmod +x /usr/local/bin/habs.sh
habs.sh
```

---

## Comparison with YABS

| Feature                     | YABS                    | HABS v2.0                      |
|-----------------------------|-------------------------|--------------------------------|
| System Information          | Basic                   | Comprehensive (+ cache, flags) |
| CPU Benchmark               | sysbench                | sysbench + stress-ng (4 tests) |
| Memory Benchmark            | ❌ Not included         | sysbench (1M) + multi-block    |
| Disk Benchmark              | dd (4K + 1M)            | dd + fio (QD=32) + ioping      |
| Network Benchmark           | speedtest-cli / iperf3  | curl multi-CDN + iperf3 + IPv6 + packet loss + traceroute |
| Geekbench 6                 | ❌                      | ✅ Auto-download + run         |
| Scoring                     | Basic numeric           | Weighted 100-pt + letter grades |
| JSON Output                 | Limited                 | Full structured (all 10 categories) |
| Quick / Full Modes          | ❌                      | ✅                            |
| Box-drawing Terminal UI     | ❌                      | ✅                            |
| File Output                 | ❌                      | ✅ `--output FILE`            |
| Disk Space Awareness        | ❌                      | ✅ Auto-scaling               |
| Auto-Install Dependencies   | ❌                      | ✅ (sysbench, stress-ng, fio) |
| Line Count                  | ~500–600                | ~1383                         |

---

## Troubleshooting

### Geekbench 6 download fails

Ensure `curl` is installed and internet connectivity is available. Geekbench 6 downloads ~100 MB from `cdn.geekbench.com`. Use `--skip-cpu --skip-memory --skip-disk --skip-network` to run Geekbench alone and isolate network issues.

### stress-ng / fio installation fails

On minimal systems, install manually:
```bash
# Debian / Ubuntu
apt-get update && apt-get install -y stress-ng fio ioping

# RHEL / CentOS / Fedora
yum install -y stress-ng fio ioping

# Alpine
apk add stress-ng fio ioping
```

### Disk benchmark is slow

WSL2, containers, and network filesystems exhibit lower I/O. The numbers reflect actual host capability under virtualization. Run `--full` on bare metal for accurate measurements.

### Network test times out

Some VPS providers block ICMP or CDN ranges. Use `--skip-network` or `--quick`.

### JSON output is blank

```bash
./habs.sh --json 2>/dev/null | jq .
```

All diagnostic messages go to stderr; stdout contains only the JSON.

---

## Contributing

Contributions welcome! Please follow these guidelines:

1. **Fork** the repository
2. Create a **feature branch** (`feat/your-feature`)
3. Ensure **shellcheck** passes: `shellcheck habs.sh`
4. Test with both `bash -n habs.sh` and a full benchmark run
5. Submit a **pull request**

### Code Style

- `set -euo pipefail` strict error handling
- `snake_case` for variables and functions
- `local` for all function-scoped variables
- Prefer POSIX-compatible tools

---

## License

MIT © 2026 HABS Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
