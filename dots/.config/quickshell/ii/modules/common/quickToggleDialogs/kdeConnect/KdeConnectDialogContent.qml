import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

StyledFlickable {
    id: root

    Layout.fillWidth: true
    Layout.fillHeight: true
    // Exactly what is laid out: any slack showed as an empty band above the footer.
    contentHeight: mainLayout.implicitHeight + mainLayout.anchors.topMargin
    // A page hugs this whole height: given any less the body can still scroll, and
    // the bottom fade greys out the last row.
    readonly property real naturalHeight: mainLayout.y + root.contentHeight
    clip: true

    readonly property var device: KdeConnectService.activeDevice
    readonly property bool connected: KdeConnectService.serviceEnabled && KdeConnectService.activeReachable
    readonly property bool hasBattery: root.connected && (root.device?.charge ?? -1) >= 0
    readonly property var plugins: root.device?.supportedPlugins ?? []
    function _has(plugin) {
        if (!root.connected)
            return false;
        return root.plugins.indexOf(plugin) >= 0;
    }
    readonly property bool hasAnyAction: root._has("kdeconnect_findmyphone")
        || root._has("kdeconnect_ping")
        || root._has("kdeconnect_clipboard")
        || root._has("kdeconnect_share")
    readonly property bool hasPairedDevices: KdeConnectService.devices.some(d => d.paired ?? false)

    signal pairRequested()

    property string feedbackMessage: ""
    property bool feedbackOk: true

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Item {
            id: maskRoot
            width: root.width
            height: root.height

            property color topFadeColor: root.atYBeginning ? Appearance.colors.colOnSurface : "transparent"
            property color bottomFadeColor: root.atYEnd ? Appearance.colors.colOnSurface : "transparent"

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: Math.min(46, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: maskRoot.topFadeColor }
                        GradientStop { position: 1.0; color: Appearance.colors.colOnSurface }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(0, parent.height - Math.min(46, parent.height / 2) - Math.min(56, parent.height / 2))
                    color: Appearance.colors.colOnSurface
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(56, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Appearance.colors.colOnSurface }
                        GradientStop { position: 1.0; color: maskRoot.bottomFadeColor }
                    }
                }
            }
        }
    }

    Connections {
        target: KdeConnectService
        function onActionFeedback(message, ok) {
            root.feedbackMessage = message;
            root.feedbackOk = ok;
            root.feedbackTimer.restart();
        }
    }

    Timer {
        id: feedbackTimer
        interval: 2600
        repeat: false
        onTriggered: {
            root.feedbackMessage = "";
            root.feedbackOk = true;
        }
    }

    ColumnLayout {
        id: mainLayout
        width: root.width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        spacing: 12

        // ── Empty states ────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: !KdeConnectService.available
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "phonelink_off"
                title: Translation.tr("KDE Connect is not installed")
                description: Translation.tr("Install the kdeconnect package to pair your phone with this desktop.")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: KdeConnectService.available && !KdeConnectService.serviceEnabled
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "sync_disabled"
                title: Translation.tr("KDE Connect service is disabled")
                description: Translation.tr("Turn it on with the switch above to reach your paired devices.")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
        Item {
            id: noPairedState
            Layout.fillWidth: true
            Layout.preferredHeight: 210
            visible: KdeConnectService.available && KdeConnectService.serviceEnabled && !root.hasPairedDevices
            ColumnLayout {
                anchors.fill: parent
                spacing: 8
                PagePlaceholder {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    shown: noPairedState.visible
                    icon: "phonelink_setup"
                    title: Translation.tr("No devices paired yet")
                    description: Translation.tr("Install the KDE Connect app on your phone, open it and pair with this desktop — or pair from here and accept the request on the phone.")
                    shape: MaterialShape.Shape.Cookie7Sided
                }
                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: noPairedState.visible
                    implicitHeight: 36
                    implicitWidth: pairText.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    contentItem: StyledText {
                        id: pairText
                        text: Translation.tr("Open Phone settings")
                        color: Appearance.colors.colOnPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.variableAxes: ({ "wght": 600 })
                    }
                    onClicked: root.pairRequested()
                    StyledToolTip {
                        text: Translation.tr("Device pairing and connection live in the Phone tab")
                    }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: KdeConnectService.available && KdeConnectService.serviceEnabled && root.hasPairedDevices && !root.connected
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "phonelink_erase"
                title: Translation.tr("Paired device is offline")
                description: Translation.tr("Open the KDE Connect app on your phone and make sure it is on the same network as this desktop.")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }

        // ── Connection pill ─────────────────────────────────────────────
        Item {
            visible: root.connected
            Layout.fillWidth: true
            implicitHeight: 56
            height: implicitHeight

            RowLayout {
                anchors.fill: parent
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12

                        MaterialSymbol {
                            text: (root.device?.type === "tablet") ? "tablet" : "smartphone"
                            iconSize: 22
                            color: Appearance.colors.colOnPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: KdeConnectService.activeDeviceDisplayName || root.device?.name || Translation.tr("Device")
                                font.bold: true
                                horizontalAlignment: Text.AlignLeft
                                color: Appearance.colors.colOnPrimary
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.hasBattery
                                    ? Math.round(root.device.charge) + "%"
                                        + (root.device.charging ? " · " + Translation.tr("Charging") : "")
                                    : Translation.tr("Connected")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                horizontalAlignment: Text.AlignLeft
                                color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.2)
                            }
                        }
                    }
                }

                RippleButton {
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: 22
                        color: Appearance.colors.colOnPrimary
                    }
                    onClicked: {
                        KdeConnectService.refreshDevices();
                        KdeConnectService.dispatchActionFeedback(Translation.tr("Refreshing devices…"), true);
                    }
                    StyledToolTip {
                        text: Translation.tr("Refresh devices")
                    }
                }
            }
        }

        // ── Action feedback ─────────────────────────────────────────────
        Rectangle {
            visible: root.feedbackMessage.length > 0
            Layout.fillWidth: true
            implicitHeight: feedbackText.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: root.feedbackOk ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer

            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                MaterialSymbol {
                    text: root.feedbackOk ? "check_circle" : "error"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.feedbackOk ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                }

                StyledText {
                    id: feedbackText
                    Layout.fillWidth: true
                    text: root.feedbackMessage
                    color: root.feedbackOk ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── Send actions ────────────────────────────────────────────────
        StyledText {
            visible: root.connected && root.hasAnyAction
            text: Translation.tr("Send actions")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            Layout.fillWidth: true
        }

        ColumnLayout {
            visible: root.connected && root.hasAnyAction
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { icon: "phone_in_talk", label: Translation.tr("Ring phone"), plugin: "kdeconnect_findmyphone" },
                    { icon: "notifications_active", label: Translation.tr("Send a ping"), plugin: "kdeconnect_ping" },
                    { icon: "content_paste", label: Translation.tr("Send clipboard to phone"), plugin: "kdeconnect_clipboard" },
                    { icon: "link", label: Translation.tr("Share clipboard as link/text"), plugin: "kdeconnect_share" },
                    { icon: "file_upload", label: Translation.tr("Send file…"), plugin: "kdeconnect_share" }
                ]

                delegate: RippleButton {
                    id: actionRow
                    required property var modelData
                    readonly property bool supported: root._has(modelData.plugin)

                    Layout.fillWidth: true
                    implicitHeight: 52
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive
                    opacity: supported ? 1.0 : 0.4
                    enabled: supported

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12

                        MaterialSymbol {
                            text: actionRow.modelData.icon
                            iconSize: 22
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: actionRow.modelData.label
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        MaterialSymbol {
                            visible: !actionRow.supported
                            text: "block"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                    }

                    onClicked: {
                        const devId = KdeConnectService.activeDeviceId;
                        switch (actionRow.modelData.icon) {
                        case "phone_in_talk":
                            KdeConnectService.findMyPhone(devId);
                            KdeConnectService.dispatchActionFeedback(Translation.tr("Ringing phone…"), true);
                            break;
                        case "notifications_active":
                            KdeConnectService.sendPing(devId, Translation.tr("Ping from ii"));
                            KdeConnectService.dispatchActionFeedback(Translation.tr("Ping sent"), true);
                            break;
                        case "content_paste":
                            if (String(Quickshell.clipboardText ?? "").length > 0) {
                                KdeConnectService.sendClipboard(devId);
                                KdeConnectService.dispatchActionFeedback(Translation.tr("Clipboard shared"), true);
                            } else {
                                KdeConnectService.dispatchActionFeedback(Translation.tr("Clipboard is empty"), false);
                            }
                            break;
                        case "link": {
                            const clip = String(Quickshell.clipboardText ?? "").trim();
                            if (!clip) {
                                KdeConnectService.dispatchActionFeedback(Translation.tr("Clipboard is empty"), false);
                                break;
                            }
                            const looksUrl = /^https?:\/\//i.test(clip) || /^[\w.-]+\.\w{2,}/.test(clip);
                            if (looksUrl) {
                                KdeConnectService.shareUrl(devId, clip);
                                KdeConnectService.dispatchActionFeedback(Translation.tr("Link shared"), true);
                            } else {
                                KdeConnectService.shareText(devId, clip);
                                KdeConnectService.dispatchActionFeedback(Translation.tr("Text shared"), true);
                            }
                            break;
                        }
                        case "file_upload":
                            KdeConnectService.sendFile(devId);
                            KdeConnectService.dispatchActionFeedback(Translation.tr("Pick a file to send…"), true);
                            break;
                        }
                    }

                    StyledToolTip {
                        text: actionRow.modelData.label
                    }
                }
            }
        }

        // ── Phone screen ────────────────────────────────────────────────
        // scrcpy over ADB: needs the phone reachable there, not just paired.
        StyledText {
            visible: root.connected
            text: Translation.tr("Phone screen")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            Layout.fillWidth: true
        }

        RowLayout {
            id: mirrorRow
            visible: root.connected
            Layout.fillWidth: true
            spacing: 6

            readonly property bool running: PhoneScrcpyService.mirrorRunning
            readonly property bool launching: PhoneScrcpyService.mirrorLaunching
            readonly property bool usable: PhoneScrcpyService.available && KdeConnectService.adbReachable

            RippleButton {
                id: mirrorButton
                Layout.fillWidth: true
                implicitHeight: 52
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                enabled: mirrorRow.running || (mirrorRow.usable && !mirrorRow.launching)
                opacity: mirrorRow.running || mirrorRow.usable ? 1.0 : 0.4
                // Focuses the window when it is already open.
                onClicked: PhoneScrcpyService.launchMirror()

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    MaterialSymbol {
                        text: mirrorRow.running ? "open_in_new" : "mobile_screen_share"
                        iconSize: 22
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: mirrorRow.running ? Translation.tr("Show mirror")
                            : mirrorRow.launching ? Translation.tr("Starting mirror…")
                            : Translation.tr("Start mirror")
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }

                    MaterialSymbol {
                        visible: !mirrorRow.running && !mirrorRow.usable
                        text: "block"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledToolTip {
                    text: !PhoneScrcpyService.available ? Translation.tr("scrcpy is not installed")
                        : !KdeConnectService.adbReachable && !mirrorRow.running
                            ? Translation.tr("The phone is not reachable over ADB")
                        : Translation.tr("Mirror the phone's screen in a window")
                }
            }

            RippleButton {
                visible: mirrorRow.running
                implicitWidth: 52
                implicitHeight: 52
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                onClicked: PhoneScrcpyService.stopMirror()

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "stop_circle"
                    iconSize: 22
                    color: Appearance.colors.colOnSurface
                }

                StyledToolTip {
                    text: Translation.tr("Stop mirror")
                }
            }
        }
    }
}
