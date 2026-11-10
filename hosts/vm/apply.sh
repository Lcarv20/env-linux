#!/bin/bash
# hosts/vm/apply.sh — QEMU/KVM guest quirks:
#   • qemu-guest-agent + spice-vdagent (only when actually running in QEMU/KVM)
#   • outputs.kdl with no hardcoded modes (Niri auto-detects the VM display)
#   • generic greeter dms.kdl (xcursor-size 32)
set -euo pipefail

HOST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$HOST_DIR/../../stages/lib.sh"

ui_header "VM · guest agents · generic outputs"

ensure_sudo

VIRT="$(systemd-detect-virt 2>/dev/null || true)"

if [[ "$VIRT" =~ ^(qemu|kvm)$ ]]; then
    if rpm -q qemu-guest-agent >/dev/null 2>&1 && rpm -q spice-vdagent >/dev/null 2>&1; then
        ui_step "qemu-guest-agent and spice-vdagent already installed"
    else
        run_cmd "Install qemu-guest-agent + spice-vdagent" \
            sudo dnf install -y qemu-guest-agent spice-vdagent \
            || ui_warn "Could not install VM guest agents — continuing."
    fi
    run_cmd "Enable qemu-guest-agent.service" \
        sudo systemctl enable --now qemu-guest-agent.service \
        || ui_warn "Could not enable qemu-guest-agent.service."
else
    ui_info "Not QEMU/KVM (systemd-detect-virt: '${VIRT:-none}') — skipping guest agents."
fi

run_cmd "outputs.kdl → ~/.config/niri/dms/outputs.kdl (no hardcoded 5K scale)" \
    install -Dm644 "$HOST_DIR/outputs.kdl" "$HOME/.config/niri/dms/outputs.kdl"

ui_info "VM stage complete — reboot to land in dms-greeter → niri."
