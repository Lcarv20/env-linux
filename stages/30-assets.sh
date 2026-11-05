#!/bin/bash
# stages/30-assets.sh — download the bundled assets release
#   https://github.com/Lcarv20/dots-linux/releases/tag/assets-v1
# verify its SHA-256 (when the sidecar checksum is published), extract and
# install: wallpapers, icons, fonts, dfiles-shell (+ patches), and bin/.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "30 · Assets (wallpapers · icons · fonts · dfiles-shell · bin)"

ASSET_REPO="Lcarv20/dots-linux"
ASSET_TAG="assets-v1"
ASSET_NAME="dots-linux-assets-v1.tar.zst"
ASSET_URL="https://github.com/$ASSET_REPO/releases/download/$ASSET_TAG/$ASSET_NAME"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dots-linux-assets"
TARBALL="$CACHE_DIR/$ASSET_NAME"
SHA_FILE="$CACHE_DIR/assets-v1.sha256"
STAGE_DIR="$CACHE_DIR/extracted/$ASSET_TAG"

# --- download -------------------------------------------------------------------
is_dry_run || mkdir -p "$CACHE_DIR"

if [[ -s "$DOTS_ROOT/assets-v1.sha256" ]] && ! is_dry_run; then
    cp -f "$DOTS_ROOT/assets-v1.sha256" "$SHA_FILE"
fi

if [[ -s "$TARBALL" ]]; then
    ui_step "Using cached tarball $TARBALL"
else
    if have gh; then
        run_cmd "Download assets (gh release download)" \
            gh release download "$ASSET_TAG" --repo "$ASSET_REPO" \
                --pattern "$ASSET_NAME" \
                --output-dir "$CACHE_DIR" --clobber \
            || run_cmd "Download assets (curl -fL)" \
                   curl -fL --retry 3 --progress-bar -o "$TARBALL" "$ASSET_URL"
    else
        run_cmd "Download assets (curl -fL)" \
            curl -fL --retry 3 --progress-bar -o "$TARBALL" "$ASSET_URL"
    fi
fi

# Fetch the checksum sidecar separately if not already in repo or cache.
if [[ ! -s "$SHA_FILE" ]]; then
    if run_cmd "Fetch checksum sidecar (optional)" \
        curl -fsSL --max-time 30 -o "$SHA_FILE" "$ASSET_URL.sha256"; then
        :
    else
        ui_warn "No assets-v1.sha256 found — skipping checksum verification."
        rm -f "$SHA_FILE"
    fi
fi

# --- verify ---------------------------------------------------------------------
if [[ -s "$SHA_FILE" ]] && grep -q "$ASSET_NAME" "$SHA_FILE"; then
    run_cmd "Verify SHA-256 of $ASSET_NAME" \
        bash -c "cd '$CACHE_DIR' && sha256sum -c assets-v1.sha256"
else
    ui_warn "Checksum file missing or does not reference $ASSET_NAME — skipping verification."
fi

# --- extract --------------------------------------------------------------------
is_dry_run || { rm -rf "$STAGE_DIR"; mkdir -p "$STAGE_DIR"; }
run_cmd "Extract tarball (zstd)" tar -x --zstd -f "$TARBALL" -C "$STAGE_DIR"

# --- wallpapers -----------------------------------------------------------------
if [[ -d "$STAGE_DIR/wallpapers" ]]; then
    copy_tree "$STAGE_DIR/wallpapers" "$HOME/Pictures/Walpapers" \
        "Install wallpapers → ~/Pictures/Walpapers/"
else
    ui_warn "No wallpapers/ in tarball — skipped."
fi

# --- icons ----------------------------------------------------------------------
if [[ -d "$STAGE_DIR/icons" ]]; then
    copy_tree "$STAGE_DIR/icons" "$HOME/.local/share/icons" \
        "Install icons → ~/.local/share/icons/"
fi

# Cursor fallback theme: ~/.icons/default inherits JuxCursor.
ICONS_DEFAULT="$HOME/.icons/default"
if is_dry_run; then
    ui_dry "Set cursor fallback → ~/.icons/default/index.theme (Inherits=JuxCursor)"
elif [[ -f "$ICONS_DEFAULT/index.theme" ]] && grep -q '^\s*Inherits\s*=\s*JuxCursor\s*$' "$ICONS_DEFAULT/index.theme"; then
    ui_step "Cursor fallback already JuxCursor"
else
    mkdir -p "$ICONS_DEFAULT"
    if [[ -f "$ICONS_DEFAULT/index.theme" ]] && grep -q '^\s*\[Icon Theme\]' "$ICONS_DEFAULT/index.theme"; then
        sed -i -E 's/^\s*Inherits\s*=.*/Inherits=JuxCursor/' "$ICONS_DEFAULT/index.theme"
        grep -q '^\s*Inherits' "$ICONS_DEFAULT/index.theme" \
            || printf 'Inherits=JuxCursor\n' >> "$ICONS_DEFAULT/index.theme"
    else
        printf '[Icon Theme]\nInherits=JuxCursor\n' > "$ICONS_DEFAULT/index.theme"
    fi
    ui_step "Cursor fallback → JuxCursor (~/.icons/default/index.theme)"
fi

# --- fonts ----------------------------------------------------------------------
if [[ -d "$STAGE_DIR/fonts" ]]; then
    copy_tree "$STAGE_DIR/fonts" "$HOME/.local/share/fonts" \
        "Install fonts → ~/.local/share/fonts/"
    run_cmd "Rebuild font cache (fc-cache -f)" fc-cache -f
fi

# --- dfiles-shell ---------------------------------------------------------------
if [[ -d "$STAGE_DIR/dfiles-shell" ]]; then
    copy_tree "$STAGE_DIR/dfiles-shell" "$HOME/.config/dfiles-shell" \
        "Install dfiles-shell → ~/.config/dfiles-shell/"
    run_cmd "Apply dfiles-shell patches (Theme.qml · ChooserWindow.qml)" \
        bash "$DOTS_ROOT/system/dfiles-patch/apply-dfiles-patch.sh"
else
    ui_warn "No dfiles-shell/ in tarball — skipped (patch step too)."
fi

# --- bin ------------------------------------------------------------------------
if [[ -d "$STAGE_DIR/bin" ]]; then
    run_cmd "Make bundled bin/ scripts executable" \
        find "$STAGE_DIR/bin" -type f -exec chmod +x {} \;
    copy_tree "$STAGE_DIR/bin" "$HOME/.local/bin" \
        "Install scripts → ~/.local/bin/"
else
    ui_warn "No bin/ in tarball — skipped."
fi

ui_info "Assets stage complete."
