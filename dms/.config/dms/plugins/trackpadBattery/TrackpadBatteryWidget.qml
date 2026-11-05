import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var devicesList: []

    function getDeviceIcon(type, isCharging) {
        if (isCharging)
            return "bolt";
        switch (type) {
        case UPowerDeviceType.Touchpad:
            return "touchpad_mouse";
        case UPowerDeviceType.Mouse:
            return "mouse";
        case UPowerDeviceType.Keyboard:
            return "keyboard";
        case UPowerDeviceType.Headphones:
            return "headphones";
        case UPowerDeviceType.Headset:
            return "headset_mic";
        case UPowerDeviceType.Speakers:
            return "speaker";
        case UPowerDeviceType.GamingInput:
            return "sports_esports";
        case UPowerDeviceType.Pen:
            return "stylus";
        default:
            return "bluetooth";
        }
    }

    function getShortName(fullName, type) {
        if (type === UPowerDeviceType.Touchpad || fullName.toLowerCase().indexOf("trackpad") !== -1)
            return "Trackpad";
        if (type === UPowerDeviceType.Mouse || fullName.toLowerCase().indexOf("mouse") !== -1)
            return "Mouse";
        if (type === UPowerDeviceType.Keyboard || fullName.toLowerCase().indexOf("keyboard") !== -1)
            return "Keyboard";
        if (type === UPowerDeviceType.Headphones || type === UPowerDeviceType.Headset)
            return "Audio";
        const parts = fullName.trim().split(" ");
        return parts[0] || "Device";
    }

    function resolveDeviceNames(dev) {
        let friendlyName = "";
        let hardwareModel = dev.model || "";

        if (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.devices) {
            const btDevs = Bluetooth.defaultAdapter.devices.values;
            const normPath = (dev.nativePath || "").toLowerCase().replace(/[:-]/g, "");
            const normSerial = (dev.serial || "").toLowerCase().replace(/[:-]/g, "");

            for (let i = 0; i < btDevs.length; i++) {
                const bt = btDevs[i];
                if (!bt || !bt.address)
                    continue;
                const normBt = bt.address.toLowerCase().replace(/[:-]/g, "");
                if (normBt.length > 0 && (normPath.indexOf(normBt) !== -1 || normSerial === normBt)) {
                    friendlyName = bt.alias || bt.name || "";
                    break;
                }
            }
        }

        if (!friendlyName) {
            friendlyName = hardwareModel || UPowerDeviceType.toString(dev.type) || "Wireless Device";
        }

        return {
            "friendly": friendlyName,
            "hardware": hardwareModel,
            "short": root.getShortName(friendlyName, dev.type)
        };
    }

    function refreshDevices() {
        const result = [];
        const devs = UPower.devices.values;
        for (let i = 0; i < devs.length; i++) {
            const dev = devs[i];
            if (!dev || !dev.ready)
                continue;
            if (dev.isLaptopBattery || dev.type === UPowerDeviceType.LinePower || dev.type === UPowerDeviceType.Unknown)
                continue;
            if (dev.percentage <= 0 && !dev.isPresent)
                continue;

            const pct = Math.round(dev.percentage * 100);
            if (pct <= 0)
                continue;

            const charging = dev.state === UPowerDeviceState.Charging;
            const names = root.resolveDeviceNames(dev);

            result.push({
                "id": dev.nativePath || ("dev_" + i),
                "displayName": names.friendly,
                "hardwareModel": names.hardware,
                "shortName": names.short,
                "percentage": pct,
                "charging": charging,
                "isLow": pct <= 20 && !charging,
                "type": dev.type,
                "icon": root.getDeviceIcon(dev.type, charging)
            });
        }
        root.devicesList = result;
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refreshDevices()
    }

    Component.onCompleted: {
        root.refreshDevices();
    }

    readonly property bool hasDevices: devicesList.length > 0

    // Only show on the top bar when peripheral devices are actually connected
    _visibilityOverride: true
    _visibilityOverrideValue: root.hasDevices

    // Control Center Integration
    ccWidgetIcon: "devices"
    ccWidgetPrimaryText: "Peripherals"
    ccWidgetSecondaryText: {
        if (devicesList.length === 0)
            return "No devices connected";
        if (devicesList.length === 1)
            return `${devicesList[0].displayName} • ${devicesList[0].percentage}%`;
        return `${devicesList.length} devices connected`;
    }
    ccWidgetIsActive: hasDevices

    // Bar Pill (Horizontal)
    horizontalBarPill: root.hasDevices ? horizontalPillComponent : null
    verticalBarPill: root.hasDevices ? verticalPillComponent : null

    Component {
        id: horizontalPillComponent
        Row {
            spacing: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: root.devicesList

                delegate: Row {
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter

                    DIcon {
                        name: modelData.icon
                        size: root.iconSize
                        color: modelData.isLow ? Theme.error : Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: `${modelData.shortName} ${modelData.percentage}%`
                        font.pixelSize: root.textSize
                        font.weight: Theme.fontWeightMedium
                        color: modelData.isLow ? Theme.error : Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    Component {
        id: verticalPillComponent
        Column {
            spacing: Theme.spacingM
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: root.devicesList

                delegate: Column {
                    spacing: Theme.spacingXXS
                    anchors.horizontalCenter: parent.horizontalCenter

                    DIcon {
                        name: modelData.icon
                        size: root.iconSize
                        color: modelData.isLow ? Theme.error : Theme.primary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: `${modelData.percentage}%`
                        font.pixelSize: root.textSize
                        font.weight: Theme.fontWeightMedium
                        color: modelData.isLow ? Theme.error : Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    popoutWidth: 320
    popoutHeight: Math.max(120, 30 + root.devicesList.length * 105)

    // Sleek Popout Card (No redundant headers or sub-badges)
    popoutContent: root.hasDevices ? popoutComponent : null

    Component {
        id: popoutComponent
        PopoutComponent {
            id: popoutCol
            headerText: ""
            detailsText: ""

            Column {
                width: parent.width
                spacing: Theme.spacingS
                padding: Theme.spacingS

                Repeater {
                    model: root.devicesList

                    delegate: DCard {
                        width: parent.width - Theme.spacingS * 2
                        height: cardRow.implicitHeight + pad * 2
                        restRadius: Theme.cornerRadiusL

                        Row {
                            id: cardRow
                            width: parent.width
                            spacing: Theme.spacingM

                            DRingGauge {
                                width: 68
                                height: 68
                                value: modelData.percentage / 100
                                startAngle: 135
                                spanAngle: 270
                                strokeWidth: 5
                                trackGap: 2
                                ringColor: modelData.isLow ? Theme.error : (modelData.charging ? Theme.primary : Theme.tertiary)
                                animated: true

                                DIcon {
                                    anchors.centerIn: parent
                                    name: modelData.icon
                                    size: 24
                                    color: modelData.isLow ? Theme.error : (modelData.charging ? Theme.primary : Theme.tertiary)
                                }
                            }

                            Column {
                                width: parent.width - 80
                                spacing: Theme.spacingXXS
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    text: `${modelData.percentage}%`
                                    font.pixelSize: Theme.fontSizeXLarge
                                    font.weight: Theme.fontWeightBold
                                    color: modelData.isLow ? Theme.error : Theme.onSurface
                                }

                                StyledText {
                                    width: parent.width
                                    text: modelData.displayName
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.onSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: modelData.charging ? "Charging via Cable" : (modelData.hardwareModel && modelData.hardwareModel !== modelData.displayName ? modelData.hardwareModel : "Battery")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: modelData.charging ? Theme.primary : Theme.onSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
