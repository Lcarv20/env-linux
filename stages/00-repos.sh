#!/bin/bash
# stages/00-repos.sh — enable third-party repositories:
#   RPM Fusion (Free + Nonfree), Terra (fyralabs), COPRs from manifest/copr.txt
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "00 · Repositories (RPM Fusion · Terra · COPR)"

# Safety: this installer is Fedora-only.
if ! grep -q '^ID=fedora' /etc/os-release 2>/dev/null; then
    ui_error "This installer targets Fedora (found: $(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null || echo unknown))."
    exit 1
fi

ensure_sudo

FEDORA_VER="$(rpm -E %fedora 2>/dev/null || true)"
if [[ -z "$FEDORA_VER" || "$FEDORA_VER" == "%fedora" ]]; then
    FEDORA_VER="$(sed -n 's/^VERSION_ID=//p' /etc/os-release 2>/dev/null | tr -d '"' || echo "41")"
fi
ui_info "Fedora release: $FEDORA_VER"

# --- RPM Fusion Free + Nonfree -------------------------------------------------
rf_free=false
rf_nonfree=false
rpm -q rpmfusion-free-release >/dev/null 2>&1 && rf_free=true
rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 && rf_nonfree=true

if $rf_free && $rf_nonfree; then
    ui_step "RPM Fusion (Free & Nonfree) already installed"
else
    to_install=()
    $rf_free || to_install+=("https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm")
    $rf_nonfree || to_install+=("https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm")
    run_cmd "Enable RPM Fusion (free + nonfree)" \
        sudo dnf install -y "${to_install[@]}" \
        || ui_warn "RPM Fusion install returned non-zero — may already be enabled or network error; continuing."
fi

# --- Terra (fyralabs) -----------------------------------------------------------
if rpm -q terra-release >/dev/null 2>&1 || [[ -f /etc/yum.repos.d/terra.repo ]]; then
    ui_step "Terra repository already configured"
else
    # NOTE: $releasever must reach dnf unexpanded, hence the single quotes.
    run_cmd "Enable Terra repo (repos.fyralabs.com)" \
        sudo dnf install -y --nogpgcheck \
        --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release \
        || ui_warn "Terra repo setup returned non-zero — it may already be configured; continuing."
fi

# --- COPR repos -----------------------------------------------------------------
run_cmd "Ensure dnf copr plugin" sudo dnf install -y dnf-plugins-core dnf5-plugins \
    || ui_info "dnf-plugins-core/dnf5-plugins check complete."

COPR_MANIFEST="$DOTS_ROOT/manifest/copr.txt"
if [[ ! -f "$COPR_MANIFEST" ]]; then
    ui_error "missing $COPR_MANIFEST"
    exit 1
fi

while read -r repo; do
    [[ -z "${repo// /}" ]] && continue
    repo_slug="${repo//\//:}"
    if ls /etc/yum.repos.d/*"$repo_slug"*.repo >/dev/null 2>&1; then
        ui_step "COPR $repo already enabled"
    else
        run_cmd "Enable COPR $repo" sudo dnf copr enable -y "$repo" \
            || ui_warn "COPR $repo could not be enabled (already enabled? plugin missing?). Continuing."
    fi
done < <(read_manifest "$COPR_MANIFEST")

ui_info "Repositories stage complete."
