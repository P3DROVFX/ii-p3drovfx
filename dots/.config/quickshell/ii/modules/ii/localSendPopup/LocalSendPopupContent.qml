pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property var transfer
    signal dismissed()
    signal acceptRequested()
    signal rejectRequested()

    readonly property bool isHovered: popupHoverHandler.hovered

    onTransferChanged: {
        dismissTimer.restart();
    }

    onIsHoveredChanged: {
        if (isHovered) {
            dismissTimer.stop();
        } else {
            dismissTimer.restart();
        }
    }

    Component.onCompleted: {
        if (!isHovered) dismissTimer.start();
    }

    // Auto-dismiss timer — stays open for 8 seconds unless hovered
    Timer {
        id: dismissTimer
        interval: 8000
        repeat: false
        // Hosted, the activity owns the lifetime: the transfer is still pending after
        // eight seconds, so nothing should take the face away.
        onTriggered: if (!root.hosted) root.dismissed()
    }

    // Expose contentBackground for mask in parent PanelWindow
    property alias contentBackground: contentBackground

    readonly property string senderName: transfer?.sender ?? Translation.tr("Unknown Device")
    readonly property string fileName: {
        if (!transfer || !transfer.files || transfer.files.length === 0) return Translation.tr("No Files");
        if (transfer.files.length === 1) return transfer.files[0].name;
        return Translation.tr("%1 files").arg(transfer.files.length);
    }
    readonly property string fileInfoText: {
        if (!transfer || !transfer.files || transfer.files.length === 0) return "";
        let totalSize = transfer.files.reduce((acc, f) => acc + (f.size || 0), 0);
        return LocalSend.formatFileSize(totalSize);
    }

    /**
     * Drawn on a host's surface rather than as a floating card of its own.
     *
     * Inside the Dynamic Island the island is the card, so the content's own rounded
     * rectangle, its border and the elevation margin around it would be a panel inside
     * a panel. Hosted, they go and the content measures itself with no margin.
     */
    property bool hosted: false
    readonly property real surfaceMargin: root.hosted ? 0 : Appearance.sizes.elevationMargin

    // Sizing
    property real popupWidth: 320
    property real horizontalPadding: 20
    property real verticalPadding: 20

    implicitWidth: popupWidth + 2 * root.surfaceMargin
    implicitHeight: contentLayout.implicitHeight + verticalPadding * 2 + 2 * root.surfaceMargin

    // Expose a static, unscaled item for the window input mask to prevent coordinate bugs during scale
    property alias staticMaskTarget: staticMaskTarget
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
    }

    // Shadow
    StyledRectangularShadow {
        target: contentBackground
        visible: !root.hosted
    }

    Rectangle {
        id: contentBackground
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
        radius: Appearance.rounding.large
        color: root.hosted ? "transparent"
            : (Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer)
        border.width: root.hosted ? 0 : 1
        border.color: Appearance.colors.colLayer0Border

        // Animations applied on the card itself to keep root window input mapping clean.
        // Hosted, the host plays the entrance; the card's own scale-and-fade on top of
        // the island's arrival read as two separate motions.
        opacity: root.hosted ? 1 : 0
        scale: root.hosted ? 1 : 0.85
        transformOrigin: Item.TopRight

        Component.onCompleted: {
            if (!root.hosted)
                entranceAnim.start();
        }

        ParallelAnimation {
            id: entranceAnim
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                from: 0; to: 1
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
            NumberAnimation {
                target: contentBackground
                property: "scale"
                from: 0.85; to: 1
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        // Prevent click-throughs to backgroundMa and dismissals when clicking inside the card
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = true
            onClicked: mouse => mouse.accepted = true
            onPressed: mouse => mouse.accepted = true
            onReleased: mouse => mouse.accepted = true
        }

        // Reliable sticky hover handling
        HoverHandler {
            id: popupHoverHandler
        }

        ColumnLayout {
            id: contentLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.horizontalPadding
                topMargin: root.verticalPadding
                bottomMargin: root.verticalPadding
            }
            spacing: 12

            // === SENDER NAME ===
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignLeft
                text: root.senderName
                font.pixelSize: 26
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }

            // === STATUS / INCOMING TEXT ===
            StyledText {
                Layout.topMargin: -8
                horizontalAlignment: Text.AlignLeft
                text: Translation.tr("Incoming File Transfer")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.main
                color: Appearance.colors.colPrimary
            }

            // === DEVICE IMAGE / ICON AREA ===
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                implicitHeight: 160
                Layout.topMargin: 4

                // Cookie shape background (centered)
                MaterialCookie {
                    id: cookieShape
                    anchors.centerIn: parent
                    implicitSize: 150
                    color: Appearance.colors.colPrimaryContainer

                    RotationAnimation on rotation {
                        from: 0; to: 360
                        duration: 15000
                        loops: Animation.Infinite
                        running: true
                    }

                    NumberAnimation on scale {
                        from: 0; to: 1
                        duration: 650
                        easing.type: Easing.OutBack
                        easing.overshoot: 2.5
                    }
                }

                // File download / share icon on top of the cookie shape
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "swap_horiz"
                    iconSize: 64
                    color: Appearance.colors.colOnPrimaryContainer

                    NumberAnimation on scale {
                        from: 0; to: 1
                        duration: 750
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                }
            }

            // === FILE NAME & INFO CARD ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                implicitHeight: 64
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHighest
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    MaterialSymbol {
                        text: "description"
                        iconSize: 24
                        color: Appearance.colors.colOnSurface
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.fileName
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.fileInfoText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // === ACTION BUTTONS ===
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                // Reject button (ErrorContainer color)
                Rectangle {
                    id: rejectBtnRect
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 40
                    implicitWidth: 80
                    implicitHeight: 40
                    radius: Appearance.rounding.full
                    color: rejectMa.containsMouse
                        ? Appearance.colors.colErrorContainerHover
                        : Appearance.m3colors.m3errorContainer

                    scale: rejectMa.pressed ? 0.92 : (rejectMa.containsMouse ? 1.05 : 1.0)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.m3colors.m3onErrorContainer
                    }

                    MouseArea {
                        id: rejectMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.rejectRequested()
                    }
                }

                // Accept button (PrimaryContainer color)
                Rectangle {
                    id: acceptBtnRect
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    implicitHeight: 40
                    radius: Appearance.rounding.full
                    color: acceptMa.containsMouse
                        ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colPrimaryContainer

                    scale: acceptMa.pressed ? 0.96 : (acceptMa.containsMouse ? 1.02 : 1.0)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "download"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            text: Translation.tr("Accept")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    MouseArea {
                        id: acceptMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.acceptRequested()
                    }
                }
            }
        }
    }

    // Click anywhere on the margins to dismiss
    MouseArea {
        id: backgroundMa
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        onWheel: wheel => wheel.accepted = true
        onClicked: root.dismissed()
        onPressed: mouse => mouse.accepted = true
        onReleased: mouse => mouse.accepted = true
    }
}
