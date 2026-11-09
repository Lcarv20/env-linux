#!/bin/bash
# stages/35-plugins.sh — restore DMS community plugins from plugins.lock.json,
# and clone/symlink custom & external plugins to ~/Developer/Software.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "35 · DMS Plugins (registry restore · custom repos)"

SOFTWARE_DIR="$HOME/Developer/Software"
PLUGINS_DIR="$HOME/.config/dms/plugins"
LOCKFILE="$DOTS_ROOT/dms/.config/dms/plugins.lock.json"
MANIFEST="$DOTS_ROOT/manifest/plugins.txt"

is_dry_run || mkdir -p "$SOFTWARE_DIR" "$PLUGINS_DIR"

# --- 1. Community registry plugins --------------------------------------------------
if have dms && [[ -f "$LOCKFILE" ]]; then
    run_cmd "Restore community plugins from lockfile (dms plugins restore)" \
        dms plugins restore "$LOCKFILE" \
        || ui_warn "dms plugins restore failed — continuing."
else
    ui_warn "dms CLI unavailable or lockfile missing — skipped community plugins restore."
fi

# --- 2. Custom and external plugins ------------------------------------------------
if [[ -f "$MANIFEST" ]]; then
    while read -r repo folder link_name || [[ -n "$repo" ]]; do
        [[ -z "${repo// /}" ]] && continue
        [[ "$repo" =~ ^# ]] && continue

        target="$SOFTWARE_DIR/$folder"
        link_target="$PLUGINS_DIR/${link_name:-$folder}"

        if [[ -d "$target/.git" ]]; then
            run_cmd "Update plugin $folder (git pull --ff-only)" \
                git -C "$target" pull --ff-only \
                || ui_warn "Could not fast-forward $folder — keeping existing local checkout."
        else
            run_cmd "Clone plugin $folder ($repo)" \
                git clone "$repo" "$target"
        fi

        # If a Makefile exists and bin/ is empty or missing, build it
        if [[ -f "$target/Makefile" && ! -d "$target/bin" ]] && have make; then
            run_cmd "Build plugin helper binary (make in $folder)" \
                make -C "$target" \
                || ui_warn "make failed in $folder — daemon will compile on first run if Go is present."
        fi

        run_cmd "Symlink $folder → ~/.config/dms/plugins/${link_name:-$folder}" \
            ln -sfn "$target" "$link_target"
    done < "$MANIFEST"
fi

ui_info "Plugins stage complete."
