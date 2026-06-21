# HABS — Hyper Absolute Benchmark Script

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-linux-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/bash-4.0%2B-black.svg" alt="Bash">
</p>

**HABS** is a modern, all-in-one Linux benchmark tool inspired by YABS (Yet Another Benchmark Script). It provides comprehensive system information gathering alongside CPU, memory, disk, and network performance tests — delivering clean, structured output suitable for VPS, dedicated servers, and cloud infrastructure evaluation.

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Options](#options)
  - [Examples](#examples)
- [Benchmarks](#benchmarks)
  - [CPU](#cpu)
  - [Memory](#memory)
  - [Disk](#disk)
  - [Network](#network)
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

- **System Information** — OS, kernel, CPU model/cache/frequency, RAM, swap, disk usage, filesystem type, virtualization detection, load averages
- **CPU Benchmark** — Single-threaded and multi-threaded performance via sysbench with scaling ratio
- **Memory Benchmark** — Sequential read and write throughput via sysbench
- **Disk Benchmark** — 1M sequential and 4K random I/O via dd with IOPS calculation; disk-space-aware auto-scaling
- **Network Benchmark** — Multi-location download speed test via curl, upload via iperf3 (optional), latency via ping
- **Scoring System** — Weighted 100-point score across CPU, memory, disk, and network with letter grades (A+ through F)
- **Flexible Output** — Clean terminal UI with box-drawing characters, JSON export for automation, and file output
- **Quick & Full Modes** — Adjustable test duration and data volume
- **Portable** — Single Bash script, zero-compile, runs on any modern Linux distribution
- **Idempotent** — Safe to run multiple times; cleans up temporary files after execution

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
| `--skip-cpu`        | Skip CPU benchmark                             |
| `--skip-memory`     | Skip memory benchmark                          |
| `--skip-disk`       | Skip disk benchmark                            |
| `--skip-network`    | Skip network benchmark                         |
| `--quick`, `-q`     | Quick mode — shorter tests, less data          |
| `--full`, `-f`      | Full mode — comprehensive tests, more data     |
| `--json`            | Output results as JSON to stdout               |
| `--output FILE`     | Save results to file                           |
| `--no-color`        | Disable colored terminal output                |
| `--verbose`, `-v`   | Enable verbose/debug output                    |

### Examples

```bash
# Full benchmark suite
./habs.sh

# Quick run for a fast overview
./habs.sh --quick

# Skip network tests on headless servers
./habs.sh --skip-network

# Export results as JSON for monitoring dashboards
./habs.sh --json --output results.json

# Full comprehensive benchmark with verbose logging
./habs.sh --full --verbose

# Silent JSON generation (suppress terminal output)
./habs.sh --skip-cpu --skip-memory --skip-disk --skip-network --json
```

---

## Benchmarks

### CPU

Uses **sysbench** to calculate events per second for prime number computation:

| Mode            | Configuration                        | Duration    |
|-----------------|--------------------------------------|-------------|
| Quick (`-q`)    | 1 thread + N threads, max-prime=10k  | ~15–30s     |
| Default         | 1 thread + N threads, max-prime=20k  | ~30–60s     |
| Full (`-f`)     | 1 thread + N threads, max-prime=50k  | ~60–120s    |

The **scaling ratio** (multi ÷ single) indicates how well the CPU utilizes multiple cores — ideal scaling equals the number of threads.

### Memory

Uses **sysbench** to measure sequential read and write throughput in MiB/s with 1M blocks:

| Mode            | Total Size                            |
|-----------------|---------------------------------------|
| Quick (`-q`)    | 2 GB                                  |
| Default         | 10 GB                                 |
| Full (`-f`)     | 20 GB                                 |

### Disk

Uses **dd** with direct I/O to bypass caching, measuring both throughput and IOPS:

| Test                  | Block Size | Mode     | File Size        |
|-----------------------|------------|----------|------------------|
| Sequential Write      | 1 MiB      | Default  | 1 GB             |
| Sequential Read       | 1 MiB      | Default  | 1 GB             |
| 4K Write              | 4 KiB      | Default  | ~1 GB            |
| 4K Read               | 4 KiB      | Default  | ~1 GB            |

When available disk space is limited, HABS automatically scales down test sizes to prevent disk-full errors.

### Network

Downloads from four global CDN locations and reports the best speed:

| Server URL                          | Provider         |
|-------------------------------------|------------------|
| `speed.cloudflare.com`              | Cloudflare       |
| `cachefly.cachefly.net`             | CacheFly         |
| `proof.ovh.net`                     | OVH              |
| `speedtest.tele2.net`               | Tele2            |

**Upload** is tested via `iperf3` against public servers (`iperf.he.net`, `iperf.online.net`) when available.

**Latency** is measured via ICMP ping to `1.1.1.1`, `8.8.8.8`, and `cloudflare.com`.

---

## Scoring

Scores are calculated on a **100-point scale** with equal weighting across four categories:

| Category | Weight | Normalization Baseline |
|----------|--------|------------------------|
| CPU      | 25 pts | 100 events/s single-threaded |
| Memory   | 25 pts | 2000 MiB/s read       |
| Disk     | 25 pts | 500 MB/s avg (1M r/w) |
| Network  | 25 pts | 500 Mbps download     |

Each category is capped at 25 points, then summed for the final score.

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

> **Note:** The scoring is designed for relative comparison. Scores are most meaningful when comparing similar system types (e.g., VPS vs VPS, dedicated vs dedicated).

---

## Output

### Terminal

```text
  ┌─ System Information ────────────────────────────────────┐
   Hostname          : server-01
   OS                : Ubuntu 24.04 LTS (x86_64)
   Kernel            : 6.8.0-31-generic
   Uptime            : 42d 3h 15m 22s
   CPU Model         : AMD EPYC 7763 64-Core Processor
   CPU Cores         : 4 cores / 4 threads
   CPU Freq          : 2.45 GHz
   CPU Cache         : L1d: 256 KiB, L1i: 256 KiB, L2: 4 MiB, L3: 32 MiB
   RAM               : 15.6 GiB total / 2.1 GiB used
   Swap              : 2.0 GiB total
   Disk              : 80G total / 12G used (15%)
   Filesystem        : ext4 on /
   Virt              : kvm
   Load Avg          : 0.15, 0.22, 0.31
  └──────────────────────────────────────────────────────────┘

  ┌─ CPU Benchmark ─────────────────────────────────────────┐
   Single:   1234.56 events/s
   Multi:    4567.89 events/s
   Scaling:  3.70x (ideal: 4x)
  └──────────────────────────────────────────────────────────┘

  ┌─ Results ───────────────────────────────────────────────┐
   CPU Score         : 25/25
   Memory Score      : 20/25
   Disk Score        : 18/25
   Network Score     : 22/25

   Total Score       : 85/100
   Grade             : A

   Benchmark completed in 3m 42s
  └──────────────────────────────────────────────────────────┘
```

### JSON

```json
{
  "tool": "HABS",
  "version": "1.0.0",
  "timestamp": "2026-06-21T12:00:00Z",
  "duration_seconds": 222,
  "system": {
    "hostname": "server-01",
    "os": "Ubuntu 24.04 LTS",
    "kernel": "6.8.0-31-generic",
    "architecture": "x86_64",
    "virtualization": "kvm",
    "cpu": {
      "model": "AMD EPYC 7763 64-Core Processor",
      "cores": 4,
      "threads": 4,
      "frequency": "2.45 GHz"
    },
    "memory": {
      "total_bytes": 16768272384,
      "used_bytes": 2254853632,
      "available_bytes": 14513418752
    }
  },
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
    }
  },
  "scores": {
    "cpu": 25,
    "memory": 20,
    "disk": 18,
    "network": 22,
    "total": 85,
    "max": 100,
    "grade": "A"
  }
}
```

---

## Requirements

| Tool       | Required | Used For                     | Installation                         |
|------------|----------|------------------------------|--------------------------------------|
| `sysbench` | Yes      | CPU & memory benchmarks      | `apt install sysbench` / `yum install sysbench` |
| `curl`     | Yes      | Network download tests       | Usually pre-installed                |
| `dd`       | Yes      | Disk I/O benchmarks          | Part of `coreutils` (pre-installed)  |
| `ping`     | Yes      | Network latency tests        | Usually pre-installed                |
| `iperf3`   | Optional | Network upload tests         | `apt install iperf3`                 |
| `python3`  | Optional | JSON parsing for iperf3      | Usually pre-installed                |

HABS attempts to auto-install `sysbench` via the system package manager on first use.

---

## Installation

### One-liner (recommended)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh)
```

### Manual

```bash
git clone https://github.com/anjarman20/Hyper-Absolute-Benchmark-Script.git
cd habs
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

| Feature                     | YABS                    | HABS                          |
|-----------------------------|-------------------------|-------------------------------|
| System Information          | Basic                   | Comprehensive (cache, virt, load, more) |
| CPU Benchmark               | sysbench (single + multi) | sysbench with scaling ratio   |
| Memory Benchmark            | ❌ Not included         | ✅ Read & write via sysbench  |
| Disk Benchmark              | dd (4K + 1M sequential) | dd + IOPS + auto-scaling      |
| Network Benchmark           | speedtest-cli / iperf3  | Multi-location curl + iperf3   |
| Scoring                     | Basic numeric           | Weighted 100-pt with letter grades |
| JSON Output                 | Limited                 | Full structured JSON export   |
| Quick / Full Modes          | ❌                      | ✅                            |
| Box-drawing Terminal UI     | ❌                      | ✅                            |
| File Output                 | ❌                      | ✅ `--output FILE`            |
| Disk Space Awareness        | ❌                      | ✅ Auto-scaling               |
| Dependencies                | Heavy (speedtest-cli)   | Minimal (auto-installs sysbench) |
| Line Count                  | ~500–600                | ~895                          |

---

## Troubleshooting

### `sysbench` installation fails

On minimal systems, the package manager may not find `sysbench`. Install it manually:

```bash
# Debian / Ubuntu
apt-get update && apt-get install -y sysbench

# RHEL / CentOS / Fedora
yum install -y sysbench
# or
dnf install -y sysbench

# Alpine
apk add sysbench

# Arch
pacman -S sysbench
```

### Disk benchmark is slow

WSL2, container environments, and network filesystems exhibit lower I/O performance. The numbers reflect actual host capabilities under virtualization. Run `--full` mode on bare metal for accurate disk measurements.

### Network test times out

Some VPS providers block ICMP (ping) or certain CDN ranges. Use `--skip-network` or specify `--quick` to reduce test durations.

### JSON output is blank

Ensure you are not mixing `--output FILE` with `--json` when expecting stdout. Without `--output`, `--json` sends the JSON to stdout. Use `2>/dev/null` to suppress diagnostic messages:

```bash
./habs.sh --json 2>/dev/null | jq .
```

---

## Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork** the repository
2. Create a **feature branch** (`feat/your-feature`)
3. Ensure **shellcheck** passes: `shellcheck habs.sh`
4. Test with both `bash -n habs.sh` and a full benchmark run
5. Submit a **pull request**

### Code Style

- Use `set -euo pipefail` for strict error handling
- Follow existing naming conventions (`snake_case` for variables, `snake_case` for functions)
- Avoid external dependencies; prefer POSIX-compatible tools
- Keep functions focused and well-documented
- Use `local` for all function-scoped variables

---

## License

MIT © 2026 HABS Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
