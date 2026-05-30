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
    
    property bool vertical: false
    property bool activated: root.displayGame && root.displayGame.state === "in"
    property color onActivatedColor: Appearance.colors.colOnPrimaryContainer

    implicitWidth: shouldBeVisible ? (vertical ? Appearance.sizes.verticalBarWidth : sportsLayoutHoriz.implicitWidth) : 0
    implicitHeight: shouldBeVisible ? (vertical ? sportsLayoutVert.implicitHeight + 8 : Appearance.sizes.baseBarHeight) : 0
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

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
            verticalOffset = vertical ? 0 : 10;
            horizontalOffset = vertical ? 10 : 0;
        }
    }

    // Handle game switches (next game)
    Connections {
        target: SportsService
        function onCurrentGameChanged() {
            if (typeof rootItem !== "undefined") rootItem.toggleVisible(root.shouldBeVisible);
            // Only trigger switch animation if we are already visible and the game actually changed
            if (shouldBeVisible && displayGame !== SportsService.currentGame) {
                if (displayGame && SportsService.currentGame && displayGame.id === SportsService.currentGame.id) {
                    // Same game, data updated. Don't animate, just update the data model.
                    displayGame = SportsService.currentGame;
                } else {
                    switchAnim.restart();
                }
            }
        }
    }

    // Animations
    SequentialAnimation {
        id: entranceAnim
        PropertyAction { target: root; property: "verticalOffset"; value: vertical ? 0 : -10 }
        PropertyAction { target: root; property: "horizontalOffset"; value: vertical ? -10 : 0 }
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
            NumberAnimation { target: root; property: "verticalOffset"; to: vertical ? 0 : 10; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "horizontalOffset"; to: vertical ? 10 : 0; duration: 200; easing.type: Easing.InCubic }
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
            NumberAnimation { target: root; property: "verticalOffset"; to: vertical ? 0 : 8; duration: 150; easing.type: Easing.InSine }
            NumberAnimation { target: root; property: "horizontalOffset"; to: vertical ? 8 : 0; duration: 150; easing.type: Easing.InSine }
        }
        ScriptAction {
            script: {
                // Update data while invisible
                if (SportsService.currentGame) {
                    displayGame = SportsService.currentGame;
                }
            }
        }
        PropertyAction { target: root; property: "verticalOffset"; value: vertical ? 0 : -8 }
        PropertyAction { target: root; property: "horizontalOffset"; value: vertical ? -8 : 0 }
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

        RowLayout {
            id: sportsLayoutHoriz
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: 12
            
            // Translate allows animating Y even when anchors.centerIn is active
            transform: Translate { 
                x: root.horizontalOffset
                y: root.verticalOffset 
            }

            // Home Team Logo
            StyledImage {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                source: root.displayGame ? root.displayGame.home.logo : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                cache: true
            }

            // Home Team Score (Only if not pre-game)
            Item {
                visible: root.displayGame ? root.displayGame.state !== "pre" : false
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: homeScoreText.implicitWidth
                implicitHeight: homeScoreText.implicitHeight

                StyledText {
                    id: homeScoreText
                    anchors.centerIn: parent
                    text: root.displayGame ? root.displayGame.home.score : ""
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: {
                        if (!root.activated) return Appearance.colors.colOnSurface;
                        return root.onActivatedColor;
                    }
                    animateChange: true
                }
            }

            // Status (Time, Period, etc)
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: statusText.implicitWidth + 12
                Layout.alignment: Qt.AlignVCenter
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
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: awayScoreText.implicitWidth
                implicitHeight: awayScoreText.implicitHeight

                StyledText {
                    id: awayScoreText
                    anchors.centerIn: parent
                    text: root.displayGame ? root.displayGame.away.score : ""
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: {
                        if (!root.activated) return Appearance.colors.colOnLayer1;
                        return root.onActivatedColor;
                    }
                    animateChange: true
                }
            }

            // Away Team Logo
            StyledImage {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                source: root.displayGame ? root.displayGame.away.logo : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                cache: true
            }
        }

        // Vertical Layout (Symmetrical & Compact Scoreboard for Vertical Bar)
        ColumnLayout {
            id: sportsLayoutVert
            visible: root.vertical
            anchors.centerIn: parent
            spacing: 6
            
            // Translate allows animating Y even when anchors.centerIn is active
            transform: Translate { 
                x: root.horizontalOffset
                y: root.verticalOffset 
            }

            // Home Team Logo & Score (Score placed under logo)
            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignHCenter
                StyledImage {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    source: root.displayGame ? root.displayGame.home.logo : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    cache: true
                }
                StyledText {
                    id: homeScoreTextVert
                    Layout.alignment: Qt.AlignHCenter
                    text: root.displayGame ? root.displayGame.home.score : ""
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: {
                        if (!root.activated) return Appearance.colors.colOnSurface;
                        return root.onActivatedColor;
                    }
                    visible: root.displayGame ? root.displayGame.state !== "pre" : false
                    animateChange: true
                }
            }

            // Status (Time, Period, etc)
            Rectangle {
                Layout.preferredHeight: 18
                Layout.preferredWidth: Appearance.sizes.verticalBarWidth - 8
                Layout.alignment: Qt.AlignHCenter
                radius: Appearance.rounding.full
                color: {
                    if (!root.displayGame) return Appearance.colors.colLayer3;
                    if (root.displayGame.state === "in") return Appearance.colors.colPrimary;
                    return Appearance.colors.colLayer3;
                }

                StyledText {
                    id: statusTextVert
                    anchors.centerIn: parent
                    // Splitting status to only take the first word when not active ("in") so that date/time string fits perfectly
                    text: root.displayGame ? (root.displayGame.state === "in" ? root.displayGame.status : root.displayGame.status.split(" ")[0]) : ""
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

            // Away Team Logo & Score (Score placed above logo for symmetry)
            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignHCenter
                StyledText {
                    id: awayScoreTextVert
                    Layout.alignment: Qt.AlignHCenter
                    text: root.displayGame ? root.displayGame.away.score : ""
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: {
                        if (!root.activated) return Appearance.colors.colOnLayer1;
                        return root.onActivatedColor;
                    }
                    visible: root.displayGame ? root.displayGame.state !== "pre" : false
                    animateChange: true
                }
                StyledImage {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    source: root.displayGame ? root.displayGame.away.logo : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    cache: true
                }
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
