#!/bin/bash
# hosts/imac18-3/apply.sh — iMac18,3 hardware quirks:
#   a) kernel args via grubby (s2idle sleep, macOS backlight quirks, 5K panel)
#   b) bt-resume-rescue (Bluetooth wakeup wedge fix) as a systemd drop-in
#   c) DKMS audio module snd_hda_macbookpro
#   d) Niri outputs.kdl (eDP-1 4K@1.25) + greeter dms.kdl (JuxCursor 37)
set -euo pipefail

HOST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$HOST_DIR/../../stages/lib.sh"

ui_header "iMac18,3 · kernel args · BT rescue · DKMS audio · outputs"

ensure_sudo

# --- a) kernel boot args -----------------------------------------------------------
KARGS=(mem_sleep_default=s2idle "acpi_osi=!Darwin" acpi_backlight=video
       "video=eDP-1:5120x2880MR@60e")

CURRENT_ARGS="$(grubby --info=DEFAULT 2>/dev/null | sed -n 's/^args="\(.*\)"/\1/p' || true)"
missing_args=()
for arg in "${KARGS[@]}"; do
    grep -qF -- "$arg" <<<"${CURRENT_ARGS:-}" || missing_args+=("$arg")
done

if ((${#missing_args[@]} == 0)); then
    ui_step "Kernel args already present on default kernel"
else
    run_cmd "grubby: add args to ALL kernels (${missing_args[*]})" \
        sudo grubby --update-kernel=ALL --args="${missing_args[*]}"
fi

# --- b) bt-resume-rescue ------------------------------------------------------------
install_file 0755 "$HOST_DIR/bt-resume-rescue" /usr/local/sbin/bt-resume-rescue \
    "bt-resume-rescue → /usr/local/sbin/bt-resume-rescue"
install_file 0644 "$HOST_DIR/bt-resume-rescue.conf" \
    /etc/systemd/system/systemd-suspend.service.d/bt-resume-rescue.conf \
    "BT rescue drop-in → systemd-suspend.service.d/"
run_cmd "systemctl daemon-reload" sudo systemctl daemon-reload

# --- c) DKMS audio: snd_hda_macbookpro ------------------------------------------------
run_cmd "Install DKMS build deps (dkms + kernel-devel)" \
    sudo dnf install -y dkms "kernel-devel-$(uname -r)" \
    || run_cmd "Install DKMS build deps (dkms + latest kernel-devel)" \
           sudo dnf install -y dkms kernel-devel \
    || ui_warn "Could not install dkms/kernel-devel — audio module skipped."

if have dkms; then
    SRC=""
    for d in /usr/src/snd_hda_macbookpro-*; do
        [[ -d "$d" ]] && SRC="$d" && break
    done

    if [[ -z "$SRC" ]]; then
        run_cmd "Clone snd_hda_macbookpro (davidjo)" \
            sudo git clone --depth=1 https://github.com/davidjo/snd_hda_macbookpro.git \
                /usr/src/snd_hda_macbookpro-git
        SRC="/usr/src/snd_hda_macbookpro-git"
    fi

    MOD_NAME="$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p'  "$SRC/dkms.conf" 2>/dev/null | head -1)"
    MOD_VER="$(sed -n  's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$SRC/dkms.conf" 2>/dev/null | head -1)"
    MOD_NAME="${MOD_NAME:-snd_hda_macbookpro}"
    MOD_VER="${MOD_VER:-git}"

    WANT_DIR="/usr/src/$MOD_NAME-$MOD_VER"
    if [[ "$SRC" != "$WANT_DIR" ]]; then
        run_cmd "Normalize DKMS source dir → $WANT_DIR" sudo cp -a "$SRC" "$WANT_DIR"
    fi

    if dkms status 2>/dev/null | grep -q "$MOD_NAME/$MOD_VER.*installed"; then
        ui_step "DKMS $MOD_NAME/$MOD_VER already installed"
    else
        run_cmd "dkms add $MOD_NAME/$MOD_VER" sudo dkms add -m "$MOD_NAME" -v "$MOD_VER" \
            || ui_warn "dkms add returned non-zero (already added?) — continuing."
        run_cmd "dkms build $MOD_NAME/$MOD_VER" sudo dkms build -m "$MOD_NAME" -v "$MOD_VER" \
            || ui_warn "dkms build failed — rebuild manually after booting the matching kernel."
        run_cmd "dkms install $MOD_NAME/$MOD_VER" sudo dkms install -m "$MOD_NAME" -v "$MOD_VER" \
            || ui_warn "dkms install failed — speakers/mic may need a manual rebuild."
    fi
else
    ui_warn "dkms unavailable — audio module not built."
fi

# --- d) outputs + greeter dms.kdl ------------------------------------------------------
run_cmd "outputs.kdl → ~/.config/niri/dms/outputs.kdl (eDP-1 3840x2160@59.997, scale 1.25)" \
    install -Dm644 "$HOST_DIR/outputs.kdl" "$HOME/.config/niri/dms/outputs.kdl"

install_file 0644 "$HOST_DIR/../../system/greetd/niri/dms-imac18-3.kdl" \
    /etc/greetd/niri/dms.kdl \
    "greetd dms.kdl → /etc/greetd/niri/dms.kdl (iMac18,3: JuxCursor 37)"

ui_info "iMac18,3 stage complete — REBOOT required for kernel args, DKMS audio and greetd."
