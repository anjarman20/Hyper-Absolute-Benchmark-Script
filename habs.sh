#!/usr/bin/env bash
# =============================================================================
#  HABS – Hyper Absolute Benchmark Script
#  Version: 2.0.0
#  URL:     https://github.com/anjarman20/Hyper-Absolute-Benchmark-Script
#  License: WTFPL
#
#  A modern Linux benchmarking suite combining YABS and byte-unixbench
#  functionality with integrated dependency management, Geekbench 6,
#  y-cruncher, fio, stress-ng, iperf3, and clean JSON export.
# =============================================================================

set -euo pipefail
shopt -s extglob nullglob

# -------- Constants ----------------------------------------------------------
readonly HABS_VERSION='2.0.0'
readonly HABS_URL='https://github.com/anjarman20/Hyper-Absolute-Benchmark-Script'
readonly HABS_NAME='HABS'
readonly HABS_COPYRIGHT='© 2026 HABS Contributors'

# Minimum required Bash version
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "Error: HABS requires Bash 4.0 or later (found ${BASH_VERSION})" >&2
    exit 1
fi

# Geometry
readonly BOX_HW='─' BOX_VW='│' BOX_TR='┐' BOX_TL='┌' BOX_BR='┘' BOX_BL='└'
readonly BOX_TM='┬' BOX_BM='┴' BOX_LM='├' BOX_RM='┤' BOX_CR='┼'

# -------- Color Definitions --------------------------------------------------
C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE='' C_ORANGE='' C_GREY=''

_init_colors() {
    if [[ $HABS_NOCOLOR -eq 1 ]]; then
        C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
        C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE='' C_ORANGE='' C_GREY=''
        return
    fi
    if [[ -t 1 ]] && [[ ${TERM:-} != dumb ]] && command -v tput &>/dev/null; then
        C_RESET=$(tput sgr0 2>/dev/null || true)
        C_BOLD=$(tput bold 2>/dev/null || true)
        C_DIM=$(tput dim 2>/dev/null || true)
        C_RED=$(tput setaf 1 2>/dev/null || true)
        C_GREEN=$(tput setaf 2 2>/dev/null || true)
        C_YELLOW=$(tput setaf 3 2>/dev/null || true)
        C_BLUE=$(tput setaf 4 2>/dev/null || true)
        C_MAGENTA=$(tput setaf 5 2>/dev/null || true)
        C_CYAN=$(tput setaf 6 2>/dev/null || true)
        C_WHITE=$(tput setaf 7 2>/dev/null || true)
        C_ORANGE=$(tput setaf 208 2>/dev/null || true)
        C_GREY=$(tput setaf 244 2>/dev/null || true)
    fi
}

# -------- Global State -------------------------------------------------------
HABS_NOCOLOR=0
HABS_QUICK=0
HABS_FULL=0
HABS_JSON=0
HABS_VERBOSE=0
HABS_OUTPUT_FILE=''
HABS_START_TIME=0
HABS_END_TIME=0

# Skip flags
HABS_SKIP_CPU=0
HABS_SKIP_MEMORY=0
HABS_SKIP_DISK=0
HABS_SKIP_NETWORK=0
HABS_SKIP_GEEKBENCH=0
HABS_SKIP_ADVANCED=0
HABS_SKIP_YCRUNCHER=1
HABS_SKIP_UNIXBENCH=1
HABS_COMPACT=0

# Results accumulator (associative array)
declare -A HABS_RESULTS=()

# Additional data structures for complex results
declare -A HABS_SYSINFO=()
declare -A HABS_SCORES=()
HABS_JSON_EXTRA=""

# Temp directory
HABS_TMPDIR=''
HABS_GEK_BIN=''
HABS_YC_BIN=''
HABS_UB_DIR=''

# -------- Signal Handling ----------------------------------------------------
_cleanup_exit() {
    local ec=$?
    if [[ -n "${HABS_TMPDIR:-}" ]] && [[ -d "$HABS_TMPDIR" ]]; then
        rm -rf "$HABS_TMPDIR" 2>/dev/null || true
    fi
    if [[ $ec -ne 0 ]] && [[ $ec -ne 0 ]]; then
        echo -e "\n${C_RED}✖${C_RESET} HABS interrupted. Cleaning up..." >&2
    fi
    exit $ec
}
trap _cleanup_exit EXIT INT TERM

# -------- Utility Functions --------------------------------------------------

_log()    { local lvl=$1; shift; echo -e "${C_GREY}[${lvl}]${C_RESET} $*" >&2; }
_info()   { _log "${C_BLUE}INFO${C_RESET}" "$@"; }
_warn()   { _log "${C_YELLOW}WARN${C_RESET}" "$@"; }
_error()  { _log "${C_RED}ERROR${C_RESET}" "$@"; }
_debug()  { [[ $HABS_VERBOSE -eq 1 ]] && _log "${C_DIM}DEBUG${C_RESET}" "$@"; }
_ok()     { [[ $HABS_COMPACT -eq 1 ]] && return; echo -e "  ${C_GREEN}✔${C_RESET} $*"; }
_skip()   { [[ $HABS_COMPACT -eq 1 ]] && return; echo -e "  ${C_YELLOW}⊘${C_RESET} $*"; }
_fail()   { [[ $HABS_COMPACT -eq 1 ]] && return; echo -e "  ${C_RED}✖${C_RESET} $*"; }

fmt_number() {
    local n=$1
    local decimals=${2:-2}
    if [[ $(echo "$n < 1000" | bc 2>/dev/null) == 1 ]] 2>/dev/null; then
        printf "%.${decimals}f" "$n"
    else
        printf "%'.${decimals}f" "$n"
    fi
}

fmt_bytes() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then echo "${bytes} B"
    elif [[ $bytes -lt 1048576 ]]; then printf "%.2f KB" "$(echo "scale=2; $bytes/1024" | bc -l 2>/dev/null || echo "$bytes/1024" | awk '{printf "%.2f", $1}')"
    elif [[ $bytes -lt 1073741824 ]]; then printf "%.2f MB" "$(echo "scale=2; $bytes/1048576" | bc -l 2>/dev/null || echo "$bytes/1048576" | awk '{printf "%.2f", $1}')"
    else printf "%.2f GB" "$(echo "scale=2; $bytes/1073741824" | bc -l 2>/dev/null || echo "$bytes/1073741824" | awk '{printf "%.2f", $1}')"
    fi
}

fmt_duration() {
    local total=$1
    local d=$((total / 86400))
    local h=$(( (total % 86400) / 3600 ))
    local m=$(( (total % 3600) / 60 ))
    local s=$((total % 60))
    local out=''
    [[ $d -gt 0 ]] && out+="${d}d "
    [[ $h -gt 0 ]] && out+="${h}h "
    [[ $m -gt 0 ]] && out+="${m}m "
    out+="${s}s"
    echo "$out"
}

run_with_timeout() {
    local timeout_sec=$1; shift
    if ! command -v timeout &>/dev/null; then
        "$@" 2>&1 || true
        return
    fi
    timeout "$timeout_sec" "$@" 2>&1 || true
}

check_command() {
    command -v "$1" &>/dev/null
}

json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/\\r}
    echo "$s"
}

json_kv() {
    local key=$1 val=$2 comma=${3:-false}
    local q=''
    [[ $comma == true ]] && q=','
    if [[ $val =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ $val == 'null' ]] || [[ $val == 'true' ]] || [[ $val == 'false' ]]; then
        printf '  "%s": %s%s\n' "$(json_escape "$key")" "$val" "$q"
    else
        printf '  "%s": "%s"%s\n' "$(json_escape "$key")" "$(json_escape "$val")" "$q"
    fi
}

json_kv_raw() {
    local key=$1 val=$2 comma=${3:-false}
    local q=''
    [[ $comma == true ]] && q=','
    printf '  "%s": %s%s\n' "$(json_escape "$key")" "$val" "$q"
}

detect_package_manager() {
    if check_command apt-get; then
        echo 'apt-get'
    elif check_command dnf; then
        echo 'dnf'
    elif check_command yum; then
        echo 'yum'
    elif check_command zypper; then
        echo 'zypper'
    elif check_command pacman; then
        echo 'pacman'
    elif check_command apk; then
        echo 'apk'
    else
        echo ''
    fi
}

auto_install() {
    local pkg=$1
    local pm
    pm=$(detect_package_manager)
    if [[ -z $pm ]] || [[ $EUID -ne 0 ]]; then
        return 1
    fi

    case $pm in
        apt-get) apt-get update -qq 2>/dev/null && apt-get install -y -qq "$pkg" 2>/dev/null ;;
        dnf)     dnf install -y -q "$pkg" 2>/dev/null ;;
        yum)     yum install -y -q "$pkg" 2>/dev/null ;;
        zypper)  zypper install -y --quiet "$pkg" 2>/dev/null ;;
        pacman)  pacman -S --noconfirm --quiet "$pkg" 2>/dev/null ;;
        apk)     apk add --no-cache --quiet "$pkg" 2>/dev/null ;;
    esac

    check_command "$pkg" && return 0 || return 1
}

ensure_command() {
    local cmd=$1 pkg=${2:-$1}
    if ! check_command "$cmd"; then
        auto_install "$pkg" || return 1
    fi
    return 0
}

get_term_width() {
    if [[ -t 1 ]]; then
        tput cols 2>/dev/null || echo 80
    else
        echo 80
    fi
}

get_arch() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64|amd64)   echo 'x86_64' ;;
        aarch64|arm64)  echo 'aarch64' ;;
        *)             echo "$arch" ;;
    esac
}

_ensure_tmpdir() {
    if [[ -z $HABS_TMPDIR ]]; then
        HABS_TMPDIR=$(mktemp -d "/tmp/habs.XXXXXX")
    fi
}

# -------- Progress / Spinner -------------------------------------------------

_spin_pid=0
_spin_msg=''

_spinner_start() {
    [[ $HABS_COMPACT -eq 1 ]] && return
    _spin_msg=$1
    if [[ $HABS_VERBOSE -eq 1 ]]; then
        echo -ne "  ${C_CYAN}⟳${C_RESET} ${_spin_msg}"
        return
    fi
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    (
        local i=0
        while kill -0 "$$" 2>/dev/null; do
            local ch="${spin:$i:1}"
            echo -ne "\r  ${C_CYAN}${ch}${C_RESET} ${_spin_msg}"
            i=$(( (i + 1) % ${#spin} ))
            sleep 0.1
        done
    ) &
    _spin_pid=$!
    disown $_spin_pid 2>/dev/null || true
}

_spinner_stop() {
    if [[ $_spin_pid -ne 0 ]]; then
        kill $_spin_pid 2>/dev/null || true
        wait $_spin_pid 2>/dev/null || true
        _spin_pid=0
    fi
    echo -ne "\r\033[K"
    [[ $HABS_VERBOSE -eq 1 ]] || true
}

_spinner_ok() {
    _spinner_stop
    _ok "$_spin_msg"
}

_spinner_fail() {
    _spinner_stop
    _fail "$_spin_msg"
}

# =============================================================================
#  OUTPUT / DISPLAY FUNCTIONS
# =============================================================================

_make_hline() {
    local len=$1
    local i
    for ((i=0; i<len; i++)); do
        echo -n "${BOX_HW}"
    done
}

_print_section_header() {
    [[ $HABS_COMPACT -eq 1 ]] && return
    local title=$1
    local tw
    tw=$(get_term_width)
    local inner=$(( tw - 4 ))
    local title_len=${#title}
    local dash_len=$(( inner - title_len - 2 ))
    [[ $dash_len -lt 1 ]] && dash_len=1

    printf "  ${C_BOLD}${C_CYAN}%s${C_RESET}" "${BOX_TL}"
    printf "${BOX_HW} ${C_BOLD}${C_WHITE}%s${C_RESET} ${C_CYAN}" "$title"
    _make_hline "$dash_len"
    printf "${C_BOLD}${C_CYAN}%s${C_RESET}\n" "${BOX_TR}"
}

_print_section_footer() {
    [[ $HABS_COMPACT -eq 1 ]] && return
    local tw
    tw=$(get_term_width)
    local inner=$(( tw - 4 ))
    printf "  ${C_CYAN}%s${C_RESET}" "${BOX_BL}"
    _make_hline "$inner"
    printf "${C_CYAN}%s${C_RESET}\n" "${BOX_BR}"
}

_print_kv() {
    [[ $HABS_COMPACT -eq 1 ]] && return
    local key=$1 val=$2 color=${3:-$C_WHITE}
    printf "  ${C_BOLD}${C_GREY}│${C_RESET}  %-22s ${C_GREY}:${C_RESET} ${color}%s${C_RESET}\n" "$key" "$val"
}

_print_kv_r() {
    local key=$1 val=$2 color=${3:-$C_WHITE}
    printf "  ${C_BOLD}${C_GREY}│${C_RESET}  %-22s ${C_GREY}:${C_RESET} ${color}%s${C_RESET}\n" "$key" "$val"
}

_print_kv_b() {
    [[ $HABS_COMPACT -eq 1 ]] && return
    local key=$1 val=$2
    printf "  ${C_BOLD}${C_GREY}│${C_RESET}  ${C_BOLD}%-22s${C_RESET} ${C_GREY}:${C_RESET} ${C_BOLD}${C_GREEN}%s${C_RESET}\n" "$key" "$val"
}

_print_compact_kv() {
    local key=$1 val=$2
    printf "  ${C_BOLD}${C_GREY}│${C_RESET}  ${C_BOLD}%-22s${C_RESET} ${C_GREY}:${C_RESET} ${C_WHITE}%s${C_RESET}\n" "$key" "$val"
}

_print_line() {
    [[ $HABS_COMPACT -eq 1 ]] && return
    printf "  ${C_BOLD}${C_GREY}│${C_RESET}  %s\n" "$1"
}

_print_subheader() {
    [[ $HABS_COMPACT -eq 1 ]] && return
    printf "  ${C_BOLD}${C_GREY}│${C_RESET}  ${C_BOLD}${C_MAGENTA}%s${C_RESET}\n" "$1"
}

_print_empty() {
    [[ $HABS_COMPACT -eq 1 ]] && return
    printf "  ${C_BOLD}${C_GREY}│${C_RESET}\n"
}

_print_info_box() {
    local msg=$1
    local tw
    tw=$(get_term_width)
    local inner=$(( tw - 8 ))
    printf "  ${C_YELLOW}%s${C_RESET}" "${BOX_TL}"
    _make_hline "$inner"
    printf "${C_YELLOW}%s${C_RESET}\n" "${BOX_TR}"
    printf "  ${C_YELLOW}│${C_RESET}  ${C_YELLOW}%s${C_RESET}\n" "$msg"
    printf "  ${C_YELLOW}%s${C_RESET}" "${BOX_BL}"
    _make_hline "$inner"
    printf "${C_YELLOW}%s${C_RESET}\n" "${BOX_BR}"
}

# =============================================================================
#  SYSTEM INFORMATION
# =============================================================================

gather_system_info() {
    _info "Gathering system information..."

    HABS_SYSINFO[hostname]=$(hostname 2>/dev/null || echo 'unknown')
    HABS_SYSINFO[os]="$( (lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i '^pretty_name=' | cut -d= -f2 | tr -d '"' || echo 'unknown') )"
    HABS_SYSINFO[kernel]=$(uname -r)
    HABS_SYSINFO[arch]=$(get_arch)
    HABS_SYSINFO[uptime_seconds]=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}' || echo 0)

    # Virtualization detection
    local virt=''
    if check_command systemd-detect-virt; then
        virt=$(systemd-detect-virt 2>/dev/null || echo 'none')
    elif [[ -f /sys/devices/virtual/misc/kvm ]]; then
        virt='kvm'
    elif [[ -f /proc/xen/capabilities ]]; then
        virt='xen'
    elif grep -qi 'container' /proc/1/cgroup 2>/dev/null; then
        virt='container'
    else
        virt='none'
    fi
    HABS_SYSINFO[virtualization]="$virt"

    # CPU info
    if [[ -f /proc/cpuinfo ]]; then
        HABS_SYSINFO[cpu_model]=$(grep -m1 'model name' /proc/cpuinfo | sed 's/.*:\s*//' | xargs)
        [[ -z "${HABS_SYSINFO[cpu_model]}" ]] && HABS_SYSINFO[cpu_model]=$(grep -m1 'Processor' /proc/cpuinfo | sed 's/.*:\s*//' | xargs) || true
        [[ -z "${HABS_SYSINFO[cpu_model]}" ]] && HABS_SYSINFO[cpu_model]='unknown'
        HABS_SYSINFO[cpu_cores]=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo || echo 1)
        HABS_SYSINFO[cpu_physical]=$(grep 'physical id' /proc/cpuinfo | sort -u | wc -l)
        [[ ${HABS_SYSINFO[cpu_physical]} -eq 0 ]] && HABS_SYSINFO[cpu_physical]=${HABS_SYSINFO[cpu_cores]}

        local cpu_mhz
        cpu_mhz=$(grep -m1 'cpu MHz' /proc/cpuinfo | sed 's/.*:\s*//' | xargs)
        if [[ -n "$cpu_mhz" ]]; then
            HABS_SYSINFO[cpu_freq]=$(echo "scale=2; $cpu_mhz / 1000" | bc -l 2>/dev/null || echo "$cpu_mhz")
        else
            HABS_SYSINFO[cpu_freq]='N/A'
        fi

        # Cache info
        HABS_SYSINFO[cpu_cache_l1d]=$(grep -m1 'cache size' /proc/cpuinfo | sed 's/.*:\s*//' | xargs)
        if [[ -z "${HABS_SYSINFO[cpu_cache_l1d]}" ]] && [[ -d /sys/devices/system/cpu/cpu0/cache ]]; then
            for dir in /sys/devices/system/cpu/cpu0/cache/index*; do
                local type
                type=$(cat "$dir/type" 2>/dev/null || true)
                local size
                size=$(cat "$dir/size" 2>/dev/null || true)
                case $type in
                    Data)  HABS_SYSINFO[cpu_cache_l1d]="${size}B" ;;
                    Instruction) HABS_SYSINFO[cpu_cache_l1i]="${size}B" ;;
                    Unified)
                        local level
                        level=$(cat "$dir/level" 2>/dev/null || true)
                        case $level in
                            2) HABS_SYSINFO[cpu_cache_l2]="${size}B" ;;
                            3) HABS_SYSINFO[cpu_cache_l3]="${size}B" ;;
                        esac
                    ;;
                esac
            done
        fi

        # CPU flags (truncated for display but stored fully)
        HABS_SYSINFO[cpu_flags_full]=$(grep -m1 'flags' /proc/cpuinfo | sed 's/.*:\s*//' || true)
        local flags="${HABS_SYSINFO[cpu_flags_full]}"
        HABS_SYSINFO[has_aes]=0; HABS_SYSINFO[has_avx]=0; HABS_SYSINFO[has_avx2]=0; HABS_SYSINFO[has_avx512]=0
        HABS_SYSINFO[has_sse4_2]=0; HABS_SYSINFO[has_neon]=0; HABS_SYSINFO[has_sve]=0
        [[ $flags == *' aes '* ]] && HABS_SYSINFO[has_aes]=1
        [[ $flags == *' avx '* ]] && HABS_SYSINFO[has_avx]=1
        [[ $flags == *' avx2 '* ]] && HABS_SYSINFO[has_avx2]=1
        [[ $flags == *' avx512'* ]] && HABS_SYSINFO[has_avx512]=1
        [[ $flags == *' sse4_2 '* ]] && HABS_SYSINFO[has_sse4_2]=1
        [[ $flags == *' neon '* ]] && HABS_SYSINFO[has_neon]=1
        [[ $flags == *' sve '* ]] && HABS_SYSINFO[has_sve]=1
    fi

    # Memory info
    if [[ -f /proc/meminfo ]]; then
        local mem_total=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
        local mem_avail=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
        local swap_total=$(grep '^SwapTotal:' /proc/meminfo | awk '{print $2}')
        local swap_free=$(grep '^SwapFree:' /proc/meminfo | awk '{print $2}')
        HABS_SYSINFO[ram_total]=$((mem_total * 1024))
        HABS_SYSINFO[ram_available]=$((mem_avail * 1024))
        HABS_SYSINFO[ram_used]=$(( (mem_total - mem_avail) * 1024 ))
        HABS_SYSINFO[swap_total]=$((swap_total * 1024))
        HABS_SYSINFO[swap_free]=$((swap_free * 1024))
        HABS_SYSINFO[swap_used]=$(( (swap_total - swap_free) * 1024 ))
    fi

    # Disk info (root partition)
    if check_command df; then
        HABS_SYSINFO[disk_total]=$(df --block-size=1 / 2>/dev/null | awk 'NR==2 {print $2}' || df -P / 2>/dev/null | awk 'NR==2 {print $2*1024}')
        HABS_SYSINFO[disk_used]=$(df --block-size=1 / 2>/dev/null | awk 'NR==2 {print $3}' || df -P / 2>/dev/null | awk 'NR==2 {print $3*1024}')
        HABS_SYSINFO[disk_avail]=$(df --block-size=1 / 2>/dev/null | awk 'NR==2 {print $4}' || df -P / 2>/dev/null | awk 'NR==2 {print $4*1024}')
        HABS_SYSINFO[disk_usage_pct]=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo 0)
    fi

    # Filesystem type
    HABS_SYSINFO[filesystem]=$(df -T / 2>/dev/null | awk 'NR==2 {print $2}' || echo 'unknown')
    HABS_SYSINFO[mount_options]=$(grep ' / ' /proc/mounts 2>/dev/null | awk '{print $4}' || echo 'unknown')

    # Load average
    if [[ -f /proc/loadavg ]]; then
        read -r l1 l2 l3 _ < /proc/loadavg
        HABS_SYSINFO[load_1]="$l1"
        HABS_SYSINFO[load_5]="$l2"
        HABS_SYSINFO[load_15]="$l3"
    fi

    # Network interfaces
    HABS_SYSINFO[ipv4]=''
    HABS_SYSINFO[ipv6]=''
    if check_command ip; then
        HABS_SYSINFO[ipv4]=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo '')
        HABS_SYSINFO[ipv6]=$(ip -6 addr show scope global 2>/dev/null | grep -oP 'inet6 \K[0-9a-f:]+' | head -1 || echo '')
        HABS_SYSINFO[interfaces]=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | paste -sd ',' || echo 'lo')
    fi

    # CPU feature strings for display
    local features=''
    [[ ${HABS_SYSINFO[has_aes]} -eq 1 ]] && features+=' AES'
    [[ ${HABS_SYSINFO[has_avx]} -eq 1 ]] && features+=' AVX'
    [[ ${HABS_SYSINFO[has_avx2]} -eq 1 ]] && features+=' AVX2'
    [[ ${HABS_SYSINFO[has_avx512]} -eq 1 ]] && features+=' AVX-512'
    [[ ${HABS_SYSINFO[has_sse4_2]} -eq 1 ]] && features+=' SSE4.2'
    [[ ${HABS_SYSINFO[has_neon]} -eq 1 ]] && features+=' NEON'
    [[ ${HABS_SYSINFO[has_sve]} -eq 1 ]] && features+=' SVE'
    features=$(echo "$features" | xargs)
    [[ -z "$features" ]] && features='N/A'
    HABS_SYSINFO[cpu_features_str]="$features"
}

display_system_info() {
    _print_section_header 'System Information'

    _print_kv 'Hostname'         "${HABS_SYSINFO[hostname]}"
    _print_kv 'OS'               "${HABS_SYSINFO[os]}"
    _print_kv 'Kernel'           "${HABS_SYSINFO[kernel]}"
    _print_kv 'CPU'              "${HABS_SYSINFO[cpu_model]} (${HABS_SYSINFO[cpu_physical]}C/${HABS_SYSINFO[cpu_cores]}T) @ ${HABS_SYSINFO[cpu_freq]} GHz"
    _print_kv 'Cache'            "L1:${HABS_SYSINFO[cpu_cache_l1d]:-N/A} L2:${HABS_SYSINFO[cpu_cache_l2]:-N/A} L3:${HABS_SYSINFO[cpu_cache_l3]:-N/A} | ${HABS_SYSINFO[cpu_features_str]}"
    _print_kv 'RAM'              "$(fmt_bytes ${HABS_SYSINFO[ram_used]}) / $(fmt_bytes ${HABS_SYSINFO[ram_total]}) ($(fmt_bytes ${HABS_SYSINFO[ram_available]}) avail)"
    _print_kv 'Disk'             "$(fmt_bytes ${HABS_SYSINFO[disk_used]}) / $(fmt_bytes ${HABS_SYSINFO[disk_total]}) (${HABS_SYSINFO[disk_usage_pct]}%) — ${HABS_SYSINFO[filesystem]}"
    _print_kv 'Net'              "IPv4:${HABS_SYSINFO[ipv4]:-N/A} IPv6:${HABS_SYSINFO[ipv6]:-N/A} (${HABS_SYSINFO[interfaces]:-N/A})"
    _print_kv 'Load'             "${HABS_SYSINFO[load_1]:-0.00} / ${HABS_SYSINFO[load_5]:-0.00} / ${HABS_SYSINFO[load_15]:-0.00} | Virt:${HABS_SYSINFO[virtualization]} Uptime:$(fmt_duration ${HABS_SYSINFO[uptime_seconds]})"

    _print_section_footer
}

# =============================================================================
#  BENCHMARK: CPU (sysbench)
# =============================================================================

bench_cpu() {
    _info "Running CPU benchmark (sysbench)..."

    _print_section_header 'CPU Benchmark (sysbench)'

    ensure_command sysbench sysbench || { _print_line 'sysbench not available'; _print_section_footer; return 1; }

    local max_prime
    local nproc
    nproc=${HABS_SYSINFO[cpu_cores]:-$(nproc)}
    [[ $nproc -lt 1 ]] && nproc=1
    if [[ $HABS_QUICK -eq 1 ]]; then
        max_prime=10000
    elif [[ $HABS_FULL -eq 1 ]]; then
        max_prime=50000
    else
        max_prime=20000
    fi

    local single_result='' multi_result=''

    # Single-threaded
    _spinner_start "CPU Single-threaded (prime ${max_prime}) ..."
    single_result=$(run_with_timeout 180 sysbench cpu --cpu-max-prime="$max_prime" --threads=1 run 2>/dev/null)
    _spinner_stop

    local single_eps
    single_eps=$(echo "$single_result" | grep 'events per second:' | grep -oP '\d+\.?\d*' | head -1 || echo '0')
    [[ -z "$single_eps" ]] && single_eps=0

    _ok "Single-threaded:  ${single_eps} events/s"

    # Multi-threaded
    _spinner_start "CPU Multi-threaded (${nproc} threads, prime ${max_prime}) ..."
    multi_result=$(run_with_timeout 300 sysbench cpu --cpu-max-prime="$max_prime" --threads="$nproc" run 2>/dev/null)
    _spinner_stop

    local multi_eps
    multi_eps=$(echo "$multi_result" | grep 'events per second:' | grep -oP '\d+\.?\d*' | head -1 || echo '0')
    [[ -z "$multi_eps" ]] && multi_eps=0

    _ok "Multi-threaded:   ${multi_eps} events/s"

    # Scaling ratio
    local scaling=0
    if [[ $(echo "$single_eps > 0" | bc -l 2>/dev/null) == 1 ]]; then
        scaling=$(echo "scale=2; $multi_eps / $single_eps" | bc -l 2>/dev/null || echo 0)
    fi

    local ideal_scaling=$nproc
    _print_empty
    _print_kv_b 'Scaling Ratio'     "${scaling}x (ideal: ${ideal_scaling}x)"

    _print_section_footer

    HABS_RESULTS[cpu_single_eps]=$single_eps
    HABS_RESULTS[cpu_multi_eps]=$multi_eps
    HABS_RESULTS[cpu_scaling]=$scaling
    HABS_RESULTS[cpu_threads]=$nproc
    HABS_RESULTS[cpu_max_prime]=$max_prime
}

# =============================================================================
#  BENCHMARK: MEMORY (sysbench)
# =============================================================================

_parse_sysbench_mbs() {
    local out=$1
    local val
    val=$(echo "$out" | grep -oP '[\d.]+(?=\s*MiB/sec)' | head -1 || echo '')
    [[ -z "$val" || "$val" == '0' ]] && val=$(echo "$out" | grep -oP 'transferred\s*\(\K[\d.]+' | head -1 || echo '')
    [[ -z "$val" || "$val" == '0' ]] && val=$(echo "$out" | grep -oP 'MiB/sec\s*\|\s*\K[\d.]+' | head -1 || echo '')
    [[ -z "$val" || "$val" == '0' ]] && val=$(echo "$out" | grep -oP '\K[\d.]+(?=\s*MiB/sec)' | tail -1 || echo '')
    [[ -z "$val" || "$val" == '0' ]] && val=$(echo "$out" | grep -i 'transferred' | grep -oP '\(*\K[0-9]+\.[0-9]+' | head -1 || echo '')
    echo "${val:-0}"
}

bench_memory() {
    _info "Running memory benchmark (sysbench)..."

    _print_section_header 'Memory Benchmark (sysbench)'

    ensure_command sysbench sysbench || { _print_line 'sysbench not available'; _print_section_footer; return 1; }

    local total_size
    if [[ $HABS_QUICK -eq 1 ]]; then
        total_size='2G'
    elif [[ $HABS_FULL -eq 1 ]]; then
        total_size='20G'
    else
        total_size='10G'
    fi

    local read_result write_result
    local read_mbs=0 write_mbs=0

    # Sequential read
    _spinner_start "Memory Read (${total_size}, 1M blocks) ..."
    read_result=$(run_with_timeout 300 sysbench memory --memory-block-size=1M --memory-total-size="$total_size" --memory-oper=read memory-run 2>/dev/null)
    _spinner_stop
    read_mbs=$(_parse_sysbench_mbs "$read_result")
    _print_kv 'Read'  "${read_mbs} MiB/s" "${C_GREEN}"

    # Sequential write
    _spinner_start "Memory Write (${total_size}, 1M blocks) ..."
    write_result=$(run_with_timeout 300 sysbench memory --memory-block-size=1M --memory-total-size="$total_size" --memory-oper=write memory-run 2>/dev/null)
    _spinner_stop
    write_mbs=$(_parse_sysbench_mbs "$write_result")
    _print_kv 'Write' "${write_mbs} MiB/s" "${C_GREEN}"

    _print_section_footer

    HABS_RESULTS[mem_read_mbs]=$read_mbs
    HABS_RESULTS[mem_write_mbs]=$write_mbs
    HABS_RESULTS[mem_total_size]=$total_size
}

# =============================================================================
#  BENCHMARK: DISK (dd)
# =============================================================================

bench_disk() {
    _info "Running disk benchmark (dd)..."

    _print_section_header 'Disk Benchmark (dd)'

    _ensure_tmpdir
    local testfile="${HABS_TMPDIR}/dd_test"
    local test_size=1024  # 1G default, in MB

    # Auto-scale based on available space
    local avail_mb=0
    if [[ -n "${HABS_SYSINFO[disk_avail]}" ]]; then
        avail_mb=$(( HABS_SYSINFO[disk_avail] / 1048576 ))
    fi
    if [[ $avail_mb -gt 0 ]] && [[ $avail_mb -lt 2000 ]]; then
        test_size=256
        _print_line "${C_YELLOW}Low disk space: scaling test to ${test_size}M${C_RESET}"
    fi

    local results_4kw=0 results_4kr=0 results_1mw=0 results_1mr=0
    local iops_4kw=0 iops_4kr=0

    # 1M Sequential Write + Read
    _spinner_start "1M Sequential Write (${test_size}M) ..."
    results_1mw=$(run_with_timeout 120 dd if=/dev/zero of="$testfile" bs=1M count="$test_size" oflag=direct 2>&1 | awk '/copied/ {print $(NF-1)}')
    _spinner_stop
    results_1mw=${results_1mw:-0}
    if [[ $results_1mw =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $(echo "$results_1mw < 10000" | bc -l 2>/dev/null) == 1 ]]; then
        results_1mw=$(echo "scale=2; $results_1mw / 1" | bc -l 2>/dev/null || echo "$results_1mw")
    fi

    _spinner_start "1M Sequential Read (${test_size}M) ..."
    results_1mr=$(run_with_timeout 120 dd if="$testfile" of=/dev/null bs=1M count="$test_size" iflag=direct 2>&1 | awk '/copied/ {print $(NF-1)}')
    _spinner_stop
    results_1mr=${results_1mr:-0}
    _print_kv '1M Seq'       "${results_1mw} MB/s Write / ${results_1mr} MB/s Read" "${C_GREEN}"

    # 4K Random Write + Read
    local test_size_4k=256
    if [[ $avail_mb -gt 0 ]] && [[ $avail_mb -lt 500 ]]; then
        test_size_4k=64
    fi
    local count_4k=$(( test_size_4k * 256 ))

    _spinner_start "4K Random Write (${test_size_4k}M) ..."
    results_4kw=$(run_with_timeout 180 dd if=/dev/zero of="${testfile}_4k" bs=4K count="$count_4k" oflag=direct 2>&1 | awk '/copied/ {print $(NF-1)}')
    _spinner_stop
    results_4kw=${results_4kw:-0}
    iops_4kw=$(echo "scale=0; $results_4kw * 1024 / 4" | bc -l 2>/dev/null || echo 0)

    _spinner_start "4K Random Read (${test_size_4k}M) ..."
    results_4kr=$(run_with_timeout 180 dd if="${testfile}_4k" of=/dev/null bs=4K count="$count_4k" iflag=direct 2>&1 | awk '/copied/ {print $(NF-1)}')
    _spinner_stop
    results_4kr=${results_4kr:-0}
    iops_4kr=$(echo "scale=0; $results_4kr * 1024 / 4" | bc -l 2>/dev/null || echo 0)
    _print_kv '4K Rand'     "${iops_4kw} IOPS Write / ${iops_4kr} IOPS Read" "${C_GREEN}"

    # Cleanup
    rm -f "$testfile" "${testfile}_4k" 2>/dev/null || true

    _print_section_footer

    HABS_RESULTS[disk_1m_write_mbs]=$results_1mw
    HABS_RESULTS[disk_1m_read_mbs]=$results_1mr
    HABS_RESULTS[disk_4k_write_mbs]=$results_4kw
    HABS_RESULTS[disk_4k_read_mbs]=$results_4kr
    HABS_RESULTS[disk_4k_write_iops]=$iops_4kw
    HABS_RESULTS[disk_4k_read_iops]=$iops_4kr
    HABS_RESULTS[disk_test_size]=$test_size
}

# =============================================================================
#  BENCHMARK: NETWORK (curl multi-CDN + iperf3)
# =============================================================================

bench_network() {
    _info "Running network benchmark..."

    _print_section_header 'Network Benchmark'

    ensure_command curl curl || { _print_line 'curl not available'; _print_section_footer; return 1; }

    local download_speeds=()
    local best_dl=0 best_server=''
    local latency_results=()
    local avg_latency=0

    # Download tests from multiple CDNs
    local dl_size='100MB'
    if [[ $HABS_QUICK -eq 1 ]]; then
        dl_size='10MB'
    fi
    local -a dl_tests=(
        "10MB|https://speed.cloudflare.com/__down?bytes=10485760|Cloudflare"
        "10MB|https://cachefly.cachefly.net/10mb.test|CacheFly"
        "10MB|https://proof.ovh.net/files/10Mb.dat|OVH"
        "10MB|https://speedtest.tele2.net/10MB.zip|Tele2"
    )
    if [[ $HABS_FULL -eq 1 ]]; then
        dl_tests=(
            "100MB|https://speed.cloudflare.com/__down?bytes=104857600|Cloudflare"
            "100MB|https://cachefly.cachefly.net/100mb.test|CacheFly"
            "100MB|https://proof.ovh.net/files/100Mb.dat|OVH"
            "100MB|https://speedtest.tele2.net/100MB.zip|Tele2"
        )
    fi

    # Download test — try all servers, show only best
    for entry in "${dl_tests[@]}"; do
        local label url server
        label=$(echo "$entry" | cut -d'|' -f1)
        url=$(echo "$entry" | cut -d'|' -f2)
        server=$(echo "$entry" | cut -d'|' -f3)

        local result
        result=$(run_with_timeout 30 curl -s -o /dev/null -w '%{speed_download}' --max-time 25 "$url" 2>/dev/null || echo '0')

        local speed_mbps
        speed_mbps=$(echo "scale=2; $result * 8 / 1000000" | bc -l 2>/dev/null || echo '0')
        download_speeds+=("$speed_mbps")
        if [[ $(echo "$speed_mbps > $best_dl" | bc -l 2>/dev/null) == 1 ]]; then
            best_dl=$speed_mbps
            best_server=$server
        fi
    done
    _print_kv 'Download' "$(fmt_number $best_dl) Mbps (${best_server})" "${C_GREEN}"

    # Upload test via iperf3
    local upload_mbps=0
    local upload_server=''
    if ! check_command iperf3 && ! ensure_command iperf3 iperf3; then
        _print_kv 'Upload' 'N/A' "${C_GREY}"
    else
        local -a iperf_servers=('iperf.he.net' 'iperf.online.net' 'iperf.scottlinux.com')
        local up_result=''
        for iperf_server in "${iperf_servers[@]}"; do
            up_result=$(run_with_timeout 30 iperf3 -c "$iperf_server" -P 2 -t 10 -J 2>/dev/null || echo '')
            if [[ -n "$up_result" ]]; then
                if check_command python3; then
                    upload_mbps=$(echo "$up_result" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    bps=d.get('end',{}).get('sum_sent',{}).get('bits_per_second',0)
    print('{:.2f}'.format(bps/1e6))
except: print('0')
" 2>/dev/null) || upload_mbps='0'
                else
                    upload_mbps=$(echo "$up_result" | grep -oP '"bits_per_second":\s*\K[0-9.]+' | head -1 || echo '0')
                    upload_mbps=$(echo "scale=2; $upload_mbps / 1000000" | bc -l 2>/dev/null || echo '0')
                fi
                if [[ $(echo "$upload_mbps > 0" | bc -l) == 1 ]]; then
                    upload_server=$iperf_server
                    _ok "Upload:  $(fmt_number $upload_mbps) Mbps (${iperf_server})"
                    break
                fi
            fi
            _skip "Upload to ${iperf_server} failed, trying next..."
            upload_mbps=0
        done
        if [[ -z "$upload_server" ]]; then
            _print_kv 'Upload' 'N/A (all iperf3 servers failed)' "${C_GREY}"
        fi
    fi

    # Latency test — show average only
    local -a ping_targets=('1.1.1.1' '8.8.8.8' 'cloudflare.com')
    local ping_count=2
    [[ $HABS_FULL -eq 1 ]] && ping_count=10

    for target in "${ping_targets[@]}"; do
        if check_command ping; then
            local ping_result
            ping_result=$(run_with_timeout 15 ping -c "$ping_count" "$target" 2>/dev/null || true)
            local avg
            avg=$(echo "$ping_result" | grep -oP '(?<=rtt min/avg/max/mdev = )[0-9.]+' | cut -d'/' -f2 || echo '0')
            [[ -z "$avg" ]] && avg=0
            latency_results+=("$avg")
        fi
    done

    local total_lat=0 count_lat=0
    for lat in "${latency_results[@]}"; do
        total_lat=$(echo "scale=2; $total_lat + $lat" | bc -l 2>/dev/null || echo '0')
        count_lat=$((count_lat + 1))
    done
    if [[ $count_lat -gt 0 ]]; then
        avg_latency=$(echo "scale=2; $total_lat / $count_lat" | bc -l 2>/dev/null || echo '0')
    fi

    _print_section_footer

    HABS_RESULTS[net_download_mbps]=$best_dl
    HABS_RESULTS[net_best_server]="$best_server"
    HABS_RESULTS[net_upload_mbps]=$upload_mbps
    HABS_RESULTS[net_avg_latency]=$avg_latency
}

# =============================================================================
#  BENCHMARK: ADVANCED CPU (openssl + threaded sysbench)
# =============================================================================

bench_advanced_cpu() {
    _info "Running advanced CPU benchmark..."

    _print_section_header 'Advanced CPU (Multi-threaded + Crypto)'

    local ncores=${HABS_SYSINFO[cpu_cores]:-$(nproc)}
    [[ $ncores -lt 1 ]] && ncores=1

    # sysbench at multiple thread levels
    local max_prime=10000
    [[ $HABS_FULL -eq 1 ]] && max_prime=50000

    local -a thread_levels=(1 2)
    [[ $ncores -ge 4 ]] && thread_levels+=(4)
    thread_levels+=("$ncores")
    local -A seen_t=()
    local -a unique_levels=()
    for t in "${thread_levels[@]}"; do
        [[ -n "${seen_t[$t]:-}" ]] && continue
        seen_t[$t]=1
        unique_levels+=("$t")
    done

    local eps_results=()
    local eps_labels=''
    for threads in "${unique_levels[@]}"; do
        local out
        out=$(run_with_timeout 120 sysbench cpu --cpu-max-prime="$max_prime" --threads="$threads" run 2>/dev/null || true)
        local eps
        eps=$(echo "$out" | grep 'events per second:' | grep -oP '\d+\.?\d*' | head -1 || echo '0')
        [[ -z "$eps" ]] && eps=0
        eps_results+=("$eps")
        eps_labels+="${threads}t:${eps}e "
    done
    _print_kv 'Threaded CPU' "${eps_labels}" "${C_GREEN}"

    HABS_RESULTS[adv_cpu_t1]=${eps_results[0]:-0}
    HABS_RESULTS[adv_cpu_t2]=${eps_results[1]:-0}
    HABS_RESULTS[adv_cpu_t4]=${eps_results[2]:-0}
    HABS_RESULTS[adv_cpu_tN]=${eps_results[-1]:-0}

    # openssl speed for crypto
    if check_command openssl; then
        local openssl_out
        openssl_out=$(run_with_timeout 30 openssl speed -evp aes-256-gcm -bytes 1048576 2>/dev/null || true)
        local aes_speed
        aes_speed=$(echo "$openssl_out" | grep -oP '^\d+\.\d+k' | tail -1 || echo '')
        [[ -z "$aes_speed" ]] && aes_speed=$(echo "$openssl_out" | grep -oP '[\d.]+\s*[kM]' | tail -1 || echo 'N/A')
        HABS_RESULTS[adv_cpu_aes]="$aes_speed"

        openssl_out=$(run_with_timeout 30 openssl speed -evp sha256 -bytes 1048576 2>/dev/null || true)
        local sha_speed
        sha_speed=$(echo "$openssl_out" | grep -oP '^\d+\.\d+k\s*$' | tail -1 || echo '')
        [[ -z "$sha_speed" ]] && sha_speed=$(echo "$openssl_out" | grep -oP '[0-9]+\.[0-9]+[kM]' | tail -1 || echo 'N/A')
        _print_kv 'Crypto' "${aes_speed} AES / ${sha_speed} SHA" "${C_GREEN}"
        HABS_RESULTS[adv_cpu_sha]="$sha_speed"
    fi

    _print_section_footer
}

# =============================================================================
#  BENCHMARK: ADVANCED MEMORY (sysbench multi-block)
# =============================================================================

bench_advanced_memory() {
    _info "Running advanced memory benchmark..."

    _print_section_header 'Advanced Memory (sysbench)'

    ensure_command sysbench sysbench || { _print_line 'sysbench not available'; _print_section_footer; return 1; }

    local total_size='2G'
    [[ $HABS_FULL -eq 1 ]] && total_size='4G'

    local -a block_sizes=('256B' '4K' '64K' '1M')
    declare -A results_read=()

    for block in "${block_sizes[@]}"; do
        local out
        out=$(run_with_timeout 180 sysbench memory --memory-block-size="$block" --memory-total-size="$total_size" --memory-oper=read memory-run 2>/dev/null || true)
        local mbs
        mbs=$(_parse_sysbench_mbs "$out")
        [[ -z "$mbs" ]] && mbs=0
        results_read[$block]=$mbs
    done
    _print_kv 'L1/L2/RAM'    "${results_read[256B]} / ${results_read[4K]} / ${results_read[64K]} MiB/s" "${C_GREEN}"

    _print_section_footer

    HABS_RESULTS[adv_mem_256b]=${results_read[256B]}
    HABS_RESULTS[adv_mem_4k]=${results_read[4K]}
    HABS_RESULTS[adv_mem_64k]=${results_read[64K]}
    HABS_RESULTS[adv_mem_1m]=${results_read[1M]}
}

# =============================================================================
#  BENCHMARK: ADVANCED DISK (fio + ioping)
# =============================================================================

bench_advanced_disk() {
    _info "Running advanced disk benchmark..."

    _print_section_header 'Advanced Disk (fio + ioping)'

    _ensure_tmpdir

    # fio random 4K mixed QD=32
    if ! check_command fio && ! ensure_command fio fio; then
        _print_kv 'FIO 4K'     'N/A' "${C_GREY}"
    else
        local fio_engine='psync'
        if fio --ioengine=io_uring --version &>/dev/null 2>&1; then
            fio_engine='io_uring'
        elif fio --ioengine=libaio --version &>/dev/null 2>&1; then
            fio_engine='libaio'
        fi

        local fio_out
        fio_out=$(run_with_timeout 90 fio --name=randrw --ioengine="$fio_engine" --direct=1 --rw=randrw --rwmixread=70 --bs=4K --iodepth=32 --size=512M --numjobs=1 --runtime=30 --time_based --group_reporting --randrepeat=0 --norandommap --output-format=json 2>/dev/null || true)

        local read_iops=0 write_iops=0 read_lat=0 write_lat=0

        local iops_vals
        iops_vals=$(echo "$fio_out" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    j=d.get('jobs',[{}])[0]
    r=j.get('read',{})
    w=j.get('write',{})
    print(r.get('iops',0))
    print(w.get('iops',0))
    print(r.get('lat_ns',{}).get('mean',0))
    print(w.get('lat_ns',{}).get('mean',0))
except:
    print('0');print('0');print('0');print('0')
" 2>/dev/null) || iops_vals='0 0 0 0'

        read_iops=$(echo "$iops_vals" | sed -n '1p')
        write_iops=$(echo "$iops_vals" | sed -n '2p')
        read_lat=$(echo "$iops_vals" | sed -n '3p')
        write_lat=$(echo "$iops_vals" | sed -n '4p')
        read_lat=$(echo "scale=1; $read_lat / 1000" | bc -l 2>/dev/null || echo "$read_lat")
        write_lat=$(echo "scale=1; $write_lat / 1000" | bc -l 2>/dev/null || echo "$write_lat")

        _print_kv 'FIO 4K'     "$(fmt_number ${read_iops%.*} 0) R / $(fmt_number ${write_iops%.*} 0) W IOPS (${read_lat}/${write_lat} µs)" "${C_GREEN}"

        HABS_RESULTS[adv_disk_fio_read_iops]=${read_iops%.*}
        HABS_RESULTS[adv_disk_fio_write_iops]=${write_iops%.*}
        HABS_RESULTS[adv_disk_fio_read_lat_us]=$read_lat
        HABS_RESULTS[adv_disk_fio_write_lat_us]=$write_lat
    fi

    # ioping latency
    _print_empty
    _print_subheader "ioping — Disk Latency"

    if ! check_command ioping && ! ensure_command ioping ioping; then
        _skip "ioping not available — skipping latency test"
        HABS_RESULTS[adv_disk_ioping_lat_ms]=0
    else
        local ioping_out
        ioping_out=$(run_with_timeout 30 ioping -c 10 -i 0.1 "${HABS_TMPDIR}" 2>/dev/null || true)
        local ioping_lat
        ioping_lat=$(echo "$ioping_out" | grep -oP 'avg=\K[0-9.]+' | head -1 || echo '0')
        [[ -z "$ioping_lat" ]] && ioping_lat=0
        _print_kv 'ioping'      "${ioping_lat} ms" "${C_GREEN}"
        HABS_RESULTS[adv_disk_ioping_lat_ms]=$ioping_lat
    fi

    _print_section_footer
}

# =============================================================================
#  BENCHMARK: ADVANCED NETWORK
# =============================================================================

bench_advanced_network() {
    _info "Running advanced network benchmark..."

    _print_section_header 'Advanced Network'

    # IPv6 download
    if check_command curl; then
        local ipv6_result
        ipv6_result=$(run_with_timeout 20 curl -6 -s -o /dev/null -w '%{speed_download}' --max-time 15 'https://speed.cloudflare.com/__down?bytes=10485760' 2>/dev/null || echo '0')
        local ipv6_mbps
        ipv6_mbps=$(echo "scale=2; $ipv6_result * 8 / 1000000" | bc -l 2>/dev/null || echo '0')
        _print_kv 'IPv6 DL'  "$(fmt_number $ipv6_mbps) Mbps" "${C_GREEN}"
        HABS_RESULTS[adv_net_ipv6_mbps]=$ipv6_mbps
    fi

    # Packet loss
    if check_command ping; then
        local ping_count=4
        [[ $HABS_FULL -eq 1 ]] && ping_count=10
        local pl_result
        pl_result=$(run_with_timeout 20 ping -c "$ping_count" '1.1.1.1' 2>&1 || true)
        local loss_pct
        loss_pct=$(echo "$pl_result" | grep -oP '\d+\.?\d*% packet loss' | grep -oP '\d+\.?\d*(?=%)' | head -1 || echo '100')
        [[ -z "$loss_pct" ]] && loss_pct=100
        _print_kv 'Packet Loss' "${loss_pct}%" "${C_GREEN}"
        HABS_RESULTS[adv_net_packet_loss_pct]=$loss_pct
    fi

    # Traceroute
    if ! check_command traceroute; then
        ensure_command traceroute traceroute || true
    fi
    if check_command traceroute; then
        local tr_out
        tr_out=$(run_with_timeout 30 traceroute -n -q 1 -w 2 '1.1.1.1' 2>&1 || true)
        local hops
        hops=$(echo "$tr_out" | grep -c '^\s*[0-9]' || echo '0')
        [[ -z "$hops" ]] && hops=0
        _print_kv 'Hops to 1.1.1.1' "${hops}" "${C_GREEN}"
        HABS_RESULTS[adv_net_traceroute_hops]=$hops
    elif check_command mtr; then
        _spinner_start "Traceroute to 1.1.1.1 (mtr) ..."
        local tr_out
        tr_out=$(run_with_timeout 30 mtr -r -c 1 -n '1.1.1.1' 2>&1 || true)
        _spinner_stop
        local hops
        hops=$(echo "$tr_out" | grep -c '^[0-9]\.' || echo '0')
        HABS_RESULTS[adv_net_traceroute_hops]=$hops
        _print_kv 'Hops to 1.1.1.1' "${hops}" "${C_GREEN}"
    else
        _skip "Neither traceroute nor mtr found — skipping"
        HABS_RESULTS[adv_net_traceroute_hops]=0
    fi

    _print_section_footer
}

# =============================================================================
#  BENCHMARK: GEEKBENCH 6
# =============================================================================

bench_geekbench6() {
    _info "Running Geekbench 6..."

    _print_section_header 'Geekbench 6'

    _ensure_tmpdir

    local arch
    arch=$(get_arch)
    local gb_url='' gb_dir=''

    # Determine download URL based on architecture
    if [[ $arch == 'x86_64' ]]; then
        gb_url='https://cdn.geekbench.com/Geekbench-6.4.0-Linux.tar.gz'
        gb_dir='Geekbench-6.4.0-Linux'
    elif [[ $arch == 'aarch64' ]]; then
        gb_url='https://cdn.geekbench.com/Geekbench-6.4.0-LinuxARMPremium.tar.gz'
        gb_dir='Geekbench-6.4.0-LinuxARMPremium'
    else
        _print_line "${C_RED}Unsupported architecture for Geekbench 6: ${arch}${C_RESET}"
        _print_section_footer
        return 1
    fi

    local gb_tarball="${HABS_TMPDIR}/geekbench.tar.gz"
    local gb_extract="${HABS_TMPDIR}/geekbench"

    # Download
    _spinner_start "Downloading Geekbench 6 ..."
    local dl_result
    dl_result=$(run_with_timeout 120 curl -sSL -o "$gb_tarball" "$gb_url" 2>&1 || true)
    _spinner_stop

    if [[ ! -f "$gb_tarball" ]] || [[ ! -s "$gb_tarball" ]]; then
        _fail "Failed to download Geekbench 6. Check internet connectivity."
        _print_section_footer
        return 1
    fi

    # Extract
    mkdir -p "$gb_extract"
    tar xzf "$gb_tarball" -C "$gb_extract" 2>/dev/null || true

    HABS_GEK_BIN=$(find "$gb_extract" -name 'geekbench6' -type f 2>/dev/null | head -1)
    if [[ -z "$HABS_GEK_BIN" ]]; then
        HABS_GEK_BIN=$(find "$gb_extract" -name 'geekbench' -type f 2>/dev/null | head -1)
    fi

    if [[ -z "$HABS_GEK_BIN" ]] || [[ ! -x "$HABS_GEK_BIN" ]]; then
        _fail "Geekbench 6 binary not found after extraction"
        _print_section_footer
        return 1
    fi
    _ok "Extracted Geekbench 6"

    # Run
    _print_empty
    _print_line "${C_DIM}Geekbench 6 typically takes 5–10 minutes to complete.${C_RESET}"
    _print_line "${C_DIM}Results are uploaded to the Geekbench Browser automatically.${C_RESET}"
    _print_empty

    _spinner_start "Running Geekbench 6 (this may take a while) ..."
    local gb_out
    gb_out=$(run_with_timeout 900 "$HABS_GEK_BIN" 2>&1 || true)
    _spinner_stop

    local single_score=0 multi_score=0 gb_url_result=''

    # Parse scores from text output
    single_score=$(echo "$gb_out" | grep -oP 'Single-Core Score:\s*\K[0-9]+' | head -1 || echo '0')
    multi_score=$(echo "$gb_out" | grep -oP 'Multi-Core Score:\s*\K[0-9]+' | head -1 || echo '0')
    gb_url_result=$(echo "$gb_out" | grep -oP 'https://browser\.geekbench\.com[^\s]*' | head -1 || echo '')

    # If text parsing failed, try JSON file
    if [[ $single_score -eq 0 ]] && [[ $multi_score -eq 0 ]]; then
        local gb_json
        gb_json=$(find "$HOME/.Geekbench6" -maxdepth 2 -name '*.json' 2>/dev/null | head -1)
        if [[ -n "$gb_json" ]] && [[ -f "$gb_json" ]]; then
            local js_data
            js_data=$(cat "$gb_json")
            single_score=$(echo "$js_data" | grep -oP '"single_score"\s*:\s*\K[0-9]+' | head -1 || echo '0')
            multi_score=$(echo "$js_data" | grep -oP '"multi_score"\s*:\s*\K[0-9]+' | head -1 || echo '0')
            [[ $single_score -eq 0 ]] && single_score=$(echo "$js_data" | grep -oP '"score"\s*:\s*\K[0-9]+' | head -1 || echo '0')
            [[ $multi_score -eq 0 ]] && multi_score=$(echo "$js_data" | grep -oP '"score"\s*:\s*\K[0-9]+' | tail -1 || echo '0')
        fi
    fi

    if [[ $single_score -eq 0 ]] && [[ $multi_score -eq 0 ]]; then
        _fail "Failed to parse Geekbench 6 results"
        _print_line "Raw output:"
        echo "$gb_out" | head -20
    else
        _print_empty
        _print_kv_b 'Single-Core Score'  "${single_score}"
        _print_kv_b 'Multi-Core Score'   "${multi_score}"
    fi

    # Clean up binary to save space
    rm -rf "$gb_extract" 2>/dev/null || true

    _print_section_footer

    HABS_RESULTS[geekbench_single]=$single_score
    HABS_RESULTS[geekbench_multi]=$multi_score
}

# =============================================================================
#  SCORING SYSTEM
# =============================================================================

get_letter_grade() {
    local score=$1
    if (( $(echo "$score >= 97" | bc -l) )); then echo 'A+'
    elif (( $(echo "$score >= 90" | bc -l) )); then echo 'A'
    elif (( $(echo "$score >= 80" | bc -l) )); then echo 'A-'
    elif (( $(echo "$score >= 70" | bc -l) )); then echo 'B+'
    elif (( $(echo "$score >= 60" | bc -l) )); then echo 'B'
    elif (( $(echo "$score >= 50" | bc -l) )); then echo 'B-'
    elif (( $(echo "$score >= 40" | bc -l) )); then echo 'C+'
    elif (( $(echo "$score >= 30" | bc -l) )); then echo 'C'
    elif (( $(echo "$score >= 20" | bc -l) )); then echo 'D'
    else echo 'F'
    fi
}

calculate_scores() {
    _info "Calculating scores..."

    # Baselines (normalization targets)
    local cpu_baseline=100      # 100 events/s single-thread = 25 pts
    local mem_baseline=2000     # 2000 MiB/s read = 25 pts
    local disk_baseline=500     # 500 MB/s avg (1M r/w) = 25 pts
    local net_baseline=500      # 500 Mbps download = 25 pts
    local gb_baseline=500       # 500 single-core score = 25 pts

    local cpu_score=0 mem_score=0 disk_score=0 net_score=0 gb_score=0

    # CPU score
    local single_eps=${HABS_RESULTS[cpu_single_eps]:-0}
    if [[ $(echo "$single_eps > 0" | bc -l) == 1 ]]; then
        cpu_score=$(echo "scale=2; ($single_eps / $cpu_baseline) * 25" | bc -l 2>/dev/null || echo 0)
    fi
    # Cap at 25
    cpu_score=$(echo "scale=2; if ($cpu_score > 25) 25 else $cpu_score" | bc -l 2>/dev/null || echo 0)

    # Memory score
    local mem_read=${HABS_RESULTS[mem_read_mbs]:-0}
    if [[ $(echo "$mem_read > 0" | bc -l) == 1 ]]; then
        mem_score=$(echo "scale=2; ($mem_read / $mem_baseline) * 25" | bc -l 2>/dev/null || echo 0)
    fi
    mem_score=$(echo "scale=2; if ($mem_score > 25) 25 else $mem_score" | bc -l 2>/dev/null || echo 0)

    # Disk score (average of 1M read and write)
    local disk_1mr=${HABS_RESULTS[disk_1m_read_mbs]:-0}
    local disk_1mw=${HABS_RESULTS[disk_1m_write_mbs]:-0}
    local disk_avg=0
    if [[ $(echo "$disk_1mr > 0" | bc -l) == 1 ]] || [[ $(echo "$disk_1mw > 0" | bc -l) == 1 ]]; then
        disk_avg=$(echo "scale=2; ($disk_1mr + $disk_1mw) / 2" | bc -l 2>/dev/null || echo 0)
        disk_score=$(echo "scale=2; ($disk_avg / $disk_baseline) * 25" | bc -l 2>/dev/null || echo 0)
    fi
    disk_score=$(echo "scale=2; if ($disk_score > 25) 25 else $disk_score" | bc -l 2>/dev/null || echo 0)

    # Network score
    local net_dl=${HABS_RESULTS[net_download_mbps]:-0}
    if [[ $(echo "$net_dl > 0" | bc -l) == 1 ]]; then
        net_score=$(echo "scale=2; ($net_dl / $net_baseline) * 25" | bc -l 2>/dev/null || echo 0)
    fi
    net_score=$(echo "scale=2; if ($net_score > 25) 25 else $net_score" | bc -l 2>/dev/null || echo 0)

    # Geekbench score
    local gb_single=${HABS_RESULTS[geekbench_single]:-0}
    if [[ $(echo "$gb_single > 0" | bc -l) == 1 ]]; then
        gb_score=$(echo "scale=2; ($gb_single / $gb_baseline) * 25" | bc -l 2>/dev/null || echo 0)
    fi
    gb_score=$(echo "scale=2; if ($gb_score > 25) 25 else $gb_score" | bc -l 2>/dev/null || echo 0)

    # Total (max 125, normalized to 100)
    local raw_total
    raw_total=$(echo "scale=2; $cpu_score + $mem_score + $disk_score + $net_score + $gb_score" | bc -l 2>/dev/null || echo 0)
    # Normalize: max possible is 125, normalize to 100
    local total=0
    if [[ $(echo "$raw_total > 0" | bc -l) == 1 ]]; then
        total=$(echo "scale=2; ($raw_total / 125) * 100" | bc -l 2>/dev/null || echo 0)
    fi

    # Round to nearest integer
    total=$(echo "scale=0; ($total + 0.5) / 1" | bc -l 2>/dev/null || echo 0)

    local grade
    grade=$(get_letter_grade "$total")

    HABS_SCORES[cpu]=$(echo "scale=2; $cpu_score / 1" | bc -l 2>/dev/null || echo 0)
    HABS_SCORES[memory]=$(echo "scale=2; $mem_score / 1" | bc -l 2>/dev/null || echo 0)
    HABS_SCORES[disk]=$(echo "scale=2; $disk_score / 1" | bc -l 2>/dev/null || echo 0)
    HABS_SCORES[network]=$(echo "scale=2; $net_score / 1" | bc -l 2>/dev/null || echo 0)
    HABS_SCORES[geekbench]=$(echo "scale=2; $gb_score / 1" | bc -l 2>/dev/null || echo 0)
    HABS_SCORES[total]="$total"
    HABS_SCORES[grade]="$grade"

    # Store in results for JSON
    HABS_RESULTS[score_cpu]=${HABS_SCORES[cpu]}
    HABS_RESULTS[score_memory]=${HABS_SCORES[memory]}
    HABS_RESULTS[score_disk]=${HABS_SCORES[disk]}
    HABS_RESULTS[score_network]=${HABS_SCORES[network]}
    HABS_RESULTS[score_geekbench]=${HABS_SCORES[geekbench]}
    HABS_RESULTS[score_total]=$total
    HABS_RESULTS[score_grade]="$grade"
}

# =============================================================================
#  OVERVIEW SUMMARY
# =============================================================================

display_overview() {
    _print_section_header 'Overview'
    _print_kv 'CPU (S/M)'   "$(fmt_number ${HABS_RESULTS[cpu_single_eps]:-0}) / $(fmt_number ${HABS_RESULTS[cpu_multi_eps]:-0}) ev/s (${HABS_RESULTS[cpu_scaling]:-0}x)" "${C_GREEN}"
    _print_kv 'Threaded'    "1t:$(fmt_number ${HABS_RESULTS[adv_cpu_t1]:-0}) 2t:$(fmt_number ${HABS_RESULTS[adv_cpu_t2]:-0}) Nt:$(fmt_number ${HABS_RESULTS[adv_cpu_tN]:-0}) ev/s" "${C_GREEN}"
    _print_kv 'Crypto'      "${HABS_RESULTS[adv_cpu_aes]:-N/A} AES / ${HABS_RESULTS[adv_cpu_sha]:-N/A} SHA" "${C_GREEN}"
    _print_kv 'Memory'      "R:${HABS_RESULTS[mem_read_mbs]:-0} W:${HABS_RESULTS[mem_write_mbs]:-0} MiB/s | L1:${HABS_RESULTS[adv_mem_256b]:-0} L2:${HABS_RESULTS[adv_mem_4k]:-0} MiB/s" "${C_GREEN}"
    _print_kv 'Disk 1M'     "W:${HABS_RESULTS[disk_1m_write_mbs]:-0} R:${HABS_RESULTS[disk_1m_read_mbs]:-0} MB/s" "${C_GREEN}"
    _print_kv 'Disk 4K'     "W:$(fmt_number ${HABS_RESULTS[disk_4k_write_iops]:-0} 0) R:$(fmt_number ${HABS_RESULTS[disk_4k_read_iops]:-0} 0) IOPS | FIO R:$(fmt_number ${HABS_RESULTS[adv_disk_fio_read_iops]:-0} 0)/W:$(fmt_number ${HABS_RESULTS[adv_disk_fio_write_iops]:-0} 0)" "${C_GREEN}"
    _print_kv 'Network'     "DL:${HABS_RESULTS[net_download_mbps]:-0} UL:${HABS_RESULTS[net_upload_mbps]:-0} Mbps | LAT:${HABS_RESULTS[net_avg_latency]:-0}ms IPv6:${HABS_RESULTS[adv_net_ipv6_mbps]:-0} Loss:${HABS_RESULTS[adv_net_packet_loss_pct]:-0}%" "${C_GREEN}"
    _print_kv 'Geekbench 6' "SC:${HABS_RESULTS[geekbench_single]:-0} MC:${HABS_RESULTS[geekbench_multi]:-0}" "${C_GREEN}"
    _print_empty
    _print_kv 'CPU Score'   "$(printf '%.1f' ${HABS_RESULTS[score_cpu]:-0})/25" "${C_GREEN}"
    _print_kv 'Memory Score' "$(printf '%.1f' ${HABS_RESULTS[score_memory]:-0})/25" "${C_GREEN}"
    _print_kv 'Disk Score'  "$(printf '%.1f' ${HABS_RESULTS[score_disk]:-0})/25" "${C_GREEN}"
    _print_kv 'Network Score' "$(printf '%.1f' ${HABS_RESULTS[score_network]:-0})/25" "${C_GREEN}"
    _print_kv 'Geekbench Score' "$(printf '%.1f' ${HABS_RESULTS[score_geekbench]:-0})/25" "${C_GREEN}"
    _print_empty
    _print_kv_b 'Total'     "${HABS_RESULTS[score_total]:-0}/100 (${HABS_RESULTS[score_grade]:-F})"
    _print_section_footer
}

# =============================================================================
#  JSON EXPORT
# =============================================================================

build_json() {
    local json=''
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo 'unknown')

    json+=$'{\n'
    json+="  \"tool\": \"${HABS_NAME}\","$'\n'
    json+="  \"version\": \"${HABS_VERSION}\","$'\n'
    json+="  \"url\": \"${HABS_URL}\","$'\n'
    json+="  \"timestamp\": \"${ts}\","$'\n'
    json+=$'  "system": {\n'
    json+="$(json_kv 'hostname'           "${HABS_SYSINFO[hostname]}" true)"$'\n'
    json+="$(json_kv 'os'                 "${HABS_SYSINFO[os]}" true)"$'\n'
    json+="$(json_kv 'kernel'             "${HABS_SYSINFO[kernel]}" true)"$'\n'
    json+="$(json_kv 'architecture'       "${HABS_SYSINFO[arch]}" true)"$'\n'
    json+="$(json_kv 'virtualization'     "${HABS_SYSINFO[virtualization]}" true)"$'\n'
    json+="$(json_kv 'uptime_seconds'     "${HABS_SYSINFO[uptime_seconds]}" true)"$'\n'
    json+=$'    "cpu": {\n'
    json+="$(json_kv 'model'              "${HABS_SYSINFO[cpu_model]}" true)"$'\n'
    json+="$(json_kv 'physical_cores'     "${HABS_SYSINFO[cpu_physical]}" true)"$'\n'
    json+="$(json_kv 'logical_cores'      "${HABS_SYSINFO[cpu_cores]}" true)"$'\n'
    json+="$(json_kv 'frequency_ghz'      "${HABS_SYSINFO[cpu_freq]}" true)"$'\n'
    json+="$(json_kv 'l1d_cache'          "${HABS_SYSINFO[cpu_cache_l1d]:-null}" true)"$'\n'
    json+="$(json_kv 'l2_cache'           "${HABS_SYSINFO[cpu_cache_l2]:-null}" true)"$'\n'
    json+="$(json_kv 'l3_cache'           "${HABS_SYSINFO[cpu_cache_l3]:-null}" true)"$'\n'
    json+="$(json_kv 'has_aes'            "${HABS_SYSINFO[has_aes]}" true)"$'\n'
    json+="$(json_kv 'has_avx'            "${HABS_SYSINFO[has_avx]}" true)"$'\n'
    json+="$(json_kv 'has_avx2'           "${HABS_SYSINFO[has_avx2]}" true)"$'\n'
    json+="$(json_kv 'has_avx512'         "${HABS_SYSINFO[has_avx512]}" true)"$'\n'
    json+="$(json_kv 'has_sse4_2'         "${HABS_SYSINFO[has_sse4_2]}" true)"$'\n'
    json+="$(json_kv 'has_neon'           "${HABS_SYSINFO[has_neon]}" true)"$'\n'
    json+="$(json_kv 'has_sve'            "${HABS_SYSINFO[has_sve]}" false)"$'\n'
    json+=$'    },\n'
    json+=$'    "memory": {\n'
    json+="$(json_kv 'ram_total_bytes'    "${HABS_SYSINFO[ram_total]}" true)"$'\n'
    json+="$(json_kv 'ram_used_bytes'     "${HABS_SYSINFO[ram_used]}" true)"$'\n'
    json+="$(json_kv 'ram_available_bytes'  "${HABS_SYSINFO[ram_available]}" true)"$'\n'
    json+="$(json_kv 'swap_total_bytes'   "${HABS_SYSINFO[swap_total]}" true)"$'\n'
    json+="$(json_kv 'swap_used_bytes'    "${HABS_SYSINFO[swap_used]}" true)"$'\n'
    json+="$(json_kv 'swap_free_bytes'    "${HABS_SYSINFO[swap_free]}" false)"$'\n'
    json+=$'    },\n'
    json+=$'    "storage": {\n'
    json+="$(json_kv 'disk_total_bytes'   "${HABS_SYSINFO[disk_total]}" true)"$'\n'
    json+="$(json_kv 'disk_used_bytes'    "${HABS_SYSINFO[disk_used]}" true)"$'\n'
    json+="$(json_kv 'disk_avail_bytes'   "${HABS_SYSINFO[disk_avail]}" true)"$'\n'
    json+="$(json_kv 'disk_usage_pct'     "${HABS_SYSINFO[disk_usage_pct]}" true)"$'\n'
    json+="$(json_kv 'filesystem'         "${HABS_SYSINFO[filesystem]}" true)"$'\n'
    json+="$(json_kv 'mount_options'      "${HABS_SYSINFO[mount_options]}" false)"$'\n'
    json+=$'    },\n'
    json+=$'    "network": {\n'
    json+="$(json_kv 'ipv4'               "${HABS_SYSINFO[ipv4]:-null}" true)"$'\n'
    json+="$(json_kv 'ipv6'               "${HABS_SYSINFO[ipv6]:-null}" true)"$'\n'
    json+="$(json_kv 'interfaces'         "${HABS_SYSINFO[interfaces]:-null}" false)"$'\n'
    json+=$'    },\n'
    json+=$'    "load": {\n'
    json+="$(json_kv 'load_1'             "${HABS_SYSINFO[load_1]:-0}" true)"$'\n'
    json+="$(json_kv 'load_5'             "${HABS_SYSINFO[load_5]:-0}" true)"$'\n'
    json+="$(json_kv 'load_15'            "${HABS_SYSINFO[load_15]:-0}" false)"$'\n'
    json+=$'    }\n'
    json+=$'  },\n'

    # Duration
    local duration=$(( HABS_END_TIME - HABS_START_TIME ))
    json+="  \"duration_seconds\": ${duration},"$'\n'

    # Benchmarks
    json+=$'  "benchmarks": {\n'

    # CPU
    json+=$'    "cpu": {\n'
    json+="$(json_kv 'single_events_per_sec'  "${HABS_RESULTS[cpu_single_eps]:-0}" true)"$'\n'
    json+="$(json_kv 'multi_events_per_sec'   "${HABS_RESULTS[cpu_multi_eps]:-0}" true)"$'\n'
    json+="$(json_kv 'scaling_ratio'          "${HABS_RESULTS[cpu_scaling]:-0}" true)"$'\n'
    json+="$(json_kv 'threads'                "${HABS_RESULTS[cpu_threads]:-0}" true)"$'\n'
    json+="$(json_kv 'max_prime'              "${HABS_RESULTS[cpu_max_prime]:-0}" false)"$'\n'
    json+=$'    },\n'

    # Memory
    json+=$'    "memory": {\n'
    json+="$(json_kv 'read_mib_per_sec'   "${HABS_RESULTS[mem_read_mbs]:-0}" true)"$'\n'
    json+="$(json_kv 'write_mib_per_sec'  "${HABS_RESULTS[mem_write_mbs]:-0}" false)"$'\n'
    json+=$'    },\n'

    # Disk
    json+=$'    "disk": {\n'
    json+="$(json_kv '1m_write_mb_per_sec'  "${HABS_RESULTS[disk_1m_write_mbs]:-0}" true)"$'\n'
    json+="$(json_kv '1m_read_mb_per_sec'   "${HABS_RESULTS[disk_1m_read_mbs]:-0}" true)"$'\n'
    json+="$(json_kv '4k_write_mb_per_sec'  "${HABS_RESULTS[disk_4k_write_mbs]:-0}" true)"$'\n'
    json+="$(json_kv '4k_read_mb_per_sec'   "${HABS_RESULTS[disk_4k_read_mbs]:-0}" true)"$'\n'
    json+="$(json_kv '4k_write_iops'        "${HABS_RESULTS[disk_4k_write_iops]:-0}" true)"$'\n'
    json+="$(json_kv '4k_read_iops'         "${HABS_RESULTS[disk_4k_read_iops]:-0}" false)"$'\n'
    json+=$'    },\n'

    # Network
    json+=$'    "network": {\n'
    json+="$(json_kv 'download_mbps'   "${HABS_RESULTS[net_download_mbps]:-0}" true)"$'\n'
    json+="$(json_kv 'upload_mbps'     "${HABS_RESULTS[net_upload_mbps]:-0}" true)"$'\n'
    json+="$(json_kv 'avg_latency_ms'  "${HABS_RESULTS[net_avg_latency]:-0}" true)"$'\n'
    json+="$(json_kv 'best_server'     "${HABS_RESULTS[net_best_server]:-}" false)"$'\n'
    json+=$'    },\n'

    # Geekbench 6
    json+=$'    "geekbench_6": {\n'
    json+="$(json_kv 'single_core_score'  "${HABS_RESULTS[geekbench_single]:-0}" true)"$'\n'
    json+="$(json_kv 'multi_core_score'   "${HABS_RESULTS[geekbench_multi]:-0}" false)"$'\n'
    json+=$'    },\n'

    # Advanced CPU
    json+=$'    "advanced_cpu": {\n'
    json+="$(json_kv 'threaded_1t'     "${HABS_RESULTS[adv_cpu_t1]:-0}" true)"$'\n'
    json+="$(json_kv 'threaded_2t'     "${HABS_RESULTS[adv_cpu_t2]:-0}" true)"$'\n'
    json+="$(json_kv 'threaded_4t'     "${HABS_RESULTS[adv_cpu_t4]:-0}" true)"$'\n'
    json+="$(json_kv 'threaded_nt'     "${HABS_RESULTS[adv_cpu_tN]:-0}" true)"$'\n'
    json+="$(json_kv 'aes_256_gcm'     "${HABS_RESULTS[adv_cpu_aes]:-0}" true)"$'\n'
    json+="$(json_kv 'sha_256'         "${HABS_RESULTS[adv_cpu_sha]:-0}" false)"$'\n'
    json+=$'    },\n'

    # Advanced Memory
    json+=$'    "advanced_memory": {\n'
    json+="$(json_kv '256b_read_mib_per_sec'  "${HABS_RESULTS[adv_mem_256b]:-0}" true)"$'\n'
    json+="$(json_kv '4k_read_mib_per_sec'    "${HABS_RESULTS[adv_mem_4k]:-0}" true)"$'\n'
    json+="$(json_kv '64k_read_mib_per_sec'   "${HABS_RESULTS[adv_mem_64k]:-0}" true)"$'\n'
    json+="$(json_kv '1m_read_mib_per_sec'    "${HABS_RESULTS[adv_mem_1m]:-0}" false)"$'\n'
    json+=$'    },\n'

    # Advanced Disk
    json+=$'    "advanced_disk": {\n'
    json+="$(json_kv 'fio_random_4k_read_iops'   "${HABS_RESULTS[adv_disk_fio_read_iops]:-0}" true)"$'\n'
    json+="$(json_kv 'fio_random_4k_write_iops'  "${HABS_RESULTS[adv_disk_fio_write_iops]:-0}" true)"$'\n'
    json+="$(json_kv 'fio_random_4k_read_lat_us'  "${HABS_RESULTS[adv_disk_fio_read_lat_us]:-0}" true)"$'\n'
    json+="$(json_kv 'fio_random_4k_write_lat_us' "${HABS_RESULTS[adv_disk_fio_write_lat_us]:-0}" true)"$'\n'
    json+="$(json_kv 'ioping_latency_ms'          "${HABS_RESULTS[adv_disk_ioping_lat_ms]:-0}" false)"$'\n'
    json+=$'    },\n'

    # Advanced Network
    json+=$'    "advanced_network": {\n'
    json+="$(json_kv 'ipv6_download_mbps'  "${HABS_RESULTS[adv_net_ipv6_mbps]:-0}" true)"$'\n'
    json+="$(json_kv 'packet_loss_pct'     "${HABS_RESULTS[adv_net_packet_loss_pct]:-0}" true)"$'\n'
    json+="$(json_kv 'traceroute_hops'     "${HABS_RESULTS[adv_net_traceroute_hops]:-0}" false)"$'\n'
    json+=$'    }\n'

    json+=$'  },\n'

    # Scores
    local total=${HABS_SCORES[total]:-0}
    local grade=${HABS_SCORES[grade]:-F}
    json+=$'  "scores": {\n'
    json+="$(json_kv 'cpu'       "${HABS_SCORES[cpu]:-0}" true)"$'\n'
    json+="$(json_kv 'memory'    "${HABS_SCORES[memory]:-0}" true)"$'\n'
    json+="$(json_kv 'disk'      "${HABS_SCORES[disk]:-0}" true)"$'\n'
    json+="$(json_kv 'network'   "${HABS_SCORES[network]:-0}" true)"$'\n'
    json+="$(json_kv 'geekbench' "${HABS_SCORES[geekbench]:-0}" true)"$'\n'
    json+="$(json_kv 'total'     "${total}" true)"$'\n'
    json+="$(json_kv 'max'       "100" true)"$'\n'
    json+="$(json_kv 'grade'     "${grade}" false)"$'\n'
    json+=$'  }\n'
    json+=$'}\n'

    echo "$json"
}

output_json() {
    local json
    json=$(build_json)

    if [[ -n "$HABS_OUTPUT_FILE" ]]; then
        echo "$json" > "$HABS_OUTPUT_FILE"
        _ok "Results saved to ${HABS_OUTPUT_FILE}"
    fi

    if [[ $HABS_JSON -eq 1 ]]; then
        echo "$json"
    fi
}

# =============================================================================
#  MAIN ORCHESTRATOR
# =============================================================================

print_banner() {
    local tw
    tw=$(get_term_width)
    local banner_width=60
    [[ $tw -lt 66 ]] && banner_width=$((tw - 6))
    local padding=$(( (tw - banner_width) / 2 - 2 ))
    [[ $padding -lt 0 ]] && padding=0

    local pad_str
    pad_str=$(printf '%*s' "$padding" '')

    echo ""
    printf "%s${C_BOLD}${C_CYAN} ╔════════════════════════════════════════════════════════╗${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║                                                                ║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_BOLD}${C_WHITE}██╗  ██╗ █████╗ ██████╗ ███████╗${C_RESET}                      ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_BOLD}${C_WHITE}██║  ██║██╔══██╗██╔══██╗██╔════╝${C_RESET}                      ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_BOLD}${C_WHITE}███████║███████║██████╔╝███████╗${C_RESET}                      ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_BOLD}${C_WHITE}██╔══██║██╔══██║██╔══██╗╚════██║${C_RESET}                      ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_BOLD}${C_WHITE}██║  ██║██║  ██║██████╔╝███████║${C_RESET}                      ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_BOLD}${C_WHITE}╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝${C_RESET}                      ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║                                                                ║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_GREY}Hyper Absolute Benchmark Script${C_RESET}                      ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_GREY}Version ${HABS_VERSION}${C_RESET}                                        ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║${C_RESET}  ${C_GREY}github.com/anjarman20/Hyper-Absolute-Benchmark-Script${C_RESET}  ${C_BOLD}${C_CYAN}║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ║                                                                ║${C_RESET}\n" "$pad_str"
    printf "%s${C_BOLD}${C_CYAN} ╚════════════════════════════════════════════════════════╝${C_RESET}\n" "$pad_str"
    echo ""
}

print_config_banner() {
    local skipped=''
    [[ $HABS_SKIP_CPU -eq 1 ]] && skipped+=' cpu'
    [[ $HABS_SKIP_MEMORY -eq 1 ]] && skipped+=' memory'
    [[ $HABS_SKIP_DISK -eq 1 ]] && skipped+=' disk'
    [[ $HABS_SKIP_NETWORK -eq 1 ]] && skipped+=' network'
    [[ $HABS_SKIP_GEEKBENCH -eq 1 ]] && skipped+=' geekbench6'
    [[ $HABS_SKIP_ADVANCED -eq 1 ]] && skipped+=' advanced'
    local enabled=''

    local mode='standard'
    [[ $HABS_QUICK -eq 1 ]] && mode='quick'
    [[ $HABS_FULL -eq 1 ]] && mode='full'

    _print_section_header 'Configuration'
    _print_kv 'Mode'     "${mode}" "${C_CYAN}"
    if [[ -n "$skipped" ]]; then
        _print_kv 'Skipped' "${skipped}" "${C_YELLOW}"
    else
        _print_kv 'Skipped' 'none' "${C_GREEN}"
    fi
    if [[ -n "$enabled" ]]; then
        _print_kv 'Enabled' "${enabled}" "${C_GREEN}"
    fi
    _print_kv 'JSON'     "$([[ $HABS_JSON -eq 1 ]] && echo 'enabled' || echo 'disabled')" "${C_CYAN}"
    _print_kv 'Output'   "${HABS_OUTPUT_FILE:-stdout}" "${C_CYAN}"
    _print_section_footer
    echo ""
}

print_header() {
    print_banner
    print_config_banner
}

print_footer() {
    echo ""
    _print_section_header 'Complete'
    local duration=$(( HABS_END_TIME - HABS_START_TIME ))
    _print_line "${C_GREEN}Benchmark suite completed in $(fmt_duration $duration).${C_RESET}"
    _print_line "${C_GREY}${HABS_NAME} v${HABS_VERSION} — ${HABS_COPYRIGHT}${C_RESET}"
    _print_section_footer
    echo ""
}

show_help() {
    cat <<EOF
${C_BOLD}${HABS_NAME} — Hyper Absolute Benchmark Script v${HABS_VERSION}${C_RESET}
${C_GREY}${HABS_URL}${C_RESET}

Usage:  bash habs.sh [options]

Options:
  -h, --help            Show this help message
  --version             Print version
  --skip-cpu            Skip CPU benchmarks (standard + advanced)
  --skip-memory         Skip memory benchmarks (standard + advanced)
  --skip-disk           Skip disk benchmarks (standard + advanced)
  --skip-network        Skip network benchmarks (standard + advanced)
  --skip-geekbench      Skip Geekbench 6
  --skip-advanced       Skip all advanced benchmarks
  --skip-y-cruncher     Skip y-cruncher benchmark
  --enable-unixbench   Enable UnixBench (disabled by default, requires gcc+make+perl)
  --quick, -q           Quick mode — shorter tests
  --full, -f            Full mode — comprehensive tests
  --json                Output results as JSON to stdout
  --output FILE         Save results to file
  --no-color            Disable colored output
  --verbose, -v         Enable verbose/debug output

Examples:
  bash habs.sh                          Run all benchmarks
  bash habs.sh --quick                  Quick overview
  bash habs.sh --skip-network           Skip network tests
  bash habs.sh --json --output results.json  Export JSON
  bash habs.sh --skip-geekbench         Skip Geekbench 6

${C_GREY}All benchmarks run by default. Use --skip-* to exclude.${C_RESET}
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)           show_help; exit 0 ;;
            --version)           echo "${HABS_NAME} v${HABS_VERSION}"; exit 0 ;;
            --skip-cpu)          HABS_SKIP_CPU=1 ;;
            --skip-memory)       HABS_SKIP_MEMORY=1 ;;
            --skip-disk)         HABS_SKIP_DISK=1 ;;
            --skip-network)      HABS_SKIP_NETWORK=1 ;;
            --skip-geekbench)    HABS_SKIP_GEEKBENCH=1 ;;
            --skip-advanced)     HABS_SKIP_ADVANCED=1 ;;
            --skip-y-cruncher)   HABS_SKIP_YCRUNCHER=1 ;;
            --enable-unixbench)          HABS_SKIP_UNIXBENCH=0 ;;
            --quick|-q)          HABS_QUICK=1 ;;
            --full|-f)           HABS_FULL=1 ;;
            --json)              HABS_JSON=1 ;;
            --output)            shift; HABS_OUTPUT_FILE="$1" ;;
            --no-color)          HABS_NOCOLOR=1; _init_colors ;;
            --verbose|-v)        HABS_VERBOSE=1 ;;
            *)                   _error "Unknown option: $1"; show_help >&2; exit 1 ;;
        esac
        shift
    done

    # Quick and full are mutually exclusive
    if [[ $HABS_QUICK -eq 1 ]] && [[ $HABS_FULL -eq 1 ]]; then
        HABS_FULL=0  # Default to quick
    fi
}

_install_deps() {
    local install_list=()
    [[ $HABS_SKIP_CPU -eq 0 ]]          && install_list+=(sysbench)
    [[ $HABS_SKIP_MEMORY -eq 0 ]]        && install_list+=(sysbench)
    [[ $HABS_SKIP_DISK -eq 0 ]]          && install_list+=(fio ioping)
    [[ $HABS_SKIP_NETWORK -eq 0 ]]       && install_list+=(iperf3)
    [[ $HABS_SKIP_ADVANCED -eq 0 ]]      && install_list+=(traceroute)
    [[ $HABS_SKIP_GEEKBENCH -eq 0 ]]     && true

    local -A seen=()
    for pkg in "${install_list[@]}"; do
        [[ -n "${seen[$pkg]:-}" ]] && continue
        seen[$pkg]=1
        if ! check_command "$pkg"; then
            echo -ne "  ${C_YELLOW}⟳${C_RESET} Installing ${pkg} ... "
            if auto_install "$pkg" &>/dev/null; then
                echo -e "${C_GREEN}done${C_RESET}"
            else
                echo -e "${C_YELLOW}skipped${C_RESET} (run as root to auto-install)"
            fi
        fi
    done
}

main() {
    HABS_START_TIME=$(date +%s)

    parse_args "$@"
    _init_colors

    # JSON-only mode: silence all stdout output except JSON itself
    local json_silent=0
    if [[ $HABS_JSON -eq 1 ]] && [[ -z "$HABS_OUTPUT_FILE" ]] && [[ $HABS_VERBOSE -eq 0 ]]; then
        json_silent=1
        exec 3>&1       # Save original stdout to fd 3
        exec 1>/dev/null # Redirect all normal stdout to /dev/null
    fi

    local show_output=0
    [[ $json_silent -eq 0 ]] && show_output=1

    # Pre-flight: install all needed dependencies
    if [[ $show_output -eq 1 ]]; then
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}──${C_RESET}  ${C_BOLD}HABS${C_RESET} — checking dependencies ..."
        _install_deps
        command -v clear &>/dev/null && clear 2>/dev/null || printf '\033[2J\033[H'
    fi

    gather_system_info

    if [[ $show_output -eq 1 ]]; then
        print_header
        display_system_info
        echo ""
        # Compact mode: benchmarks run silently, results in Overview
        HABS_COMPACT=1
    fi

    # Run benchmarks (each wrapped with || true to prevent set -e from aborting)
    if [[ $HABS_SKIP_CPU -eq 0 ]]; then
        bench_cpu || true
    fi

    if [[ $HABS_SKIP_MEMORY -eq 0 ]]; then
        bench_memory || true
    fi

    if [[ $HABS_SKIP_DISK -eq 0 ]]; then
        bench_disk || true
    fi

    if [[ $HABS_SKIP_NETWORK -eq 0 ]]; then
        bench_network || true
    fi

    if [[ $HABS_SKIP_GEEKBENCH -eq 0 ]]; then
        bench_geekbench6 || true
    fi

    if [[ $HABS_SKIP_ADVANCED -eq 0 ]]; then
        bench_advanced_cpu || true
        bench_advanced_memory || true
        bench_advanced_disk || true
        bench_advanced_network || true
    fi

    HABS_END_TIME=$(date +%s)

    # Restore normal display for overview
    HABS_COMPACT=0

    # Calculate scores and show overview
    calculate_scores
    if [[ $show_output -eq 1 ]]; then
        echo ""
        display_overview
    fi

    # Restore stdout before JSON output
    if [[ $json_silent -eq 1 ]]; then
        exec 1>&3-      # Restore stdout, close fd 3
    fi

    # Output JSON if requested (writes to true stdout)
    if [[ $HABS_JSON -eq 1 ]] || [[ -n "$HABS_OUTPUT_FILE" ]]; then
        output_json
    fi

    # Print completion footer
    if [[ $show_output -eq 1 ]]; then
        print_footer
    fi
}

# -------- Entry Point --------------------------------------------------------
main "$@"
