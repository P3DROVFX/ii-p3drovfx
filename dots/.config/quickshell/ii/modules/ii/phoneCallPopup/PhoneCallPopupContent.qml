pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

/**
 * The call card: who is calling, a photo (or initial) on a turning cookie that pulses
 * while the phone rings, and the call's buttons. They go to the phone through
 * PhoneCallService: over ii link when the app reports calls, else ADB; when neither can
 * act, the card says to answer on the phone instead of showing dead buttons.
 */
Item {
    id: root

    signal hideRequested()

    readonly property bool ringing: PhoneCallService.callState === "ringing"
    readonly property bool canAct: PhoneCallService.controllable || PhoneCallService._simulated
    readonly property string name: PhoneCallService.displayName
    readonly property string number: PhoneCallService.number !== "" && PhoneCallService.number !== root.name ? PhoneCallService.number : ""
    readonly property string avatarPath: PhoneCallService.avatarPath

    // The call's length, ticking only while one is in progress and on screen.
    property double now: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: !root.ringing && PhoneCallService.active
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
    readonly property string elapsed: {
        const s = Math.max(0, Math.floor((root.now - PhoneCallService.stateSince) / 1000));
        const m = Math.floor(s / 60);
        return `${m}:${String(s % 60).padStart(2, "0")}`;
    }

    property real popupWidth: 320
    property real padding: 20
    readonly property real surfaceMargin: Appearance.sizes.elevationMargin

    implicitWidth: popupWidth + 2 * root.surfaceMargin
    implicitHeight: contentLayout.implicitHeight + padding * 2 + 2 * root.surfaceMargin

    property alias staticMaskTarget: staticMaskTarget
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
    }

    Rectangle {
        id: card
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
        radius: Appearance.rounding.large
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer

        opacity: 0
        scale: 0.85
        transformOrigin: Item.TopRight
        Component.onCompleted: entrance.start()
        ParallelAnimation {
            id: entrance
            NumberAnimation {
                target: card
                property: "opacity"
                from: 0
                to: 1
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
            NumberAnimation {
                target: card
                property: "scale"
                from: 0.85
                to: 1
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        // Clicks inside the card stay in it.
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = true
        }

        ColumnLayout {
            id: contentLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.padding
            }
            spacing: 12

            // ── Status, and closing the card (the call goes on) ─────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: root.ringing ? "ring_volume" : "call"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.ringing ? Translation.tr("Incoming call") : Translation.tr("On a call · %1").arg(root.elapsed)
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                }
                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.hideRequested()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            // ── Who ─────────────────────────────────────────────────────────
            StyledText {
                Layout.fillWidth: true
                text: root.name
                font.pixelSize: 26
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }
            StyledText {
                Layout.topMargin: -8
                visible: root.number !== ""
                text: root.number
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }

            // ── Photo on the cookie; it breathes while the phone rings ──────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                implicitHeight: 160

                MaterialCookie {
                    id: cookie
                    anchors.centerIn: parent
                    implicitSize: 150
                    color: root.ringing ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: root.ringing ? 6000 : 15000
                        loops: Animation.Infinite
                        running: true
                    }
                    SequentialAnimation on scale {
                        running: root.ringing
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation {
                            to: 1.07
                            duration: 550
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            to: 1
                            duration: 650
                            easing.type: Easing.InOutQuad
                        }
                    }
                }

                ClippingRectangle {
                    id: photo
                    anchors.centerIn: parent
                    width: 104
                    height: 104
                    radius: width / 2
                    color: "transparent"
                    visible: avatar.status === Image.Ready
                    Image {
                        id: avatar
                        anchors.fill: parent
                        source: root.avatarPath !== "" ? "file://" + root.avatarPath : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(208, 208)
                        asynchronous: true
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !photo.visible
                    text: (root.name.match(/\p{L}/u)?.[0] ?? "").toUpperCase()
                    font.pixelSize: 56
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold
                    color: root.ringing ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !photo.visible && !/\p{L}/u.test(root.name)
                    text: "person"
                    iconSize: 64
                    color: root.ringing ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                }
            }

            // ── Buttons ─────────────────────────────────────────────────────
            StyledText {
                Layout.fillWidth: true
                visible: !root.canAct
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Translation.tr("Answer on the phone")
                color: Appearance.colors.colSubtext
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.canAct
                spacing: 8

                CallButton {
                    icon: "call_end"
                    label: root.ringing ? Translation.tr("Decline") : Translation.tr("End")
                    colBackground: Appearance.m3colors.m3errorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    colForeground: Appearance.m3colors.m3onErrorContainer
                    onClicked: PhoneCallService.decline()
                }
                CallButton {
                    visible: root.ringing
                    icon: "volume_off"
                    label: Translation.tr("Silence")
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colForeground: Appearance.colors.colOnSurface
                    onClicked: PhoneCallService.silence()
                }
                CallButton {
                    visible: root.ringing
                    icon: "call"
                    label: Translation.tr("Answer")
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colForeground: Appearance.colors.colOnPrimary
                    onClicked: PhoneCallService.answer()
                }
            }
        }
    }

    /** A pill: icon over label, squeezing a little when pressed. */
    component CallButton: Rectangle {
        id: button
        property string icon
        property string label
        property color colBackground
        property color colBackgroundHover
        property color colForeground
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 64
        implicitHeight: 64
        radius: Appearance.rounding.large
        color: buttonMa.containsMouse ? button.colBackgroundHover : button.colBackground
        scale: buttonMa.pressed ? 0.94 : 1

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: button.icon
                iconSize: Appearance.font.pixelSize.huge
                color: button.colForeground
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: button.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: button.colForeground
            }
        }

        MouseArea {
            id: buttonMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
