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
# The UI is pure bash (no gum dependency): prompts render on /dev/tty, colors
# are dropped when piped / NO_COLOR is set. run_cmd() logs to setup.log and
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
if [[ ( -t 1 || -t 2 ) && -z "${NO_COLOR:-}" ]]; then
    C_RST=$'\e[0m';  C_BLD=$'\e[1m'
    C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'
    C_BLU=$'\e[34m'; C_MAG=$'\e[35m'; C_CYN=$'\e[36m'; C_GRY=$'\e[90m'
else
    C_RST=""; C_BLD=""
    C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_MAG=""; C_CYN=""; C_GRY=""
fi

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

# ------------------------------------------------------------------ UI ------
# Prompts draw on /dev/tty and read keys from /dev/tty, so they keep working
# inside $(command substitution). When no terminal is available (CI, pipes,
# --yes) they silently return their default instead of hanging.
#
# After an answer, every prompt collapses into ONE summary line:
#     ? Proceed with this plan? › Yes

ui_tty() { # ui_tty -> rc 0 when we can talk to a human
    [[ -t 2 ]] || return 1
    { : </dev/tty; } 2>/dev/null
}

# Usable card width (clamped to 52..76 cols so layouts stay tight on wide
# monitors and never wrap mid-word inside Niri tiled columns).
_ui_width() {
    local c
    c="$(tput cols 2>/dev/null </dev/tty || tput cols 2>/dev/null || echo 76)"
    (( c > 0 )) || c=76
    c=$(( c - 2 ))
    (( c > 76 )) && c=76
    (( c < 52 )) && c=52
    echo "$c"
}

# Repeat a character N times.
_ui_rep() {
    local ch="$1" n="$2" out="" i
    for ((i=0; i<n; i++)); do out+="$ch"; done
    printf '%s' "$out"
}

# Draw a horizontal section header rule:  ── TITLE ──────────────
ui_rule_top() { # ui_rule_top [BADGE] TITLE
    local badge="$1" title="$2" w pad
    w="$(_ui_width)"
    local plain_len=$(( 4 + ${#badge} + (${#badge} > 0 ? 1 : 0) + ${#title} ))
    pad=$(( w - plain_len ))
    (( pad < 2 )) && pad=2
    if [[ -n "$badge" ]]; then
        printf '\n  %s──%s %s%s%s %s%s%s %s%s%s\n' \
            "$C_MAG" "$C_RST" \
            "$C_GRY" "$badge" "$C_RST" \
            "$C_BLD$C_MAG" "$title" "$C_RST" \
            "$C_MAG" "$(_ui_rep '─' "$pad")" "$C_RST"
    else
        printf '\n  %s──%s %s%s%s %s%s%s\n' \
            "$C_MAG" "$C_RST" \
            "$C_BLD$C_MAG" "$title" "$C_RST" \
            "$C_MAG" "$(_ui_rep '─' "$pad")" "$C_RST"
    fi
}

ui_rule_bottom() {
    local w
    w="$(_ui_width)"
    printf '  %s%s%s\n' "$C_MAG" "$(_ui_rep '─' "$w")" "$C_RST"
}

shopt -s extglob

# Word-wrap a two-column row with hanging indent so lines never split mid-word.
# Usage: ui_row PREFIX VISIBLE_PREFIX_LEN TEXT [TEXT_COLOR]
ui_row() {
    local prefix="$1" plen="$2" text="$3" tcol="${4:-}"
    local w avail word plain wlen cur=0
    w="$(_ui_width)"
    avail=$(( w - plen + 2 ))
    (( avail < 20 )) && avail=20

    local -a words=()
    read -ra words <<<"$text"
    printf '%s%s' "$prefix" "$tcol"
    for word in "${words[@]}"; do
        plain="${word//$'\e'\[*([0-9;])m/}"
        wlen=${#plain}
        if (( cur == 0 )); then
            printf '%s' "$word"
            cur=$wlen
        elif (( cur + 1 + wlen <= avail )); then
            printf ' %s' "$word"
            cur=$(( cur + 1 + wlen ))
        else
            printf '%s\n%*s%s%s' "$C_RST" "$plen" "" "$tcol" "$word"
            cur=$wlen
        fi
    done
    printf '%s\n' "$C_RST"
}

# Table item inside a stage card:  • Label (18 cols)   Word-wrapped description
ui_item() { # ui_item LABEL DESCRIPTION [BULLET_CHAR]
    local label="$1" desc="$2" bullet="${3:-•}"
    local col_w=19 pad prefix
    pad=$(( col_w - ${#label} ))
    (( pad < 2 )) && pad=2
    prefix="$(printf '  %s%s%s %s%s%s%*s' "$C_CYN" "$bullet" "$C_RST" "$C_BLD" "$label" "$C_RST" "$pad" "")"
    local plen=$(( 4 + ${#label} + pad ))
    ui_row "$prefix" "$plen" "$desc" ""
}

# "Why:" paragraph at the top of a stage card, word-wrapped with hanging indent.
ui_why() { # ui_why TEXT
    local prefix
    prefix="$(printf '  %sWhy:%s ' "$C_BLD" "$C_RST")"
    ui_row "$prefix" 7 "$1" "$C_GRY"
    printf '\n'
}

ui_header() { # section banner
    log STAGE "=== $* ==="
    # When ./install runs a stage it already drew a stage card with the same
    # title — skip the stage's own first banner so nothing is shown twice.
    if [[ "${ENV_INSTALL_NESTED:-}" == "1" && -z "${ENV_UI_HEADER_SHOWN:-}" ]]; then
        export ENV_UI_HEADER_SHOWN=1
        return 0
    fi
    export ENV_UI_HEADER_SHOWN=1
    ui_rule_top "" "$*"
}

ui_stage_card() { # ui_stage_card INDEX TOTAL TITLE  (body rendered by caller or stdin)
    local idx="$1" total="$2" title="$3"
    log STAGE "=== [$idx/$total] $title ==="
    ui_rule_top "[$idx/$total]" "$title"
}

ui_step()  { ui_row "$(printf '  %s✔%s  ' "$C_GRN" "$C_RST")" 5 "$*" ""; log OK "$*"; }
ui_info()  { ui_row "$(printf '  %s•%s  ' "$C_CYN" "$C_RST")" 5 "$*" ""; log INFO "$*"; }
ui_warn()  { ui_row "$(printf '  %s⚠%s  ' "$C_YLW" "$C_RST")" 5 "$*" ""; log WARN "$*"; }
ui_error() { ui_row "$(printf '  %s✖%s  ' "$C_RED" "$C_RST")" 5 "$*" "" >&2; log ERROR "$*"; }
ui_dry()   { ui_row "$(printf '  %s[dry-run]%s ' "$C_YLW" "$C_RST")" 12 "$*" ""; log DRY "$*"; }

# Read one key from the terminal; arrows / escape sequences normalized to
# up|down|left|right|enter|space|tab|esc or the literal character.
_ui_key() {
    local k rest=""
    IFS= read -rsn1 k </dev/tty || { echo esc; return; }
    if [[ "$k" == $'\e' ]]; then
        IFS= read -rsn2 -t 0.05 rest </dev/tty || true
        case "$rest" in
            '[A'|'OA') echo up ;;    '[B'|'OB') echo down ;;
            '[C'|'OC') echo right ;; '[D'|'OD') echo left ;;
            *)         echo esc ;;
        esac
        return
    fi
    case "$k" in
        '')     echo enter ;;
        ' ')    echo space ;;
        $'\t')  echo tab ;;
        *)      printf '%s\n' "$k" ;;
    esac
}

# Rows a printed string occupies (accounts for wrapping on narrow terminals).
_ui_rows() {
    local text="$1" cols
    cols="$(tput cols 2>/dev/null </dev/tty || echo 80)"; (( cols > 0 )) || cols=80
    local len=${#text}
    (( len == 0 )) && { echo 1; return; }
    echo $(( (len + cols - 1) / cols ))
}

_ui_summary() { # _ui_summary PROMPT ANSWER — the collapsed one-liner
    printf '  %s?%s %s %s›%s %s%s%s\n' "$C_CYN" "$C_RST" "$1" "$C_GRY" "$C_RST" "$C_BLD" "$2" "$C_RST" >/dev/tty
    log ASK "$1 -> $2"
}

_ui_cursor_hide() { printf '\e[?25l' >/dev/tty; }
_ui_cursor_show() { printf '\e[?25h' >/dev/tty 2>/dev/null || true; }

ui_buttons() { # ui_buttons PROMPT BTN1 BTN2... -> echoes picked button (inline, ←/→)
    local prompt="$1"; shift
    local -a btn=("$@")
    local n=${#btn[@]} sel=0 key i hot
    if ! ui_tty; then printf '%s\n' "${btn[0]}"; return 0; fi

    _ui_cursor_hide
    trap '_ui_cursor_show' RETURN
    while :; do
        printf '\r\e[2K  %s?%s %s%s%s  ' "$C_CYN" "$C_RST" "$C_BLD" "$prompt" "$C_RST" >/dev/tty
        for ((i=0; i<n; i++)); do
            if (( i == sel )); then
                printf '\e[1;30;45m  %s  \e[0m ' "${btn[i]}" >/dev/tty
            else
                printf '\e[37;100m  %s  \e[0m ' "${btn[i]}" >/dev/tty
            fi
        done
        printf ' %s←/→ enter%s' "$C_GRY" "$C_RST" >/dev/tty
        key="$(_ui_key)"
        case "$key" in
            left|h|up|k)          sel=$(( (sel - 1 + n) % n )) ;;
            right|l|down|j|tab)   sel=$(( (sel + 1) % n )) ;;
            enter)                break ;;
            esc|q)                sel=$(( n - 1 )); break ;;
            *)  # first-letter hotkeys (y / n / s …)
                for ((i=0; i<n; i++)); do
                    hot="${btn[i]:0:1}"
                    if [[ "${key,,}" == "${hot,,}" ]]; then sel=$i; break 2; fi
                done ;;
        esac
    done
    printf '\r\e[2K' >/dev/tty
    _ui_summary "$prompt" "${btn[sel]}"
    printf '%s\n' "${btn[sel]}"
}

ui_confirm() { # ui_confirm PROMPT -> rc 0 = yes
    if [[ "$ASSUME_YES" == "true" ]]; then
        log ASK "$* -> yes (--yes)"
        return 0
    fi
    [[ "$(ui_buttons "$*" "Yes" "No")" == "Yes" ]]
}

ui_choose() { # ui_choose PROMPT opt1 opt2... -> echoes picked option (vertical radio)
    local prompt="$1"; shift
    local -a opts=("$@")
    local n=${#opts[@]} sel=0 key i rows
    if ! ui_tty; then printf '%s\n' "${opts[0]}"; return 0; fi

    _ui_draw_radio() {
        for ((i=0; i<n; i++)); do
            printf '\e[2K' >/dev/tty
            if (( i == sel )); then
                printf '   %s●%s %s%s%s\n' "$C_MAG" "$C_RST" "$C_BLD" "${opts[i]}" "$C_RST" >/dev/tty
            else
                printf '   %s○ %s%s\n' "$C_GRY" "${opts[i]}" "$C_RST" >/dev/tty
            fi
        done
    }

    _ui_cursor_hide
    trap '_ui_cursor_show' RETURN
    printf '  %s?%s %s%s%s %s(↑/↓ enter)%s\n' "$C_CYN" "$C_RST" "$C_BLD" "$prompt" "$C_RST" "$C_GRY" "$C_RST" >/dev/tty
    rows=$(_ui_rows "    ? $prompt (↑/↓ enter)")
    _ui_draw_radio
    while :; do
        key="$(_ui_key)"
        case "$key" in
            up|k)       sel=$(( (sel - 1 + n) % n )) ;;
            down|j|tab) sel=$(( (sel + 1) % n )) ;;
            enter)      break ;;
            esc|q)      printf '\e[%dA\e[J' $(( n + rows )) >/dev/tty; return 1 ;;
            [1-9])      (( key <= n )) && { sel=$(( key - 1 )); break; } ;;
        esac
        printf '\e[%dA' "$n" >/dev/tty
        _ui_draw_radio
    done
    printf '\e[%dA\e[J' $(( n + rows )) >/dev/tty
    _ui_summary "$prompt" "${opts[sel]}"
    printf '%s\n' "${opts[sel]}"
}

ui_choose_multi() { # ui_choose_multi PROMPT opt1 opt2... -> one pick per line
    local prompt="$1"; shift
    local -a opts=("$@") marked=()
    local n=${#opts[@]} sel=0 key i rows
    for ((i=0; i<n; i++)); do marked[i]=1; done   # everything pre-selected
    if ! ui_tty; then printf '%s\n' "${opts[@]}"; return 0; fi

    _ui_draw_checks() {
        local box
        for ((i=0; i<n; i++)); do
            printf '\e[2K' >/dev/tty
            (( marked[i] )) && box="${C_GRN}■${C_RST}" || box="${C_GRY}□${C_RST}"
            if (( i == sel )); then
                printf '  %s›%s %s %s%s%s\n' "$C_MAG" "$C_RST" "$box" "$C_BLD" "${opts[i]}" "$C_RST" >/dev/tty
            else
                printf '    %s %s\n' "$box" "${opts[i]}" >/dev/tty
            fi
        done
    }

    _ui_cursor_hide
    trap '_ui_cursor_show' RETURN
    printf '  %s?%s %s%s%s %s(↑/↓ move · space toggle · a all/none · enter)%s\n' \
        "$C_CYN" "$C_RST" "$C_BLD" "$prompt" "$C_RST" "$C_GRY" "$C_RST" >/dev/tty
    rows=$(_ui_rows "    ? $prompt (↑/↓ move · space toggle · a all/none · enter)")
    _ui_draw_checks
    while :; do
        key="$(_ui_key)"
        case "$key" in
            up|k)       sel=$(( (sel - 1 + n) % n )) ;;
            down|j|tab) sel=$(( (sel + 1) % n )) ;;
            space|x)    marked[sel]=$(( 1 - marked[sel] )) ;;
            a)  local any=0; for ((i=0; i<n; i++)); do (( marked[i] )) && any=1; done
                for ((i=0; i<n; i++)); do marked[i]=$(( 1 - any )); done ;;
            enter)      break ;;
            esc|q)      printf '\e[%dA\e[J' $(( n + rows )) >/dev/tty; return 1 ;;
        esac
        printf '\e[%dA' "$n" >/dev/tty
        _ui_draw_checks
    done
    printf '\e[%dA\e[J' $(( n + rows )) >/dev/tty

    local -a picked=()
    for ((i=0; i<n; i++)); do (( marked[i] )) && picked+=("${opts[i]}"); done
    _ui_summary "$prompt" "${#picked[@]} selected"
    ((${#picked[@]})) && printf '%s\n' "${picked[@]}"
    return 0
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

    if ui_tty; then
        # Swimming fish animation (120ms interval)
        local -a frames=(
            ">))'>    "
            " >))'>   "
            "  >))'>  "
            "   >))'> "
            "    >))'>"
            "    <'((<"
            "   <'((< "
            "  <'((<  "
            " <'((<   "
            "<'((<    "
        )
        local i=0 n=${#frames[@]} start=$SECONDS elapsed timer=""
        local cols max_d d_disp
        cols="$(tput cols 2>/dev/null </dev/tty || echo 80)"
        (( cols > 0 )) || cols=80
        max_d=$(( cols - 24 ))
        (( max_d < 20 )) && max_d=20
        d_disp="$desc"
        if (( ${#desc} > max_d )); then
            d_disp="${desc:0:$(( max_d - 3 ))}..."
        fi

        _ui_cursor_hide
        trap '_ui_cursor_show' RETURN
        "$@" >"$out" 2>&1 &
        local pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            elapsed=$(( SECONDS - start ))
            (( elapsed > 0 )) && timer=" ${C_GRY}(${elapsed}s)${C_RST}" || timer=""
            printf '\r\e[2K  %s%s%s %s%s' "$C_CYN" "${frames[i]}" "$C_RST" "$d_disp" "$timer" >/dev/tty
            i=$(( (i + 1) % n ))
            sleep 0.12
        done
        wait "$pid" || rc=$?
        printf '\r\e[2K' >/dev/tty
        _ui_cursor_show
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
