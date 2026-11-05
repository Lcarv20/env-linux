import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Plugins

// dankCursorAdapt — daemon plugin.
//
// Follows the DMS dynamic palette and switches the cursor theme to the
// installed variant whose color is closest to the current accent color
// (dark variants in dark mode, *-Light variants in light mode).
//
// GATING: this plugin only acts while the DMS cursor setting is
// "System Default". When the user picks a specific cursor theme, the
// plugin stands down (and syncs gsettings/GTK to the manual choice so
// GTK apps agree with niri/Xresources, which DMS updates itself).

QtObject {
    id: root

    // injected by PluginService
    property string pluginId: ""
    property var pluginService: null

    readonly property var log: Log.scoped("dankCursorAdapt")

    // ------------------------------------------------------------------ cfg
    readonly property string family: "Bibata-Material"
    readonly property string lightSuffix: "-Light"
    readonly property real chromaThreshold: 0.18
    readonly property string mapPath: {
        const cache = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache");
        return cache + "/dms/cursor-adapt-map.json";
    }
    readonly property string refreshTool: (Quickshell.env("HOME") || "") + "/.local/bin/dms-cursor-adapt"

    // --------------------------------------------------------------- state
    property var colorMap: ({})
    property bool mapLoaded: false
    property bool mapRefreshAttempted: false
    property string lastApplied: ""
    property string lastMode: ""
    property string lastAccent: ""
    property string statusMessage: "starting"

    readonly property bool cursorIsDefault: {
        const cs = SettingsData.cursorSettings;
        const theme = cs && cs.theme ? cs.theme : "System Default";
        return theme === "System Default";
    }
    readonly property bool enabled: pluginService
        ? pluginService.loadPluginData(pluginId, "enabled", true)
        : true;
    // Swap the variant sets: dark-mode accents pick from the *-Light pool and
    // vice versa. Some people prefer the contrast of "inverted" cursors.
    readonly property bool invertSets: pluginService
        ? pluginService.loadPluginData(pluginId, "invertSets", false)
        : false;
    readonly property string currentMode: SessionData.isLightMode ? "light" : "dark";
    readonly property string currentAccentHex: colorToHex(Theme.primary);

    // ------------------------------------------------------------ plumbing
    property Timer applyTimer: Timer {
        interval: 600
        onTriggered: root.applyNow()
    }

    Component.onCompleted: {
        log.info("daemon loaded (cursor gate: " + (cursorIsDefault ? "System Default" : "manual theme") + ")");
        // QtObject has no default property, so hook signals imperatively
        // (same pattern DMS's own Theme.qml uses).
        SettingsData.cursorSettingsChanged.connect(onCursorConfigChanged);
        Theme.primaryChanged.connect(scheduleApply);
        SessionData.isLightModeChanged.connect(scheduleApply);
        Qt.callLater(startup);
    }

    function startup() {
        statusMessage = cursorIsDefault ? "loading color map" : "standby: manual cursor theme";
        loadMap(() => {
            if (cursorIsDefault)
                scheduleApply();
            else
                standDown();
        });
    }

    // -------------------------------------------------------------- events
    function onCursorConfigChanged() {
        if (cursorIsDefault) {
            // (Re)activate. DMS just rewrote cursor.kdl/Xresources with its
            // possibly-stale cached "system default"; re-assert fresh state.
            if (!mapLoaded)
                loadMap(() => scheduleApply());
            else
                scheduleApply();
        } else {
            applyTimer.stop();
            standDown();
        }
    }

    function scheduleApply() {
        if (!cursorIsDefault || !enabled) {
            if (!enabled)
                statusMessage = "disabled in plugin settings";
            return;
        }
        applyTimer.restart();
    }

    // When the user picks an explicit cursor theme, DMS updates niri's
    // cursor.kdl and ~/.Xresources on *changes* — but not at startup, and it
    // never touches gsettings/GTK/default. Do a full sync of every layer to
    // the manual choice so they all agree, then idle (no palette following).
    function standDown() {
        const cs = SettingsData.cursorSettings;
        const manual = cs && cs.theme ? cs.theme : "";
        if (!manual || manual === "System Default")
            return;
        lastApplied = "";
        lastMode = "";
        lastAccent = "";
        statusMessage = "standby: manual cursor theme (" + manual + ")";
        log.info("standing down, syncing all layers to manual theme: " + manual);
        Proc.runCommand("dankCursorAdaptStandDown", ["sh", "-c", applyScript(manual, cs.size || 24, !!(cs.niri && cs.niri.hideWhenTyping), cs.niri ? (cs.niri.hideAfterInactiveMs || 0) : 0)]);
    }

    // ------------------------------------------------------------ applying
    function applyNow() {
        if (!cursorIsDefault) {
            statusMessage = "standby: manual cursor theme";
            return;
        }
        if (!enabled) {
            statusMessage = "disabled in plugin settings";
            return;
        }
        if (!mapLoaded) {
            if (!mapRefreshAttempted) {
                mapRefreshAttempted = true;
                refreshMapAndApply();
            }
            return;
        }
        const accent = currentAccentHex;
        const mode = currentMode;
        const theme = pickVariant(accent, (mode === "light") !== invertSets);
        if (!theme) {
            statusMessage = "error: no matching cursor variant";
            log.error("no variant matched accent " + accent + " (map has " + Object.keys(colorMap).length + " entries)");
            return;
        }
        const cs = SettingsData.cursorSettings;
        const size = cs && cs.size ? cs.size : 24;
        const hideTyping = !!(cs && cs.niri && cs.niri.hideWhenTyping);
        const hideAfterMs = cs && cs.niri ? (cs.niri.hideAfterInactiveMs || 0) : 0;

        lastApplied = theme;
        lastMode = mode;
        lastAccent = accent;
        statusMessage = "active: " + theme + (invertSets ? " (sets swapped)" : "");

        Proc.runCommand("dankCursorAdaptApply", ["sh", "-c", applyScript(theme, size, hideTyping, hideAfterMs)], (stdout, exitCode) => {
            if (exitCode === 0) {
                log.info("applied " + theme + " (mode=" + mode + ", accent=" + accent + ", size=" + size + ")");
                if (pluginService)
                    pluginService.savePluginData(pluginId, "lastApplied", { theme: theme, mode: mode, accent: accent });
            } else {
                statusMessage = "error: apply failed (exit " + exitCode + ")";
                log.error("apply failed: " + stdout);
            }
        });
    }

    // Map reload + re-apply (used by the settings page button).
    function reloadMapAndApply() {
        loadMap(() => {
            if (cursorIsDefault)
                applyNow();
        });
    }

    // Rebuild the map with the external tool, then reload + apply.
    function refreshMapAndApply() {
        Proc.runCommand("dankCursorAdaptRefresh", [refreshTool, "--refresh-map"], (stdout, exitCode) => {
            if (exitCode !== 0)
                log.warn("map refresh tool failed: " + stdout);
            reloadMapAndApply();
        });
    }

    // ------------------------------------------------------------ map i/o
    function loadMap(callback) {
        Proc.runCommand("dankCursorAdaptMapLoad", ["cat", mapPath], (stdout, exitCode) => {
            if (exitCode === 0 && stdout && stdout.trim()) {
                try {
                    colorMap = JSON.parse(stdout.trim());
                    mapLoaded = true;
                    log.info("color map loaded: " + Object.keys(colorMap).length + " variants");
                } catch (e) {
                    statusMessage = "error: bad color map JSON";
                    log.error("failed to parse color map: " + e.message);
                }
            } else if (!mapRefreshAttempted) {
                mapRefreshAttempted = true;
                log.info("color map missing at " + mapPath + " — building via " + refreshTool + " --refresh-map");
                refreshMapAndApply();
                return;
            } else {
                statusMessage = "error: color map missing (run --refresh-map)";
                log.error("color map not readable at " + mapPath);
            }
            if (callback && mapLoaded)
                callback();
        });
    }

    // ------------------------------------------------------------ matching
    function colorToHex(c) {
        const part = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
        return "#" + part(c.r) + part(c.g) + part(c.b);
    }

    function hexToColor(hex) {
        const h = hex.replace("#", "");
        return Qt.rgba(parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255, 1);
    }

    function hueDistance(a, b) {
        const d = Math.abs(a - b) % 1.0;
        return Math.min(d, 1.0 - d);
    }

    function pickVariant(accentHex, wantLight) {
        const acc = hexToColor(accentHex);
        let aHue = acc.hslHue, aSat = acc.hslSaturation, aLight = acc.hslLightness;
        if (aHue < 0) aHue = 0;
        if (aSat < 0) aSat = 0;
        const aChroma = aSat >= chromaThreshold;

        let bestStrict = null, bestStrictScore = 1e9;
        let bestAny = null, bestAnyScore = 1e9;

        for (const name in colorMap) {
            if (name.endsWith(lightSuffix) !== wantLight)
                continue;
            const c = hexToColor(colorMap[name]);
            let h = c.hslHue, s = c.hslSaturation, l = c.hslLightness;
            if (h < 0) h = 0;
            if (s < 0) s = 0;
            const chroma = s >= chromaThreshold;

            let score;
            if (aChroma === chroma) {
                if (aChroma)
                    score = hueDistance(aHue, h) * 8.0 + Math.abs(aSat - s) * 0.5 + Math.abs(aLight - l) * 0.3;
                else
                    score = Math.abs(aLight - l) + 0.3 * Math.abs(aSat - s);
            } else {
                score = 99.0;
            }
            if (score < bestStrictScore) {
                bestStrictScore = score;
                bestStrict = name;
            }
            const loose = aChroma
                ? hueDistance(aHue, h) * 8.0 + Math.abs(aSat - s) * 0.5 + Math.abs(aLight - l) * 0.3
                : Math.abs(aLight - l) + 0.3 * Math.abs(aSat - s);
            if (loose < bestAnyScore) {
                bestAnyScore = loose;
                bestAny = name;
            }
        }
        if (bestStrict && bestStrictScore < 99.0)
            return bestStrict;
        return bestAny;
    }

    // ------------------------------------------------------ script builders
    function validName(theme) {
        return /^[A-Za-z0-9._-]+$/.test(theme);
    }

    // All layer writes in one shot, ordered:
    // ~/.icons/default pointer -> gsettings -> GTK ini -> Xresources -> niri cursor.kdl -> reload
    function applyScript(theme, size, hideTyping, hideAfterMs) {
        if (!validName(theme))
            return "echo 'invalid theme name' >&2; exit 1";
        const kdl = [
            "// ! DO NOT EDIT !",
            "// ! AUTO-GENERATED BY DMS !",
            "// ! CHANGES WILL BE OVERWRITTEN !",
            "// ! PLACE YOUR CUSTOM CONFIGURATION ELSEWHERE !",
            "",
            "cursor {",
            "    xcursor-theme \"" + theme + "\"",
            "    xcursor-size " + size
        ];
        if (hideTyping)
            kdl.push("    hide-when-typing");
        if (hideAfterMs > 0)
            kdl.push("    hide-after-inactive-ms " + hideAfterMs);
        kdl.push("}");
        const kdlArgs = kdl.map(l => "'" + l + "'").join(" ");

        return [
            "set -e",
            "mkdir -p \"$HOME/.icons/default\" \"$HOME/.config/niri/dms\"",
            "printf '%s\\n' '[Icon Theme]' 'Name=Default' 'Comment=Default Cursor Theme (managed by dankCursorAdapt)' 'Inherits=" + theme + "' > \"$HOME/.icons/default/index.theme\"",
            "gsettings set org.gnome.desktop.interface cursor-theme " + theme,
            "gsettings set org.gnome.desktop.interface cursor-size " + size,
            gtkSyncLines(theme, size),
            "if [ -f \"$HOME/.Xresources\" ]; then",
            "  grep -q '^\\s*Xcursor\\.theme:' \"$HOME/.Xresources\" && sed -i \"s|^\\s*Xcursor\\.theme:.*|Xcursor.theme: " + theme + "|\" \"$HOME/.Xresources\" || printf 'Xcursor.theme: %s\\n' " + theme + " >> \"$HOME/.Xresources\"",
            "  grep -q '^\\s*Xcursor\\.size:' \"$HOME/.Xresources\" && sed -i \"s|^\\s*Xcursor\\.size:.*|Xcursor.size: " + size + "|\" \"$HOME/.Xresources\" || printf 'Xcursor.size: %s\\n' " + size + " >> \"$HOME/.Xresources\"",
            "fi",
            "printf '%s\\n' " + kdlArgs + " > \"$HOME/.config/niri/dms/cursor.kdl\"",
            "niri msg action load-config-file || true"
        ].join("\n");
    }

    function gtkSyncLines(theme, size) {
        return [
            "sync_gtk() {",
            "  f=\"$1\"; [ -f \"$f\" ] || return 0",
            "  if grep -q '^gtk-cursor-theme-name=' \"$f\"; then sed -i \"s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=" + theme + "/\" \"$f\"; else printf 'gtk-cursor-theme-name=%s\\n' " + theme + " >> \"$f\"; fi",
            "  if grep -q '^gtk-cursor-theme-size=' \"$f\"; then sed -i \"s/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=" + size + "/\" \"$f\"; else printf 'gtk-cursor-theme-size=%s\\n' " + size + " >> \"$f\"; fi",
            "}",
            "sync_gtk \"$HOME/.config/gtk-3.0/settings.ini\"",
            "sync_gtk \"$HOME/.config/gtk-4.0/settings.ini\""
        ].join("\n");
    }
}
