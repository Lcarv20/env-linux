#!/bin/bash
# stages/45-own-software.sh — clone and build personal tools:
#   • web-app-installer (Go CLI/TUI: turns web pages into chromeless desktop apps)
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "45 · Own software (web-app-installer)"

SOFTWARE_DIR="$HOME/Developer/Software"
REPO_URL="https://github.com/Lcarv20/web-app-installer.git"
APP_DIR="$SOFTWARE_DIR/web-app-installer"

is_dry_run || mkdir -p "$SOFTWARE_DIR"

# --- web-app-installer --------------------------------------------------------------
if [[ -d "$APP_DIR/.git" ]]; then
    run_cmd "Update web-app-installer (git pull --ff-only)" \
        git -C "$APP_DIR" pull --ff-only \
        || ui_warn "Could not fast-forward web-app-installer — keeping existing local checkout."
elif [[ -d "$APP_DIR" ]]; then
    ui_info "$APP_DIR already exists (non-git) — keeping as is."
else
    run_cmd "Clone web-app-installer ($REPO_URL)" \
        git clone "$REPO_URL" "$APP_DIR" \
        || ui_warn "Could not clone web-app-installer — skipping."
fi

if have make && have go && [[ -d "$APP_DIR" ]]; then
    run_cmd "Build and install web-app-installer (make install)" \
        make -C "$APP_DIR" install \
        || ui_warn "make install failed for web-app-installer — continuing."
elif ! is_dry_run; then
    ui_warn "go or make missing on PATH — could not compile web-app-installer. Run 'dots-linux/setup' first."
fi

ui_info "Own software stage complete."
