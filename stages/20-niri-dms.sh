#!/bin/bash
# stages/20-niri-dms.sh — verify the Niri + Dux Shell stack is actually
# installed, and remove legacy unowned binaries in ~/.local/bin that would
# shadow the RPM-managed ones (old wtype / swww installs).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "20 · Niri + Dux Shell verification"

REQUIRED_BINARIES=(niri dms dms-greeter dfiles awww matugen wtype)

# --- verification ---------------------------------------------------------------
missing=()
for bin in "${REQUIRED_BINARIES[@]}"; do
    have "$bin" || missing+=("$bin")
done

if is_dry_run; then
    if ((${#missing[@]})); then
        ui_dry "verification would fail — currently missing: ${missing[*]}"
    else
        ui_dry "all desktop binaries present (${REQUIRED_BINARIES[*]})"
    fi
elif ((${#missing[@]})); then
    ui_error "Missing required binaries: ${missing[*]}"
    ui_info "Run stages 00-repos.sh and 10-desktop-base.sh first, then retry."
    exit 1
else
    ui_step "niri · dms · dms-greeter · dfiles · awww · matugen · wtype all installed"
fi

# --- legacy cleanup -------------------------------------------------------------
# ~/.local/bin precedes /usr/bin in PATH, so stale copies here shadow the
# RPM-provided binaries. Remove anything present that rpm does NOT own.
shopt -s nullglob
LEGACY=( "$HOME"/.local/bin/swww* )
[[ -x /usr/bin/wtype ]] && LEGACY+=( "$HOME/.local/bin/wtype" )
shopt -u nullglob

for f in "${LEGACY[@]}"; do
    { [[ -e "$f" ]] || [[ -L "$f" ]]; } || continue
    if rpm -qf --quiet "$f" 2>/dev/null; then
        ui_warn "Skipping $f — owned by an rpm package."
        continue
    fi
    if [[ -L "$f" ]]; then
        run_cmd "Remove legacy symlink $f" rm -f "$f"
    else
        run_cmd "Remove legacy unowned binary $f" rm -f "$f"
    fi
done

ui_info "Niri + DMS stage complete."
