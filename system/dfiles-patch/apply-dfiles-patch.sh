#!/bin/bash
# system/dfiles-patch/apply-dfiles-patch.sh — idempotent patches for the
# dux-files (dfiles-shell) QML sources in ~/.config/dfiles-shell:
#
#   1. Common/Theme.qml
#        launcherWidthLarge:    960   (bigger launcher grid)
#        launcherHeightDefault: 700
#   2. Modules/ChooserWindow.qml
#        Wayland window title prefixed with "Dux Chooser · " so niri can float
#        portal picker windows without floating the main file manager (both
#        share app-id dev.duxlabs.files).
#
# Usage:
#   apply-dfiles-patch.sh            # just (re-)apply patches to what's there
#   apply-dfiles-patch.sh --refresh  # re-copy pristine sources from
#                                    # $XDG_RUNTIME_DIR/dfiles-shell/ first
#                                    # (use after a dux-files RPM upgrade), then
#                                    # re-apply the patches idempotently.
#
# Environment overrides:
#   DFILES_SHELL_DIR  (default ~/.config/dfiles-shell)
#   DFILES_SHELL_SRC  (default $XDG_RUNTIME_DIR/dfiles-shell)
set -euo pipefail

DEST="${DFILES_SHELL_DIR:-$HOME/.config/dfiles-shell}"
SRC="${DFILES_SHELL_SRC:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dfiles-shell}"

THEME="$DEST/Common/Theme.qml"
CHOOSER="$DEST/Modules/ChooserWindow.qml"

say()  { printf '  ✔ %s\n' "$1"; }
skip() { printf '  • %s\n' "$1"; }
die()  { printf '  ✖ %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- --refresh ----
if [[ "${1:-}" == "--refresh" ]]; then
    [[ -d "$SRC" ]] || die "refresh source '$SRC' does not exist — is dux-files running?"
    [[ -d "$DEST" ]] || mkdir -p "$DEST"
    cp -a "$SRC/." "$DEST/"
    skip "Refreshed $DEST from $SRC"
elif [[ -n "${1:-}" ]]; then
    die "Unknown option: $1 (expected --refresh or nothing)"
fi

[[ -f "$THEME"   ]] || die "$THEME not found — run stages/30-assets.sh or --refresh first"
[[ -f "$CHOOSER" ]] || die "$CHOOSER not found — run stages/30-assets.sh or --refresh first"

# --------------------------------------------------------- patch 1: Theme.qml --
# Set the numeric value of a `readonly property real KEY: N` line (sed only,
# no digit-adjacent backrefs -> unambiguous & idempotent).
set_theme_value() { # set_theme_value KEY VALUE
    local key="$1" val="$2"
    if grep -Eq "^[[:space:]]*readonly property (real|int) ${key}:[[:space:]]*${val}([[:space:]]|\$)" "$THEME"; then
        skip "Theme.qml: $key already $val"
        return 0
    fi
    if grep -Eq "^[[:space:]]*readonly property (real|int) ${key}:" "$THEME"; then
        sed -i -E "/^[[:space:]]*readonly property (real|int) ${key}:/s/:[[:space:]]*[-0-9.]+/: ${val}/" "$THEME"
        grep -Eq "^[[:space:]]*readonly property (real|int) ${key}:[[:space:]]*${val}([[:space:]]|\$)" "$THEME" \
            && say "Theme.qml: $key → $val" \
            || die "Theme.qml: patched $key but could not verify (upstream format changed?)"
    else
        die "Theme.qml: no '${key}:' property line found (upstream changed?)"
    fi
}

set_theme_value launcherWidthLarge 960
set_theme_value launcherHeightDefault 700

# ------------------------------------------------- patch 2: ChooserWindow.qml --
TITLE_PATCHED='title: "Dux Chooser · " + chooserTitle'
if grep -qF "$TITLE_PATCHED" "$CHOOSER"; then
    skip "ChooserWindow.qml: title already prefixed with 'Dux Chooser · '"
else
    # Fast path: sed on the exact known shape `title: chooserTitle`.
    sed -i -E 's|^([[:space:]]*)title:[[:space:]]*chooserTitle[[:space:]]*$|\1'"$TITLE_PATCHED"'|' "$CHOOSER"

    # Lenient fallback for slightly different upstream formatting.
    if ! grep -qF "$TITLE_PATCHED" "$CHOOSER"; then
        python3 - "$CHOOSER" <<'PYEOF' || true
import re, sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
new, n = re.subn(r'^([ \t]*)title:[ \t]*chooserTitle[ \t]*([//].*)?$',
                 r'\1title: "Dux Chooser · " + chooserTitle', src, flags=re.M)
if n:
    open(path, "w", encoding="utf-8").write(new)
PYEOF
    fi

    grep -qF "$TITLE_PATCHED" "$CHOOSER" \
        || die "ChooserWindow.qml: could not patch title (upstream changed?)"

    # Re-add the explanatory comment above the title if it got lost.
    if ! grep -qF 'stable prefix so niri can float' "$CHOOSER"; then
        python3 - "$CHOOSER" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").readlines()
c1 = "// Wayland title carries a stable prefix so niri can float portal picker windows\n"
c2 = "// without floating the main file manager (both share app-id dev.duxlabs.files).\n"
out = []
for ln in lines:
    if 'title: "Dux Chooser · " + chooserTitle' in ln:
        indent = ln[:len(ln) - len(ln.lstrip())]
        out.append(indent + c1)
        out.append(indent + c2)
    out.append(ln)
open(path, "w", encoding="utf-8").writelines(out)
PYEOF
    fi
    say 'ChooserWindow.qml: title → "Dux Chooser · " + chooserTitle'
fi

skip "dfiles-shell patches are up to date ($DEST)"
