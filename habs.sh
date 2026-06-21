#!/usr/bin/env bash
#
# HABS - Hyper Absolute Benchmark Script
# Modern Linux benchmark tool inspired by YABS
# Supports VPS, dedicated servers, and cloud infrastructure
#
# Usage:
#   bash <(curl -sSL https://raw.githubusercontent.com/.../habs.sh)
#   bash habs.sh [options]
#
# Options:
#   -h, --help         Show help message
#   --version          Show version
#   --skip-cpu         Skip CPU benchmark
#   --skip-memory      Skip memory benchmark
#   --skip-disk        Skip disk benchmark
#   --skip-network     Skip network benchmark
#   -q, --quick        Quick mode (shorter/darker tests)
#   -f, --full         Full mode (comprehensive tests)
#   --json             Output results as JSON
#   --output FILE      Save results to file
#   --no-color         Disable colored output
#   -v, --verbose      Verbose output

set -euo pipefail

# ============================================================
# GLOBALS
# ============================================================
readonly VERSION="1.0.0"
START_TIME=0
TEMP_FILES=()

# CLI configuration
CONFIG_SKIP_CPU=false
CONFIG_SKIP_MEMORY=false
CONFIG_SKIP_DISK=false
CONFIG_SKIP_NETWORK=false
CONFIG_QUICK=false
CONFIG_FULL=false
CONFIG_JSON=false
CONFIG_OUTPUT=""
CONFIG_NO_COLOR=false
CONFIG_VERBOSE=false

# Results
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

# ============================================================
# COLOR DEFINITIONS
# ============================================================
setup_colors() {
  if [ -t 1 ] && [ "$CONFIG_NO_COLOR" = false ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_MAGENTA='\033[0;35m'
    C_CYAN='\033[0;36m'
    C_WHITE='\033[0;37m'
  else
    C_RESET=''; C_BOLD=''; C_DIM=''
    C_RED=''; C_GREEN=''; C_YELLOW=''
    C_BLUE=''; C_MAGENTA=''; C_CYAN=''; C_WHITE=''
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
  local s=$1 d=0 h=0 m=0
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

setup_signals() {
  trap cleanup EXIT
  trap 'echo -e "\n${C_YELLOW}Interrupted. Cleaning up...${C_RESET}"; cleanup; exit 1' INT TERM
}

command_exists() {
  command -v "$1" &>/dev/null
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

# ============================================================
# SECTION HEADERS
# ============================================================

print_header() {
  echo ""
  echo -e "  ${C_CYAN}__  __    _    ____  ______${C_RESET}"
  echo -e "  ${C_CYAN}|  \/  |  / \  | __ )|__  / |${C_RESET}  ${C_BOLD}Hyper Absolute Benchmark Script${C_RESET}"
  echo -e "  ${C_CYAN}| |\/| | / _ \ |  _ \  / /| |${C_RESET}  ${C_DIM}Version ${VERSION}${C_RESET}"
  echo -e "  ${C_CYAN}| |  | |/ ___ \| |_) |/ /_|_|${C_RESET}  ${C_DIM}Modern Linux Benchmark Tool${C_RESET}"
  echo -e "  ${C_CYAN}|_|  |_/_/   \_\____/____(_)${C_RESET}"
  echo ""
  local cols=58
  printf "  ${C_DIM}%s${C_RESET}\n" "$(printf '%*s' "$cols" | tr ' ' '─')"
  echo ""
}

section_start() {
  echo ""
  echo -e "  ${C_BOLD}${C_CYAN}┌─ $1 ─${C_RESET}$(printf '%*s' $((50 - ${#1})) '' | tr ' ' '─')${C_BOLD}${C_CYAN}┐${C_RESET}"
}

section_end() {
  echo -e "  ${C_BOLD}${C_CYAN}└$(printf '%*s' 56 '' | tr ' ' '─')┘${C_RESET}"
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
      local cores
      cores=$(lscpu 2>/dev/null | awk -F: '/^CPU\(s\):/ {gsub(/ /,"",$2); print $2}')
      [ -n "$cores" ] && SYS_CPU_CORES=$cores

      local freq
      freq=$(lscpu 2>/dev/null | awk -F: '/MHz/ {gsub(/ /,"",$2); print $2; exit}')
      if [ -n "$freq" ]; then
        SYS_CPU_FREQ=$(awk "BEGIN {printf \"%.2f GHz\", $freq/1000}" 2>/dev/null)
      else
        local max_freq
        max_freq=$(lscpu 2>/dev/null | awk -F: '/max MHz/ {gsub(/ /,"",$2); print $2}')
        [ -n "$max_freq" ] && SYS_CPU_FREQ=$(awk "BEGIN {printf \"%.2f GHz\", $max_freq/1000}" 2>/dev/null)
      fi

      SYS_CPU_CACHE=$(lscpu 2>/dev/null | awk -F: '/L[1-3]/ {gsub(/^ */,"",$1); gsub(/^ /,"",$2); printf "%s: %s, ", $1, $2}' | sed 's/, $//')
    fi

    [ -z "$SYS_CPU_FREQ" ] && SYS_CPU_FREQ=$(awk '/cpu MHz/ {printf "%.2f GHz", $NF/1000; exit}' /proc/cpuinfo 2>/dev/null || echo "N/A")
    [ -z "$SYS_CPU_FREQ" ] && SYS_CPU_FREQ="N/A"
  fi

  if [ -f /proc/meminfo ]; then
    local mem_total mem_avail swap_total swap_free
    mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)

    SYS_RAM_TOTAL=$((mem_total * 1024))
    SYS_RAM_AVAIL=$((mem_avail * 1024))
    SYS_RAM_USED=$((SYS_RAM_TOTAL - SYS_RAM_AVAIL))
    SYS_SWAP_TOTAL=$((swap_total * 1024))
  fi

  local disk_info
  disk_info=$(df -h / 2>/dev/null | tail -1)
  if [ -n "$disk_info" ]; then
    SYS_DISK_TOTAL=$(echo "$disk_info" | awk '{print $2}')
    SYS_DISK_USED=$(echo "$disk_info" | awk '{print $3}')
    SYS_DISK_AVAIL=$(echo "$disk_info" | awk '{print $4}')
    SYS_DISK_PCT=$(echo "$disk_info" | awk '{print $5}')
    SYS_DISK_MOUNT=$(echo "$disk_info" | awk '{print $6}')
    SYS_DISK_FSTYPE=$(df -T / 2>/dev/null | tail -1 | awk '{print $2}')
  fi

  if command_exists systemd-detect-virt; then
    SYS_VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")
  elif command_exists hostnamectl; then
    SYS_VIRT=$(hostnamectl 2>/dev/null | awk -F: '/Virtualization/ {gsub(/^ /,"",$2); print $2}') || echo "none"
  else
    SYS_VIRT="none/detect"
  fi

  if [ -f /proc/loadavg ]; then
    SYS_LOAD=$(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg)
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
  [ -n "$SYS_CPU_CACHE" ] && info_row "CPU Cache"     "${SYS_CPU_CACHE}"
  info_row "RAM"            "$(format_bytes $SYS_RAM_TOTAL) total / $(format_bytes $SYS_RAM_USED) used"
  info_row "Swap"           "$(format_bytes $SYS_SWAP_TOTAL) total"
  info_row "Disk"           "${SYS_DISK_TOTAL} total / ${SYS_DISK_USED} used (${SYS_DISK_PCT})"
  info_row "Filesystem"     "${SYS_DISK_FSTYPE} on ${SYS_DISK_MOUNT}"
  info_row "Virt"           "${SYS_VIRT}"
  info_row "Load Avg"       "${SYS_LOAD}"
  section_end
}

# ============================================================
# CPU BENCHMARK
# ============================================================

bench_cpu() {
  section_start "CPU Benchmark"
  ensure_sysbench || { section_end; return 1; }

  local max_prime=20000
  [ "$CONFIG_QUICK" = true ] && max_prime=10000
  [ "$CONFIG_FULL" = true ] && max_prime=50000

  echo -e "  ${C_BOLD}Single-threaded test (max prime=${max_prime})...${C_RESET}"
  local single_out
  single_out=$(sysbench cpu --cpu-max-prime="$max_prime" --threads=1 run 2>/dev/null)
  RESULT_CPU_SINGLE=$(echo "$single_out" | sed -n 's/.*events per second:\s*\([0-9.]*\).*/\1/p')
  [ -z "$RESULT_CPU_SINGLE" ] && RESULT_CPU_SINGLE=0
  echo -e "  ${C_GREEN}✓${C_RESET} Single:  ${C_BOLD}${RESULT_CPU_SINGLE}${C_RESET} events/s"

  echo -e "  ${C_BOLD}Multi-threaded test (${SYS_CPU_THREADS} threads, max prime=${max_prime})...${C_RESET}"
  local multi_out
  multi_out=$(sysbench cpu --cpu-max-prime="$max_prime" --threads="$SYS_CPU_THREADS" run 2>/dev/null)
  RESULT_CPU_MULTI=$(echo "$multi_out" | sed -n 's/.*events per second:\s*\([0-9.]*\).*/\1/p')
  [ -z "$RESULT_CPU_MULTI" ] && RESULT_CPU_MULTI=0

  echo -e "  ${C_GREEN}✓${C_RESET} Multi:   ${C_BOLD}${RESULT_CPU_MULTI}${C_RESET} events/s"

  if [ "$(awk "BEGIN {print ($RESULT_CPU_SINGLE > 0)}")" -eq 1 ]; then
    local ratio
    ratio=$(awk "BEGIN {printf \"%.2f\", $RESULT_CPU_MULTI / $RESULT_CPU_SINGLE}" 2>/dev/null)
    echo -e "  ${C_DIM}  Scaling: ${ratio}x (ideal: ${SYS_CPU_THREADS}x)${C_RESET}"
  fi

  section_end
}

# ============================================================
# MEMORY BENCHMARK
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
# DISK BENCHMARK
# ============================================================

bench_disk() {
  section_start "Disk Benchmark"
  local temp_dir="${TMPDIR:-/tmp}"

  if [ ! -w "$temp_dir" ]; then
    temp_dir="."
  fi

  local count_1m=1024
  local count_4k=256000
  [ "$CONFIG_QUICK" = true ] && count_1m=512 && count_4k=128000
  [ "$CONFIG_FULL" = true ] && count_1m=2048 && count_4k=512000

  # Check available disk space
  local avail_kb=0
  if command_exists df; then
    avail_kb=$(df -k "$temp_dir" 2>/dev/null | tail -1 | awk '{print $4}')
  fi
  local needed_kb=$((count_1m * 1024 + count_4k * 4))
  if [ "$avail_kb" -gt 0 ] && [ "$avail_kb" -lt "$needed_kb" ]; then
    local scale_down=$((avail_kb / needed_kb))
    [ "$scale_down" -lt 1 ] && scale_down=1
    count_1m=$((count_1m * scale_down / 2))
    count_4k=$((count_4k * scale_down / 2))
    [ "$count_1m" -lt 16 ] && count_1m=16
    [ "$count_4k" -lt 4096 ] && count_4k=4096
    log_warn "Disk space limited, reducing test size"
  fi

  local tmpfile
  tmpfile=$(mktemp -p "$temp_dir" habs_disk.XXXXXX 2>/dev/null || mktemp habs_disk.XXXXXX)
  TEMP_FILES+=("$tmpfile")

  echo -e "  ${C_BOLD}1M sequential write test (${count_1m} blocks)...${C_RESET}"
  local out_1m_w
  out_1m_w=$(dd if=/dev/zero of="$tmpfile" bs=1M count="$count_1m" oflag=direct 2>&1) || true
  RESULT_DISK_1M_WRITE=$(echo "$out_1m_w" | sed -n 's/.*, \([0-9.]*\) [MG]B\/s.*/\1/p')
  if [ -z "$RESULT_DISK_1M_WRITE" ]; then
    local bytes tm
    bytes=$(echo "$out_1m_w" | grep -o '^[0-9]* bytes' | grep -o '[0-9]*' | head -1)
    tm=$(echo "$out_1m_w" | grep -o '[0-9.]* seconds' | grep -o '[0-9.]*' | head -1)
    [ -n "$bytes" ] && [ -n "$tm" ] && [ "$(awk "BEGIN {print ($tm > 0)}")" -eq 1 ] && \
      RESULT_DISK_1M_WRITE=$(awk "BEGIN {printf \"%.2f\", $bytes / $tm / 1000000}" 2>/dev/null)
  fi
  [ -z "$RESULT_DISK_1M_WRITE" ] && RESULT_DISK_1M_WRITE=0
  echo -e "  ${C_GREEN}✓${C_RESET} 1M Write: ${C_BOLD}${RESULT_DISK_1M_WRITE}${C_RESET} MB/s"

  echo -e "  ${C_BOLD}1M sequential read test...${C_RESET}"
  is_root && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  local out_1m_r
  out_1m_r=$(dd if="$tmpfile" of=/dev/null bs=1M iflag=direct 2>&1) || true
  RESULT_DISK_1M_READ=$(echo "$out_1m_r" | sed -n 's/.*, \([0-9.]*\) [MG]B\/s.*/\1/p')
  if [ -z "$RESULT_DISK_1M_READ" ]; then
    local bytes tm
    bytes=$(echo "$out_1m_r" | grep -o '^[0-9]* bytes' | grep -o '[0-9]*' | head -1)
    tm=$(echo "$out_1m_r" | grep -o '[0-9.]* seconds' | grep -o '[0-9.]*' | head -1)
    [ -n "$bytes" ] && [ -n "$tm" ] && [ "$(awk "BEGIN {print ($tm > 0)}")" -eq 1 ] && \
      RESULT_DISK_1M_READ=$(awk "BEGIN {printf \"%.2f\", $bytes / $tm / 1000000}" 2>/dev/null)
  fi
  [ -z "$RESULT_DISK_1M_READ" ] && RESULT_DISK_1M_READ=0
  echo -e "  ${C_GREEN}✓${C_RESET} 1M Read:  ${C_BOLD}${RESULT_DISK_1M_READ}${C_RESET} MB/s"

  rm -f "$tmpfile"
  tmpfile=$(mktemp -p "$temp_dir" habs_disk.XXXXXX 2>/dev/null || mktemp habs_disk.XXXXXX)
  TEMP_FILES+=("$tmpfile")

  echo -e "  ${C_BOLD}4K write test (${count_4k} blocks)...${C_RESET}"
  local out_4k_w
  out_4k_w=$(dd if=/dev/zero of="$tmpfile" bs=4k count="$count_4k" oflag=direct 2>&1) || true
  RESULT_DISK_4K_WRITE=$(echo "$out_4k_w" | sed -n 's/.*, \([0-9.]*\) [MG]B\/s.*/\1/p')
  if [ -z "$RESULT_DISK_4K_WRITE" ]; then
    local bytes tm
    bytes=$(echo "$out_4k_w" | grep -o '^[0-9]* bytes' | grep -o '[0-9]*' | head -1)
    tm=$(echo "$out_4k_w" | grep -o '[0-9.]* seconds' | grep -o '[0-9.]*' | head -1)
    [ -n "$bytes" ] && [ -n "$tm" ] && [ "$(awk "BEGIN {print ($tm > 0)}")" -eq 1 ] && \
      RESULT_DISK_4K_WRITE=$(awk "BEGIN {printf \"%.2f\", $bytes / $tm / 1000000}" 2>/dev/null)
  fi
  [ -z "$RESULT_DISK_4K_WRITE" ] && RESULT_DISK_4K_WRITE=0

  local iops_4k_w=0
  [ "$(awk "BEGIN {print ($RESULT_DISK_4K_WRITE > 0)}")" -eq 1 ] && \
    iops_4k_w=$(awk "BEGIN {printf \"%.0f\", $RESULT_DISK_4K_WRITE * 1000000 / 4096}" 2>/dev/null)
  echo -e "  ${C_GREEN}✓${C_RESET} 4K Write: ${C_BOLD}${RESULT_DISK_4K_WRITE}${C_RESET} MB/s (${iops_4k_w} IOPS)"

  echo -e "  ${C_BOLD}4K read test...${C_RESET}"
  is_root && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  local out_4k_r
  out_4k_r=$(dd if="$tmpfile" of=/dev/null bs=4k iflag=direct 2>&1) || true
  RESULT_DISK_4K_READ=$(echo "$out_4k_r" | sed -n 's/.*, \([0-9.]*\) [MG]B\/s.*/\1/p')
  if [ -z "$RESULT_DISK_4K_READ" ]; then
    local bytes tm
    bytes=$(echo "$out_4k_r" | grep -o '^[0-9]* bytes' | grep -o '[0-9]*' | head -1)
    tm=$(echo "$out_4k_r" | grep -o '[0-9.]* seconds' | grep -o '[0-9.]*' | head -1)
    [ -n "$bytes" ] && [ -n "$tm" ] && [ "$(awk "BEGIN {print ($tm > 0)}")" -eq 1 ] && \
      RESULT_DISK_4K_READ=$(awk "BEGIN {printf \"%.2f\", $bytes / $tm / 1000000}" 2>/dev/null)
  fi
  [ -z "$RESULT_DISK_4K_READ" ] && RESULT_DISK_4K_READ=0

  local iops_4k_r=0
  [ "$(awk "BEGIN {print ($RESULT_DISK_4K_READ > 0)}")" -eq 1 ] && \
    iops_4k_r=$(awk "BEGIN {printf \"%.0f\", $RESULT_DISK_4K_READ * 1000000 / 4096}" 2>/dev/null)
  echo -e "  ${C_GREEN}✓${C_RESET} 4K Read:  ${C_BOLD}${RESULT_DISK_4K_READ}${C_RESET} MB/s (${iops_4k_r} IOPS)"

  section_end
}

# ============================================================
# NETWORK BENCHMARK
# ============================================================

bench_network() {
  section_start "Network Benchmark"

  if ! command_exists curl; then
    echo -e "  ${C_YELLOW}curl not found. Skipping network benchmark.${C_RESET}"
    section_end
    return 1
  fi

  local urls=(
    "https://speed.cloudflare.com/__down?bytes=100000000"
    "https://cachefly.cachefly.net/100mb.test"
    "https://proof.ovh.net/files/100Mb.dat"
    "https://speedtest.tele2.net/100MB.zip"
  )

  local timeout=15
  [ "$CONFIG_QUICK" = true ] && timeout=8
  [ "$CONFIG_FULL" = true ] && timeout=30

  local best_speed=0 best_server=""

  echo -e "  ${C_BOLD}Download speed test...${C_RESET}"
  for url in "${urls[@]}"; do
    local server
    server=$(echo "$url" | awk -F/ '{print $3}')

    echo -ne "  ${C_DIM}  ${server}...${C_RESET} " >&2

    local speed_bps
    speed_bps=$(curl -sL --max-time "$timeout" -o /dev/null -w "%{speed_download}" "$url" 2>/dev/null) || true

    if [ -n "$speed_bps" ] && [ "$(awk "BEGIN {print ($speed_bps > 0)}")" -eq 1 ]; then
      local speed_mbps
      speed_mbps=$(awk "BEGIN {printf \"%.2f\", $speed_bps * 8 / 1000000}" 2>/dev/null)
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

  # iperf3 upload test
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
      echo -e "  ${C_YELLOW}  iperf3 servers unreachable, upload skipped${C_RESET}"
    fi
  fi

  # Latency test
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
# SCORING
# ============================================================

calculate_score() {
  local cpu_score=0 mem_score=0 disk_score=0 net_score=0

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

  local total=$((cpu_score + mem_score + disk_score + net_score))

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

  echo "${total}|${grade}|${cpu_score}|${mem_score}|${disk_score}|${net_score}"
}

print_results() {
  local data grade_line
  data=$(calculate_score)
  IFS='|' read -r total grade cpu_score mem_score disk_score net_score <<< "$data"

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
  IFS='|' read -r total grade cpu_score mem_score disk_score net_score <<< "$data"

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
    }
  },
  "scores": {
    "cpu": ${cpu_score},
    "memory": ${mem_score},
    "disk": ${disk_score},
    "network": ${net_score},
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
Modern Linux benchmark tool inspired by YABS

Usage:  bash habs.sh [options]

Options:
  -h, --help         Show this help message
  --version          Show version
  --skip-cpu         Skip CPU benchmark
  --skip-memory      Skip memory benchmark
  --skip-disk        Skip disk benchmark
  --skip-network     Skip network benchmark
  -q, --quick        Quick mode (shorter tests, less data)
  -f, --full         Full mode (more comprehensive tests)
  --json             Output results as JSON to stdout
  --output FILE      Save text/JSON output to file
  --no-color         Disable colored terminal output
  -v, --verbose      Verbose/debug output

Examples:
  bash habs.sh                        Run all benchmarks
  bash habs.sh --quick                Quick benchmark run
  bash habs.sh --skip-network         Skip network tests
  bash habs.sh --json --output result.json

Requirements:
  sysbench    CPU & memory benchmarks
  curl        Network download speed tests
  dd          Disk I/O benchmarks
  ping        Network latency tests
  iperf3      Network upload test (optional)
  python3     JSON parsing for iperf3 (optional)

HELPEOF
}

# ============================================================
# MAIN
# ============================================================

main() {
  START_TIME=$(date +%s)

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)       print_help; exit 0 ;;
      --version)       echo "HABS v${VERSION}"; exit 0 ;;
      --skip-cpu)      CONFIG_SKIP_CPU=true ;;
      --skip-memory)   CONFIG_SKIP_MEMORY=true ;;
      --skip-disk)     CONFIG_SKIP_DISK=true ;;
      --skip-network)  CONFIG_SKIP_NETWORK=true ;;
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

  setup_colors
  setup_signals

  # Redirect text output to file (not in JSON mode)
  if [ -n "$CONFIG_OUTPUT" ] && [ "$CONFIG_JSON" = false ]; then
    exec > >(tee -a "$CONFIG_OUTPUT") 2>&1 || true
  fi

  if [ "$CONFIG_JSON" = false ]; then
    print_header
  fi

  gather_system_info

  if [ "$CONFIG_JSON" = false ]; then
    print_system_info
  fi

  [ "$CONFIG_SKIP_CPU" = false ]     && bench_cpu     || log_debug "Skipping CPU benchmark"
  [ "$CONFIG_SKIP_MEMORY" = false ]  && bench_memory  || log_debug "Skipping memory benchmark"
  [ "$CONFIG_SKIP_DISK" = false ]    && bench_disk    || log_debug "Skipping disk benchmark"
  [ "$CONFIG_SKIP_NETWORK" = false ] && bench_network || log_debug "Skipping network benchmark"

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
}

main "$@"
