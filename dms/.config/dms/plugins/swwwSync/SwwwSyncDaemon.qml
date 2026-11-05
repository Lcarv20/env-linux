import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property bool isExternalManagerActive: {
        var prefs = SettingsData.screenPreferences?.wallpaper;
        return Array.isArray(prefs) && prefs.length === 0;
    }

    onIsExternalManagerActiveChanged: {
        if (!isExternalManagerActive) {
            console.info("swwwSync: 'Use external manager' disabled. Terminating awww-daemon.");
            Quickshell.execDetached(["awww", "kill"]);
        } else {
            console.info("swwwSync: 'Use external manager' enabled. Starting awww-daemon.");
            daemonCheckProcess.running = true;
        }
    }

    Connections {
        target: SessionData
        function onWallpaperPathChanged() {
            if (root.isExternalManagerActive) {
                applyWallpaper(SessionData.wallpaperPath);
            }
        }
    }

    function mapTransition(trans) {
        switch (trans) {
        case "stripes":
            return "wave";
        case "disc":
            return "center";
        case "portal":
            return "outer";
        case "iris bloom":
            return "grow";
        case "wipe":
            return "wipe";
        case "fade":
            return "fade";
        case "pixelate":
            return "any";
        case "random":
            return "random";
        case "none":
            return "none";
        default:
            return "fade";
        }
    }

    function mapResize(fillMode) {
        switch (fillMode) {
        case "Fit":
            return "fit";
        case "Stretch":
            return "stretch";
        case "Pad":
            return "no";
        case "Fill":
        default:
            return "crop";
        }
    }

    function applyWallpaper(path) {
        if (!isExternalManagerActive || !path || path.startsWith("#"))
            return;

        var dmsTrans = SessionData.wallpaperTransition || "fade";
        var awwwTrans = mapTransition(dmsTrans);
        var fillMode = SettingsData.wallpaperFillMode || "Fill";
        var resize = mapResize(fillMode);

        var args = [
            "awww",
            "img",
            path,
            "--filter",
            "Bilinear",
            "--resize",
            resize,
            "--transition-type",
            awwwTrans,
            "--transition-fps",
            "60"
        ];

        if (awwwTrans !== "none") {
            args.push("--transition-duration");
            args.push("1");
        }

        var proc = processComponent.createObject(root, {
            cmdArgs: args
        });
        if (proc) {
            proc.running = true;
        }
    }

    Component {
        id: processComponent

        Process {
            property var cmdArgs: []
            command: cmdArgs

            onExited: (exitCode) => {
                destroy();
            }
        }
    }

    Process {
        id: daemonCheckProcess
        command: ["awww", "query"]
        onExited: (exitCode) => {
            if (!root.isExternalManagerActive)
                return;

            if (exitCode !== 0) {
                Quickshell.execDetached(["awww-daemon"]);
                initTimer.start();
            } else if (SessionData.wallpaperPath) {
                applyWallpaper(SessionData.wallpaperPath);
            }
        }
    }

    Timer {
        id: initTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.isExternalManagerActive && SessionData.wallpaperPath) {
                applyWallpaper(SessionData.wallpaperPath);
            }
        }
    }

    Component.onCompleted: {
        console.info("swwwSync: Animated wallpaper bridge active. External manager enabled:", isExternalManagerActive);
        if (isExternalManagerActive) {
            daemonCheckProcess.running = true;
        } else {
            Quickshell.execDetached(["awww", "kill"]);
        }
    }

    Component.onDestruction: {
        Quickshell.execDetached(["awww", "kill"]);
    }
}
