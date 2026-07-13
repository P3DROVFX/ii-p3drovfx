import qs.modules.ii.bar.popups.sports
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

MouseArea {
    id: root
    property bool vertical: false

    readonly property bool shouldBeVisible: Config.options.bar.sports.enable && SportsService.allGames.length > 0
    
    // Stable game for animations - prevents instant data swap during transitions
    property var displayGame: SportsService.currentGame
    
    // Keeps the widget "alive" during exit animation
    property bool internalVisible: shouldBeVisible
    visible: internalVisible || opacity > 0
    
    implicitWidth: shouldBeVisible ? (vertical ? Appearance.sizes.verticalBarWidth : layout.implicitWidth + 8) : 0
    implicitHeight: shouldBeVisible ? (vertical ? layoutVert.implicitHeight + 8 : Appearance.sizes.baseBarHeight) : 0
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    // Animation offsets
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
        Qt.callLater(() => { root.isReady = true; });
    }

    // Connections for switch animation
    Connections {
        target: SportsService
        function onCurrentGameChanged() {
            if (typeof rootItem !== "undefined") rootItem.toggleVisible(root.shouldBeVisible);
            if (shouldBeVisible && displayGame !== SportsService.currentGame) {
                if (displayGame && SportsService.currentGame && displayGame.id === SportsService.currentGame.id) {
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
                if (SportsService.currentGame) displayGame = SportsService.currentGame;
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

    property bool isReady: false

    Behavior on implicitWidth {
        enabled: root.isReady
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
        }
    }

    Behavior on implicitHeight {
        enabled: root.isReady
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
        }
    }

    RowLayout {
        id: layout
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 4
        transform: Translate { x: root.horizontalOffset; y: root.verticalOffset }

        MaterialShape {
            Layout.alignment: Qt.AlignVCenter
            shapeString: "Cookie7Sided"
            color: Appearance.colors.colSecondaryContainer
            implicitSize: Appearance.sizes.baseBarHeight - 8
            StyledImage {
                anchors.centerIn: parent
                width: parent.implicitSize - 14
                height: parent.implicitSize - 14
                source: root.displayGame ? root.displayGame.home.logo : ""
            }
        }

        Rectangle {
            id: statusPill
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: Appearance.sizes.baseBarHeight - 14
            Layout.preferredWidth: Math.max(statusText.implicitWidth + 16, 30)
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary
            
            StyledText {
                id: statusText
                anchors.centerIn: parent
                // If game state is "in" (active), show score. Otherwise show full status (time/date)
                text: root.displayGame ? (root.displayGame.state === "in" ? `${root.displayGame.home.score} - ${root.displayGame.away.score}` : root.displayGame.status) : ""
                font.pixelSize: 10
                font.weight: Font.Black
                color: Appearance.colors.colOnPrimary
                animateChange: true
            }
        }

        MaterialShape {
            Layout.alignment: Qt.AlignVCenter
            shapeString: "Cookie7Sided"
            color: Appearance.colors.colSecondaryContainer
            implicitSize: Appearance.sizes.baseBarHeight - 8
            StyledImage {
                anchors.centerIn: parent
                width: parent.implicitSize - 14
                height: parent.implicitSize - 14
                source: root.displayGame ? root.displayGame.away.logo : ""
            }
        }
    }

    // Vertical Material
    ColumnLayout {
        id: layoutVert
        visible: root.vertical
        anchors {
            top: parent.top
            topMargin: 4
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 6
        transform: Translate { x: root.horizontalOffset; y: root.verticalOffset }

        // Home Team
        ColumnLayout {
            spacing: 2
            Layout.alignment: Qt.AlignHCenter
            MaterialShape {
                Layout.alignment: Qt.AlignHCenter
                shapeString: "Cookie7Sided"
                color: Appearance.colors.colSecondaryContainer
                implicitSize: Appearance.sizes.verticalBarWidth - 8
                StyledImage {
                    anchors.centerIn: parent
                    width: parent.implicitSize - 12
                    height: parent.implicitSize - 12
                    source: root.displayGame ? root.displayGame.home.logo : ""
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.displayGame ? root.displayGame.home.score : ""
                font.pixelSize: 12
                font.weight: Font.Black
                color: Appearance.colors.colOnSurface
                visible: root.displayGame ? root.displayGame.state !== "pre" : false
                animateChange: true
            }
        }

        // Status
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Appearance.sizes.verticalBarWidth - 8
            implicitHeight: 20 // Fixed height is probably okay here for vertical flow
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary
            StyledText {
                anchors.centerIn: parent
                text: root.displayGame ? (root.displayGame.state === "in" ? root.displayGame.status : root.displayGame.status.split(" ")[0]) : ""
                font.pixelSize: 8
                font.weight: Font.Black
                color: Appearance.colors.colOnPrimary
                animateChange: true
            }
        }

        // Away Team
        ColumnLayout {
            spacing: 2
            Layout.alignment: Qt.AlignHCenter
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.displayGame ? root.displayGame.away.score : ""
                font.pixelSize: 12
                font.weight: Font.Black
                color: Appearance.colors.colOnSurface
                visible: root.displayGame ? root.displayGame.state !== "pre" : false
                animateChange: true
            }
            MaterialShape {
                Layout.alignment: Qt.AlignHCenter
                shapeString: "Cookie7Sided"
                color: Appearance.colors.colSecondaryContainer
                implicitSize: Appearance.sizes.verticalBarWidth - 8
                StyledImage {
                    anchors.centerIn: parent
                    width: parent.implicitSize - 12
                    height: parent.implicitSize - 12
                    source: root.displayGame ? root.displayGame.away.logo : ""
                }
            }
        }
    }

    SportsPopup {
        hoverTarget: root
    }
}
