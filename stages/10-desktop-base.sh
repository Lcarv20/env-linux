#!/bin/bash
# stages/10-desktop-base.sh — core dnf packages (Wayland/Niri/Dux desktop),
# mise bootstrap + core CLI tools, and zsh as the login shell.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "10 · Desktop base (dnf core · mise · zsh)"

ensure_sudo

# --- core dnf packages ----------------------------------------------------------
CORE_MANIFEST="$DOTS_ROOT/manifest/dnf-core.txt"
[[ -f "$CORE_MANIFEST" ]] || { ui_error "missing $CORE_MANIFEST"; exit 1; }

mapfile -t CORE_PKGS < <(read_manifest "$CORE_MANIFEST")
((${#CORE_PKGS[@]} > 0)) || { ui_error "dnf-core.txt is empty"; exit 1; }

ui_info "Installing ${#CORE_PKGS[@]} core packages (niri, dms, pipewire, portals, fonts, …)"
run_cmd "dnf install core desktop packages (${#CORE_PKGS[@]})" \
    sudo dnf install -y "${CORE_PKGS[@]}"

# --- mise -----------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
if ! have mise; then
    run_cmd "Install mise (mise.run)" bash -c 'curl -fsSL https://mise.run | sh' \
        || { ui_error "mise installation failed"; exit 1; }
else
    ui_step "mise already installed ($(mise --version 2>/dev/null | head -1))"
fi

# Make `mise` resolvable in *this* shell even on a fresh install.
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash 2>/dev/null)" || true

MISE_CORE="$DOTS_ROOT/manifest/mise-core.txt"
if have mise && [[ -f "$MISE_CORE" ]]; then
    while read -r tool; do
        [[ -z "${tool// /}" ]] && continue
        run_cmd "mise: $tool@latest" mise use -g "$tool@latest" \
            || ui_warn "mise could not install $tool — continuing."
    done < <(read_manifest "$MISE_CORE")
else
    ui_warn "mise unavailable — skipped core CLI tools ($MISE_CORE)."
fi

# --- antidote (zsh plugin manager) ---------------------------------------------
ANTIDOTE_DIR="${ZDOTDIR:-$HOME}/.antidote"
if [[ -d "$ANTIDOTE_DIR" ]]; then
    ui_step "antidote already present ($ANTIDOTE_DIR)"
else
    run_cmd "Install antidote zsh plugin manager → ~/.antidote" \
        git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_DIR"
fi

# --- login shell ----------------------------------------------------------------
ZSH_BIN="/usr/bin/zsh"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" == "$ZSH_BIN" ]]; then
    ui_step "Login shell already $ZSH_BIN"
elif [[ -x "$ZSH_BIN" ]]; then
    run_cmd "Set login shell → $ZSH_BIN" sudo usermod -s "$ZSH_BIN" "$USER"
else
    ui_warn "$ZSH_BIN not found — zsh install must have failed; login shell unchanged."
fi

ui_info "Desktop base stage complete."
