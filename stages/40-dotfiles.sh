#!/bin/bash
# stages/40-dotfiles.sh — back up conflicting files, stow every core package
# with --no-folding, then initialize GTK cursor settings and ~/.Xresources.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "40 · Dotfiles (stow --no-folding)"

STOW_PKGS=(fastfetch ghostty git lazygit lsd nvim starship zed zsh
           niri dms portals environment systemd-user scripts
           desktop-tools)
[[ "$WITH_MANGO" == "true" ]] && STOW_PKGS+=(mango)

BACKUP_DIR="$HOME/.dots-backup-$(date +%Y%m%d-%H%M%S)"
stow_failures=0

# --- stow (with conflict backup) -------------------------------------------------
for pkg in "${STOW_PKGS[@]}"; do
    pkgdir="$DOTS_ROOT/$pkg"
    if [[ ! -d "$pkgdir" ]]; then
        ui_warn "Package '$pkg' not present in repo yet — skipping (stow it later with: stow --no-folding $pkg)"
        continue
    fi

    # Back up any non-symlink file in $HOME that would conflict with this
    # package's files. Symlinks (already stowed) are left alone — stow is
    # idempotent for those.
    while IFS= read -r -d '' rel; do
        rel="${rel#./}"
        target="$HOME/$rel"
        { [[ -e "$target" ]] || [[ -L "$target" ]]; } || continue
        [[ -L "$target" ]] && continue
        [[ "$(readlink -f "$target" 2>/dev/null)" == "$DOTS_ROOT/"* ]] && continue
        is_dry_run || mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        run_cmd "Backup conflicting ~/$rel" mv "$target" "$BACKUP_DIR/$rel" \
            || { ui_warn "Could not back up ~/$rel — stow may fail for $pkg"; continue; }
    done < <(cd "$pkgdir" && find . -mindepth 1 \( -type f -o -type l \) -print0)

    run_cmd "stow --no-folding $pkg" \
        stow --dir="$DOTS_ROOT" --target="$HOME" --no-folding -S "$pkg" \
        || { ui_warn "stow $pkg failed — see $LOG_FILE"; stow_failures=$((stow_failures + 1)); }
done

if ((stow_failures > 0)); then
    ui_error "$stow_failures stow package(s) failed — resolve conflicts and re-run this stage."
    exit 1
fi

# If installed under a username other than lcarv, rewrite DFILES_SHELL_DIR in niri config.kdl.
if [[ "$HOME" != "/home/lcarv" && -f "$DOTS_ROOT/niri/.config/niri/config.kdl" ]]; then
    if is_dry_run; then
        ui_dry "Adapt DFILES_SHELL_DIR in niri/config.kdl → $HOME/.config/dfiles-shell"
    else
        sed -i "s|/home/lcarv/.config/dfiles-shell|$HOME/.config/dfiles-shell|g" \
            "$DOTS_ROOT/niri/.config/niri/config.kdl"
        ui_step "Adapted DFILES_SHELL_DIR in niri/config.kdl → $HOME/.config/dfiles-shell"
    fi
fi

# --- GTK cursor settings ---------------------------------------------------------
upsert_ini() { # upsert_ini FILE SECTION KEY VALUE  (edits through symlinks)
    local file="$1" section="$2" key="$3" val="$4" tmp
    if [[ -L "$file" ]]; then
        file="$(readlink -f "$file")" || return 1
    fi
    mkdir -p "$(dirname "$file")"
    touch "$file"
    tmp="$(mktemp)"
    awk -v sec="$section" -v key="$key" -v val="$val" '
        BEGIN { insec = 0; done = 0 }
        $0 ~ "^\\[" sec "\\]" { insec = 1; print; next }
        /^\[/ { if (insec && !done) { print key " = " val; done = 1 } insec = 0; print; next }
        insec && $0 ~ "^[ \t]*" key "[ \t]*=" { if (!done) { print key " = " val; done = 1 } next }
        { print }
        END { if (!done) { if (!insec) print "[" sec "]"; print key " = " val } }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"   # preserve inode: safe for stowed/symlinked targets
    rm -f "$tmp"
}

upsert_xresource() { # upsert_xresource FILE KEY VALUE
    local file="$1" key="$2" val="$3"
    if [[ -L "$file" ]]; then
        file="$(readlink -f "$file")" || return 1
    fi
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if grep -qE "^[[:space:]]*${key}:" "$file"; then
        sed -i -E "s|^[[:space:]]*${key}:.*|${key}: ${val}|" "$file"
    else
        printf '%s: %s\n' "$key" "$val" >> "$file"
    fi
}

for gtkver in 3.0 4.0; do
    ini="$HOME/.config/gtk-$gtkver/settings.ini"
    if is_dry_run; then
        ui_dry "GTK $gtkver cursor theme/size → $ini"
    else
        upsert_ini "$ini" Settings gtk-cursor-theme-name JuxCursor
        upsert_ini "$ini" Settings gtk-cursor-theme-size 32
        ui_step "GTK $gtkver cursor: JuxCursor @ 32"
    fi
done

if is_dry_run; then
    ui_dry "Xcursor.theme/Xcursor.size → ~/.Xresources"
else
    upsert_xresource "$HOME/.Xresources" Xcursor.theme JuxCursor
    upsert_xresource "$HOME/.Xresources" Xcursor.size 32
    ui_step "~/.Xresources: Xcursor.theme JuxCursor · Xcursor.size 32"
fi

# --- DMS initial state, default palette & cursor color map ---------------------
DMS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dms"
DMS_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dms"

if is_dry_run; then
    ui_dry "Seed default DMS session.json ($DMS_STATE_DIR/session.json) and palette ($DMS_CACHE_DIR/dms-colors.json)"
    ui_dry "Build Bibata Patched cursor color map (~/.local/bin/dms-cursor-adapt --refresh-map)"
else
    mkdir -p "$DMS_STATE_DIR" "$DMS_CACHE_DIR"
    if [[ ! -s "$DMS_STATE_DIR/session.json" && -f "$DOTS_ROOT/system/dms/session.json" ]]; then
        sed "s|__HOME__|$HOME|g" "$DOTS_ROOT/system/dms/session.json" > "$DMS_STATE_DIR/session.json"
        ui_step "Seeded default DMS session state (wallpaper: rogue.jpg) → $DMS_STATE_DIR/session.json"
    else
        ui_step "DMS session.json already present"
    fi

    if [[ ! -s "$DMS_CACHE_DIR/dms-colors.json" && -f "$DOTS_ROOT/system/dms/dms-colors.json" ]]; then
        cp -f "$DOTS_ROOT/system/dms/dms-colors.json" "$DMS_CACHE_DIR/dms-colors.json"
        ui_step "Seeded default DMS Material 3 palette → $DMS_CACHE_DIR/dms-colors.json"
    else
        ui_step "DMS color palette already present"
    fi

    if [[ -x "$HOME/.local/bin/dms-cursor-adapt" ]]; then
        run_cmd "Build cursor color map (dms-cursor-adapt --refresh-map)" \
            "$HOME/.local/bin/dms-cursor-adapt" --refresh-map
    fi
fi

ui_info "Dotfiles stage complete."
