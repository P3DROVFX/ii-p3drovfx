import qs.modules.ii.bar.shared
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

StyledPopup {
    id: root
    stickyHover: true

    // Design Tokens
    readonly property color colBg: Appearance.colors.colLayer1
    readonly property color colCard: Appearance.colors.colSurfaceContainerHigh
    readonly property color colPill: Appearance.colors.colSecondaryContainer
    readonly property color colOnPill: Appearance.colors.colOnSecondaryContainer
    readonly property color colText: Appearance.colors.colOnLayer2
    readonly property color colSubtext: Appearance.colors.colOnLayer1
    readonly property int radMain: Appearance.rounding.verylarge
    readonly property int radFull: Appearance.rounding.full

    popupRadius: radMain

    contentItem: Item {
        id: content
        implicitWidth: 485
        implicitHeight: gamesColumn.visibleHeight

        StyledFlickable {
            id: flickable
            anchors.fill: parent
            contentHeight: gamesColumn.implicitHeight
            clip: true
            interactive: (gamesColumn.draggedIndex === -1) && (contentHeight > height)

            Item {
                id: gamesColumn
                width: 485

                property int maxCards: Config.options.bar.sports.maxCardsPopup
                property int draggedIndex: -1
                property int hoverIndex: -1
                property real dragY: 0
                property bool snapping: false

                NumberAnimation {
                    id: snapAnimation
                    target: gamesColumn
                    property: "dragY"
                    duration: 200
                    easing.type: Easing.OutCubic
                    onFinished: {
                        gamesColumn.snapping = false;
                        gamesColumn.completeReorder();
                    }
                }

                function getTargetCardY(draggedIdx, targetIdx) {
                    if (draggedIdx === targetIdx) {
                        return getCardY(draggedIdx, SportsService.allGames);
                    }
                    let temp = [...SportsService.allGames];
                    let item = temp.splice(draggedIdx, 1)[0];
                    temp.splice(targetIdx, 0, item);
                    return getCardY(targetIdx, temp);
                }

                function completeReorder() {
                    if (gamesColumn.draggedIndex !== -1 && gamesColumn.hoverIndex !== -1) {
                        if (gamesColumn.draggedIndex !== gamesColumn.hoverIndex) {
                            let arr = [...SportsService.allGames];
                            let item = arr.splice(gamesColumn.draggedIndex, 1)[0];
                            arr.splice(gamesColumn.hoverIndex, 0, item);

                            // Whichever game is at the first index (index 0) becomes the active game
                            SportsService.currentGameIndex = 0;
                            SportsService.currentGame = arr[0];

                            SportsService.customOrder = arr.map(g => g.id);

                            gamesColumn.draggedIndex = -1;
                            gamesColumn.hoverIndex = -1;

                            SportsService.allGames = arr;
                        } else {
                            gamesColumn.draggedIndex = -1;
                            gamesColumn.hoverIndex = -1;
                        }
                    }
                }

                function getCardY(idx, gamesList) {
                    let yPos = 0;
                    for (let i = 0; i < idx; i++) {
                        let physicalIdx = gamesList.length > 0 ? (i + SportsService.currentGameIndex) % gamesList.length : i;
                        let md = gamesList[physicalIdx];
                        let cardH = (md && md.lastPlay) ? 190 : 140;
                        yPos += cardH + 8;
                    }
                    return yPos;
                }

                property real visibleHeight: {
                    if (SportsService.allGames.length === 0) return 140;
                    let limit = Math.min(SportsService.allGames.length, maxCards);
                    return Math.max(0, getCardY(limit, SportsService.allGames) - 8);
                }

                implicitHeight: SportsService.allGames.length === 0 ? 140 : Math.max(0, getCardY(SportsService.allGames.length, SportsService.allGames) - 8)

                Connections {
                    target: Config.options.bar.sports
                    function onMaxCardsPopupChanged() {
                        gamesColumn.maxCards = Config.options.bar.sports.maxCardsPopup;
                    }
                }

                Repeater {
                    id: rep
                    model: SportsService.allGames
                    delegate: Rectangle {
                        id: card
                        width: 485
                        height: modelData?.lastPlay ? 190 : 140
                        implicitHeight: height
                        radius: root.radMain
                        
                        readonly property int totalCount: SportsService.allGames.length
                        readonly property int vIndex: index
                        readonly property int visualIndex: {
                            let len = SportsService.allGames.length;
                            if (len === 0) return index;
                            return (index - SportsService.currentGameIndex + len) % len;
                        }
                        readonly property int previewIndex: {
                            if (gamesColumn.draggedIndex === -1) {
                                return visualIndex;
                            }
                            if (gamesColumn.draggedIndex === index) {
                                return gamesColumn.hoverIndex;
                            }
                            if (gamesColumn.draggedIndex > gamesColumn.hoverIndex) {
                                if (index >= gamesColumn.hoverIndex && index < gamesColumn.draggedIndex) {
                                    return index + 1;
                                }
                            } else if (gamesColumn.draggedIndex < gamesColumn.hoverIndex) {
                                if (index <= gamesColumn.hoverIndex && index > gamesColumn.draggedIndex) {
                                    return index - 1;
                                }
                            }
                            return index;
                        }

                        color: root.colCard

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Appearance.colors.colPrimaryContainer
                            opacity: previewIndex === 0 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                        }

                        z: gamesColumn.draggedIndex === index ? 100 : 10 - index

                        y: {
                            if (gamesColumn.draggedIndex === -1) {
                                return gamesColumn.getCardY(visualIndex, SportsService.allGames);
                            }
                            if (gamesColumn.draggedIndex === index) {
                                return gamesColumn.dragY;
                            }
                            let dH = ((SportsService.allGames[gamesColumn.draggedIndex]?.lastPlay ? 190 : 140) + 8);
                            if (gamesColumn.draggedIndex > gamesColumn.hoverIndex) {
                                if (index >= gamesColumn.hoverIndex && index < gamesColumn.draggedIndex) {
                                    return gamesColumn.getCardY(index, SportsService.allGames) + dH;
                                }
                            } else if (gamesColumn.draggedIndex < gamesColumn.hoverIndex) {
                                if (index <= gamesColumn.hoverIndex && index > gamesColumn.draggedIndex) {
                                    return gamesColumn.getCardY(index, SportsService.allGames) - dH;
                                }
                            }
                            return gamesColumn.getCardY(index, SportsService.allGames);
                        }

                        Behavior on y {
                            enabled: gamesColumn.draggedIndex !== index && !gamesColumn.snapping
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.OutCubic
                            }
                        }

                        scale: gamesColumn.draggedIndex === index ? 1.03 : 1.0
                        opacity: gamesColumn.draggedIndex === index ? 0.9 : 1.0
                        
                        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6 && gamesColumn.draggedIndex === -1
                        
                        onStartAnimChanged: {
                            if (startAnim) {
                                card.opacity = 0.0;
                                card.scale = 0.85;
                                cardTranslate.y = 25;
                                
                                homeLogoCont.scale = 0.8;
                                homeTeamName.opacity = 0.0;
                                homeScore.opacity = 0.0;
                                homeScore.scale = 0.9;

                                awayLogoCont.scale = 0.8;
                                awayTeamName.opacity = 0.0;
                                awayScore.opacity = 0.0;
                                awayScore.scale = 0.9;

                                statusPill.opacity = 0.0;
                                statusPill.scale = 0.9;
                                leagueText.opacity = 0.0;
                                
                                Qt.callLater(function() {
                                    cardAnim.start();
                                    homeLogoContAnim.start();
                                    homeTeamNameAnim.start();
                                    homeScoreAnim.start();
                                    awayLogoContAnim.start();
                                    awayTeamNameAnim.start();
                                    awayScoreAnim.start();
                                    statusPillAnim.start();
                                    leagueTextAnim.start();
                                });
                            }
                        }

                        Connections {
                            target: root
                            function onPopupOpenProgressChanged() {
                                if (root && root.popupOpenProgress === 0.0) {
                                    cardAnim.stop();
                                    homeLogoContAnim.stop();
                                    homeTeamNameAnim.stop();
                                    homeScoreAnim.stop();
                                    awayLogoContAnim.stop();
                                    awayTeamNameAnim.stop();
                                    awayScoreAnim.stop();
                                    statusPillAnim.stop();
                                    leagueTextAnim.stop();

                                    card.opacity = 0.0;
                                    card.scale = 0.85;
                                    cardTranslate.y = 25;
                                    
                                    homeLogoCont.scale = 0.8;
                                    homeTeamName.opacity = 0.0;
                                    homeScore.opacity = 0.0;
                                    homeScore.scale = 0.9;

                                    awayLogoCont.scale = 0.8;
                                    awayTeamName.opacity = 0.0;
                                    awayScore.opacity = 0.0;
                                    awayScore.scale = 0.9;

                                    statusPill.opacity = 0.0;
                                    statusPill.scale = 0.9;
                                    leagueText.opacity = 0.0;
                                }
                            }
                        }
                        
                        transform: Translate {
                            id: cardTranslate
                            y: (gamesColumn.draggedIndex !== index && root.opened && root.popupOpenProgress > 0.6) ? 0 : (gamesColumn.draggedIndex === index ? 0 : 25)
                        }
                        
                        SequentialAnimation {
                            id: cardAnim
                            PauseAnimation { duration: 40 + index * 100 }
                            ParallelAnimation {
                                NumberAnimation { target: card; property: "opacity"; to: 1.0; duration: 300 }
                                NumberAnimation { target: card; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                NumberAnimation { target: cardTranslate; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                            }
                        }

                        DragManager {
                            id: dragArea
                            anchors.fill: parent
                            interactive: !gamesColumn.snapping
                            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            onPressed: (mouse) => {
                                if (SportsService.currentGameIndex > 0 && SportsService.currentGameIndex < SportsService.allGames.length) {
                                    let arr = [...SportsService.allGames];
                                    let rotationCount = SportsService.currentGameIndex;
                                    for (let r = 0; r < rotationCount; r++) {
                                        let first = arr.shift();
                                        arr.push(first);
                                    }
                                    SportsService.currentGameIndex = 0;
                                    SportsService.allGames = arr;
                                }

                                gamesColumn.draggedIndex = index;
                                gamesColumn.hoverIndex = index;
                                gamesColumn.dragY = gamesColumn.getCardY(index, SportsService.allGames);
                            }

                            onDragPressed: (diffX, diffY) => {
                                let startY = gamesColumn.getCardY(index, SportsService.allGames);
                                gamesColumn.dragY = startY + diffY;

                                // Find the index where the card is currently hovering
                                let cy = gamesColumn.dragY + card.height / 2;
                                let newHover = 0;
                                let tc = SportsService.allGames.length;
                                for (let i = 0; i < tc; i++) {
                                    let yStart = gamesColumn.getCardY(i, SportsService.allGames);
                                    let md = SportsService.allGames[i];
                                    let h = (md && md.lastPlay) ? 190 : 140;
                                    if (cy >= yStart && cy <= yStart + h + 8) {
                                        newHover = i;
                                        break;
                                    }
                                    if (cy > yStart + h + 8) {
                                        newHover = i;
                                    }
                                }
                                newHover = Math.max(0, Math.min(newHover, tc - 1));
                                gamesColumn.hoverIndex = newHover;
                            }

                            onDragReleased: (diffX, diffY) => {
                                if (gamesColumn.draggedIndex !== -1 && gamesColumn.hoverIndex !== -1) {
                                    gamesColumn.snapping = true;
                                    let targetY = gamesColumn.getTargetCardY(gamesColumn.draggedIndex, gamesColumn.hoverIndex);
                                    snapAnimation.to = targetY;
                                    snapAnimation.start();
                                }
                            }
                        }

                        Item {
                            id: teamHeader
                            width: parent.width
                            height: 140
                            anchors.top: parent.top

                            Item {
                                anchors.fill: parent
                                anchors.margins: 20

                            // Home Team
                            Item {
                                id: homeSection
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 140
                                height: 100

                                Rectangle {
                                    id: homeLogoCont
                                    width: 72
                                    height: 72
                                    radius: root.radFull
                                    color: previewIndex === 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    scale: 0.8

                                    SequentialAnimation {
                                        id: homeLogoContAnim
                                        PauseAnimation { duration: 40 + index * 100 + 60 }
                                        NumberAnimation { target: homeLogoCont; property: "scale"; from: 0.8; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                    }

                                    StyledImage {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        source: modelData?.home?.logo ?? ""
                                        fillMode: Image.PreserveAspectFit
                                        mipmap: true
                                        smooth: true
                                    }
                                }

                                StyledText {
                                    id: homeTeamName
                                    anchors.top: homeLogoCont.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData?.home?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: previewIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colText
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    elide: Text.ElideRight
                                    width: 130
                                    horizontalAlignment: Text.AlignHCenter
                                    opacity: 0.0

                                    SequentialAnimation {
                                        id: homeTeamNameAnim
                                        PauseAnimation { duration: 40 + index * 100 + 120 }
                                        NumberAnimation { target: homeTeamName; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                    }
                                }

                                StyledText {
                                    id: homeScore
                                    anchors.left: homeLogoCont.right
                                    anchors.leftMargin: (text.length > 3) ? 4 : 12
                                    anchors.verticalCenter: homeLogoCont.verticalCenter
                                    text: modelData?.home?.score ?? "0"
                                    font.pixelSize: (text.length > 3) ? 16 : 32
                                    font.weight: Font.DemiBold
                                    color: previewIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colText
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    visible: modelData?.state !== "pre"
                                    opacity: 0.0
                                    scale: 0.9

                                    SequentialAnimation {
                                        id: homeScoreAnim
                                        PauseAnimation { duration: 40 + index * 100 + 180 }
                                        ParallelAnimation {
                                            NumberAnimation { target: homeScore; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                            NumberAnimation { target: homeScore; property: "scale"; from: 0.9; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                        }
                                    }
                                }
                            }

                            // Center Info
                            Column {
                                id: centerSection
                                anchors.centerIn: parent
                                width: 140
                                spacing: 12

                                Rectangle {
                                    id: statusPill
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 32
                                    radius: root.radFull
                                    color: previewIndex === 0 ? Appearance.colors.colPrimary : root.colPill
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    
                                    readonly property int dynamicPadding: modelData?.state === "in" ? 20 : 6
                                    width: statusLabel.implicitWidth + (dynamicPadding * 2)
                                    opacity: 0.0
                                    scale: 0.9

                                    SequentialAnimation {
                                        id: statusPillAnim
                                        PauseAnimation { duration: 40 + index * 100 + 100 }
                                        ParallelAnimation {
                                            NumberAnimation { target: statusPill; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                            NumberAnimation { target: statusPill; property: "scale"; from: 0.9; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                        }
                                    }

                                    StyledText {
                                        id: statusLabel
                                        anchors.centerIn: parent
                                        text: modelData?.status ?? ""
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: previewIndex === 0 ? Appearance.colors.colOnPrimary : root.colOnPill
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                }

                                StyledText {
                                    id: leagueText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData?.league ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Light
                                    color: previewIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colSubtext
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    elide: Text.ElideRight
                                    width: 120
                                    horizontalAlignment: Text.AlignHCenter
                                    opacity: 0.0

                                    SequentialAnimation {
                                        id: leagueTextAnim
                                        PauseAnimation { duration: 40 + index * 100 + 140 }
                                        NumberAnimation { target: leagueText; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                    }
                                }
                            }

                            // Away Team
                            Item {
                                id: awaySection
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 140
                                height: 100

                                Rectangle {
                                    id: awayLogoCont
                                    width: 72
                                    height: 72
                                    radius: root.radFull
                                    color: previewIndex === 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    scale: 0.8

                                    SequentialAnimation {
                                        id: awayLogoContAnim
                                        PauseAnimation { duration: 40 + index * 100 + 60 }
                                        NumberAnimation { target: awayLogoCont; property: "scale"; from: 0.8; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                    }

                                    StyledImage {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        source: modelData?.away?.logo ?? ""
                                        fillMode: Image.PreserveAspectFit
                                        mipmap: true
                                        smooth: true
                                    }
                                }

                                StyledText {
                                    id: awayTeamName
                                    anchors.top: awayLogoCont.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData?.away?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: previewIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colText
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    elide: Text.ElideRight
                                    width: 130
                                    horizontalAlignment: Text.AlignHCenter
                                    opacity: 0.0

                                    SequentialAnimation {
                                        id: awayTeamNameAnim
                                        PauseAnimation { duration: 40 + index * 100 + 120 }
                                        NumberAnimation { target: awayTeamName; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                    }
                                }

                                StyledText {
                                    id: awayScore
                                    anchors.right: awayLogoCont.left
                                    anchors.rightMargin: (text.length > 3) ? 4 : 12
                                    anchors.verticalCenter: awayLogoCont.verticalCenter
                                    text: modelData?.away?.score ?? "0"
                                    font.pixelSize: (text.length > 3) ? 16 : 32
                                    font.weight: Font.DemiBold
                                    color: previewIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colText
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    visible: modelData?.state !== "pre"
                                    opacity: 0.0
                                    scale: 0.9

                                    SequentialAnimation {
                                        id: awayScoreAnim
                                        PauseAnimation { duration: 40 + index * 100 + 180 }
                                        ParallelAnimation {
                                            NumberAnimation { target: awayScore; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                            NumberAnimation { target: awayScore; property: "scale"; from: 0.9; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                        }
                                    }
                                }
                            }
                        }
                    }

                        Rectangle {
                            width: parent.width - 40
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 140
                            height: 1
                            color: Appearance.colors.colOutline
                            opacity: 0.3
                            visible: modelData?.lastPlay ? true : false
                        }

                        StyledText {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            height: 50
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: modelData?.lastPlay ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: previewIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colSubtext
                            Behavior on color { ColorAnimation { duration: 200 } }
                            visible: modelData?.lastPlay ? true : false
                        }
                    }
                }

                StyledText {
                    visible: SportsService.allGames.length === 0
                    width: 485
                    height: 140
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("No matches found.")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        ScrollEdgeFade {
            target: flickable
            color: root.colBg
        }
    }
}
