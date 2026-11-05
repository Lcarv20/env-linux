#!/bin/bash
# stages/50-services.sh — system + user services:
#   • /etc/opt/chrome/policies/managed (group-writable for dux-chrome-theme)
#   • greetd config (config.toml, niri config.kdl + host-specific dms.kdl)
#   • disable conflicting DMs, enable greetd, graphical.target
#   • enable systemd --user units
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ui_header "50 · Services (chrome policies · greetd · user units)"

resolve_host_profile
ensure_sudo

# --- Chrome managed-policies dir -------------------------------------------------
# dux-chrome-theme writes color.json here without sudo:
# root:$USER ownership, mode 0775.
run_cmd "/etc/opt/chrome/policies/managed (root:$USER, 0775)" \
    sudo install -d -o root -g "$USER" -m 0775 /etc/opt/chrome/policies/managed

# --- greetd & dms-greeter -------------------------------------------------------
if getent passwd greeter >/dev/null 2>&1; then
    run_cmd "Add greeter user to video,render groups" \
        sudo usermod -aG video,render greeter || true
fi
if getent group greeter >/dev/null 2>&1; then
    run_cmd "Add $USER to greeter group" \
        sudo usermod -aG greeter "$USER" || true
fi

if have dms-greeter; then
    run_cmd "Enable dms-greeter in greetd (dms-greeter enable --yes)" \
        sudo dms-greeter enable --yes || true
    run_cmd "Sync user DMS state & ACLs to greeter (dms-greeter sync --yes)" \
        dms-greeter sync --yes || true
fi

install_file 0644 "$DOTS_ROOT/system/greetd/config.toml" /etc/greetd/config.toml \
    "greetd → /etc/greetd/config.toml (dms-greeter --command niri)"

install_file 0644 "$DOTS_ROOT/system/greetd/niri/config.kdl" /etc/greetd/niri/config.kdl \
    "greetd niri → /etc/greetd/niri/config.kdl"

DMS_KDL="$DOTS_ROOT/system/greetd/niri/dms-generic.kdl"
case "$HOST_PROFILE" in
    imac18-3) DMS_KDL="$DOTS_ROOT/system/greetd/niri/dms-imac18-3.kdl" ;;
    vm)       DMS_KDL="$DOTS_ROOT/system/greetd/niri/dms-generic.kdl" ;;
    *)        ui_info "No specific host profile — using generic dms.kdl" ;;
esac
install_file 0644 "$DMS_KDL" /etc/greetd/niri/dms.kdl \
    "greetd dms.kdl → /etc/greetd/niri/dms.kdl (profile: $HOST_PROFILE)"

# Greeter cache dir used by `dms-greeter --cache-dir`.
run_cmd "Create /var/cache/dms-greeter (user greeter)" \
    sudo install -d -o greeter -g greeter -m 0750 /var/cache/dms-greeter \
    || run_cmd "Create /var/cache/dms-greeter (plain)" sudo mkdir -p /var/cache/dms-greeter

# --- display managers -------------------------------------------------------------
for dm in gdm sddm; do
    if systemctl is-active --quiet "$dm" 2>/dev/null; then
        run_cmd "Disable conflicting display manager: $dm" sudo systemctl disable --now "$dm"
    fi
done

run_cmd "Enable greetd.service" sudo systemctl enable greetd.service
run_cmd "Set default target → graphical.target" sudo systemctl set-default graphical.target

# --- systemd user units -----------------------------------------------------------
USER_UNITS=(dms.service dfiles.service dsearch.service dux-chrome-theme.path niri-zoomd.service)

if is_dry_run; then
    ui_dry "Wire systemd --user .wants symlinks + enable ${USER_UNITS[*]}"
else
    # Explicitly wire .wants symlinks so units are enabled even when ./install
    # runs from a headless console TTY where systemd --user bus isn't active yet.
    USER_SD="$HOME/.config/systemd/user"
    mkdir -p "$USER_SD/niri.service.wants" \
             "$USER_SD/graphical-session.target.wants" \
             "$USER_SD/default.target.wants"

    [[ -f /usr/lib/systemd/user/dms.service ]] && {
        ln -sfn /usr/lib/systemd/user/dms.service "$USER_SD/niri.service.wants/dms.service"
        ln -sfn /usr/lib/systemd/user/dms.service "$USER_SD/graphical-session.target.wants/dms.service"
    }
    [[ -f /usr/lib/systemd/user/dfiles.service ]] && \
        ln -sfn /usr/lib/systemd/user/dfiles.service "$USER_SD/graphical-session.target.wants/dfiles.service"
    [[ -f /usr/lib/systemd/user/dsearch.service ]] && \
        ln -sfn /usr/lib/systemd/user/dsearch.service "$USER_SD/default.target.wants/dsearch.service"
    [[ -f "$USER_SD/niri-zoomd.service" ]] && \
        ln -sfn "$USER_SD/niri-zoomd.service" "$USER_SD/niri.service.wants/niri-zoomd.service"
    [[ -f "$USER_SD/dux-chrome-theme.path" ]] && \
        ln -sfn "$USER_SD/dux-chrome-theme.path" "$USER_SD/default.target.wants/dux-chrome-theme.path"

    if have dms; then
        dms systemd enable --compositor niri >/dev/null 2>&1 || true
    fi

    systemctl --user daemon-reload 2>/dev/null \
        || ui_warn "Could not reload user daemon (no user bus yet?) — .wants symlinks will activate on login."
    for unit in "${USER_UNITS[@]}"; do
        run_cmd "Enable user unit $unit" systemctl --user enable "$unit" \
            || ui_info "Wired $unit via .wants symlink (activates on graphical login)."
    done
fi

ui_info "Services stage complete. A reboot lands you in dms-greeter → niri."
