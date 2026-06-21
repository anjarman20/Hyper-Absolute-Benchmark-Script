#!/usr/bin/env bash
#
# HABS - Hyper Absolute Benchmark Script
# Modern Linux benchmark tool with Geekbench 6 & advanced benchmarks
# Supports VPS, dedicated servers, and cloud infrastructure
#
# Usage:
#   bash <(curl -sSL https://raw.githubusercontent.com/anjarman20/Hyper-Absolute-Benchmark-Script/main/habs.sh)
#   bash habs.sh [options]
#
# Options:
#   -h, --help            Show help message
#   --version             Show version
#   --skip-cpu            Skip CPU benchmark
#   --skip-memory         Skip memory benchmark
#   --skip-disk           Skip disk benchmark
#   --skip-network        Skip network benchmark
#   -q, --quick           Quick mode (shorter/darker tests)
#   -f, --full            Full mode (comprehensive tests)
#   --json                Output results as JSON
#   --output FILE         Save results to file
#   --no-color            Disable colored output
#   -v, --verbose         Verbose output
#
# All benchmarks (Geekbench 6, advanced CPU/memory/disk/network)
# run by default. Use --skip-* flags to exclude specific tests.

set -euo pipefail

# ============================================================
# GLOBALS
# ============================================================
readonly VERSION="2.0.0"
START_TIME=0
TEMP_FILES=()

# CLI configuration
CONFIG_SKIP_CPU=false
CONFIG_SKIP_MEMORY=false
CONFIG_SKIP_DISK=false
CONFIG_SKIP_NETWORK=false
CONFIG_GEEKBENCH=true
CONFIG_ADVANCED=true
CONFIG_QUICK=false
CONFIG_FULL=false
CONFIG_JSON=false
CONFIG_OUTPUT=""
CONFIG_NO_COLOR=false
CONFIG_VERBOSE=false

# Standard results
RESULT_CPU_SINGLE=0
RESULT_CPU_MULTI=0
RESULT_MEM_READ=0
RESULT_MEM_WRITE=0
RESULT_DISK_4K_WRITE=0
RESULT_DISK_4K_READ=0
RESULT_DISK_1M_WRITE=0
RESULT_DISK_1M_READ=0
RESULT_NET_DOWNLOAD=0
RESULT_NET_UPLOAD=0
RESULT_NET_LATENCY=0

# Geekbench results
RESULT_GB_SINGLE=0
RESULT_GB_MULTI=0

# Advanced CPU results
RESULT_ADV_CPU_MATRIX=0
RESULT_ADV_CPU_FPU=0
RESULT_ADV_CPU_CRYPT=0
RESULT_ADV_CPU_CACHE=0

# Advanced memory results
RESULT_ADV_MEM_LATENCY=0
RESULT_ADV_MEM_256B=0
RESULT_ADV_MEM_4K=0
RESULT_ADV_MEM_64K=0
RESULT_ADV_MEM_1M=0

# Advanced disk results
RESULT_ADV_FIO_RND_R_IOPS=0
RESULT_ADV_FIO_RND_W_IOPS=0
RESULT_ADV_FIO_RND_R_LAT=0
RESULT_ADV_FIO_RND_W_LAT=0
RESULT_ADV_IOPING_LAT=0

# Advanced network results
RESULT_ADV_NET_IPV6=0
RESULT_ADV_NET_PLOSS=0
RESULT_ADV_NET_HOPS=0

# System info
SYS_HOSTNAME=""
SYS_OS=""
SYS_KERNEL=""
SYS_UPTIME=""
SYS_CPU_MODEL=""
SYS_CPU_CORES=0
SYS_CPU_THREADS=0
SYS_CPU_FREQ=""
SYS_CPU_CACHE=""
SYS_CPU_FLAGS=""
SYS_RAM_TOTAL=0
SYS_RAM_USED=0
SYS_RAM_AVAIL=0
SYS_SWAP_TOTAL=0
SYS_DISK_TOTAL=""
SYS_DISK_USED=""
SYS_DISK_AVAIL=""
SYS_DISK_PCT=""
SYS_DISK_MOUNT=""
SYS_DISK_FSTYPE=""
SYS_VIRT=""
SYS_LOAD=""
SYS_ARCH=""
SYS_AES=""
SYS_VMX=""
SYS_ISP=""
SYS_ASN=""
SYS_ORG=""
SYS_LOCATION=""
SYS_COUNTRY=""
SYS_IPV4=false
SYS_IPV6=false

# ============================================================
# COLOR DEFINITIONS
# ============================================================
setup_colors() {
  if [ -t 1 ] && [ "$CONFIG_NO_COLOR" = false ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_ITALIC='\033[3m'
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_MAGENTA='\033[0;35m'
    C_CYAN='\033[0;36m'
    C_WHITE='\033[0;37m'
  else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_ITALIC=''
    C_RED=''; C_GREEN=''; C_YELLOW=''
    C_BLUE=''; C_MAGENTA=''; C_CYAN=''; C_WHITE=''
  fi

  # Box-drawing: ASCII by default (always safe), Unicode only with HABS_UNICODE=1
  if [ "${HABS_UNICODE:-0}" = "1" ] && [ "$CONFIG_NO_COLOR" = false ]; then
    C_TL="┌"; C_TR="┐"; C_BL="└"; C_BR="┘"
    C_H="─"; C_V="│"
  else
    C_TL="+"; C_TR="+"; C_BL="+"; C_BR="+"
    C_H="-"; C_V="|"
  fi
}

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

die() {
  echo -e "${C_RED}Error:${C_RESET} $1" >&2
  exit 1
}

log_debug() {
  [ "$CONFIG_VERBOSE" = true ] && echo -e "${C_DIM}[DEBUG]${C_RESET} $1" >&2 || true
}

log_info() {
  echo -e "${C_BLUE}==>${C_RESET} $1" >&2
}

log_success() {
  echo -e "${C_GREEN}==>${C_RESET} $1" >&2
}

log_warn() {
  echo -e "${C_YELLOW}==>${C_RESET} $1" >&2
}

format_bytes() {
  local bytes=$1 precision=${2:-2}
  if [ "$(awk "BEGIN {print ($bytes < 1024)}")" -eq 1 ]; then
    echo "${bytes} B"
  elif [ "$(awk "BEGIN {print ($bytes < 1048576)}")" -eq 1 ]; then
    awk "BEGIN {printf \"%.${precision}f KiB\", $bytes/1024}"
  elif [ "$(awk "BEGIN {print ($bytes < 1073741824)}")" -eq 1 ]; then
    awk "BEGIN {printf \"%.${precision}f MiB\", $bytes/1048576}"
  else
    awk "BEGIN {printf \"%.${precision}f GiB\", $bytes/1073741824}"
  fi
}

format_duration() {
  local s=${1:-0} d=0 h=0 m=0
  d=$((s / 86400)); s=$((s % 86400))
  h=$((s / 3600));  s=$((s % 3600))
  m=$((s / 60));    s=$((s % 60))
  local out=""
  [ "$d" -gt 0 ] && out="${d}d "
  [ "$h" -gt 0 ] && out="${out}${h}h "
  [ "$m" -gt 0 ] && out="${out}${m}m "
  out="${out}${s}s"
  echo "$out"
}

cleanup() {
  for f in "${TEMP_FILES[@]}"; do
    [ -f "$f" ] && rm -f "$f" 2>/dev/null || true
  done
}

cleanup_geekbench() {
  [ -n "${GB_DIR:-}" ] && [ -d "$GB_DIR" ] && rm -rf "$GB_DIR" 2>/dev/null || true
}

setup_signals() {
  trap cleanup EXIT
  trap 'echo -e "\n${C_YELLOW}Interrupted. Cleaning up...${C_RESET}"; cleanup; cleanup_geekbench; exit 1' INT TERM
}

command_exists() {
  command -v "$1" &>/dev/null
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

download_url() {
  local url=$1 dest=$2 timeout=${3:-60}
  if command_exists curl; then
    curl -sSL --max-time "$timeout" -o "$dest" "$url" 2>/dev/null
  elif command_exists wget; then
    wget -q --timeout="$timeout" -O "$dest" "$url" 2>/dev/null
  else
    return 1
  fi
}

# ============================================================
# SECTION HEADERS
# ============================================================

print_header() {
  echo ""
  echo -e "  ${C_CYAN} _   _    _     ____   ____  ${C_RESET}"
  echo -e "  ${C_CYAN}| | | |  / \   | __ ) / ___| ${C_RESET}  ${C_BOLD}Hyper Absolute Benchmark Script${C_RESET}"
  echo -e "  ${C_CYAN}| |_| | / _ \  |  _ \ \___ \\ ${C_RESET}  ${C_DIM}Version ${VERSION}${C_RESET}"
  echo -e "  ${C_CYAN}|  _  |/ ___ \\| |_) | ___) |${C_RESET}  ${C_DIM}Modern Linux Benchmark Tool${C_RESET}"
  echo -e "  ${C_CYAN}|_| |_/_/   \\_\\____/|____/ ${C_RESET}"
  echo ""
  local cols=58
  printf "  ${C_DIM}%s${C_RESET}\n" "$(printf '%*s' "$cols" | tr ' ' "${C_H}")"
  echo ""
}

section_start() {
  echo ""
  echo -e "  ${C_BOLD}${C_CYAN}${C_TL} $1 ${C_H}$(printf '%*s' $((50 - ${#1})) '' | tr ' ' "${C_H}")${C_TR}${C_RESET}"
}

section_end() {
  echo -e "  ${C_BOLD}${C_CYAN}${C_BL}$(printf '%*s' 56 '' | tr ' ' "${C_H}")${C_BR}${C_RESET}"
  echo ""
}

info_row() {
  printf "  ${C_BOLD}%-18s${C_RESET} %s\n" " $1" ": $2"
}

# ============================================================
# INSTALL DEPENDENCIES
# ============================================================

_SYSBENCH_CHECKED=false
_SYSBENCH_AVAILABLE=false

ensure_sysbench() {
  if [ "$_SYSBENCH_CHECKED" = true ]; then
    [ "$_SYSBENCH_AVAILABLE" = true ] && return 0 || return 1
  fi
  _SYSBENCH_CHECKED=true
  if command_exists sysbench; then
    _SYSBENCH_AVAILABLE=true
    return 0
  fi
  log_info "Installing sysbench..."
  if command_exists apt-get; then
    apt-get install -y sysbench &>/dev/null && { log_success "sysbench installed"; _SYSBENCH_AVAILABLE=true; return 0; }
  elif command_exists yum; then
    yum install -y sysbench &>/dev/null && { log_success "sysbench installed"; _SYSBENCH_AVAILABLE=true; return 0; }
  elif command_exists apk; then
    apk add sysbench &>/dev/null && { log_success "sysbench installed"; _SYSBENCH_AVAILABLE=true; return 0; }
  elif command_exists pacman; then
    pacman -S --noconfirm sysbench &>/dev/null && { log_success "sysbench installed"; _SYSBENCH_AVAILABLE=true; return 0; }
  elif command_exists zypper; then
    zypper install -y sysbench &>/dev/null && { log_success "sysbench installed"; _SYSBENCH_AVAILABLE=true; return 0; }
  fi
  log_warn "sysbench could not be installed. CPU/memory benchmarks will be skipped."
  return 1
}

ensure_stress_ng() {
  if command_exists stress-ng; then
    return 0
  fi
  log_info "Installing stress-ng..."
  if command_exists apt-get; then
    apt-get install -y stress-ng &>/dev/null && log_success "stress-ng installed" && return 0
  elif command_exists yum; then
    yum install -y stress-ng &>/dev/null && log_success "stress-ng installed" && return 0
  elif command_exists apk; then
    apk add stress-ng &>/dev/null && log_success "stress-ng installed" && return 0
  elif command_exists pacman; then
    pacman -S --noconfirm stress-ng &>/dev/null && log_success "stress-ng installed" && return 0
  elif command_exists zypper; then
    zypper install -y stress-ng &>/dev/null && log_success "stress-ng installed" && return 0
  fi
  log_warn "stress-ng not available. Advanced CPU skipped."
  return 1
}

ensure_fio() {
  if command_exists fio; then
    return 0
  fi
  log_info "Installing fio..."
  if command_exists apt-get; then
    apt-get install -y fio &>/dev/null && log_success "fio installed" && return 0
  elif command_exists yum; then
    yum install -y fio &>/dev/null && log_success "fio installed" && return 0
  elif command_exists apk; then
    apk add fio &>/dev/null && log_success "fio installed" && return 0
  elif command_exists pacman; then
    pacman -S --noconfirm fio &>/dev/null && log_success "fio installed" && return 0
  fi
  log_warn "fio not available. Advanced disk skipped."
  return 1
}

# ============================================================
# SYSTEM INFORMATION
# ============================================================

gather_system_info() {
  log_info "Gathering system information..."

  SYS_HOSTNAME=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo "unknown")

  if [ -f /etc/os-release ]; then
    SYS_OS=$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release 2>/dev/null)
    [ -z "$SYS_OS" ] && SYS_OS=$(sed -n 's/^PRETTY_NAME=\(.*\)/\1/p' /etc/os-release 2>/dev/null)
  fi
  [ -z "$SYS_OS" ] && SYS_OS="Unknown"

  SYS_KERNEL=$(uname -r)
  SYS_ARCH=$(uname -m)

  if [ -f /proc/uptime ]; then
    local up=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
    SYS_UPTIME=$(format_duration "$up")
  fi

  if [ -f /proc/cpuinfo ]; then
    SYS_CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | xargs)
    [ -z "$SYS_CPU_MODEL" ] && SYS_CPU_MODEL=$(grep -m1 'Processor' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | xargs)
    [ -z "$SYS_CPU_MODEL" ] && SYS_CPU_MODEL="Unknown"

    SYS_CPU_THREADS=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
    SYS_CPU_CORES=$SYS_CPU_THREADS

    if command_exists lscpu; then
      local lscpu_out
      lscpu_out=$(lscpu 2>/dev/null) || true
      if [ -n "$lscpu_out" ]; then
        local cores
        cores=$(echo "$lscpu_out" | awk -F: '/^CPU\(s\):/ {gsub(/ /,"",$2); print $2}')
        [ -n "$cores" ] && SYS_CPU_CORES=$cores

        local freq
        freq=$(echo "$lscpu_out" | awk -F: '/MHz/ {gsub(/ /,"",$2); print $2; exit}')
        if [ -n "$freq" ]; then
          SYS_CPU_FREQ=$(awk "BEGIN {printf \"%.2f GHz\", $freq/1000}" 2>/dev/null || echo "")
        else
          local max_freq
          max_freq=$(echo "$lscpu_out" | awk -F: '/max MHz/ {gsub(/ /,"",$2); print $2}')
          [ -n "$max_freq" ] && SYS_CPU_FREQ=$(awk "BEGIN {printf \"%.2f GHz\", $max_freq/1000}" 2>/dev/null || echo "")
        fi

        SYS_CPU_CACHE=$(echo "$lscpu_out" | awk -F: '/^L[1-3][di]? cache:/ {gsub(/^ */,"",$1); gsub(/^ /,"",$2); printf "%s: %s, ", $1, $2}' | sed 's/, $//') || true
        SYS_CPU_FLAGS=$(echo "$lscpu_out" | awk -F: '/^[Ff]lags/ {print $2}' | xargs) || true
      fi
    fi

    [ -z "$SYS_CPU_FREQ" ] && SYS_CPU_FREQ=$(awk '/cpu MHz/ {printf "%.2f GHz", $NF/1000; exit}' /proc/cpuinfo 2>/dev/null || echo "N/A")
    [ -z "$SYS_CPU_FREQ" ] && SYS_CPU_FREQ="N/A"
    [ -z "$SYS_CPU_FLAGS" ] && SYS_CPU_FLAGS=$(grep -m1 'flags\|Features' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | xargs || echo "")
  fi

  if [ -f /proc/meminfo ]; then
    local mem_total mem_avail swap_total
    mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo) || true
    mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo) || true
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo) || true

    : "${mem_total:=0}" "${mem_avail:=0}" "${swap_total:=0}"
    SYS_RAM_TOTAL=$((mem_total * 1024))
    SYS_RAM_AVAIL=$((mem_avail * 1024))
    SYS_RAM_USED=$((SYS_RAM_TOTAL - SYS_RAM_AVAIL))
    SYS_SWAP_TOTAL=$((swap_total * 1024))
  fi

  local disk_info
  disk_info=$(df -h / 2>/dev/null | tail -1) || true
  if [ -n "$disk_info" ]; then
    SYS_DISK_TOTAL=$(echo "$disk_info" | awk '{print $2}') || true
    SYS_DISK_USED=$(echo "$disk_info" | awk '{print $3}') || true
    SYS_DISK_AVAIL=$(echo "$disk_info" | awk '{print $4}') || true
    SYS_DISK_PCT=$(echo "$disk_info" | awk '{print $5}') || true
    SYS_DISK_MOUNT=$(echo "$disk_info" | awk '{print $6}') || true
    SYS_DISK_FSTYPE=$(df -T / 2>/dev/null | tail -1 | awk '{print $2}') || true
  fi

  if command_exists systemd-detect-virt; then
    SYS_VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")
  elif command_exists hostnamectl; then
    SYS_VIRT=$(hostnamectl 2>/dev/null | awk -F: '/Virtualization/ {gsub(/^ /,"",$2); print $2}') || true
    [ -z "$SYS_VIRT" ] && SYS_VIRT="none"
  else
    SYS_VIRT="none/detect"
  fi

  if [ -f /proc/cpuinfo ]; then
    SYS_AES=$(grep -q 'aes' /proc/cpuinfo 2>/dev/null && echo "Enabled" || echo "Disabled")
    SYS_VMX=$(grep -q 'vmx\|svm' /proc/cpuinfo 2>/dev/null && echo "Enabled" || echo "Disabled")
  fi

  if [ -f /proc/loadavg ]; then
    SYS_LOAD=$(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg) || true
  fi

  # IPv4/IPv6 connectivity check
  if command_exists ping; then
    ping -4 -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && SYS_IPV4=true || SYS_IPV4=false
    ping -6 -c 1 -W 2 2001:4860:4860::8888 >/dev/null 2>&1 && SYS_IPV6=true || SYS_IPV6=false
  fi

  # Network info via ip-api.com (non-blocking, short timeout)
  if command_exists curl && [ "$SYS_IPV4" = true ]; then
    local ip_info
    ip_info=$(curl -s --max-time 3 http://ip-api.com/json/ 2>/dev/null) || true
    if [ -n "$ip_info" ]; then
      SYS_ISP=$(echo "$ip_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('isp','?'))" 2>/dev/null || echo "")
      SYS_ASN=$(echo "$ip_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('as','?'))" 2>/dev/null || echo "")
      SYS_ORG=$(echo "$ip_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('org','?'))" 2>/dev/null || echo "")
      [ -z "$SYS_ORG" ] && SYS_ORG=$(echo "$ip_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('org','?'))" 2>/dev/null || echo "")
      SYS_COUNTRY=$(echo "$ip_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('country','?'))" 2>/dev/null || echo "")
      local city region
      city=$(echo "$ip_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('city',''))" 2>/dev/null || echo "")
      region=$(echo "$ip_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('regionName',''))" 2>/dev/null || echo "")
      [ -n "$city" ] && [ -n "$region" ] && SYS_LOCATION="${city}, ${region}" || SYS_LOCATION="$city$region"
    fi
  fi

  log_success "System information gathered"
}

print_system_info() {
  section_start "System Information"
  info_row "Hostname"       "${SYS_HOSTNAME}"
  info_row "OS"             "${SYS_OS} (${SYS_ARCH})"
  info_row "Kernel"         "${SYS_KERNEL}"
  info_row "Uptime"         "${SYS_UPTIME}"
  info_row "CPU Model"      "${SYS_CPU_MODEL}"
  info_row "CPU Cores"      "${SYS_CPU_CORES} cores / ${SYS_CPU_THREADS} threads"
  info_row "CPU Freq"       "${SYS_CPU_FREQ}"
  if [ -n "$SYS_CPU_CACHE" ]; then
    IFS=',' read -ra cache_lines <<< "$SYS_CPU_CACHE"
    for cl in "${cache_lines[@]}"; do
      cl=$(echo "$cl" | xargs)
      case "$cl" in
        L1d*)   info_row "L1d Cache"  "${cl#L1d cache: }" ;;
        L1i*)   info_row "L1i Cache"  "${cl#L1i cache: }" ;;
        L2*)    info_row "L2 Cache"   "${cl#L2 cache: }" ;;
        L3*)    info_row "L3 Cache"   "${cl#L3 cache: }" ;;
      esac
    done
  fi
  local ram_pct=0
  [ "$SYS_RAM_TOTAL" -gt 0 ] && ram_pct=$(( SYS_RAM_USED * 100 / SYS_RAM_TOTAL ))
  info_row "RAM"            "$(format_bytes $SYS_RAM_USED) used / $(format_bytes $SYS_RAM_TOTAL) total (${ram_pct}%)"
  info_row "Swap"           "$(format_bytes $SYS_SWAP_TOTAL) total"
  info_row "Disk"           "${SYS_DISK_USED} used / ${SYS_DISK_TOTAL} total (${SYS_DISK_PCT})"
  info_row "Filesystem"     "${SYS_DISK_FSTYPE} on ${SYS_DISK_MOUNT}"
  info_row "Virt"           "${SYS_VIRT}"
  info_row "AES-NI"         "${SYS_AES}"
  info_row "VM-x/AMD-V"     "${SYS_VMX}"
  info_row "Load Avg"       "${SYS_LOAD}"
  if [ -n "$SYS_ISP" ]; then
    info_row "ISP"           "${SYS_ISP}"
    [ -n "$SYS_ASN" ] && info_row "ASN"   "${SYS_ASN}"
    [ -n "$SYS_LOCATION" ] && info_row "Location" "${SYS_LOCATION}"
  fi
  local ipv4_status="${SYS_IPV4}"
  local ipv6_status="${SYS_IPV6}"
  [ "$SYS_IPV4" = true ] && ipv4_status="Online" || ipv4_status="Offline"
  [ "$SYS_IPV6" = true ] && ipv6_status="Online" || ipv6_status="Offline"
  info_row "IPv4/IPv6"      "${ipv4_status} / ${ipv6_status}"
  section_end
}

# ============================================================
# CPU BENCHMARK (Standard)
# ============================================================

bench_cpu() {
  section_start "CPU Benchmark"

  echo -e "  ${C_YELLOW}Running CPU benchmark. Tests run at reduced priority (nice -n 19).${C_RESET}"

  ensure_sysbench || { section_end; return 1; }

  local cpu_time=6
  local max_prime=15000
  [ "$CONFIG_QUICK" = true ] && cpu_time=3 && max_prime=10000
  [ "$CONFIG_FULL" = true ] && cpu_time=12 && max_prime=30000

  echo -e "  ${C_BOLD}Single-core test (${cpu_time}s)...${C_RESET}"
  local single_out
  single_out=$(nice -n 19 sysbench cpu --cpu-max-prime="$max_prime" --threads=1 --time="$cpu_time" run 2>/dev/null)
  RESULT_CPU_SINGLE=$(echo "$single_out" | sed -n 's/.*events per second:\s*\([0-9.]*\).*/\1/p')
  [ -z "$RESULT_CPU_SINGLE" ] && RESULT_CPU_SINGLE=0
  echo -e "  ${C_GREEN}✓${C_RESET} Single-core:  ${C_BOLD}$(printf "%'.0f" "$RESULT_CPU_SINGLE" 2>/dev/null || echo "$RESULT_CPU_SINGLE")${C_RESET} events/s"

  echo -e "  ${C_BOLD}Multi-core test (${SYS_CPU_THREADS} cores, ${cpu_time}s)...${C_RESET}"
  local multi_out
  multi_out=$(nice -n 19 sysbench cpu --cpu-max-prime="$max_prime" --threads="$SYS_CPU_THREADS" --time="$cpu_time" run 2>/dev/null)
  RESULT_CPU_MULTI=$(echo "$multi_out" | sed -n 's/.*events per second:\s*\([0-9.]*\).*/\1/p')
  [ -z "$RESULT_CPU_MULTI" ] && RESULT_CPU_MULTI=0

  echo -e "  ${C_GREEN}✓${C_RESET} Multi-core:   ${C_BOLD}$(printf "%'.0f" "$RESULT_CPU_MULTI" 2>/dev/null || echo "$RESULT_CPU_MULTI")${C_RESET} events/s"

  if [ "$(awk "BEGIN {print ($RESULT_CPU_SINGLE > 0)}")" -eq 1 ]; then
    local ratio
    ratio=$(awk "BEGIN {printf \"%.2f\", $RESULT_CPU_MULTI / $RESULT_CPU_SINGLE}" 2>/dev/null)
    echo -e "  ${C_DIM}  Scaling:     ${ratio}x (ideal: ${SYS_CPU_THREADS}x)${C_RESET}"
  fi

  section_end
}

# ============================================================
# GEEKBENCH 6
# ============================================================

bench_geekbench() {
  section_start "Geekbench 6"

  local gb_url="https://cdn.geekbench.com/Geekbench-6.7.1-Linux.tar.gz"
  local gb_tar="/tmp/geekbench6.tar.gz"
  GB_DIR="/tmp/geekbench6-$$"

  if [ -f "$GB_DIR/geekbench6" ]; then
    log_info "Using cached Geekbench 6 in ${GB_DIR}"
  else
    echo -e "  ${C_BOLD}Checking internet connectivity...${C_RESET}"
    if command_exists curl; then
      curl -sI --max-time 5 "https://cdn.geekbench.com" >/dev/null 2>&1 || {
        echo -e "  ${C_YELLOW}Cannot reach Geekbench CDN. Skipping.${C_RESET}"
        section_end
        return 1
      }
    fi
    echo -e "  ${C_BOLD}Downloading Geekbench 6 (~100 MB)...${C_RESET}"
    if ! download_url "$gb_url" "$gb_tar" 120; then
      echo -e "  ${C_RED}Failed to download Geekbench 6. Check internet connection.${C_RESET}"
      section_end
      return 1
    fi
    echo -e "  ${C_GREEN}Downloaded. Extracting...${C_RESET}"
    mkdir -p "$GB_DIR"
    tar -xzf "$gb_tar" -C "$GB_DIR" --strip-components=1 2>/dev/null || {
      echo -e "  ${C_RED}Failed to extract Geekbench 6.${C_RESET}"
      rm -rf "$GB_DIR" 2>/dev/null || true
      section_end
      return 1
    }
    rm -f "$gb_tar"
  fi

  local gb_bin="$GB_DIR/geekbench6"
  if [ ! -x "$gb_bin" ]; then
    echo -e "  ${C_RED}Geekbench 6 binary not found.${C_RESET}"
    section_end
    return 1
  fi

  echo -e "  ${C_BOLD}Running Geekbench 6 (this takes 5-10 minutes)...${C_RESET}"
  echo -e "  ${C_DIM}Geekbench measures AES, LZMA, JPEG, HTML5, SQLite, and more${C_RESET}"

  local gb_out
  gb_out=$("$gb_bin" --json --no-upload 2>/dev/null) || true
  local gb_exit=$?

  if [ "$gb_exit" -ne 0 ] || [ -z "$gb_out" ]; then
    echo -e "  ${C_RED}Geekbench 6 failed with exit code ${gb_exit}${C_RESET}"
    section_end
    return 1
  fi

  RESULT_GB_SINGLE=$(echo "$gb_out" | grep -o '"single": [0-9]*' | grep -o '[0-9]*' | head -1)
  RESULT_GB_MULTI=$(echo "$gb_out" | grep -o '"multi": [0-9]*' | grep -o '[0-9]*' | head -1)

  if [ -z "$RESULT_GB_SINGLE" ]; then
    local gb_json_file
    gb_json_file=$(find "$GB_DIR" -name "*.json" -newer "$gb_bin" 2>/dev/null | head -1)
    if [ -n "$gb_json_file" ]; then
      RESULT_GB_SINGLE=$(grep -o '"single_score": [0-9]*' "$gb_json_file" 2>/dev/null | grep -o '[0-9]*' | head -1)
      RESULT_GB_MULTI=$(grep -o '"multi_score": [0-9]*' "$gb_json_file" 2>/dev/null | grep -o '[0-9]*' | head -1)
    fi
  fi

  [ -z "$RESULT_GB_SINGLE" ] && RESULT_GB_SINGLE=0
  [ -z "$RESULT_GB_MULTI" ] && RESULT_GB_MULTI=0

  echo -e "  ${C_GREEN}✓${C_RESET} Single-Core: ${C_BOLD}${RESULT_GB_SINGLE}${C_RESET}"
  echo -e "  ${C_GREEN}✓${C_RESET} Multi-Core:  ${C_BOLD}${RESULT_GB_MULTI}${C_RESET}"

  section_end
  log_success "Geekbench 6 complete"
}

# ============================================================
# ADVANCED CPU (stress-ng)
# ============================================================

bench_advanced_cpu() {
  section_start "Advanced CPU (stress-ng)"

  if ! ensure_stress_ng; then
    section_end
    return 1
  fi

  local duration=20
  [ "$CONFIG_QUICK" = true ] && duration=10
  [ "$CONFIG_FULL" = true ] && duration=30

  echo -e "  ${C_BOLD}Matrix multiplication test (${duration}s)...${C_RESET}"
  local matrix_out
  matrix_out=$(stress-ng --matrix 0 --matrix-size 256 -t "$duration" --metrics-brief 2>&1) || true
  RESULT_ADV_CPU_MATRIX=$(echo "$matrix_out" | awk '/matrix/ {for(i=1;i<=NF;i++) if($i~/^[0-9.]+$/) {print $i; exit}}')
  [ -z "$RESULT_ADV_CPU_MATRIX" ] && RESULT_ADV_CPU_MATRIX=0
  echo -e "  ${C_GREEN}✓${C_RESET} Matrix:  ${C_BOLD}${RESULT_ADV_CPU_MATRIX}${C_RESET} bogo ops/s"

  echo -e "  ${C_BOLD}FPU test (${duration}s)...${C_RESET}"
  local fpu_out
  fpu_out=$(stress-ng --fpu 0 -t "$duration" --metrics-brief 2>&1) || true
  RESULT_ADV_CPU_FPU=$(echo "$fpu_out" | awk '/fpu/ {for(i=1;i<=NF;i++) if($i~/^[0-9.]+$/) {print $i; exit}}')
  [ -z "$RESULT_ADV_CPU_FPU" ] && RESULT_ADV_CPU_FPU=0
  echo -e "  ${C_GREEN}✓${C_RESET} FPU:     ${C_BOLD}${RESULT_ADV_CPU_FPU}${C_RESET} bogo ops/s"

  echo -e "  ${C_BOLD}Crypto operations test (${duration}s)...${C_RESET}"
  local crypt_out
  crypt_out=$(stress-ng --crypt 0 -t "$duration" --metrics-brief 2>&1) || true
  RESULT_ADV_CPU_CRYPT=$(echo "$crypt_out" | awk '/crypt/ {for(i=1;i<=NF;i++) if($i~/^[0-9.]+$/) {print $i; exit}}')
  [ -z "$RESULT_ADV_CPU_CRYPT" ] && RESULT_ADV_CPU_CRYPT=0
  echo -e "  ${C_GREEN}✓${C_RESET} Crypto:  ${C_BOLD}${RESULT_ADV_CPU_CRYPT}${C_RESET} bogo ops/s"

  echo -e "  ${C_BOLD}Cache thrash test (${duration}s)...${C_RESET}"
  local cache_out
  cache_out=$(stress-ng --cache 0 -t "$duration" --metrics-brief 2>&1) || true
  RESULT_ADV_CPU_CACHE=$(echo "$cache_out" | awk '/cache/ {for(i=1;i<=NF;i++) if($i~/^[0-9.]+$/) {print $i; exit}}')
  [ -z "$RESULT_ADV_CPU_CACHE" ] && RESULT_ADV_CPU_CACHE=0
  echo -e "  ${C_GREEN}✓${C_RESET} Cache:   ${C_BOLD}${RESULT_ADV_CPU_CACHE}${C_RESET} bogo ops/s"

  section_end
}

# ============================================================
# ADVANCED MEMORY (Multi-block & Latency)
# ============================================================

bench_advanced_memory() {
  section_start "Advanced Memory"

  if ! ensure_sysbench; then
    section_end
    return 1
  fi

  local mem_total="4G"
  [ "$CONFIG_QUICK" = true ] && mem_total="1G"
  [ "$CONFIG_FULL" = true ] && mem_total="8G"

  echo -e "  ${C_BOLD}Multi-block-size memory test...${C_RESET}"

  for blk in "256B" "4K" "64K" "1M"; do
    local bs_var
    bs_var=$(echo "$blk" | sed 's/B//')
    local out
    out=$(sysbench memory --memory-block-size="$blk" --memory-total-size="$mem_total" --memory-oper=read run 2>/dev/null)
    local speed
    speed=$(echo "$out" | sed -n 's/.*(\([0-9.]*\) MiB\/sec).*/\1/p')
    [ -z "$speed" ] && speed=0

    case "$blk" in
      "256B") RESULT_ADV_MEM_256B=$speed ;;
      "4K")   RESULT_ADV_MEM_4K=$speed ;;
      "64K")  RESULT_ADV_MEM_64K=$speed ;;
      "1M")   RESULT_ADV_MEM_1M=$speed ;;
    esac
    echo -e "  ${C_GREEN}✓${C_RESET} ${blk} Read: ${C_BOLD}${speed}${C_RESET} MiB/s"
  done

  # Memory latency using sysbench
  if command_exists lscpu; then
    echo -e "  ${C_BOLD}Memory latency estimation...${C_RESET}"
    local latency_ns="N/A"
    local l1_size l2_size l3_size
    l1_size=$(lscpu 2>/dev/null | awk -F: '/L1d/ {print $2}' | awk '{print $1}')
    l2_size=$(lscpu 2>/dev/null | awk -F: '/L2/ {print $2}' | awk '{print $1}')
    l3_size=$(lscpu 2>/dev/null | awk -F: '/L3/ {print $2}' | awk '{print $1}')

    RESULT_ADV_MEM_LATENCY=0
    echo -e "  ${C_GREEN}✓${C_RESET} L1 Cache: ${C_BOLD}${l1_size:-N/A}${C_RESET} | L2: ${l2_size:-N/A} | L3: ${l3_size:-N/A}"
  fi

  section_end
}

# ============================================================
# ADVANCED DISK (ioping only — fio tests in standard disk benchmark)
# ============================================================

bench_advanced_disk() {
  section_start "Advanced Disk"

  local temp_dir="${TMPDIR:-/tmp}"
  [ ! -w "$temp_dir" ] && temp_dir="."

  # Additional SSD-specific tests using fio
  if command_exists fio && python3 -c "import json" 2>/dev/null; then
    local fio_file="$temp_dir/habs_adv_disk.$$"
    TEMP_FILES+=("$fio_file")

    echo -e "  ${C_BOLD}Sequential 1M QD=8 (fio)...${C_RESET}"
    local out_sq8
    out_sq8=$(_run_fio_test "seq8" "1M" "read" 8 "1G" "" "$fio_file")
    local bw_sq8=$(_parse_fio_result "$out_sq8" "bw" "read")
    bw_sq8=$(awk "BEGIN {printf \"%.0f\", $bw_sq8 / 1000}" 2>/dev/null || echo 0)
    echo -e "  ${C_GREEN}✓${C_RESET} Seq 1M QD=8: ${C_BOLD}${bw_sq8}${C_RESET} MB/s"

    rm -f "$fio_file"

    # Trim/discard test for SSD
    if [ -d /sys/block ] && command_exists lsblk; then
      local rot
      rot=$(lsblk -d -o ROTA 2>/dev/null | tail -1 | xargs)
      if [ "$rot" = "0" ]; then
        echo -e "  ${C_DIM}  SSD detected: trim/discard not tested (non-destructive only)${C_RESET}"
      fi
    fi
  else
    echo -e "  ${C_DIM}  fio+python3 for extra disk tests${C_RESET}"
  fi

  section_end
}

# ============================================================
# ADVANCED NETWORK (IPv6, packet loss, traceroute)
# ============================================================

bench_advanced_network() {
  section_start "Advanced Network"

  if ! command_exists curl; then
    echo -e "  ${C_YELLOW}curl not found.${C_RESET}"
    section_end
    return 1
  fi

  # IPv6 speed test
  echo -e "  ${C_BOLD}IPv6 download test...${C_RESET}"
  local ipv6_url="https://speed.cloudflare.com/__down?bytes=50000000"
  local ipv6_speed
  ipv6_speed=$(curl -6 -sL --max-time 10 -o /dev/null -w "%{speed_download}" "$ipv6_url" 2>/dev/null) || ipv6_speed=""
  if [ -n "$ipv6_speed" ] && [ "$(awk "BEGIN {print ($ipv6_speed > 0)}")" -eq 1 ]; then
    RESULT_ADV_NET_IPV6=$(awk "BEGIN {printf \"%.2f\", $ipv6_speed * 8 / 1000000}" 2>/dev/null)
    echo -e "  ${C_GREEN}✓${C_RESET} IPv6: ${C_BOLD}${RESULT_ADV_NET_IPV6}${C_RESET} Mbps"
  else
    echo -e "  ${C_YELLOW}  IPv6 not available or slow${C_RESET}"
    RESULT_ADV_NET_IPV6=0
  fi

  # Packet loss test
  echo -e "  ${C_BOLD}Packet loss test...${C_RESET}"
  local ploss
  ploss=$(ping -c 10 -W 1 "1.1.1.1" 2>/dev/null | awk '/packet loss/ {print $6}' | sed 's/%//')
  if [ -n "$ploss" ]; then
    RESULT_ADV_NET_PLOSS=$ploss
    echo -e "  ${C_GREEN}✓${C_RESET} Packet loss: ${C_BOLD}${RESULT_ADV_NET_PLOSS}%${C_RESET}"
  else
    RESULT_ADV_NET_PLOSS=-1
    echo -e "  ${C_YELLOW}  Packet loss test failed${C_RESET}"
  fi

  # Traceroute hop count
  echo -e "  ${C_BOLD}Traceroute to cloudflare.com...${C_RESET}"
  local hops=0
  if command_exists traceroute; then
    hops=$(traceroute -n -q 1 -w 1 "1.1.1.1" 2>/dev/null | grep -c '[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*' || true)
  elif command_exists mtr; then
    hops=$(mtr -r -c 1 -n "1.1.1.1" 2>/dev/null | wc -l)
  fi
  if [ -n "$hops" ] && [ "$hops" -gt 0 ]; then
    RESULT_ADV_NET_HOPS=$hops
    echo -e "  ${C_GREEN}✓${C_RESET} Hops to 1.1.1.1: ${C_BOLD}${RESULT_ADV_NET_HOPS}${C_RESET}"
  else
    RESULT_ADV_NET_HOPS=0
    echo -e "  ${C_YELLOW}  Traceroute not available${C_RESET}"
  fi

  section_end
}

# ============================================================
# STANDARD MEMORY BENCHMARK
# ============================================================

bench_memory() {
  section_start "Memory Benchmark"
  ensure_sysbench || { section_end; return 1; }

  local mem_total="10G"
  local mem_block="1M"
  [ "$CONFIG_QUICK" = true ] && mem_total="2G"
  [ "$CONFIG_FULL" = true ] && mem_total="20G"

  echo -e "  ${C_BOLD}Memory read test (${mem_total})...${C_RESET}"
  local read_out
  read_out=$(sysbench memory --memory-block-size="$mem_block" --memory-total-size="$mem_total" --memory-oper=read run 2>/dev/null)
  RESULT_MEM_READ=$(echo "$read_out" | sed -n 's/.*(\([0-9.]*\) MiB\/sec).*/\1/p')
  [ -z "$RESULT_MEM_READ" ] && RESULT_MEM_READ=0
  echo -e "  ${C_GREEN}✓${C_RESET} Read:  ${C_BOLD}${RESULT_MEM_READ}${C_RESET} MiB/s"

  echo -e "  ${C_BOLD}Memory write test (${mem_total})...${C_RESET}"
  local write_out
  write_out=$(sysbench memory --memory-block-size="$mem_block" --memory-total-size="$mem_total" --memory-oper=write run 2>/dev/null)
  RESULT_MEM_WRITE=$(echo "$write_out" | sed -n 's/.*(\([0-9.]*\) MiB\/sec).*/\1/p')
  [ -z "$RESULT_MEM_WRITE" ] && RESULT_MEM_WRITE=0
  echo -e "  ${C_GREEN}✓${C_RESET} Write: ${C_BOLD}${RESULT_MEM_WRITE}${C_RESET} MiB/s"

  section_end
}

# ============================================================
# DISK BENCHMARK (fio — 4k/64k/512k/1m mixed 50/50, dd fallback)
# ============================================================

bench_disk() {
  section_start "Disk Benchmark"
  local temp_dir="${TMPDIR:-/tmp}"
  [ ! -w "$temp_dir" ] && temp_dir="."

  local fio_file="$temp_dir/habs_disk.$$"
  TEMP_FILES+=("$fio_file")

  # ZFS space inflation check
  local zfs_inflate=1
  [ -f "/sys/module/zfs/parameters/spa_asize_inflation" ] && zfs_inflate=$(cat /sys/module/zfs/parameters/spa_asize_inflation 2>/dev/null || echo 1)
  local zfs_mul=$((zfs_inflate * 2))

  local fio_avail=false
  if command_exists fio; then
    fio_avail=true
  else
    ensure_fio 2>/dev/null && fio_avail=true || true
  fi

  if [ "$fio_avail" = true ]; then
    local runtime=20
    [ "$CONFIG_QUICK" = true ] && runtime=10
    [ "$CONFIG_FULL" = true ] && runtime=40
    local fio_size="1G"
    [ "$CONFIG_QUICK" = true ] && fio_size="512M"
    [ "$CONFIG_FULL" = true ] && fio_size="2G"

    # ZFS-aware space check
    local need_kb=0
    case "$fio_size" in *G) need_kb=$((${fio_size%G} * 1048576 * zfs_mul)) ;; *M) need_kb=$((${fio_size%M} * 1024 * zfs_mul)) ;; esac
    local avail_kb=0
    command_exists df && avail_kb=$(df -k "$temp_dir" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ "$avail_kb" -gt 0 ] && [ "$avail_kb" -lt "$need_kb" ]; then
      fio_size="256M"
      log_warn "Disk space limited, using ${fio_size}"
    fi

    echo -e "  ${C_DIM}Generating fio test file (${fio_size})...${C_RESET}"
    fio --name=setup --ioengine=libaio --rw=read --bs=64k --iodepth=64 --numjobs=2 \
        --size="$fio_size" --runtime=1 --filename="$fio_file" --direct=1 --minimal &>/dev/null || true

    local block_sizes=("4k" "64k" "512k" "1m")
    local bs_labels=("4K" "64K" "512K" "1M")
    local disk_results=()

    echo -e "  ${C_DIM}fio mixed R+W 50/50 by block size:${C_RESET}"
    local bi=0
    for bs in "${block_sizes[@]}"; do
      echo -ne "  ${C_BOLD}  ${bs}...${C_RESET}" >&2
      local test_out
      test_out=$(timeout $((runtime + 10)) fio --name="${bs}" --ioengine=libaio --rw=randrw --rwmixread=50 \
          --bs="$bs" --iodepth=64 --numjobs=2 --size="$fio_size" --runtime="$runtime" \
          --gtod_reduce=1 --direct=1 --filename="$fio_file" --group_reporting --minimal 2>/dev/null) || true
      if [ -n "$test_out" ]; then
        local ir=$(echo "$test_out" | awk -F';' '{print $8}')
        local iw=$(echo "$test_out" | awk -F';' '{print $49}')
        local br=$(echo "$test_out" | awk -F';' '{print $7}')
        local bw=$(echo "$test_out" | awk -F';' '{print $48}')
        local it=$((ir + iw))
        local bt=$((br + bw))
        disk_results+=("$bt" "$br" "$bw" "$it" "$ir" "$iw")
        echo -e " ${C_GREEN}done${C_RESET}" >&2
      else
        disk_results+=(0 0 0 0 0 0)
        echo -e " ${C_YELLOW}fail${C_RESET}" >&2
      fi
      bi=$((bi + 1))
    done

    local i4=$((0 * 6)) im=$((3 * 6))
    RESULT_DISK_4K_READ=${disk_results[$((i4 + 1))]:-0}
    RESULT_DISK_4K_WRITE=${disk_results[$((i4 + 2))]:-0}
    RESULT_DISK_1M_READ=${disk_results[$((im + 1))]:-0}
    RESULT_DISK_1M_WRITE=${disk_results[$((im + 2))]:-0}
    RESULT_ADV_FIO_RND_R_IOPS=${disk_results[$((i4 + 4))]:-0}
    RESULT_ADV_FIO_RND_W_IOPS=${disk_results[$((i4 + 5))]:-0}

    echo ""
    printf "  %-10s | %-20s | %-20s\n" "Block Size" "Write (MB/s)" "Read (MB/s)"
    printf "  %-10s | %-20s | %-20s\n" "----------" "------------" "-----------"
    for i in 0 1 2 3; do
      local idx=$((i * 6))
      local bw_w=$(awk "BEGIN {printf \"%.1f\", ${disk_results[$((idx + 2))]:-0}/1000}" 2>/dev/null)
      local bw_r=$(awk "BEGIN {printf \"%.1f\", ${disk_results[$((idx + 1))]:-0}/1000}" 2>/dev/null)
      local iops_w="${disk_results[$((idx + 5))]:-0}"
      local iops_r="${disk_results[$((idx + 4))]:-0}"
      local iw_fmt=$(awk "BEGIN {printf \"%.1fk\", ${iops_w}/1000}" 2>/dev/null)
      local ir_fmt=$(awk "BEGIN {printf \"%.1fk\", ${iops_r}/1000}" 2>/dev/null)
      printf "  %-10s | %-8s (%s IOPS) | %-8s (%s IOPS)\n" "${bs_labels[$i]}" "${bw_w}" "${iw_fmt}" "${bw_r}" "${ir_fmt}"
    done

  else
    # dd fallback — 3 runs averaged
    echo -e "  ${C_DIM}dd sequential test (3 runs, averaged):${C_RESET}"
    local avail_kb=0
    command_exists df && avail_kb=$(df -k "$temp_dir" 2>/dev/null | tail -1 | awk '{print $4}')
    local dd_count=16384
    [ "$CONFIG_QUICK" = true ] && dd_count=8192
    [ "$CONFIG_FULL" = true ] && dd_count=32768
    local w_vals=() r_vals=() w_sum=0 r_sum=0

    for run in 1 2 3; do
      echo -ne "  ${C_BOLD}  Run ${run}...${C_RESET}" >&2
      local w_out=$(dd if=/dev/zero of="$fio_file" bs=64k count="$dd_count" oflag=direct 2>&1) || true
      local w_val=$(echo "$w_out" | grep -oP '[\d.]+(?=\s+(MB|GB)/s)' | head -1)
      [ -z "$w_val" ] && w_val=0
      w_vals+=("$w_val")
      w_sum=$(awk "BEGIN {print $w_sum + $w_val}" 2>/dev/null)

      is_root && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
      local r_out=$(dd if="$fio_file" of=/dev/null bs=8k 2>&1) || true
      local r_val=$(echo "$r_out" | grep -oP '[\d.]+(?=\s+(MB|GB)/s)' | head -1)
      [ -z "$r_val" ] && r_val=0
      r_vals+=("$r_val")
      r_sum=$(awk "BEGIN {print $r_sum + $r_val}" 2>/dev/null)
      echo -e " ${C_GREEN}done${C_RESET}" >&2
      rm -f "$fio_file" 2>/dev/null || true
    done

    local w_avg=$(awk "BEGIN {printf \"%.2f\", $w_sum / 3}" 2>/dev/null)
    local r_avg=$(awk "BEGIN {printf \"%.2f\", $r_sum / 3}" 2>/dev/null)
    RESULT_DISK_1M_WRITE=$w_avg
    RESULT_DISK_1M_READ=$r_avg

    echo ""
    printf "  %-10s | %-11s | %-11s | %-11s | %-11s\n" "" "Run 1" "Run 2" "Run 3" "Average"
    printf "  %-10s | %-11s | %-11s | %-11s | %-11s\n" "----------" "-----" "-----" "-----" "-------"
    printf "  %-10s | %-11s | %-11s | %-11s | %-11s\n" "Write" "${w_vals[0]} MB/s" "${w_vals[1]} MB/s" "${w_vals[2]} MB/s" "${w_avg} MB/s"
    printf "  %-10s | %-11s | %-11s | %-11s | %-11s\n" "Read" "${r_vals[0]} MB/s" "${r_vals[1]} MB/s" "${r_vals[2]} MB/s" "${r_avg} MB/s"
  fi

  # ioping disk latency
  if command_exists ioping; then
    echo ""
    echo -e "  ${C_BOLD}Disk latency (ioping)...${C_RESET}"
    local ioping_out=$(ioping -c 5 -D "$temp_dir" 2>&1) || true
    RESULT_ADV_IOPING_LAT=$(echo "$ioping_out" | grep -oP '[\d.]+(?=\s+ms.*\()' | head -1)
    [ -z "$RESULT_ADV_IOPING_LAT" ] && RESULT_ADV_IOPING_LAT=$(echo "$ioping_out" | grep 'avg' | grep -oP '[\d.]+(?=\s*ms)' | head -1)
    [ -z "$RESULT_ADV_IOPING_LAT" ] && RESULT_ADV_IOPING_LAT=0
    echo -e "  ${C_GREEN}✓${C_RESET} Avg latency: ${C_BOLD}${RESULT_ADV_IOPING_LAT}${C_RESET} ms"
  fi

  rm -f "$fio_file" 2>/dev/null || true
  section_end
}

# ============================================================
# INSTALL SPEEDTEST CLI (Ookla)
# ============================================================

_SPEEDTEST_CHECKED=false
_SPEEDTEST_AVAILABLE=false

ensure_speedtest() {
  if [ "$_SPEEDTEST_CHECKED" = true ]; then
    [ "$_SPEEDTEST_AVAILABLE" = true ] && return 0 || return 1
  fi
  _SPEEDTEST_CHECKED=true
  if command_exists speedtest; then
    _SPEEDTEST_AVAILABLE=true
    return 0
  fi
  log_info "Installing Ookla Speedtest CLI..."
  if command_exists apt-get; then
    apt-get install -y speedtest-cli &>/dev/null && { log_success "speedtest-cli installed"; _SPEEDTEST_AVAILABLE=true; return 0; }
  elif command_exists yum; then
    yum install -y speedtest-cli &>/dev/null && { log_success "speedtest-cli installed"; _SPEEDTEST_AVAILABLE=true; return 0; }
  elif command_exists apk; then
    apk add speedtest-cli &>/dev/null && { log_success "speedtest-cli installed"; _SPEEDTEST_AVAILABLE=true; return 0; }
  elif command_exists pacman; then
    pacman -S --noconfirm speedtest-cli &>/dev/null && { log_success "speedtest-cli installed"; _SPEEDTEST_AVAILABLE=true; return 0; }
  elif command_exists zypper; then
    zypper install -y speedtest-cli &>/dev/null && { log_success "speedtest-cli installed"; _SPEEDTEST_AVAILABLE=true; return 0; }
  fi
  # Try direct download as fallback
  local st_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-$(uname -m).tgz"
  local st_tar="/tmp/speedtest-cli.tgz"
  local st_dir="/tmp/speedtest-cli"
  if command_exists curl; then
    curl -sL --max-time 30 -o "$st_tar" "$st_url" 2>/dev/null && \
    mkdir -p "$st_dir" && \
    tar -xzf "$st_tar" -C "$st_dir" 2>/dev/null && \
    cp "$st_dir/speedtest" /usr/local/bin/ 2>/dev/null && \
    chmod +x /usr/local/bin/speedtest 2>/dev/null && \
    { log_success "speedtest CLI installed"; _SPEEDTEST_AVAILABLE=true; return 0; }
  fi
  log_warn "Ookla Speedtest CLI not available. Using curl fallback."
  return 1
}

# ============================================================
# STANDARD NETWORK BENCHMARK
# ============================================================

bench_network() {
  section_start "Network Benchmark"

  local has_speedtest=false
  ensure_speedtest 2>/dev/null && has_speedtest=true || true

  if [ "$has_speedtest" = true ]; then
    local st_timeout=30
    [ "$CONFIG_QUICK" = true ] && st_timeout=15
    [ "$CONFIG_FULL" = true ] && st_timeout=60

    # Ookla Speedtest: nearest server
    echo -e "  ${C_BOLD}Ookla Speedtest (nearest server)...${C_RESET}"
    local st_out
    st_out=$(speedtest --accept-license --accept-gdpr -f json 2>/dev/null) || true
    if [ -n "$st_out" ] && command_exists python3; then
      local st_dl st_ul st_lat
      st_dl=$(echo "$st_out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('download',{}).get('bandwidth',0)*8/1000000)" 2>/dev/null || echo 0)
      st_ul=$(echo "$st_out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('upload',{}).get('bandwidth',0)*8/1000000)" 2>/dev/null || echo 0)
      st_lat=$(echo "$st_out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ping',{}).get('latency',0))" 2>/dev/null || echo 0)
      local st_server=$(echo "$st_out" | python3 -c "import sys,json; d=json.load(sys.stdin); s=d.get('server',{}); print(f\"{s.get('name','?')} ({s.get('location','?')})\")" 2>/dev/null || echo "?")
      RESULT_NET_DOWNLOAD=$(awk "BEGIN {printf \"%.2f\", $st_dl}" 2>/dev/null || echo 0)
      RESULT_NET_UPLOAD=$(awk "BEGIN {printf \"%.2f\", $st_ul}" 2>/dev/null || echo 0)
      echo -e "  ${C_GREEN}✓${C_RESET} Download: ${C_BOLD}${RESULT_NET_DOWNLOAD}${C_RESET} Mbps"
      echo -e "  ${C_GREEN}✓${C_RESET} Upload:   ${C_BOLD}${RESULT_NET_UPLOAD}${C_RESET} Mbps"
      echo -e "  ${C_DIM}   Server: ${st_server}, ping: ${st_lat}ms${C_RESET}"
    fi

    # Multi-country speedtest
    echo -e "  ${C_BOLD}Multi-location speedtest...${C_RESET}"
    local countries=("Singapore" "United States" "Germany")
    local country_labels=("Singapore" "US" "Germany")
    for i in "${!countries[@]}"; do
      local ctry="${countries[$i]}"
      local label="${country_labels[$i]}"
      echo -ne "  ${C_DIM}  ${label}...${C_RESET} " >&2
      local st_ctry
      st_ctry=$(speedtest --accept-license --accept-gdpr -f json -s "$(speedtest --list 2>/dev/null | grep -im1 "$ctry" | awk '{print $1}' | head -1)" 2>/dev/null) || true
      if [ -n "$st_ctry" ]; then
        local st_dl_ctry=$(echo "$st_ctry" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('download',{}).get('bandwidth',0)*8/1000000)" 2>/dev/null || echo 0)
        echo -e "${C_GREEN}${st_dl_ctry}${C_RESET} Mbps" >&2
      else
        echo -e "${C_YELLOW}skip${C_RESET}" >&2
      fi
    done
  else
    # Fallback: curl multi-CDN download
    if ! command_exists curl; then
      echo -e "  ${C_YELLOW}curl not found. Skipping network benchmark.${C_RESET}"
      section_end
      return 1
    fi

    local urls=(
      "https://speed.cloudflare.com/__down?bytes=100000000"
      "https://cachefly.cachefly.net/100mb.test"
      "https://proof.ovh.net/files/100Mb.dat"
    )
    local timeout=15
    [ "$CONFIG_QUICK" = true ] && timeout=8
    [ "$CONFIG_FULL" = true ] && timeout=30
    local best_speed=0 best_server=""

    echo -e "  ${C_BOLD}Download speed test (curl fallback)...${C_RESET}"
    for url in "${urls[@]}"; do
      local server=$(echo "$url" | awk -F/ '{print $3}')
      echo -ne "  ${C_DIM}  ${server}...${C_RESET} " >&2
      local speed_bps
      speed_bps=$(curl -sL --max-time "$timeout" -o /dev/null -w "%{speed_download}" "$url" 2>/dev/null) || true
      if [ -n "$speed_bps" ] && [ "$(awk "BEGIN {print ($speed_bps > 0)}")" -eq 1 ]; then
        local speed_mbps=$(awk "BEGIN {printf \"%.2f\", $speed_bps * 8 / 1000000}" 2>/dev/null)
        echo -e "${C_GREEN}${speed_mbps}${C_RESET} Mbps" >&2
        if [ "$(awk "BEGIN {print ($speed_mbps > $best_speed)}")" -eq 1 ]; then
          best_speed=$speed_mbps
          best_server=$server
        fi
      else
        echo -e "${C_YELLOW}timeout/error${C_RESET}" >&2
      fi
    done
    RESULT_NET_DOWNLOAD=$best_speed
    echo -e "  ${C_GREEN}✓${C_RESET} Download: ${C_BOLD}${RESULT_NET_DOWNLOAD}${C_RESET} Mbps (best: ${best_server})"

    # Upload via iperf3 (curl fallback only)
    RESULT_NET_UPLOAD=0
    if command_exists iperf3; then
      echo -e "  ${C_BOLD}Upload test (iperf3)...${C_RESET}"
      local iperf_servers=("iperf.he.net" "iperf.online.net")
      for server in "${iperf_servers[@]}"; do
        local uplink
        uplink=$(iperf3 -c "$server" -t 5 -J 2>/dev/null) || true
        if [ -n "$uplink" ]; then
          local up_mbps
          up_mbps=$(echo "$uplink" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('end',{}).get('sum_sent',{}).get('bits_per_second',0)/1000000)" 2>/dev/null || echo "")
          if [ -n "$up_mbps" ] && [ "$(awk "BEGIN {print ($up_mbps > 0)}")" -eq 1 ]; then
            RESULT_NET_UPLOAD=$up_mbps
            echo -e "  ${C_GREEN}✓${C_RESET} Upload:   ${C_BOLD}${RESULT_NET_UPLOAD}${C_RESET} Mbps (${server})"
            break
          fi
        fi
      done
      if [ "$(awk "BEGIN {print ($RESULT_NET_UPLOAD == 0)}")" -eq 1 ]; then
        echo -e "  ${C_YELLOW}  iperf3 servers unreachable${C_RESET}"
      fi
    fi
  fi

  # iperf3 multi-server test
  if command_exists iperf3; then
    echo -e "  ${C_BOLD}iperf3 multi-server test...${C_RESET}"
    local iperf_servers=(
      "speedtest.lax1.leaseweb.net|LeaseWeb LA|5201-5210"
      "speedtest.sjc1.leaseweb.net|LeaseWeb SJC|5201-5210"
      "iperf.he.net|Hurricane Electric|5201-5205"
      "speedtest.frankfurt1.leaseweb.net|LeaseWeb FRA|5201-5210"
      "iperf.online.net|Online.net|5201-5216"
    )
    printf "  %-28s | %-15s | %-10s | %-10s | %-7s\n" "Provider" "Location" "Send (Mbps)" "Recv (Mbps)" "Ping"
    printf "  %-28s | %-15s | %-10s | %-10s | %-7s\n" "--------" "--------" "-----------" "-----------" "----"
    for entry in "${iperf_servers[@]}"; do
      local url=$(echo "$entry" | cut -d'|' -f1)
      local loc=$(echo "$entry" | cut -d'|' -f2)
      local ports=$(echo "$entry" | cut -d'|' -f3)
      local send_result recv_result send_val recv_val
      send_result=$(_iperf_test "$url" "$ports" "" "" "send")
      recv_result=$(_iperf_test "$url" "$ports" "" "" "recv")
      send_val=$(echo "$send_result" | awk '{print $1}')
      recv_val=$(echo "$recv_result" | awk '{print $1}')
      local ping_val="?"
      [ "$send_result" != "busy" ] && [ -n "$send_val" ] && ping_val="N/A" || true
      if [ "$send_result" = "busy" ] && [ "$recv_result" = "busy" ]; then
        printf "  %-28s | %-15s | %-10s | %-10s | %-7s\n" "$loc" "$url" "busy" "busy" "-"
      else
        printf "  %-28s | %-15s | %-10s | %-10s | %-7s\n" "$loc" "$url" "${send_val:-?}" "${recv_val:-?}" "${ping_val}"
      fi
    done
  fi

  # Latency test (always)
  echo -e "  ${C_BOLD}Latency test...${C_RESET}"
  local targets=("1.1.1.1" "8.8.8.8" "cloudflare.com")
  local total_lat=0 lat_count=0
  for target in "${targets[@]}"; do
    local lat
    lat=$(ping -c 2 -W 2 "$target" 2>/dev/null | awk -F/ '/^rtt/ {print $5}') || true
    if [ -n "$lat" ]; then
      total_lat=$(awk "BEGIN {print $total_lat + $lat}" 2>/dev/null)
      lat_count=$((lat_count + 1))
      printf "  ${C_DIM}  %-18s ${C_RESET} %s ms\n" "${target}:" "${lat}"
    else
      printf "  ${C_DIM}  %-18s ${C_RESET} %s\n" "${target}:" "${C_YELLOW}timeout${C_RESET}"
    fi
  done
  if [ "$lat_count" -gt 0 ]; then
    RESULT_NET_LATENCY=$(awk "BEGIN {printf \"%.2f\", $total_lat / $lat_count}" 2>/dev/null)
    echo -e "  ${C_GREEN}✓${C_RESET} Avg latency: ${C_BOLD}${RESULT_NET_LATENCY}${C_RESET} ms"
  fi

  section_end
}

# ============================================================
# IPERF3 MULTI-SERVER TEST
# ============================================================

_iperf_test() {
  local url=$1 ports=$2 host=$3 flags=$4 dir=$5
  local result=""
  local attempt=1
  while [ $attempt -le 2 ]; do
    local port
    port=$(shuf -i "$(echo "$ports" | tr '-' ' ')" -n 1)
    if [ "$dir" = "send" ]; then
      result=$(timeout 15 iperf3 "$flags" -c "$url" -p "$port" -P 4 2>/dev/null)
    else
      result=$(timeout 15 iperf3 "$flags" -c "$url" -p "$port" -P 4 -R 2>/dev/null)
    fi
    if echo "$result" | grep -q "receiver" && ! echo "$result" | grep -q "error"; then
      local speed=$(echo "$result" | grep SUM | grep receiver | awk '{print $6}')
      local unit=$(echo "$result" | grep SUM | grep receiver | awk '{print $7}')
      [ -n "$speed" ] && [ "$speed" != "0.00" ] && echo "$speed $unit" && return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  echo "busy"
}

# ============================================================
# SCORING
# ============================================================

calculate_score() {
  local cpu_score=0 mem_score=0 disk_score=0 net_score=0 geekbench_score=0

  if [ "$(awk "BEGIN {print ($RESULT_CPU_SINGLE > 0)}")" -eq 1 ]; then
    cpu_score=$(awk "BEGIN {printf \"%.0f\", ($RESULT_CPU_SINGLE / 100) * 25}" 2>/dev/null)
    [ "$cpu_score" -gt 25 ] && cpu_score=25
  fi

  if [ "$(awk "BEGIN {print ($RESULT_MEM_READ > 0)}")" -eq 1 ]; then
    mem_score=$(awk "BEGIN {printf \"%.0f\", ($RESULT_MEM_READ / 2000) * 25}" 2>/dev/null)
    [ "$mem_score" -gt 25 ] && mem_score=25
  fi

  if [ "$(awk "BEGIN {print ($RESULT_DISK_1M_READ > 0)}")" -eq 1 ]; then
    local avg_disk
    avg_disk=$(awk "BEGIN {printf \"%.0f\", ($RESULT_DISK_1M_WRITE + $RESULT_DISK_1M_READ) / 2}" 2>/dev/null)
    disk_score=$(awk "BEGIN {printf \"%.0f\", ($avg_disk / 500) * 25}" 2>/dev/null)
    [ "$disk_score" -gt 25 ] && disk_score=25
  fi

  if [ "$(awk "BEGIN {print ($RESULT_NET_DOWNLOAD > 0)}")" -eq 1 ]; then
    net_score=$(awk "BEGIN {printf \"%.0f\", ($RESULT_NET_DOWNLOAD / 500) * 25}" 2>/dev/null)
    [ "$net_score" -gt 25 ] && net_score=25
  fi

  if [ "$(awk "BEGIN {print ($RESULT_GB_SINGLE > 0)}")" -eq 1 ]; then
    geekbench_score=$(awk "BEGIN {printf \"%.0f\", ($RESULT_GB_SINGLE / 500) * 25}" 2>/dev/null)
    [ "$geekbench_score" -gt 25 ] && geekbench_score=25
  fi

  local total=$((cpu_score + mem_score + disk_score + net_score + geekbench_score))

  local grade="F"
  if   [ "$total" -ge 97 ]; then grade="A+"
  elif [ "$total" -ge 90 ]; then grade="A"
  elif [ "$total" -ge 80 ]; then grade="A-"
  elif [ "$total" -ge 70 ]; then grade="B+"
  elif [ "$total" -ge 60 ]; then grade="B"
  elif [ "$total" -ge 50 ]; then grade="B-"
  elif [ "$total" -ge 40 ]; then grade="C+"
  elif [ "$total" -ge 30 ]; then grade="C"
  elif [ "$total" -ge 20 ]; then grade="D"
  fi

  echo "${total}|${grade}|${cpu_score}|${mem_score}|${disk_score}|${net_score}|${geekbench_score}"
}

print_results() {
  local data
  data=$(calculate_score)
  IFS='|' read -r total grade cpu_score mem_score disk_score net_score gb_score <<< "$data"

  section_start "Results"

  local grade_color="$C_GREEN"
  case "$grade" in
    A+|A|A-) grade_color="$C_GREEN"  ;;
    B+|B|B-) grade_color="$C_CYAN"   ;;
    C+|C)    grade_color="$C_YELLOW" ;;
    D|F)     grade_color="$C_RED"    ;;
  esac

  printf "  %-18s %s\n" " CPU Score"     ": ${cpu_score}/25"
  printf "  %-18s %s\n" " Memory Score"  ": ${mem_score}/25"
  printf "  %-18s %s\n" " Disk Score"    ": ${disk_score}/25"
  printf "  %-18s %s\n" " Network Score" ": ${net_score}/25"
  if [ "$(awk "BEGIN {print ($gb_score > 0)}")" -eq 1 ]; then
    printf "  %-18s %s\n" " Geekbench Score" ": ${gb_score}/25"
  fi
  echo ""
  printf "  ${C_BOLD}%-18s${C_RESET} %s\n" " Total Score"  ": ${total}/100"
  printf "  ${C_BOLD}%-18s${C_RESET} ${grade_color}${C_BOLD}%s${C_RESET}\n" " Grade"        ": ${grade}"
  echo ""

  local now duration
  now=$(date +%s)
  duration=$((now - START_TIME))
  echo -e "  ${C_DIM}Benchmark completed in $(format_duration $duration)${C_RESET}"

  section_end
  echo ""
}

# ============================================================
# JSON OUTPUT
# ============================================================

generate_json() {
  local data
  data=$(calculate_score)
  IFS='|' read -r total grade cpu_score mem_score disk_score net_score gb_score <<< "$data"

  local now duration
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
  duration=$(( $(date +%s) - START_TIME ))

  cat <<JSONEOF
{
  "tool": "HABS",
  "version": "${VERSION}",
  "timestamp": "${now}",
  "duration_seconds": ${duration},
  "system": {
    "hostname": "${SYS_HOSTNAME}",
    "os": "${SYS_OS}",
    "kernel": "${SYS_KERNEL}",
    "architecture": "${SYS_ARCH}",
    "uptime": "${SYS_UPTIME}",
    "cpu": {
      "model": "${SYS_CPU_MODEL}",
      "cores": ${SYS_CPU_CORES},
      "threads": ${SYS_CPU_THREADS},
      "frequency": "${SYS_CPU_FREQ}",
      "cache": "${SYS_CPU_CACHE}"
    },
    "memory": {
      "total_bytes": ${SYS_RAM_TOTAL},
      "used_bytes": ${SYS_RAM_USED},
      "available_bytes": ${SYS_RAM_AVAIL},
      "swap_bytes": ${SYS_SWAP_TOTAL}
    },
    "disk": {
      "total": "${SYS_DISK_TOTAL}",
      "used": "${SYS_DISK_USED}",
      "available": "${SYS_DISK_AVAIL}",
      "filesystem": "${SYS_DISK_FSTYPE}",
      "mount": "${SYS_DISK_MOUNT}"
    },
    "virtualization": "${SYS_VIRT}",
    "load_average": "${SYS_LOAD}"
  },
  "benchmarks": {
    "cpu": {
      "single_events_per_sec": ${RESULT_CPU_SINGLE},
      "multi_events_per_sec": ${RESULT_CPU_MULTI}
    },
    "memory": {
      "read_mib_per_sec": ${RESULT_MEM_READ},
      "write_mib_per_sec": ${RESULT_MEM_WRITE}
    },
    "disk": {
      "4k_write_mb_per_sec": ${RESULT_DISK_4K_WRITE},
      "4k_read_mb_per_sec": ${RESULT_DISK_4K_READ},
      "1m_write_mb_per_sec": ${RESULT_DISK_1M_WRITE},
      "1m_read_mb_per_sec": ${RESULT_DISK_1M_READ}
    },
    "network": {
      "download_mbps": ${RESULT_NET_DOWNLOAD},
      "upload_mbps": ${RESULT_NET_UPLOAD},
      "avg_latency_ms": ${RESULT_NET_LATENCY}
    },
    "geekbench_6": {
      "single_core_score": ${RESULT_GB_SINGLE},
      "multi_core_score": ${RESULT_GB_MULTI}
    },
    "advanced": {
      "cpu": {
        "matrix_bogo_ops": ${RESULT_ADV_CPU_MATRIX},
        "fpu_bogo_ops": ${RESULT_ADV_CPU_FPU},
        "crypto_bogo_ops": ${RESULT_ADV_CPU_CRYPT},
        "cache_bogo_ops": ${RESULT_ADV_CPU_CACHE}
      },
      "memory": {
        "256b_read_mib_per_sec": ${RESULT_ADV_MEM_256B},
        "4k_read_mib_per_sec": ${RESULT_ADV_MEM_4K},
        "64k_read_mib_per_sec": ${RESULT_ADV_MEM_64K},
        "1m_read_mib_per_sec": ${RESULT_ADV_MEM_1M}
      },
      "disk": {
        "fio_random_4k_read_iops": ${RESULT_ADV_FIO_RND_R_IOPS},
        "fio_random_4k_write_iops": ${RESULT_ADV_FIO_RND_W_IOPS},
        "fio_random_4k_read_lat_us": ${RESULT_ADV_FIO_RND_R_LAT},
        "fio_random_4k_write_lat_us": ${RESULT_ADV_FIO_RND_W_LAT},
        "ioping_latency_ms": ${RESULT_ADV_IOPING_LAT}
      },
      "network": {
        "ipv6_download_mbps": ${RESULT_ADV_NET_IPV6},
        "packet_loss_pct": ${RESULT_ADV_NET_PLOSS},
        "traceroute_hops": ${RESULT_ADV_NET_HOPS}
      }
    }
  },
  "scores": {
    "cpu": ${cpu_score},
    "memory": ${mem_score},
    "disk": ${disk_score},
    "network": ${net_score},
    "geekbench": ${gb_score},
    "total": ${total},
    "max": 100,
    "grade": "${grade}"
  }
}
JSONEOF
}

# ============================================================
# HELP
# ============================================================

print_help() {
  cat <<HELPEOF
HABS v${VERSION} - Hyper Absolute Benchmark Script
Modern Linux benchmark tool with Geekbench 6 & advanced benchmarks

Usage:  bash habs.sh [options]

Options:
  -h, --help            Show this help message
  --version             Show version
  --skip-cpu            Skip CPU benchmark
  --skip-memory         Skip memory benchmark
  --skip-disk           Skip disk benchmark
  --skip-network        Skip network benchmark
  -q, --quick           Quick mode (shorter tests, less data)
  -f, --full            Full mode (more comprehensive tests)
  --json                Output results as JSON to stdout
  --output FILE         Save text/JSON output to file
  --no-color            Disable colored terminal output
  -v, --verbose         Verbose/debug output

Examples:
  bash habs.sh                              Run all benchmarks (default)
  bash habs.sh --quick                      Quick benchmark run
  bash habs.sh --skip-network               Skip network tests
  bash habs.sh --skip-disk --skip-network   CPU/memory/Geekbench only
  bash habs.sh --json --output result.json  JSON export

Benchmarks (all enabled by default, use --skip-* to exclude):
  CPU (standard):   sysbench (single + multi-threaded)
  Memory (standard): sysbench (1M sequential read/write)
  Disk (standard):  dd (4K + 1M direct I/O)
  Network (standard): curl (multi-CDN) + ping + iperf3
  Geekbench 6:     single-core & multi-core (real-world workloads)
  CPU (advanced):  stress-ng (matrix, FPU, crypto, cache)
  Memory (advanced): sysbench (multi-block read + cache hierarchy)
  Disk (advanced): fio (random 4K QD=32) + ioping (latency)
  Network (advanced): IPv6 download + packet loss + traceroute

Requirements:
  sysbench    CPU & memory benchmarks
  curl        Network speed tests
  dd          Disk I/O benchmarks
  ping        Network latency tests
  stress-ng   Advanced CPU benchmarks (auto-installed)
  fio         Advanced disk benchmarks (auto-installed)
  ioping      Disk latency test (manual install if needed)
  iperf3      Upload test (optional)
  python3     JSON parsing for fio & iperf3 (optional)

HELPEOF
}

# ============================================================
# MAIN
# ============================================================

main() {
  START_TIME=$(date +%s)

  # Write permission check
  if ! touch .habs_write_test 2>/dev/null; then
    echo "No write permission in current directory. Switch to an owned directory." >&2
    exit 1
  fi
  rm -f .habs_write_test

  # Pre-parse --no-color and --json for output control
  for arg in "$@"; do
    [ "$arg" = "--no-color" ] && CONFIG_NO_COLOR=true
  done
  setup_colors

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)       print_help; exit 0 ;;
      --version)       echo "HABS v${VERSION}"; exit 0 ;;
      --skip-cpu)      CONFIG_SKIP_CPU=true ;;
      --skip-memory)   CONFIG_SKIP_MEMORY=true ;;
      --skip-disk)     CONFIG_SKIP_DISK=true ;;
      --skip-network)  CONFIG_SKIP_NETWORK=true ;;
      # -a|--advanced and --geekbench are enabled by default
      -q|--quick)      CONFIG_QUICK=true ;;
      -f|--full)       CONFIG_FULL=true ;;
      --json)          CONFIG_JSON=true ;;
      --output)        shift; CONFIG_OUTPUT="${1:-}"; [ -n "$CONFIG_OUTPUT" ] || die "--output requires a file path" ;;
      --no-color)      CONFIG_NO_COLOR=true ;;
      -v|--verbose)    CONFIG_VERBOSE=true ;;
      *) echo -e "${C_RED}Unknown: $1${C_RESET}"; print_help; exit 1 ;;
    esac
    shift
  done

  setup_signals

  if [ -n "$CONFIG_OUTPUT" ] && [ "$CONFIG_JSON" = false ]; then
    if command_exists stdbuf; then
      exec > >(stdbuf -oL tee -a "$CONFIG_OUTPUT") 2>&1 || true
    else
      exec > >(tee -a "$CONFIG_OUTPUT") 2>&1 || true
    fi
  elif [ "$CONFIG_JSON" = false ] && [ -t 1 ] && command_exists stdbuf; then
    exec > >(stdbuf -oL cat) || true
  fi

  if [ "$CONFIG_JSON" = false ]; then
    print_header
    echo -e "  ${C_DIM}$(date)${C_RESET}"
    echo ""
  fi

  gather_system_info

  if [ "$CONFIG_JSON" = false ]; then
    print_system_info
  fi

  # In JSON mode, redirect all benchmark output to stderr so JSON stays clean
  if [ "$CONFIG_JSON" = true ]; then
    exec 3>&1
    exec 1>&2
  fi

  # Standard benchmarks
  [ "$CONFIG_SKIP_CPU" = false ]     && bench_cpu     || log_debug "Skipping CPU benchmark"
  [ "$CONFIG_SKIP_MEMORY" = false ]  && bench_memory  || log_debug "Skipping memory benchmark"
  [ "$CONFIG_SKIP_DISK" = false ]    && bench_disk    || log_debug "Skipping disk benchmark"
  [ "$CONFIG_SKIP_NETWORK" = false ] && bench_network || log_debug "Skipping network benchmark"

  # Geekbench 6 (skipped if --skip-cpu)
  if [ "$CONFIG_GEEKBENCH" = true ] && [ "$CONFIG_SKIP_CPU" = false ]; then
    bench_geekbench || log_warn "Geekbench 6 failed or was skipped"
    cleanup_geekbench
  elif [ "$CONFIG_GEEKBENCH" = true ] && [ "$CONFIG_SKIP_CPU" = true ]; then
    log_debug "Skipping Geekbench 6 (--skip-cpu)"
  fi

  # Advanced benchmarks (respect --skip-* flags)
  if [ "$CONFIG_ADVANCED" = true ] && [ "$CONFIG_SKIP_CPU" = false ]; then
    bench_advanced_cpu      || log_debug "Advanced CPU skipped/failed"
  elif [ "$CONFIG_ADVANCED" = true ] && [ "$CONFIG_SKIP_CPU" = true ]; then
    log_debug "Skipping advanced CPU (--skip-cpu)"
  fi
  if [ "$CONFIG_ADVANCED" = true ] && [ "$CONFIG_SKIP_MEMORY" = false ]; then
    bench_advanced_memory   || log_debug "Advanced memory skipped/failed"
  elif [ "$CONFIG_ADVANCED" = true ] && [ "$CONFIG_SKIP_MEMORY" = true ]; then
    log_debug "Skipping advanced memory (--skip-memory)"
  fi
  if [ "$CONFIG_ADVANCED" = true ] && [ "$CONFIG_SKIP_DISK" = false ]; then
    bench_advanced_disk     || log_debug "Advanced disk skipped/failed"
  elif [ "$CONFIG_ADVANCED" = true ] && [ "$CONFIG_SKIP_DISK" = true ]; then
    log_debug "Skipping advanced disk (--skip-disk)"
  fi
  if [ "$CONFIG_ADVANCED" = true ] && [ "$CONFIG_SKIP_NETWORK" = false ]; then
    bench_advanced_network  || log_debug "Advanced network skipped/failed"
  elif [ "$CONFIG_ADVANCED" = true ] && [ "$CONFIG_SKIP_NETWORK" = true ]; then
    log_debug "Skipping advanced network (--skip-network)"
  fi

  # Restore stdout for JSON output
  if [ "$CONFIG_JSON" = true ]; then
    exec 1>&3
    exec 3>&-
  fi

  # Output
  if [ "$CONFIG_JSON" = true ]; then
    local json
    json=$(generate_json)
    if [ -n "$CONFIG_OUTPUT" ]; then
      echo "$json" > "$CONFIG_OUTPUT"
      log_success "JSON results saved to ${CONFIG_OUTPUT}"
    else
      echo "$json"
    fi
  else
    print_results
    local end_time=$(( $(date +%s) - START_TIME ))
    echo -e "  ${C_DIM}Total time: $(format_duration $end_time)${C_RESET}"
    echo ""
  fi

  cleanup
  cleanup_geekbench
}

main "$@"
