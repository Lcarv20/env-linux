import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

// Settings page for dankCursorAdapt. Talks to the live daemon instance
// through pluginService.pluginDaemonInstances for reactive status.

PluginSettings {
    id: root
    pluginId: "dankCursorAdapt"

    function daemon() {
        return pluginService && pluginService.pluginDaemonInstances
            ? (pluginService.pluginDaemonInstances["dankCursorAdapt"] || null)
            : null;
    }

    StyledText {
        text: "Adaptive Cursor"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent ? parent.width : 300
        wrapMode: Text.Wrap
        text: "Follows the DMS dynamic palette: dark mode uses the dark Bibata variants, light mode uses the -Light set, and the variant color matches the current accent. Only active while the cursor theme in Settings is set to \"System Default\" — picking a specific cursor theme pauses it."
        color: Theme.surfaceTextSecondary
        font.pixelSize: Theme.fontSizeSmall
    }

    // ------------------------------------------------------------ status
    StyledText {
        text: {
            const d = root.daemon();
            if (!d)
                return "Daemon not running";
            return d.statusMessage;
        }
        font.pixelSize: Theme.fontSizeMedium
        color: {
            const d = root.daemon();
            if (!d)
                return Theme.tempDanger;
            if (d.statusMessage.indexOf("error") === 0)
                return Theme.tempDanger;
            if (d.statusMessage.indexOf("standby") === 0 || d.statusMessage.indexOf("disabled") === 0)
                return Theme.surfaceTextSecondary;
            return Theme.surfaceText;
        }
    }

    StyledText {
        text: {
            const d = root.daemon();
            if (!d)
                return "";
            const accent = d.lastAccent || d.currentAccentHex;
            const mode = d.lastMode || d.currentMode;
            const variant = d.lastApplied || "—";
            return "Mode: " + mode + "   Accent: " + accent + "   Variant: " + variant;
        }
        color: Theme.surfaceTextSecondary
        font.pixelSize: Theme.fontSizeSmall
    }

    // ------------------------------------------------------------ actions
    Row {
        spacing: Theme.spacingM

        DButton {
            text: "Apply now"
            iconName: "refresh"
            onClicked: {
                const d = root.daemon();
                if (d)
                    d.applyNow();
            }
        }

        DButton {
            text: "Rebuild color map"
            iconName: "build"
            onClicked: {
                const d = root.daemon();
                if (d)
                    d.refreshMapAndApply();
            }
        }
    }

    // ------------------------------------------------------------ settings
    ToggleSetting {
        settingKey: "enabled"
        label: "Enable adaptive cursor"
        description: "Master switch. The plugin still only acts while the DMS cursor theme is \"System Default\"."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "invertSets"
        label: "Swap light/dark sets"
        description: "Use the dark cursor variants in light mode and the light variants in dark mode (inverted contrast)."
        defaultValue: false
    }

    // Re-apply immediately when any setting above changes, so toggles act
    // instantly instead of waiting for the next palette change.
    onSettingChanged: {
        const d = root.daemon();
        if (d)
            d.applyNow();
    }
}
