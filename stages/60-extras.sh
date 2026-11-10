#!/bin/bash
# stages/60-extras.sh — optional extras (runs only when WITH_EXTRAS=true):
#   dnf extras, mise language runtimes, Keychron udev rule,
#   and the 'mango' stow package when requested.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "$WITH_EXTRAS" != "true" ]]; then
    ui_info "Extras skipped (WITH_EXTRAS is not true)."
    exit 0
fi

ui_header "60 · Extras (dnf extras · runtimes · udev · mango)"

ensure_sudo

# --- dnf extras ---------------------------------------------------------------------
DNF_EXTRAS_MANIFEST="$DOTS_ROOT/manifest/dnf-extras.txt"
if [[ -f "$DNF_EXTRAS_MANIFEST" ]]; then
    mapfile -t XPKGS < <(read_manifest "$DNF_EXTRAS_MANIFEST")
    to_install_xpkgs=()
    for pkg in "${XPKGS[@]}"; do
        if rpm -q "$pkg" >/dev/null 2>&1; then
            ui_step "Extra package $pkg already installed"
        else
            to_install_xpkgs+=("$pkg")
        fi
    done
    if ((${#to_install_xpkgs[@]} > 0)); then
        run_cmd "dnf install extras (${#to_install_xpkgs[@]})" \
            sudo dnf install -y "${to_install_xpkgs[@]}" \
            || ui_warn "Could not install some extras — continuing."
    fi
fi

# --- mise language runtimes --------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
MISE_EXTRAS="$DOTS_ROOT/manifest/mise-extras.txt"
if have mise && [[ -f "$MISE_EXTRAS" ]]; then
    while read -r tool; do
        [[ -z "${tool// /}" ]] && continue
        run_cmd "mise: $tool@latest" mise use -g "$tool@latest" \
            || ui_warn "mise could not install $tool — continuing."
    done < <(read_manifest "$MISE_EXTRAS")
else
    ui_warn "mise unavailable — skipped extras runtimes ($MISE_EXTRAS)."
fi

# --- Keychron udev rule --------------------------------------------------------------
# Sets fnmode=2 so F1-F12 act as regular function keys by default (instead of media keys).
if [[ -f "$DOTS_ROOT/system/udev/50-keychron.rules" ]]; then
    install_file 0644 "$DOTS_ROOT/system/udev/50-keychron.rules" /etc/udev/rules.d/50-keychron.rules \
        "Keychron udev rule (F1-F12 fn-mode) → /etc/udev/rules.d/50-keychron.rules"
    run_cmd "Reload udev rules" sudo udevadm control --reload-rules
    run_cmd "Trigger udev events" sudo udevadm trigger
fi

# --- mango --------------------------------------------------------------------------
if [[ "$WITH_MANGO" == "true" ]]; then
    if [[ -d "$DOTS_ROOT/mango" ]]; then
        run_cmd "stow --no-folding mango" \
            stow --dir="$DOTS_ROOT" --target="$HOME" --no-folding -S mango \
            || ui_warn "stow mango failed — see $LOG_FILE"
    else
        ui_warn "WITH_MANGO=true but no 'mango' package in the repo — skipped."
    fi
fi

ui_info "Extras stage complete."
