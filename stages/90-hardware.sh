#!/bin/bash
# stages/90-hardware.sh — dispatch to the host-specific quirk handler:
#   HOST_PROFILE=imac18-3 → hosts/imac18-3/apply.sh
#   HOST_PROFILE=vm       → hosts/vm/apply.sh
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

resolve_host_profile

case "$HOST_PROFILE" in
    imac18-3|vm)
        ui_header "90 · Hardware profile: $HOST_PROFILE"
        run_cmd "Run hosts/$HOST_PROFILE/apply.sh" \
            bash "$DOTS_ROOT/hosts/$HOST_PROFILE/apply.sh"
        ;;
    *)
        ui_info "No hardware profile (HOST_PROFILE='$HOST_PROFILE') — nothing to do."
        ;;
esac
