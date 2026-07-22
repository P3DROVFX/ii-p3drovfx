pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Reusable compact card for the Phone panel footer.
 *
 * Layout (compact — state != "active"):
 *   ┌──────────────────────────────────────────────────┐
 *   │ [icon] Title                                       │
 *   │        Subtitle                                    │
 *   └──────────────────────────────────────────────────┘
 *
 * Layout (expanded — state === "active"):
 *   ┌──────────────────────────────────────────────────┐
 *   │ [icon] Title                                       │
 *   │        Status detail line · 7m12s · IP · device   │
 *   │                                                     │
 *   │ [ STOP / KILL ]  [action1] [action2] [action3]    │
 *   │                                                     │
 *   │ (lastError banner if any — visible inline)         │
 *   └──────────────────────────────────────────────────┘
 *
 * Click behaviour:
 *   • Main click area → emits `clicked()`.
 *     - Idle/connecting: start the feature.
 *     - Active: emits `clicked()` — usually a context action (focus scrcpy,
 *       toggle mute for mic, etc.) defined per-card.
 *
 * The `expandedWhenActive` flag controls whether the card grows in height
 * when state === "active" — callers that want a flat card even when running
 * (e.g. sub-pages) can pass `expandedWhenActive: false`.
 */
Item {
    id: root

    // ─── Public API ─────────────────────────────────────────
    property string iconName: "smart_display"
    property string title: ""
    property string subtitle: ""
    property string state: "ready"  // ready | active | connecting | unavailable | offline
    property int iconShape: MaterialShape.Shape.Cookie9Sided
    property bool enabled: true
    property bool expandedWhenActive: true

    /** Inline detail string shown beneath subtitle when active (e.g.
     *  "7m12s · 192.168.1.42:4747 · /dev/video10"). Caller builds the
     *  composite — we just render it. */
    property string detailLine: ""

    /** Last error message shown inline when state === "active" but the
     *  service reports an error. */
    property string lastError: ""

    /** Inline action chips to render in the expanded row. Each entry:
     *  { icon: "flip", label: "Mirror", onClicked: () => ... }. */
    property var inlineActions: []

    signal clicked()
    signal stopClicked()

    /** Enables drag-and-drop file sharing onto the card when it is active.
     *  Dropped file:// URLs are emitted via `filesDropped`. */
    property bool dropEnabled: false

    signal filesDropped(urls: var)

    // Compact height when idle; expanded when active.
    implicitHeight: root._isActive && root.expandedWhenActive
        ? expandedContainer.implicitHeight + 16
        : 68
    height: implicitHeight

    readonly property bool _isActive: state === "active"
    readonly property bool _isConnecting: state === "connecting"
    readonly property bool _isUnavailable: state === "unavailable"
    readonly property bool _isOffline: state === "offline"
    readonly property color _foreground: (root._isUnavailable || root._isOffline) ? Appearance.colors.colOnLayer3 : Appearance.colors.colOnPrimaryContainer

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Flat card background — no RippleButton, no OpacityMask layer, no shadow.
    Rectangle {
        id: cardBackground
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: root._isUnavailable || root._isOffline
            ? Appearance.colors.colLayer3
            : Appearance.colors.colPrimaryContainer
        opacity: root.enabled ? 1.0 : 0.55
        Behavior on color {
            animation: Appearance.animation.elementMoveFast
                .colorAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root._isUnavailable || root._isOffline || root._isConnecting
                ? Appearance.colors.colLayer0
                : "transparent"
            opacity: root._isUnavailable || root._isOffline ? 0.25 : (root._isConnecting ? 0.12 : 0.0)
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        // Subtle hover/press highlight — no shadow/blur. The color is picked
        // to be visible against either the primary gradient or the muted
        // offline/unavailable background.
        Rectangle {
            id: hoverOverlay
            anchors.fill: parent
            radius: parent.radius
            color: root._isUnavailable || root._isOffline
                ? Appearance.colors.colOnLayer3
                : Appearance.colors.colOnPrimaryContainer
            opacity: cardMouseArea.containsPress ? 0.14
                     : (cardMouseArea.containsMouse ? 0.07 : 0.0)
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    MouseArea {
        id: cardMouseArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: expandedContainer
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 6
        opacity: root.enabled ? 1.0 : 0.5

        // Micro-scale feedback on press — makes the card feel tactile
        // without the shadow/ripple artifacts of the old RippleButton base.
        scale: cardMouseArea.containsPress ? 0.995 : 1.0
        Behavior on scale {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }

        // Top row: icon + title + subtitle + status indicator.
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                id: featureIcon
                Layout.alignment: Qt.AlignVCenter
                implicitSize: 36
                iconSize: 18
                padding: 9
                text: root._isUnavailable ? "download"
                    : root._isOffline ? "cast"
                    : root.iconName
                shape: root.iconShape
                color: ColorUtils.transparentize(root._foreground, 0.82)
                colSymbol: root._foreground
                animateChange: true
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root._isConnecting
                    NumberAnimation {
                        from: 0.45; to: 1.0
                        duration: 750
                        easing.type: Easing.InOutCubic
                    }
                    NumberAnimation {
                        from: 1.0; to: 0.45
                        duration: 750
                        easing.type: Easing.InOutCubic
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root._foreground
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root._foreground
                    opacity: 0.7
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // Status indicator on the right:
            //   • connecting → spinner icon rotating
            //   • active (running) → filled circle pulsing
            //   • otherwise → small arrow_forward (indicates clickable)
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root._isConnecting && !root._isActive
                    text: "arrow_forward"
                    iconSize: 18
                    fill: 1.0
                    color: root._foreground
                    opacity: 0.4
                }

                MaterialSymbol {
                    id: activeIcon
                    anchors.centerIn: parent
                    visible: root._isActive && !root._isConnecting
                    text: "check_circle"
                    iconSize: 18
                    color: Appearance.colors.colOnPrimaryContainer
                    fill: 1.0
                    opacity: 1.0
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: root._isActive && !root._isConnecting
                        NumberAnimation {
                            from: 0.6; to: 1.0
                            duration: 1100
                            easing.type: Easing.InOutCubic
                        }
                        NumberAnimation {
                            from: 1.0; to: 0.6
                            duration: 1100
                            easing.type: Easing.InOutCubic
                        }
                    }
                }

                Item {
                    id: spinner
                    anchors.centerIn: parent
                    visible: root._isConnecting
                    width: 18; height: 18

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "progress_activity"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimaryContainer
                        fill: 1.0
                    }
                    RotationAnimation on rotation {
                        target: spinner
                        running: root._isConnecting
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }
            }
        }

        // Expanded detail row — shown only when state === "active".
        ColumnLayout {
            Layout.fillWidth: true
            visible: root._isActive && root.expandedWhenActive
            opacity: visible ? 1.0 : 0.0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Spacer that contributes to implicitHeight even when
            // invisible. Without this, the Column collapse.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                visible: parent.visible
            }

            // Detail line (elapsed timer, IP, device).
            StyledText {
                Layout.fillWidth: true
                visible: root.detailLine.length > 0
                text: root.detailLine
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace || font.family
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.8
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }

            // Inline error banner — visible only if there's a lastError.
            Rectangle {
                Layout.fillWidth: true
                visible: root.lastError.length > 0
                Layout.preferredHeight: 26
                radius: Appearance.rounding.small
                color: Appearance.colors.colErrorContainer
                opacity: 0.85
                StyledText {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: Text.AlignVCenter
                    text: root.lastError.length > 80
                        ? root.lastError.substring(0, 77) + "…"
                        : root.lastError
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnErrorContainer
                    elide: Text.ElideRight
                }
            }

            // Inline actions row — Stop (big) + atalhos contextuais.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.inlineActions.length > 0

                // Big Stop button.
                RippleButton {
                    Layout.preferredHeight: 36
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    colRipple: Appearance.colors.colErrorContainerActive
                    scale: down ? 0.97 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutQuad
                        }
                    }
                    contentItem: RowLayout {
                        spacing: 6
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "stop_circle"
                            iconSize: 18
                            color: Appearance.colors.colOnErrorContainer
                            fill: 1.0
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Stop")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }
                    onClicked: root.stopClicked()
                    StyledToolTip {
                        text: Translation.tr("Stop")
                    }
                }

                // Inline action chips — staggered fade-in when the row appears.
                Repeater {
                    model: root.inlineActions
                    delegate: RippleButton {
                        id: chip
                        required property var modelData
                        required property int index
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: ColorUtils.transparentize(
                            Appearance.colors.colOnPrimaryContainer, 0.82)
                        colBackgroundHover: ColorUtils.transparentize(
                            Appearance.colors.colOnPrimaryContainer, 0.70)
                        colRipple: ColorUtils.transparentize(
                            Appearance.colors.colOnPrimaryContainer, 0.60)
                        opacity: 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: chip.modelData?.icon ?? ""
                            iconSize: 18
                            fill: 1.0
                            color: Appearance.colors.colOnPrimaryContainer
                            animateChange: true
                        }
                        onClicked: {
                            const fn = chip.modelData?.onClicked
                            if (typeof fn === "function") fn()
                        }
                        StyledToolTip {
                            text: chip.modelData?.label ?? ""
                        }

                        Component.onCompleted: chipEntranceTimer.restart()
                        Timer {
                            id: chipEntranceTimer
                            interval: chip.index * 45
                            repeat: false
                            onTriggered: chip.opacity = 1.0
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 240
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }

    // Drag-and-drop overlay — accepts file:// URLs when active.
    DropArea {
        id: dropArea
        anchors.fill: parent
        enabled: root.dropEnabled && root._isActive

        onEntered: drag => {
            if (drag.hasUrls) {
                drag.accepted = true
                drag.acceptProposedAction()
            }
        }

        onDropped: drag => {
            if (drag.urls && drag.urls.length > 0) {
                const urls = Array.from(drag.urls)
                root.filesDropped(urls)
            }
            drag.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.colors.colPrimaryContainer
            border.color: Appearance.colors.colPrimary
            border.width: 2
            opacity: dropArea.containsDrag ? 0.4 : 0.0
            visible: opacity > 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "drive_file_move_rtl"
                iconSize: 30
                color: Appearance.colors.colOnPrimaryContainer
                fill: 1.0
                opacity: parent.opacity * 2.0
                visible: dropArea.containsDrag
                scale: visible ? 1.0 : 0.8
                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutBack
                    }
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                text: Translation.tr("Drop to share on phone")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnPrimaryContainer
                opacity: parent.opacity * 2.5
                visible: dropArea.containsDrag
                scale: visible ? 1.0 : 0.8
                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutBack
                    }
                }
            }
        }
    }
}
