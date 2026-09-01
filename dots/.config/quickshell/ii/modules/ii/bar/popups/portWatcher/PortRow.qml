pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * One served port.
 *
 * Same two-page slide the Wi-Fi and Bluetooth dialogs use: the row itself
 * stays a row, and its actions live on a second page that slides in from the
 * right. Corner radii follow the list position and round the edges that touch
 * the open row.
 */
Item {
    id: root

    property var entry: null
    property bool showActions: false
    property bool isFirst: false
    property bool isLast: false
    property bool aboveOpen: false
    property bool belowOpen: false
    property int animDelay: 0
    property bool startAnim: false

    signal openRequested
    signal closeRequested

    readonly property bool exposed: root.entry?.exposed ?? false
    readonly property bool manageable: root.entry?.canManage ?? false
    readonly property bool isTcp: String(root.entry?.protocol ?? "") === "tcp"
    readonly property int connections: Number(root.entry?.connections ?? 0)
    readonly property string category: String(root.entry?.category ?? "app")
    readonly property bool busy: PortWatcher.actionBusy
        && PortWatcher.busyPortId === String(root.entry?.id ?? "")

    readonly property string categoryIcon: {
        switch (root.category) {
        case "web":
            return "language";
        case "database":
            return "database";
        case "dev":
            return "terminal";
        case "system":
            return "settings_ethernet";
        default:
            return "deployed_code";
        }
    }

    implicitHeight: 56
    height: implicitHeight
    clip: true

    // Radius system, straight from WifiNetworkItem: outer corners at the ends
    // of the list, tight ones between rows, full pills for the open row and
    // for the edges it touches.
    readonly property real rFull: height / 2
    readonly property real rOuter: Appearance.rounding.large
    readonly property real rInner: Appearance.rounding.verysmall

    readonly property real topRadius: root.showActions ? rFull : (root.aboveOpen ? rFull : (root.isFirst ? rOuter : rInner))
    readonly property real bottomRadius: root.showActions ? rFull : (root.belowOpen ? rFull : (root.isLast ? rOuter : rInner))

    // ── Entrance ─────────────────────────────────────────────────────────────
    opacity: 0.0
    transform: Translate {
        id: rowTranslate
        y: 18
    }

    onStartAnimChanged: {
        if (root.startAnim) {
            root.opacity = 0.0;
            rowTranslate.y = 18;
            Qt.callLater(() => rowAnim.start());
        } else {
            rowAnim.stop();
            root.opacity = 0.0;
            rowTranslate.y = 18;
        }
    }

    SequentialAnimation {
        id: rowAnim
        PauseAnimation {
            duration: root.animDelay
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 1.0
                duration: 260
            }
            NumberAnimation {
                target: rowTranslate
                property: "y"
                to: 0
                duration: 340
                easing.type: Easing.OutCubic
            }
        }
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: flick.width * 2 + 8
        contentHeight: flick.height
        interactive: false
        clip: true

        contentX: root.showActions ? (flick.width + 8) : 0

        Behavior on contentX {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutExpo
            }
        }

        Row {
            height: flick.height
            spacing: 8

            // ── PAGE 1: the port ─────────────────────────────────────────────
            Rectangle {
                id: mainCard

                width: flick.width
                height: flick.height

                topLeftRadius: root.topRadius
                topRightRadius: root.topRadius
                bottomLeftRadius: root.bottomRadius
                bottomRightRadius: root.bottomRadius

                color: cardMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                    : cardMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                    : Appearance.colors.colSurfaceContainerHighest

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                Behavior on topLeftRadius {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on topRightRadius {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on bottomLeftRadius {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on bottomRightRadius {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openRequested()
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 20
                        rightMargin: 16
                    }
                    spacing: 10

                    MaterialSymbol {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.categoryIcon
                        fill: 1
                        iconSize: 22
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: ":" + String(root.entry?.port ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                        textFormat: Text.PlainText
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        // The protocol earns its place: a TCP and a UDP listener
                        // on the same port are two rows, and without it they
                        // read as the same row printed twice.
                        text: {
                            const parts = [String(root.entry?.process ?? ""),
                                String(root.entry?.protocol ?? "").toUpperCase()];
                            const service = String(root.entry?.service ?? "");
                            if (service.length > 0)
                                parts.push(service);
                            return parts.join(" · ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.35)
                        textFormat: Text.PlainText
                    }

                    StyledText {
                        visible: root.connections > 0
                        text: String(root.connections)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }

                    MaterialSymbol {
                        text: root.exposed ? "public" : "lock"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.normal
                        color: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.3)
                    }

                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: 22
                        color: Appearance.colors.colSubtext
                        opacity: cardMouse.containsMouse ? 1 : 0.6

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                    }
                }

                StyledToolTip {
                    text: {
                        const command = String(root.entry?.command ?? "");
                        const pid = Number(root.entry?.pid ?? 0);
                        const where = root.exposed
                            ? Translation.tr("Reachable from the network")
                            : Translation.tr("Local only");
                        const identity = pid > 0
                            ? Translation.tr("PID %1 · %2").arg(pid).arg(where)
                            : where;
                        return command.length > 0 ? `${identity}\n${command}` : identity;
                    }
                    alternativeVisibleCondition: cardMouse.containsMouse
                    extraVisibleCondition: false
                    requireOverlay: false
                }
            }

            // ── PAGE 2: what you can do with it ──────────────────────────────
            RowLayout {
                width: flick.width
                height: flick.height
                spacing: 8

                // Back
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    radius: root.rFull
                    color: backMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                        : backMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                        : Appearance.colors.colSurfaceContainerHighest

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_forward"
                        iconSize: 24
                        color: Appearance.colors.colOnSurface
                    }

                    StyledToolTip {
                        text: Translation.tr("Back")
                        alternativeVisibleCondition: backMouse.containsMouse
                        extraVisibleCondition: false
                        requireOverlay: false
                    }
                }

                // Copy address
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    radius: root.rFull
                    color: copyMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                        : copyMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                        : Appearance.colors.colSurfaceContainerHighest

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    MouseArea {
                        id: copyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            PortWatcher.copyAddress(root.entry);
                            root.closeRequested();
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "content_copy"
                        iconSize: 22
                        color: Appearance.colors.colOnSurface
                    }

                    StyledToolTip {
                        text: Translation.tr("Copy %1").arg(PortWatcher.addressFor(root.entry))
                        alternativeVisibleCondition: copyMouse.containsMouse
                        extraVisibleCondition: false
                        requireOverlay: false
                    }
                }

                // Open in the browser
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    radius: root.rFull
                    opacity: root.isTcp ? 1 : 0.4
                    color: openMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                        : openMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                        : Appearance.colors.colSurfaceContainerHighest

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    MouseArea {
                        id: openMouse
                        anchors.fill: parent
                        enabled: root.isTcp
                        hoverEnabled: root.isTcp
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            PortWatcher.openInBrowser(root.entry);
                            root.closeRequested();
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_new"
                        iconSize: 22
                        color: Appearance.colors.colOnSurface
                    }

                    StyledToolTip {
                        text: Translation.tr("Open %1").arg(PortWatcher.urlFor(root.entry))
                        alternativeVisibleCondition: openMouse.containsMouse
                        extraVisibleCondition: false
                        requireOverlay: false
                    }
                }

                // Stop the owning process
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: root.rFull
                    opacity: root.manageable ? 1 : 0.4
                    color: stopMouse.containsPress ? Appearance.colors.colErrorContainerActive
                        : stopMouse.containsMouse ? Appearance.colors.colErrorContainerHover
                        : Appearance.colors.colErrorContainer

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    MouseArea {
                        id: stopMouse
                        anchors.fill: parent
                        enabled: root.manageable && !PortWatcher.actionBusy
                        hoverEnabled: root.manageable
                        cursorShape: root.busy ? Qt.WaitCursor : Qt.PointingHandCursor
                        onClicked: {
                            PortWatcher.stopPort(root.entry, false);
                            root.closeRequested();
                        }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        opacity: root.busy ? 0 : 1

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }

                        MaterialSymbol {
                            text: "stop_circle"
                            fill: 1
                            iconSize: 18
                            color: Appearance.colors.colOnErrorContainer
                        }

                        StyledText {
                            text: Translation.tr("Stop")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnErrorContainer
                            elide: Text.ElideRight
                        }
                    }

                    MaterialShape {
                        anchors.centerIn: parent
                        implicitSize: 20
                        shapeString: "Cookie7Sided"
                        color: Appearance.colors.colOnErrorContainer
                        opacity: root.busy ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }

                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 2000
                            loops: Animation.Infinite
                            running: root.busy
                        }
                    }

                    StyledToolTip {
                        text: root.manageable
                            ? Translation.tr("Ask %1 to stop").arg(String(root.entry?.process ?? ""))
                            : Translation.tr("This process cannot be managed from your session")
                        alternativeVisibleCondition: stopMouse.containsMouse
                        extraVisibleCondition: false
                        requireOverlay: false
                    }
                }

                // Force stop
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    radius: root.rFull
                    opacity: root.manageable ? 1 : 0.4
                    color: killMouse.containsPress ? Appearance.colors.colErrorActive
                        : killMouse.containsMouse ? Appearance.colors.colErrorHover
                        : Appearance.colors.colError

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    MouseArea {
                        id: killMouse
                        anchors.fill: parent
                        enabled: root.manageable && !PortWatcher.actionBusy
                        hoverEnabled: root.manageable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            PortWatcher.stopPort(root.entry, true);
                            root.closeRequested();
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "bolt"
                        fill: 1
                        iconSize: 22
                        color: Appearance.colors.colOnError
                    }

                    StyledToolTip {
                        text: Translation.tr("Force stop with SIGKILL")
                        alternativeVisibleCondition: killMouse.containsMouse
                        extraVisibleCondition: false
                        requireOverlay: false
                    }
                }
            }
        }
    }
}
