#!/bin/bash
# stages/40-dotfiles.sh — back up conflicting files, stow every core package
# with --no-folding, then initialize GTK cursor settings and ~/.Xresources.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "40 · Dotfiles (stow --no-folding)"

STOW_PKGS=(niri dms portals environment systemd-user scripts)
[[ "$WITH_MANGO" == "true" ]] && STOW_PKGS+=(mango)

pkg_description() {
    case "$1" in
        niri)         echo "Niri compositor layout & keybindings" ;;
        dms)          echo "Dux Shell settings, themes & plugin configuration" ;;
        portals)      echo "XDG portal FileChooser pin (dfiles;gtk) & default app associations" ;;
        environment)  echo "environment.d (Wayland flags, dynamic cursor, file chooser geometry)" ;;
        systemd-user) echo "systemd --user units (wallpaper radius cycler, zoom daemon)" ;;
        scripts)      echo "custom helper scripts (radius cycler, niri column navigation)" ;;
        mango)        echo "Mango compositor config" ;;
        *)            echo "$1" ;;
    esac
}

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

    run_cmd "stow --no-folding $pkg ($(pkg_description "$pkg"))" \
        stow --dir="$DOTS_ROOT" --target="$HOME" --no-folding -S "$pkg" \
        || { ui_warn "stow $pkg reported conflict(s) — existing configs preserved; see $LOG_FILE"; stow_failures=$((stow_failures + 1)); }
done

if ((stow_failures > 0)); then
    ui_warn "$stow_failures stow package(s) reported conflicts. Your existing files were preserved."
else
    ui_step "All desktop dotfiles stowed successfully"
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
        upsert_ini "$ini" Settings gtk-cursor-theme-name Adwaita
        upsert_ini "$ini" Settings gtk-cursor-theme-size 32
        ui_step "GTK $gtkver cursor: Adwaita @ 32"
    fi
done

if is_dry_run; then
    ui_dry "Xcursor.theme/Xcursor.size → ~/.Xresources"
else
    upsert_xresource "$HOME/.Xresources" Xcursor.theme Adwaita
    upsert_xresource "$HOME/.Xresources" Xcursor.size 32
    ui_step "~/.Xresources: Xcursor.theme Adwaita · Xcursor.size 32"
fi

# --- DMS initial state, default palette & cursor color map ---------------------
DMS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dms"
DMS_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dms"

if is_dry_run; then
    ui_dry "Seed default DMS session.json ($DMS_STATE_DIR/session.json) and palette ($DMS_CACHE_DIR/dms-colors.json)"
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
fi

ui_info "Dotfiles stage complete."
