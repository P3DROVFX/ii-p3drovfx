pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import "../../../dock/utilities/UtilityFiles.js" as UtilityFiles

/*
 * Send (2x1): files to a phone over KDE Connect or to a LocalSend device on
 * the network. Drop files anywhere on the card, or choose them. The target
 * shape on the left is the state - a cookie waiting, a burst while a drag is
 * over it, a sunny check once sent; on the right, the way (a two-segment
 * group) and the device as chips, remembered between sessions.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "send_drop"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 14
    readonly property real targetWidth: 176

    readonly property bool localSend: (root.options?.backend ?? "kdeconnect") === "localsend"
    readonly property var kdeDevices: (KdeConnectService.devices ?? []).filter(device => device.paired)
    readonly property string kdeDeviceId: String(root.options?.kdeDevice ?? "") || KdeConnectService.activeDeviceId
    readonly property var kdeDevice: root.kdeDevices.find(device => device.id === root.kdeDeviceId) ?? null
    readonly property string localIp: String(root.options?.localsendIp ?? "")
    readonly property string localAlias: String(root.options?.localsendAlias ?? "")
    readonly property var localDevices: {
        const list = Array.from(LocalSend.discoveredDevices ?? []);
        // The remembered device stays pickable even before a scan finds it.
        if (root.localIp && !list.some(device => device.ip === root.localIp))
            list.unshift({ ip: root.localIp, name: root.localAlias || root.localIp });
        return list;
    }

    readonly property bool ready: root.localSend
        ? (LocalSend.available && root.localIp.length > 0)
        : (root.kdeDevice?.reachable === true)
    readonly property bool sending: root.localSend && LocalSend.sending
    property int lastSent: 0
    readonly property bool justSent: root.lastSent > 0 && !root.sending
    property bool dragOver: false

    function setBackend(backend) {
        if (!root.actionsEnabled)
            return;
        root.options.backend = backend;
        if (backend === "localsend" && LocalSend.available && !LocalSend.scanning)
            LocalSend.startScanning();
    }

    function send(paths) {
        if (!root.actionsEnabled || paths.length === 0 || !root.ready)
            return;
        if (root.localSend) {
            LocalSend.clearDroppedFiles();
            for (const path of paths)
                LocalSend.addDroppedFile(path);
            LocalSend.sendToDevice(root.localIp);
        } else {
            for (const path of paths)
                KdeConnectService.shareUrl(root.kdeDeviceId, UtilityFiles.fileUri(path));
        }
        root.lastSent = paths.length;
        sentTimer.restart();
    }

    Timer {
        id: sentTimer
        interval: 2600
        onTriggered: root.lastSent = 0
    }

    Process {
        id: picker
        command: ["bash", "-c",
            "if command -v kdialog >/dev/null 2>&1; then kdialog --getopenfilename \"$HOME\" --multiple 2>/dev/null | tr '\\n' '|'; "
            + "elif command -v zenity >/dev/null 2>&1; then zenity --file-selection --multiple --separator '|' 2>/dev/null; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = this.text.trim().split("|").map(s => s.trim()).filter(s => s.length > 0);
                root.send(UtilityFiles.dedupe(paths));
            }
        }
    }

    readonly property string targetName: root.localSend
        ? (root.localAlias || Translation.tr("No device chosen"))
        : (root.kdeDevice?.name || Translation.tr("No phone paired"))
    readonly property string stateText: {
        if (root.dragOver)
            return root.ready ? Translation.tr("Release to send") : Translation.tr("Pick a device first");
        if (root.sending)
            return Translation.tr("Sending…");
        if (root.justSent)
            return root.lastSent === 1 ? Translation.tr("Sent 1 file") : Translation.tr("Sent %1 files").arg(root.lastSent);
        if (root.localSend && !LocalSend.available)
            return Translation.tr("LocalSend not installed");
        return root.ready ? Translation.tr("Drop files here") : Translation.tr("No device ready");
    }

    DropArea {
        anchors.fill: parent
        enabled: root.actionsEnabled
        keys: ["text/uri-list"]
        onEntered: root.dragOver = true
        onExited: root.dragOver = false
        onDropped: drop => {
            root.dragOver = false;
            const paths = Array.from(drop.urls ?? []).map(url => UtilityFiles.pathFromUrl(url)).filter(p => p.length > 0);
            root.send(UtilityFiles.dedupe(paths));
            drop.accept();
        }
    }

    // ── Target ──
    Rectangle {
        id: target
        x: root.padding
        y: root.padding
        width: root.targetWidth
        height: root.designHeight - root.padding * 2
        radius: Appearance.rounding.normal
        color: root.dragOver ? ColorUtils.mix(WidgetColorScheme.accentColor, WidgetColorScheme.pillBgColor, 0.2) : WidgetColorScheme.pillBgColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Item {
            id: targetShape
            anchors.horizontalCenter: parent.horizontalCenter
            y: 28
            width: 108
            height: 108
            scale: root.dragOver ? 1.08 : 1

            Behavior on scale {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }

            MaterialShape {
                anchors.fill: parent
                shape: root.justSent ? MaterialShape.Shape.Sunny
                    : root.sending ? MaterialShape.Shape.Flower
                    : root.dragOver ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie12Sided
                color: root.justSent || root.dragOver || root.sending ? WidgetColorScheme.accentColor : WidgetColorScheme.pillFillColor

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.justSent ? "done_all" : (root.localSend ? "near_me" : "phone_android")
                iconSize: 44
                fill: 1
                color: root.justSent || root.dragOver || root.sending ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnPillFill
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            width: parent.width - 20
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.stateText
            color: WidgetColorScheme.textColorOnBg
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": 620, "wdth": 92, "ROND": 100 })
        }
    }

    // ── Way ──
    Item {
        id: way
        anchors.left: target.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding
        height: 40

        Repeater {
            model: [
                { id: "kdeconnect", label: "KDE Connect", symbol: "smartphone" },
                { id: "localsend", label: "LocalSend", symbol: "near_me" }
            ]

            delegate: WidgetButton {
                id: segment
                required property var modelData
                required property int index
                readonly property bool chosen: (segment.modelData.id === "localsend") === root.localSend
                readonly property real outerRadius: root.pill(height)
                property real joinRadius: segment.chosen || segment.down ? segment.outerRadius : Appearance.rounding.verysmall
                Behavior on joinRadius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                x: segment.index === 0 ? 0 : (way.width + 3) / 2
                width: (way.width - 3) / 2
                height: way.height
                symbol: segment.chosen ? "check" : segment.modelData.symbol
                symbolSize: 16
                label: segment.modelData.label
                labelSize: Appearance.font.pixelSize.smaller
                colFill: segment.chosen ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor
                colContent: segment.chosen ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
                topLeftRadius: segment.index === 0 ? segment.outerRadius : segment.joinRadius
                bottomLeftRadius: segment.index === 0 ? segment.outerRadius : segment.joinRadius
                topRightRadius: segment.index === 1 ? segment.outerRadius : segment.joinRadius
                bottomRightRadius: segment.index === 1 ? segment.outerRadius : segment.joinRadius
                onClicked: root.setBackend(segment.modelData.id)
            }
        }
    }

    // ── Devices ──
    Flickable {
        id: devicesFlick
        anchors.left: way.left
        anchors.right: way.right
        anchors.top: way.bottom
        anchors.topMargin: 12
        anchors.bottom: chooseKey.top
        anchors.bottomMargin: 10
        clip: true
        contentWidth: width
        contentHeight: chips.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Flow {
            id: chips
            width: devicesFlick.width
            spacing: 6

            Repeater {
                model: root.localSend ? root.localDevices : root.kdeDevices

                delegate: WidgetButton {
                    id: chip
                    required property var modelData
                    readonly property string chipName: root.localSend ? String(chip.modelData.name ?? chip.modelData.ip) : String(chip.modelData.name ?? "")
                    readonly property bool chosen: root.localSend ? chip.modelData.ip === root.localIp : chip.modelData.id === root.kdeDeviceId
                    readonly property bool online: root.localSend || chip.modelData.reachable === true
                    width: Math.min(chips.width, chipMeasure.implicitWidth + 50)
                    height: 34
                    symbol: chip.chosen ? "check" : (root.localSend ? "devices" : (chip.online ? "smartphone" : "phonelink_off"))
                    symbolSize: 16
                    label: chip.chipName
                    labelSize: Appearance.font.pixelSize.smaller
                    colFill: chip.chosen ? WidgetColorScheme.pillFillColor : WidgetColorScheme.pillBgColor
                    colContent: chip.chosen ? WidgetColorScheme.textColorOnPillFill : WidgetColorScheme.textColorOnBg
                    restRadius: chip.chosen ? Appearance.rounding.small : root.pill(height)
                    onClicked: {
                        if (root.localSend) {
                            root.options.localsendIp = String(chip.modelData.ip);
                            root.options.localsendAlias = chip.chipName;
                        } else {
                            root.options.kdeDevice = String(chip.modelData.id);
                        }
                    }

                    StyledText {
                        id: chipMeasure
                        visible: false
                        text: chip.chipName
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            WidgetButton {
                visible: root.localSend && LocalSend.available
                width: 84
                height: 34
                enabled: !LocalSend.scanning
                symbol: "radar"
                symbolSize: 16
                label: LocalSend.scanning ? Translation.tr("Scanning") : Translation.tr("Scan")
                labelSize: Appearance.font.pixelSize.smaller
                colFill: WidgetColorScheme.cardBgColor
                colContent: WidgetColorScheme.subtextColorOnBg
                onClicked: LocalSend.startScanning()
            }
        }

        StyledText {
            visible: (root.localSend ? root.localDevices.length : root.kdeDevices.length) === 0
            width: parent.width
            wrapMode: Text.Wrap
            y: root.localSend && LocalSend.available ? 44 : 0
            text: root.localSend
                ? (LocalSend.available ? Translation.tr("No devices found yet.") : Translation.tr("Install LocalSend in Settings → Devices & phone."))
                : Translation.tr("No paired phones. Pair one in KDE Connect.")
            color: WidgetColorScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    // ── Choose ──
    WidgetButton {
        id: chooseKey
        anchors.left: way.left
        anchors.right: way.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        height: 48
        enabled: root.ready && !root.sending
        symbol: "attach_file"
        label: Translation.tr("Choose files for %1").arg(root.targetName)
        labelAxes: ({ "wght": 620, "wdth": 92, "ROND": 100 })
        colFill: WidgetColorScheme.accentColor
        colContent: WidgetColorScheme.onAccentColor
        onClicked: picker.running = true
    }

    Component.onCompleted: {
        if (!root.isPreview && root.localSend && LocalSend.available && !LocalSend.scanning)
            LocalSend.startScanning();
    }
}
