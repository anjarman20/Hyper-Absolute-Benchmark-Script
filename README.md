<p align="center">
  <img src="banner.png" alt="HABS Banner" width="800">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-2.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-WTFPL-brightgreen.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-linux-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/bash-4.0%2B-black.svg" alt="Bash">
  <img src="https://img.shields.io/badge/arch-x86__64%20%7C%20ARM64-blueviolet" alt="Architecture">
</p>

<p align="center">
  <b>HABS</b> — Hyper Absolute Benchmark Script<br>
  Professional Linux benchmarking suite • 12 benchmark categories<br>
  Compact output • JSON export • Auto-dependency handling
</p>

---

## Table of Contents

- [Quick Start](#quick-start)
- [Usage](#usage)
- [Benchmarks](#benchmarks)
  - [CPU](#cpu)
  - [Memory](#memory)
  - [Disk](#disk)
  - [Network](#network)
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
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Quick Start

```bash
# Run directly
bash <(curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh)

# Or download and run
curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh -o habs.sh
chmod +x habs.sh
./habs.sh
```

> Running `./habs.sh` runs **all 12 benchmark categories**.

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
| `--skip-advanced`     | Skip advanced benchmarks                       |
| `--quick`, `-q`       | Quick mode — shorter tests                     |
| `--full`, `-f`        | Full mode — comprehensive tests                |
| `--json`              | Output results as JSON to stdout               |
| `--output FILE`       | Save results to file                           |
| `--no-color`          | Disable colored terminal output                |
| `--verbose`, `-v`     | Enable verbose/debug output                    |

### Examples

```bash
# Full benchmark suite
./habs.sh

# Quick overview
./habs.sh --quick

# Skip network tests
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

All benchmarks run by default. Use `--skip-*` to exclude.

### CPU

Uses **sysbench** for prime number computation:

| Mode            | Configuration               | Duration    |
|-----------------|-----------------------------|-------------|
| Quick (`-q`)    | 1t + Nt, max-prime=10k      | ~15–30s     |
| Default         | 1t + Nt, max-prime=20k      | ~30–60s     |
| Full (`-f`)     | 1t + Nt, max-prime=50k      | ~60–120s    |

Scaling ratio shows multi-core utilization.

### Memory

Sequential read/write throughput via sysbench (1M blocks):

| Mode            | Total Size  |
|-----------------|-------------|
| Quick (`-q`)    | 2 GB        |
| Default         | 10 GB       |
| Full (`-f`)     | 20 GB       |

### Disk

**dd** with direct I/O, bypassing caching. Auto-scales when disk space is limited. IOPS calculated automatically.

| Test             | Block Size |
|------------------|------------|
| 1M Seq Write     | 1 MiB      |
| 1M Seq Read      | 1 MiB      |
| 4K Random Write  | 4 KiB      |
| 4K Random Read   | 4 KiB      |

### Network

Multi-CDN download (best result reported), iperf3 upload, ICMP latency:

| Measure     | Method                                  |
|-------------|-----------------------------------------|
| Download    | curl — Cloudflare, CacheFly, OVH, Tele2 |
| Upload      | iperf3 — he.net, online.net, scottlinux |
| Latency     | ping — 1.1.1.1, 8.8.8.8, cloudflare    |
| IPv6        | curl via IPv6 to Cloudflare             |
| Packet Loss | ping to 1.1.1.1                         |
| Traceroute  | hop count to 1.1.1.1                    |

### Geekbench 6

Auto-downloads Geekbench 6 CLI from `cdn.geekbench.com` and runs the full suite:

| Metric       | Description                                   |
|-------------|-----------------------------------------------|
| Single-Core | 25+ real-world workloads                      |
| Multi-Core  | Same workloads, all cores simultaneously      |

- Duration: **5–10 minutes**
- Architecture: x86_64 + ARM64
- Results exported to JSON, parsed automatically

### Advanced CPU

Multi-threaded **sysbench** at 1t, 2t, 4t, Nt levels + **OpenSSL** crypto throughput (AES-256-GCM, SHA-256).

### Advanced Memory

Multi-block sysbench read test:

| Block Size | Target         |
|------------|----------------|
| 256B       | L1 cache       |
| 4K         | L2/L3 cache    |
| 64K        | RAM bandwidth  |

### Advanced Disk

| Tool     | Test                                |
|----------|-------------------------------------|
| **fio**  | Random 4K QD=32, 70/30 R/W, io_uring/libaio/psync auto-detect |
| **ioping** | Actual disk response time (ms)     |

### Advanced Network

| Test          | Method                                 |
|---------------|----------------------------------------|
| IPv6 Download | curl via IPv6 to Cloudflare            |
| Packet Loss   | ICMP ping to 1.1.1.1                   |
| Traceroute    | Hop count to 1.1.1.1                   |

---

## Scoring

Weighted 100-point scale, normalized from 5 categories (25 pts max each):

| Category      | Baseline                    |
|---------------|-----------------------------|
| CPU           | 100 events/s single-thread  |
| Memory        | 2000 MiB/s read             |
| Disk          | 500 MB/s avg (1M r/w)      |
| Network       | 500 Mbps download           |
| Geekbench 6   | 500 single-core score       |

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

Compact professional output with all results in a single clean view:

```
  ┌─ System Information ────────────────────────────────────┐
   Hostname : server-01       OS : Ubuntu 24.04
   CPU      : AMD EPYC 7713 (8C/16T) @ 3.0 GHz | AES AVX2
   RAM      : 2.5 GB / 15.6 GB    Disk : 3% — ext4
   Net      : IPv4:203.0.113.1    | AS13335 Cloudflare
   Load     : 0.15 / 0.20 / 0.25  Virt : kvm  Up : 12h 4m
  └──────────────────────────────────────────────────────────┘

  ┌─ Overview ──────────────────────────────────────────────┐
   CPU S/M  : 1234 / 5678 ev/s (4.6x)  | Crypto : AES/SHA
   Memory   : R:10240 W:5120 MiB/s     | L1/L2 : 256/128
   Disk 1M  : W:870 R:1234 MB/s        | 4K : 32k/42k IOPS
   FIO 4K   : 84k R / 36k W IOPS       | ioping : 0.42 ms
   Network  : DL:860 UL:242 Mbps       | LAT : 1.1 ms
   GB6      : SC:1234 MC:5678          | AS13335 Cloudflare
   Scores   : CPU 25.0  MEM 18.7  DISK 15.2  NET 22.1  GB 24.5
   Total    : 82/100 (A-)
  └──────────────────────────────────────────────────────────┘
```

### JSON

Full structured JSON with all benchmark results:

```json
{
  "tool": "HABS",
  "version": "2.0.0",
  "duration_seconds": 754,
  "system": {
    "hostname": "server-01",
    "cpu": { "model": "AMD EPYC 7713", "logical_cores": 8 },
    "memory": { "ram_total_bytes": 16506322944 },
    "network": { "ipv4": "203.0.113.1", "asn": "13335 Cloudflare" }
  },
  "benchmarks": {
    "cpu": { "single_events_per_sec": 1234.56 },
    "memory": { "read_mib_per_sec": 1095.67 },
    "disk": { "1m_read_mb_per_sec": 1234.5 },
    "network": { "download_mbps": 456.78 },
    "geekbench_6": { "single_core_score": 1234 },
    "advanced_cpu": { "aes_256_gcm": "14296285.18k" },
    "advanced_disk": { "fio_random_4k_read_iops": 84373 }
  },
  "scores": { "total": 82, "grade": "A-" }
}
```

---

## Requirements

| Tool        | Required | Used For                              | Auto-Install |
|-------------|----------|---------------------------------------|--------------|
| `sysbench`  | Yes      | CPU, memory, advanced memory          | ✅           |
| `curl`      | Yes      | Network download, Geekbench, ASN lookup | ❌ (pre-installed) |
| `dd`        | Yes      | Disk I/O                              | ❌ (coreutils) |
| `ping`      | Yes      | Latency, packet loss                  | ❌ (pre-installed) |
| `python3`   | Yes      | JSON parsing                          | ❌ (pre-installed) |
| `bc`        | Yes      | Arithmetic calculations               | ❌ (pre-installed) |
| `fio`       | Yes*     | Advanced disk (QD=32 IOPS)            | ✅           |
| `ioping`    | No       | Disk latency                          | ✅           |
| `iperf3`    | No       | Upload speed                          | ✅           |
| `traceroute` | No      | Hop count                             | ✅           |
| `openssl`   | No       | Crypto benchmark                      | ❌ (pre-installed) |

`*` — part of `--skip-advanced`

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

### System-wide

```bash
sudo curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh -o /usr/local/bin/habs
sudo chmod +x /usr/local/bin/habs
habs
```

---

## Troubleshooting

### Geekbench 6 fails
Ensure curl works and internet is available. Geekbench downloads ~100 MB. If scores show `SC:0` / `MC:0`, Geekbench may be stuck waiting for upload — results are saved to JSON locally but may require the paid Pro version for offline use.

### Dependencies won't install
Run as root or install manually:
```bash
apt-get install -y sysbench fio ioping iperf3 traceroute
```

### Disk benchmark is slow
WSL2, containers, and network filesystems exhibit lower I/O. Run `--full` on bare metal.

### Network test times out
Some providers block ICMP or CDN ranges. Use `--skip-network` or `--quick`.

### JSON output is blank
```bash
./habs.sh --json 2>/dev/null | jq .
```
All messages go to stderr; stdout contains only JSON.

---

## Contributing

1. **Fork** the repository
2. Create a **feature branch** (`feat/your-feature`)
3. Ensure **shellcheck** passes: `shellcheck habs.sh`
4. Test with `bash -n habs.sh` and a full benchmark run
5. Submit a **pull request**

### Code Style

- `set -euo pipefail` strict error handling
- `snake_case` for variables and functions
- `local` for all function-scoped variables

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
