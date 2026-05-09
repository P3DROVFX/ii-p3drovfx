import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

MouseArea {
    id: root

    // Original visibility logic
    readonly property bool shouldBeVisible: Config.options.bar.sports.enable && SportsService.currentGame !== null
    
    // Stable game for animations - prevents instant data swap during transitions
    property var displayGame: SportsService.currentGame
    
    // Keeps the widget "alive" during exit animation
    property bool internalVisible: shouldBeVisible
    visible: internalVisible || opacity > 0
    
    readonly property bool isVertical: Config.options.bar.vertical
    property bool activated: root.displayGame && root.displayGame.state === "in"
    property color onActivatedColor: Appearance.colors.colOnPrimaryContainer

    implicitWidth: shouldBeVisible ? (isVertical ? Appearance.sizes.verticalBarWidth : sportsLayout.implicitWidth) : 0
    implicitHeight: shouldBeVisible ? (isVertical ? sportsLayout.implicitHeight : Appearance.sizes.barHeight) : 0
    hoverEnabled: true

    // Vertical offset for the slide animation - using transform: Translate bypasses anchor restrictions
    property real verticalOffset: 0
    property real horizontalOffset: 0

    // Synchronize visibility with the bar system but wait for animations
    onShouldBeVisibleChanged: {
        if (typeof rootItem !== "undefined") rootItem.toggleVisible(shouldBeVisible);
        if (shouldBeVisible) {
            internalVisible = true;
            displayGame = SportsService.currentGame;
            entranceAnim.restart();
        } else {
            exitAnim.restart();
        }
    }

    Component.onCompleted: {
        if (typeof rootItem !== "undefined") rootItem.toggleVisible(shouldBeVisible);
        if (shouldBeVisible) {
            opacity = 1;
            verticalOffset = 0;
            horizontalOffset = 0;
        } else {
            opacity = 0;
            verticalOffset = isVertical ? 0 : 10;
            horizontalOffset = isVertical ? 10 : 0;
        }
    }

    // Handle game switches (next game)
    Connections {
        target: SportsService
        function onCurrentGameChanged() {
            if (typeof rootItem !== "undefined") rootItem.toggleVisible(root.shouldBeVisible);
            // Only trigger switch animation if we are already visible and the game actually changed
            if (shouldBeVisible && displayGame !== SportsService.currentGame) {
                switchAnim.restart();
            }
        }
    }

    // Animations
    SequentialAnimation {
        id: entranceAnim
        PropertyAction { target: root; property: "verticalOffset"; value: isVertical ? 0 : -10 }
        PropertyAction { target: root; property: "horizontalOffset"; value: isVertical ? -10 : 0 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "verticalOffset"; to: 0; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "horizontalOffset"; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
    }

    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "verticalOffset"; to: isVertical ? 0 : 10; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "horizontalOffset"; to: isVertical ? 10 : 0; duration: 200; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                internalVisible = false;
            }
        }
    }

    SequentialAnimation {
        id: switchAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InSine }
            NumberAnimation { target: root; property: "verticalOffset"; to: isVertical ? 0 : 8; duration: 150; easing.type: Easing.InSine }
            NumberAnimation { target: root; property: "horizontalOffset"; to: isVertical ? 8 : 0; duration: 150; easing.type: Easing.InSine }
        }
        ScriptAction {
            script: {
                // Update data while invisible
                if (SportsService.currentGame) {
                    displayGame = SportsService.currentGame;
                }
            }
        }
        PropertyAction { target: root; property: "verticalOffset"; value: isVertical ? 0 : -8 }
        PropertyAction { target: root; property: "horizontalOffset"; value: isVertical ? -8 : 0 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: 150; easing.type: Easing.OutSine }
            NumberAnimation { target: root; property: "verticalOffset"; to: 0; duration: 150; easing.type: Easing.OutSine }
            NumberAnimation { target: root; property: "horizontalOffset"; to: 0; duration: 150; easing.type: Easing.OutSine }
        }
    }

    onClicked: {
        SportsService.nextGame();
    }

    SportsPopup {
        hoverTarget: root
    }

    Item {
        id: contentClipper
        anchors.fill: parent
        clip: true

        GridLayout {
            id: sportsLayout
            columns: isVertical ? 1 : 5
            rows: isVertical ? 5 : 1
            rowSpacing: isVertical ? 2 : 4
            columnSpacing: 12
            anchors.centerIn: parent
            
            // Translate allows animating Y even when anchors.centerIn is active
            transform: Translate { 
                x: root.horizontalOffset
                y: root.verticalOffset 
            }

            // Home Team Logo
            StyledImage {
                Layout.preferredWidth: isVertical ? 20 : 24
                Layout.preferredHeight: isVertical ? 20 : 24
                Layout.alignment: Qt.AlignCenter
                source: root.displayGame ? root.displayGame.home.logo : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                cache: true
            }

            // Home Team Score (Only if not pre-game)
            Item {
                visible: root.displayGame ? root.displayGame.state !== "pre" : false
                Layout.alignment: Qt.AlignCenter
                implicitWidth: homeScoreText.implicitWidth
                implicitHeight: homeScoreText.implicitHeight

                StyledText {
                    id: homeScoreText
                    anchors.centerIn: parent
                    text: root.displayGame ? root.displayGame.home.score : ""
                    font.weight: Font.DemiBold
                    font.pixelSize: isVertical ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                    color: {
                        if (!root.activated) return Appearance.colors.colOnSurface;
                        return root.onActivatedColor;
                    }
                    animateChange: true
                }
            }

            // Status (Time, Period, etc)
            Rectangle {
                Layout.preferredHeight: isVertical ? 18 : 20
                Layout.preferredWidth: statusText.implicitWidth + (isVertical ? 8 : 12)
                Layout.alignment: Qt.AlignCenter
                radius: Appearance.rounding.full
                color: {
                    if (!root.displayGame) return Appearance.colors.colLayer3;
                    if (root.displayGame.state === "in") return Appearance.colors.colPrimary;
                    return Appearance.colors.colLayer3;
                }

                StyledText {
                    id: statusText
                    anchors.centerIn: parent
                    text: root.displayGame ? root.displayGame.status : ""
                    font.weight: Font.Bold
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: {
                        if (!root.displayGame) return Appearance.colors.colOnLayer3;
                        if (root.displayGame.state === "in") return Appearance.colors.colOnPrimary;
                        return Appearance.colors.colOnLayer3;
                    }
                    animateChange: true
                }
            }

            // Away Team Score (Only if not pre-game)
            Item {
                visible: root.displayGame ? root.displayGame.state !== "pre" : false
                Layout.alignment: Qt.AlignCenter
                implicitWidth: awayScoreText.implicitWidth
                implicitHeight: awayScoreText.implicitHeight

                StyledText {
                    id: awayScoreText
                    anchors.centerIn: parent
                    text: root.displayGame ? root.displayGame.away.score : ""
                    font.weight: Font.DemiBold
                    font.pixelSize: isVertical ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                    color: {
                        if (!root.activated) return Appearance.colors.colOnLayer1;
                        return root.onActivatedColor;
                    }
                    animateChange: true
                }
            }

            // Away Team Logo
            StyledImage {
                Layout.preferredWidth: isVertical ? 20 : 24
                Layout.preferredHeight: isVertical ? 20 : 24
                Layout.alignment: Qt.AlignCenter
                source: root.displayGame ? root.displayGame.away.logo : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                cache: true
            }
        }
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
        }
    }
}
