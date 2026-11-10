#!/bin/bash
# stages/lib.sh — shared plumbing for every dots-linux installer stage.
#
# Environment contract (set by ./install, safe to override when running a
# stage by hand):
#   DRY_RUN=true|false      Skip every mutating command (default: false)
#   HOST_PROFILE=auto|imac18-3|vm|none   Hardware profile to target
#   WITH_EXTRAS=true|false  Stage 60 honors this
#   WITH_MANGO=true|false   Stow the 'mango' package (stages 40 & 60)
#   PROFILE=minimal|full|custom
#   LOG_FILE=path           Installer log (default: <repo>/setup.log)
#
# Every UI helper prefers `gum` and degrades gracefully to pure bash (no
# symbols mangled when piped / NO_COLOR set). run_cmd() logs to setup.log and
# is the ONLY way stages should execute mutating commands — it is what makes
# --dry-run work end-to-end.

DOTS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${LOG_FILE:-$DOTS_ROOT/setup.log}"
DRY_RUN="${DRY_RUN:-false}"
HOST_PROFILE="${HOST_PROFILE:-auto}"
WITH_EXTRAS="${WITH_EXTRAS:-false}"
WITH_MANGO="${WITH_MANGO:-false}"
PROFILE="${PROFILE:-custom}"
ASSUME_YES="${ASSUME_YES:-false}"

# ---------------------------------------------------------------- colors ----
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RST=$'\e[0m';  C_BLD=$'\e[1m'
    C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'
    C_BLU=$'\e[34m'; C_MAG=$'\e[35m'; C_CYN=$'\e[36m'; C_GRY=$'\e[90m'
else
    C_RST=""; C_BLD=""
    C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_MAG=""; C_CYN=""; C_GRY=""
fi

GUM_BIN="$(command -v gum 2>/dev/null || true)"

# --------------------------------------------------------------- helpers ----
have()        { command -v "$1" &>/dev/null; }
is_dry_run()  { [[ "$DRY_RUN" == "true" ]]; }

log() { # log LEVEL MESSAGE...
    local lvl="$1"; shift
    printf '%s [%s] %s\n' "$(date '+%F %T')" "$lvl" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

# Detect the hardware profile: iMac18,3 -> imac18-3, any VM -> vm, else none.
detect_host_profile() {
    local product="" virt=""
    [[ -r /sys/devices/virtual/dmi/id/product_name ]] && product="$(</sys/devices/virtual/dmi/id/product_name)"
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    if [[ "$product" == "iMac18,3" ]]; then
        echo "imac18-3"
        return
    fi
    case "$virt" in
        qemu|kvm|vmware|bochs|microsoft|xen) echo "vm" ;;
        *)                                   echo "none" ;;
    esac
}

# Resolve HOST_PROFILE=auto exactly once per stage.
resolve_host_profile() {
    if [[ "$HOST_PROFILE" == "auto" ]]; then
        HOST_PROFILE="$(detect_host_profile)"
    fi
}

ensure_sudo() { # make sure we have cached sudo credentials (skipped in dry-run)
    is_dry_run && return 0
    (( EUID == 0 )) && return 0
    sudo -n true 2>/dev/null && return 0
    ui_info "sudo credentials are needed for system-level changes:"
    sudo -v || { ui_error "sudo authentication failed"; return 1; }
}

# ------------------------------------------------------------- gum-ish UI ----
ui_header() { # big section banner
    log STAGE "=== $* ==="
    if [[ -n "$GUM_BIN" && -t 1 ]]; then
        gum style --border rounded --border-foreground 212 --foreground 213 \
            --padding '0 3' --margin '1 0' --bold -- "$*"
    else
        printf '\n %s%s\n  %s\n %s%s\n' \
            "$C_MAG" "$(printf '━%.0s' {1..40})" \
            "${C_BLD}${C_MAG}$*${C_RST}" \
            "$(printf '━%.0s' {1..40})" "$C_RST"
    fi
}

ui_step()  { printf '  %s✔%s %s\n' "$C_GRN" "$C_RST" "$*"; log OK "$*"; }
ui_info()  { printf '  %s•%s %s\n' "$C_CYN" "$C_RST" "$*"; log INFO "$*"; }
ui_warn()  { printf '  %s⚠%s  %s\n' "$C_YLW" "$C_RST" "$*"; log WARN "$*"; }
ui_error() { printf '  %s✖%s %s\n' "$C_RED" "$C_RST" "$*" >&2; log ERROR "$*"; }
ui_dry()   { printf '  %s[dry-run]%s %s\n' "$C_YLW" "$C_RST" "$*"; log DRY "$*"; }

ui_confirm() { # ui_confirm PROMPT -> rc 0 = yes
    if [[ "$ASSUME_YES" == "true" ]]; then
        ui_info "$* (assuming yes)"
        return 0
    fi
    if [[ -n "$GUM_BIN" && -t 0 && -t 1 ]]; then
        gum confirm "$*"
        return
    fi
    local ans
    ans="$(ui_choose "$*" "Yes — proceed" "No — abort / skip")" || return 1
    [[ "$ans" == "Yes — proceed" ]]
}

ui_choose() { # ui_choose PROMPT opt1 opt2... -> echoes picked option
    local prompt="$1"; shift
    if [[ -n "$GUM_BIN" && -t 0 && -t 1 ]]; then
        gum choose --header "$prompt" "$@"
        return
    fi

    local -a opts=("$@")
    local count=${#opts[@]}
    local selected=0
    local key rest

    # Non-interactive / piped fallback
    if [[ ! -t 0 || ! -t 1 ]]; then
        local line
        if read -r line 2>/dev/null; then
            for opt in "${opts[@]}"; do
                [[ "$opt" == "$line" ]] && { printf '%s\n' "$opt"; return 0; }
            done
        fi
        printf '%s\n' "${opts[0]}"
        return 0
    fi

    printf '\e[?25l' >&2
    trap 'printf "\e[?25h" >&2' RETURN INT TERM

    printf '%s\n' "$prompt" >&2
    for ((i=0; i<count; i++)); do
        if (( i == selected )); then
            printf '  %s●%s %s%s%s\n' "$C_CYN" "$C_RST" "$C_BLD" "${opts[i]}" "$C_RST" >&2
        else
            printf '  %s○ %s%s\n' "$C_GRY" "${opts[i]}" "$C_RST" >&2
        fi
    done

    while :; do
        IFS= read -rsn1 key
        if [[ "$key" == $'\e' ]]; then
            read -rsn2 -t 0.05 rest || rest=""
            key+="$rest"
        fi

        case "$key" in
            $'\e[A'|k|K) # Up
                (( selected > 0 )) && (( selected-- )) || selected=$(( count - 1 ))
                ;;
            $'\e[B'|j|J) # Down
                (( selected < count - 1 )) && (( selected++ )) || selected=0
                ;;
            "") # Enter
                break
                ;;
            [1-9])
                local num=$(( key - 1 ))
                if (( num >= 0 && num < count )); then
                    selected=$num
                    break
                fi
                ;;
            q|Q)
                return 1
                ;;
        esac

        printf '\e[%dA' "$count" >&2
        for ((i=0; i<count; i++)); do
            printf '\e[2K' >&2
            if (( i == selected )); then
                printf '  %s●%s %s%s%s\n' "$C_CYN" "$C_RST" "$C_BLD" "${opts[i]}" "$C_RST" >&2
            else
                printf '  %s○ %s%s\n' "$C_GRY" "${opts[i]}" "$C_RST" >&2
            fi
        done
    done

    printf '\e[?25h' >&2
    trap - RETURN INT TERM
    printf '%s\n' "${opts[selected]}"
}

ui_choose_multi() { # ui_choose_multi PROMPT opt1 opt2... -> one pick per line
    local prompt="$1"; shift
    if [[ -n "$GUM_BIN" && -t 0 && -t 1 ]]; then
        gum choose --no-limit --header "$prompt" "$@"
        return
    fi

    local -a opts=("$@")
    local count=${#opts[@]}
    local selected=0
    local key rest
    local -a marked=()
    for ((i=0; i<count; i++)); do marked[i]=0; done

    # Non-interactive / piped fallback
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf '%s\n' "${opts[@]}"
        return 0
    fi

    printf '\e[?25l' >&2
    trap 'printf "\e[?25h" >&2' RETURN INT TERM

    printf '%s %s(Use arrows, Space to toggle, Enter to confirm)%s\n' "$prompt" "$C_GRY" "$C_RST" >&2
    for ((i=0; i<count; i++)); do
        local check="[ ]"
        (( marked[i] )) && check="[✔]"
        if (( i == selected )); then
            printf '  %s%s %s%s%s\n' "$C_CYN" "$check" "$C_BLD" "${opts[i]}" "$C_RST" >&2
        else
            printf '  %s%s %s%s\n' "$C_GRY" "$check" "${opts[i]}" "$C_RST" >&2
        fi
    done

    while :; do
        IFS= read -rsn1 key
        if [[ "$key" == $'\e' ]]; then
            read -rsn2 -t 0.05 rest || rest=""
            key+="$rest"
        fi

        case "$key" in
            $'\e[A'|k|K)
                (( selected > 0 )) && (( selected-- )) || selected=$(( count - 1 ))
                ;;
            $'\e[B'|j|J)
                (( selected < count - 1 )) && (( selected++ )) || selected=0
                ;;
            " ") # Space toggles
                (( marked[selected] = 1 - marked[selected] ))
                ;;
            "") # Enter confirms
                break
                ;;
            q|Q)
                return 1
                ;;
        esac

        printf '\e[%dA' "$count" >&2
        for ((i=0; i<count; i++)); do
            printf '\e[2K' >&2
            local check="[ ]"
            (( marked[i] )) && check="[✔]"
            if (( i == selected )); then
                printf '  %s%s %s%s%s\n' "$C_CYN" "$check" "$C_BLD" "${opts[i]}" "$C_RST" >&2
            else
                printf '  %s%s %s%s\n' "$C_GRY" "$check" "${opts[i]}" "$C_RST" >&2
            fi
        done
    done

    printf '\e[?25h' >&2
    trap - RETURN INT TERM

    local any=0
    for ((i=0; i<count; i++)); do
        if (( marked[i] )); then
            printf '%s\n' "${opts[i]}"
            any=1
        fi
    done
    if (( any == 0 )); then
        printf '%s\n' "${opts[selected]}"
    fi
}

# ------------------------------------------------------------ run_cmd -------
run_cmd() { # run_cmd DESCRIPTION COMMAND [ARGS...]
    local desc="$1"; shift
    log RUN "$*"
    if is_dry_run; then
        ui_dry "$desc ${C_GRY}($*)${C_RST}"
        return 0
    fi

    local out rc=0
    out="$(mktemp)"

    if [[ -n "$GUM_BIN" && -t 1 ]]; then
        gum spin --spinner dot --title "  $desc …" -- "$@" >"$out" 2>&1 || rc=$?
    elif [[ -t 1 ]]; then
        # pure-bash braille spinner fallback
        local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 cols
        cols="$(tput cols 2>/dev/null || echo 80)"
        "$@" >"$out" 2>&1 &
        local pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            i=$(( (i + 1) % ${#spin} ))
            printf '\r  %s %s' "${spin:$i:1}" "$desc" >&2
            sleep 0.08
        done
        wait "$pid" || rc=$?
        printf '\r%*s\r' "$cols" "" >&2
    else
        printf '  %s…%s %s\n' "$C_GRY" "$C_RST" "$desc"
        "$@" >"$out" 2>&1 || rc=$?
    fi

    cat "$out" >> "$LOG_FILE" 2>/dev/null || true
    if (( rc == 0 )); then
        ui_step "$desc"
    else
        ui_error "$desc failed (exit $rc) — last output:"
        tail -n 5 "$out" | sed 's/^/      /' >&2
        log FAIL "$desc (rc=$rc)"
    fi
    rm -f "$out"
    return "$rc"
}

# install_file MODE SRC DEST [DESC] — install -D; auto-sudo for system paths.
install_file() {
    local mode="$1" src="$2" dest="$3"
    local desc="${4:-$(basename "$src") → $dest}"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest" 2>/dev/null; then
        ui_step "$desc (already up to date)"
        return 0
    fi
    local -a cmd=(install -Dm "$mode" "$src" "$dest")
    case "$dest" in
        /etc/*|/usr/*|/opt/*|/var/*) run_cmd "$desc" sudo "${cmd[@]}" || ui_warn "Could not install $dest — continuing." ;;
        *)                           run_cmd "$desc" "${cmd[@]}" || ui_warn "Could not install $dest — continuing." ;;
    esac
}

# copy_tree SRC DEST DESC — copy *contents* of SRC into DEST (mkdir -p first).
copy_tree() {
    local src="$1" dest="$2" desc="$3"
    is_dry_run || mkdir -p "$dest"
    run_cmd "$desc" cp -a "$src/." "$dest/"
}

# read a manifest into an array (strips comments + blank lines)
read_manifest() { # read_manifest FILE -> prints one entry per line
    grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || true
}
