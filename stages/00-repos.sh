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

FEDORA_VER="$(rpm -E %fedora)"
ui_info "Fedora release: $FEDORA_VER"

# --- RPM Fusion Free + Nonfree -------------------------------------------------
run_cmd "Enable RPM Fusion Free + Nonfree" \
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
    || ui_warn "RPM Fusion enable returned non-zero — may already be enabled; continuing."

# --- Terra (fyralabs) -----------------------------------------------------------
# NOTE: $releasever must reach dnf unexpanded, hence the single quotes.
run_cmd "Enable Terra repo (repos.fyralabs.com)" \
    sudo dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release \
    || ui_warn "Terra repo setup returned non-zero — it may already be configured."

# --- COPR repos -----------------------------------------------------------------
run_cmd "Ensure dnf copr plugin" sudo dnf install -y dnf-plugins-core dnf5-plugins \
    || ui_warn "Could not install copr plugins (one of them may not exist on this dnf)."

COPR_MANIFEST="$DOTS_ROOT/manifest/copr.txt"
if [[ ! -f "$COPR_MANIFEST" ]]; then
    ui_error "missing $COPR_MANIFEST"
    exit 1
fi

while read -r repo; do
    [[ -z "${repo// /}" ]] && continue
    run_cmd "Enable COPR $repo" sudo dnf copr enable -y "$repo" \
        || ui_warn "COPR $repo could not be enabled (already enabled? plugin missing?)."
done < <(read_manifest "$COPR_MANIFEST")

ui_info "Repositories stage complete."
