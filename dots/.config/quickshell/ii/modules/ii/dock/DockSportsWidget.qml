pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "./widgets"

/**
 * Horizontal sports scoreboard for the dock.
 *
 * The scoreboard intentionally uses the same compact team/status arrangement
 * as the horizontal bar sports widget. Its popup is a dock-local PopupWindow
 * so hover open/close never shares the bar popup lifecycle.
 */
Item {
    id: root

    property bool isVertical: false
    property var dockContent: null
    property int delegateIndex: -1
    property bool sportsHovered: false
    property var displayGame: SportsService.currentGame
    property real contentOpacity: 1.0

    readonly property bool shouldBeVisible: (Config.options?.dock?.enableSportsWidget ?? true) && !root.isVertical
        && SportsService.allGames.length > 0
    readonly property bool activated: root.displayGame?.state === "in"
    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    // Keep the outer slot and the background margins identical to the
    // weather widget so both horizontal widgets occupy the same dock height.
    readonly property real dotMargin: root.dockContent?.dotMargin ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    readonly property real slotSize: root.dockContent?.buttonSlotSize ?? (root.buttonSize + root.dotMargin * 2)
    readonly property real slotHeight: root.dockContent
        ? (root.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : (root.buttonSize + root.dotMarginV * 2)
    readonly property real teamLogoSize: Math.round(root.buttonSize * 0.68)
    readonly property real fixedLength: root.dockContent
        ? root.dockContent.buttonSlotSize * root.dockContent.sportsWidgetSlots
        : root.slotSize * 3.25
    readonly property real contentPadding: Math.max(Appearance.sizes.elevationMargin, Math.round(root.buttonSize * 0.14))
    readonly property real rowSpacing: Math.max(4, Math.round(root.buttonSize * 0.13))
    readonly property real statusPadding: Math.max(Appearance.sizes.elevationMargin * 0.75, Math.round(root.buttonSize * 0.1))
    readonly property real minimumLogoSize: Appearance.font.pixelSize.small
    readonly property string displayStatus: SportsService.compactMatchStatus(root.displayGame?.status ?? "", root.displayGame?.state ?? "")
    readonly property real widgetRadius: (Config.options?.dock?.widgetRadius ?? -1) >= 0
        ? Config.options.dock.widgetRadius
        : Appearance.rounding.normal
    readonly property color scoreColor: root.activated
        ? Appearance.colors.colOnPrimaryContainer
        : Appearance.colors.colOnLayer1
    readonly property color statusColor: root.activated
        ? Appearance.colors.colOnPrimary
        : Appearance.colors.colOnLayer3

    visible: root.shouldBeVisible || root.opacity > 0
    opacity: root.shouldBeVisible ? 1.0 : 0.0
    implicitWidth: root.shouldBeVisible ? root.fixedLength : 0
    implicitHeight: root.shouldBeVisible ? root.slotHeight : 0

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    onShouldBeVisibleChanged: {
        if (root.shouldBeVisible && SportsService.currentGame)
            root.displayGame = SportsService.currentGame
    }

    Connections {
        target: SportsService

        function onCurrentGameChanged() {
            if (!root.shouldBeVisible || !SportsService.currentGame) {
                root.displayGame = SportsService.currentGame
                return
            }

            if (root.displayGame?.id === SportsService.currentGame.id) {
                root.displayGame = SportsService.currentGame
                return
            }

            switchAnimation.restart()
        }
    }

    SequentialAnimation {
        id: switchAnimation

        NumberAnimation {
            target: root
            property: "contentOpacity"
            to: 0.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }

        ScriptAction {
            script: root.displayGame = SportsService.currentGame
        }

        NumberAnimation {
            target: root
            property: "contentOpacity"
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    function nextGame(): void {
        if (root.shouldBeVisible)
            SportsService.nextGame()
    }

    MouseArea {
        id: interactionArea
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        property real pressCoord: 0
        property bool dragActive: false

        onEntered: {
            root.sportsHovered = true
            if (!root.dockContent?.suppressHover)
                root.dockContent?.onButtonEntered(root)
        }

        onExited: {
            root.sportsHovered = false
            root.dockContent?.onButtonExited(root)
        }

        onPressed: event => {
            if (event.button === Qt.LeftButton)
                pressCoord = root.isVertical ? event.y : event.x
        }

        onPositionChanged: event => {
            if (!pressed || !(event.buttons & Qt.LeftButton))
                return

            const currentCoord = root.isVertical ? event.y : event.x
            const distance = Math.abs(currentCoord - pressCoord)
            if (!dragActive && distance > 5 && root.delegateIndex >= 0) {
                dragActive = true
                root.dockContent?.startItemDrag(root.delegateIndex, interactionArea, event.x, event.y)
            }

            if (dragActive)
                root.dockContent?.moveItemDrag(interactionArea, event.x, event.y)
        }

        onReleased: event => {
            if (dragActive) {
                dragActive = false
                root.dockContent?.endItemDrag()
                return
            }

            if (event.button === Qt.LeftButton)
                root.nextGame()
        }

        onCanceled: {
            if (dragActive) {
                dragActive = false
                root.dockContent?.cancelDrag()
            }
        }
    }

    Rectangle {
        id: sportsBackground
        anchors.fill: parent
        anchors.leftMargin: root.dotMargin
        anchors.rightMargin: root.dotMargin
        anchors.topMargin: root.dotMarginV
        anchors.bottomMargin: root.dotMarginV
        radius: root.widgetRadius
        clip: true
        color: root.activated
            ? Appearance.colors.colPrimaryContainer
            : (root.sportsHovered ? Appearance.colors.colLayer2Base : Appearance.colors.colLayer1Base)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(sportsBackground)
        }

        RowLayout {
            id: sportsLayout
            readonly property real availableWidth: Math.max(0, sportsBackground.width - root.contentPadding * 2)
            readonly property real adaptiveSpacing: Math.min(root.rowSpacing, Math.max(2, availableWidth * 0.04))
            readonly property real adaptiveLogoSize: Math.max(root.minimumLogoSize, Math.min(root.teamLogoSize,
                (availableWidth - statusText.implicitWidth - root.statusPadding * 2
                    - homeScoreText.implicitWidth - awayScoreText.implicitWidth
                    - adaptiveSpacing * 4) / 2))
            anchors.centerIn: parent
            width: Math.min(implicitWidth, availableWidth)
            spacing: adaptiveSpacing
            opacity: root.contentOpacity

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(sportsLayout)
            }

            StyledImage {
                Layout.preferredWidth: sportsLayout.adaptiveLogoSize
                Layout.preferredHeight: sportsLayout.adaptiveLogoSize
                Layout.alignment: Qt.AlignVCenter
                source: root.displayGame?.home?.logo ?? ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                cache: false
            }

            StyledText {
                id: homeScoreText
                Layout.alignment: Qt.AlignVCenter
                visible: root.displayGame?.state !== "pre"
                text: root.displayGame?.home?.score ?? ""
                font.weight: Font.DemiBold
                font.pixelSize: Appearance.font.pixelSize.normal
                color: root.scoreColor
                animateChange: true
            }

            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: statusText.implicitWidth + root.statusPadding * 2
                Layout.alignment: Qt.AlignVCenter
                radius: Appearance.rounding.full
                color: root.activated ? Appearance.colors.colPrimary : Appearance.colors.colLayer3

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                StyledText {
                    id: statusText
                    anchors.centerIn: parent
                    text: root.displayStatus
                    font.weight: Font.Bold
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.statusColor
                    animateChange: true
                }
            }

            StyledText {
                id: awayScoreText
                Layout.alignment: Qt.AlignVCenter
                visible: root.displayGame?.state !== "pre"
                text: root.displayGame?.away?.score ?? ""
                font.weight: Font.DemiBold
                font.pixelSize: Appearance.font.pixelSize.normal
                color: root.scoreColor
                animateChange: true
            }

            StyledImage {
                Layout.preferredWidth: sportsLayout.adaptiveLogoSize
                Layout.preferredHeight: sportsLayout.adaptiveLogoSize
                Layout.alignment: Qt.AlignVCenter
                source: root.displayGame?.away?.logo ?? ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                cache: false
            }
        }
    }

    Loader {
        id: popupLoader
        // The dock anchor is cheap, but its popup type owns a separate
        // PopupWindow and must not exist for every idle sports delegate.
        // Keep it through the short close fade so hover can still finish
        // cleanly, then destroy the complete popup tree.
        active: root.shouldBeVisible
            && (interactionArea.containsMouse || (item?.surfaceOpacity ?? 0) > 0.01)
        sourceComponent: DockSportsPopup {
            anchorItem: root
            showPopup: interactionArea.containsMouse
        }
    }
}
