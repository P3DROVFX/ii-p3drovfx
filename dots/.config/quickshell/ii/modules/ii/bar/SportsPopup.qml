import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

StyledPopup {
    id: root

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
        implicitHeight: Math.max(140, gamesColumn.implicitHeight)

        StyledFlickable {
            anchors.fill: parent
            contentHeight: gamesColumn.implicitHeight
            clip: true
            interactive: contentHeight > height

            Item {
                id: gamesColumn
                width: 485

                property int maxCards: Config.options.bar.sports.maxCardsPopup
                property int visibleCards: Math.min(SportsService.allGames.length, maxCards)
                property bool hasMore: SportsService.allGames.length > maxCards

                property real lastCardY: {
                    if (visibleCards === 0) return 0;
                    let yPos = 0;
                    let tc = SportsService.allGames.length;
                    for (let i = 0; i < tc; i++) {
                        let vIdx = tc === 0 ? i : ((i - SportsService.currentGameIndex + tc) % tc);
                        if (vIdx < visibleCards - 1) {
                            let md = SportsService.allGames[i];
                            yPos += ((md && md.lastPlay) ? 190 : 140) + 8;
                        }
                    }
                    return yPos;
                }

                property real lastCardHeight: {
                    if (visibleCards === 0) return 140;
                    let tc = SportsService.allGames.length;
                    for (let i = 0; i < tc; i++) {
                        let vIdx = tc === 0 ? i : ((i - SportsService.currentGameIndex + tc) % tc);
                        if (vIdx === visibleCards - 1) {
                            let md = SportsService.allGames[i];
                            return (md && md.lastPlay) ? 190 : 140;
                        }
                    }
                    return 140;
                }

                Connections {
                    target: Config.options.bar.sports
                    function onMaxCardsPopupChanged() {
                        gamesColumn.maxCards = Config.options.bar.sports.maxCardsPopup;
                    }
                }

                implicitHeight: {
                    if (visibleCards === 0) return 0;
                    let h = 0;
                    let tc = SportsService.allGames.length;
                    for (let i = 0; i < tc; i++) {
                        let vIdx = tc === 0 ? i : ((i - SportsService.currentGameIndex + tc) % tc);
                        if (vIdx < maxCards) {
                            let md = SportsService.allGames[i];
                            h += (md && md.lastPlay) ? 190 : 140;
                        }
                    }
                    h += Math.max(0, visibleCards - 1) * 8;
                    if (hasMore) h += 12;
                    return h;
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
                        property int vIndex: {
                            if (totalCount === 0)
                                return index;
                            let dIdx = SportsService.currentGameIndex;
                            return (index - dIdx + totalCount) % totalCount;
                        }

                        color: root.colCard

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Appearance.colors.colPrimaryContainer
                            opacity: vIndex === 0 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                        }

                        z: vIndex < gamesColumn.maxCards ? 10 - vIndex : -3

                        y: {
                            let yPos = 0;
                            let trigger = Math.min(vIndex, gamesColumn.maxCards);
                            for (let i = 0; i < totalCount; i++) {
                                let otherV = totalCount === 0 ? i : ((i - SportsService.currentGameIndex + totalCount) % totalCount);
                                if (otherV < trigger) {
                                    let md = SportsService.allGames[i];
                                    let cardH = (md && md.lastPlay) ? 190 : 140;
                                    yPos += cardH + 8;
                                }
                            }
                            if (vIndex >= gamesColumn.maxCards) {
                                yPos += 12;
                            }
                            return yPos;
                        }

                        Behavior on y {
                            NumberAnimation {
                                duration: 400
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.1
                            }
                        }
                        
                        opacity: vIndex < gamesColumn.maxCards ? 1 : 0
                        visible: opacity > 0 || vIndex < gamesColumn.maxCards
                        Behavior on opacity { NumberAnimation { duration: 200 } }
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
                                    color: vIndex === 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter

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
                                    anchors.top: homeLogoCont.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData?.home?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: vIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colText
                                    elide: Text.ElideRight
                                    width: 100
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                StyledText {
                                    anchors.left: homeLogoCont.right
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: homeLogoCont.verticalCenter
                                    text: modelData?.home?.score ?? "0"
                                    font.pixelSize: 32
                                    font.weight: Font.DemiBold
                                    color: vIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colText
                                    visible: modelData?.state !== "pre"
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
                                    color: vIndex === 0 ? Appearance.colors.colPrimary : root.colPill
                                    
                                    readonly property int dynamicPadding: modelData?.state === "in" ? 20 : 6
                                    width: statusLabel.implicitWidth + (dynamicPadding * 2)

                                    StyledText {
                                        id: statusLabel
                                        anchors.centerIn: parent
                                        text: modelData?.status ?? ""
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: vIndex === 0 ? Appearance.colors.colOnPrimary : root.colOnPill
                                    }
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData?.league ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Light
                                    color: vIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colSubtext
                                    elide: Text.ElideRight
                                    width: 120
                                    horizontalAlignment: Text.AlignHCenter
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
                                    color: vIndex === 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter

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
                                    anchors.top: awayLogoCont.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData?.away?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: vIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colText
                                    elide: Text.ElideRight
                                    width: 100
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                StyledText {
                                    anchors.right: awayLogoCont.left
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: awayLogoCont.verticalCenter
                                    text: modelData?.away?.score ?? "0"
                                    font.pixelSize: 32
                                    font.weight: Font.DemiBold
                                    color: vIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colText
                                    visible: modelData?.state !== "pre"
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
                            color: vIndex === 0 ? Appearance.colors.colOnPrimaryContainer : root.colSubtext
                            visible: modelData?.lastPlay ? true : false
                        }
                    }
                }

                Rectangle {
                    id: stack1
                    y: gamesColumn.lastCardY + 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 485 - 32
                    height: gamesColumn.lastCardHeight
                    z: -1
                    visible: gamesColumn.hasMore
                    color: root.colCard
                    opacity: 0.4
                    radius: root.radMain
                }

                Rectangle {
                    id: stack2
                    y: gamesColumn.lastCardY + 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 485 - 64
                    height: gamesColumn.lastCardHeight
                    z: -2
                    visible: gamesColumn.hasMore
                    color: root.colCard
                    opacity: 0.2
                    radius: root.radMain
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
    }
}
