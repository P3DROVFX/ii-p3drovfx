pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Dock-local sports popup. It deliberately uses PopupWindow anchoring, just
// like DockTooltip, instead of StyledPopup's PanelWindow margins. The dock
// item is therefore the only positioning source and every hover can create a
// fresh, stateless visible surface.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool showPopup: false

    readonly property string dockPosition: anchorItem?.dockContent?.dockPos
        ?? dock.dockEffectivePosition
    readonly property real popupGap: Appearance.sizes.elevationMargin
    readonly property real cardWidth: Appearance.sizes.dockButtonSize * 8.5
    readonly property real cardHeight: Appearance.sizes.dockButtonSize * 2.45
    readonly property real cardWithPlayHeight: Appearance.sizes.dockButtonSize * 3.3
    readonly property real teamLogoSize: Appearance.sizes.dockButtonSize * 1.15
    readonly property real cardPadding: Appearance.sizes.elevationMargin * 1.5
    readonly property real cardSpacing: Appearance.sizes.elevationMargin
    readonly property real teamColumnWidth: Appearance.sizes.dockButtonSize * 2.45
    readonly property real centerColumnWidth: Appearance.sizes.dockButtonSize * 2.2
    readonly property real popupPadding: Appearance.sizes.elevationMargin * 1.25
    readonly property real shadowMargin: Appearance.sizes.elevationMargin
    readonly property int maxCards: Math.max(1, Config.options?.bar?.sports?.maxCardsPopup ?? 3)
    readonly property real slideDistance: Math.max(
        Appearance.sizes.elevationMargin * 3,
        Appearance.sizes.dockButtonSize * 0.35
    )
    readonly property real slideOffsetX: root.dockPosition === "left"
        ? -root.slideDistance
        : (root.dockPosition === "right" ? root.slideDistance : 0)
    readonly property real slideOffsetY: root.dockPosition === "top"
        ? -root.slideDistance
        : (root.dockPosition === "bottom" ? root.slideDistance : 0)

    // These are imperative animation targets rather than bindings. Keeping
    // them on the popup root lets the anchored window remain still while its
    // visible surface slides from the dock edge.
    property real surfaceOpacity: 0.0
    property real surfaceSlideX: 0.0
    property real surfaceSlideY: 0.0

    readonly property var orderedGames: {
        const games = SportsService.allGames ?? []
        if (games.length === 0)
            return []

        const currentIndex = Math.max(0, Math.min(SportsService.currentGameIndex, games.length - 1))
        return games.slice(currentIndex).concat(games.slice(0, currentIndex))
    }
    readonly property var displayGames: root.orderedGames.slice(0, root.maxCards)

    function requestAnchorUpdate() {
        if (root.showPopup && root.anchor.window)
            anchorUpdateTimer.restart()
    }

    Timer {
        id: anchorUpdateTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root.showPopup && root.anchor.window)
                root.anchor.updateAnchor()
        }
    }

    anchor {
        window: root.anchorItem?.QsWindow?.window ?? null
        adjustment: PopupAdjustment.None
        edges: Edges.Top | Edges.Left

        // PopupWindow's anchor rect is expressed in the host window's screen
        // coordinates. mapToItem(null) is the same coordinate path used by
        // the dock tooltip and remains correct when magnification moves the
        // delegate inside the dock panel.
        rect.x: {
            if (!root.anchorItem)
                return 0

            const _ = root.anchorItem.x + root.anchorItem.y + root.anchorItem.width
                + root.anchorItem.height + root.anchorItem.scale + root.width
            if (root.dockPosition === "left") {
                const mappedRight = root.anchorItem.mapToItem(null, root.anchorItem.width, 0)
                return mappedRight.x + root.popupGap
            }
            if (root.dockPosition === "right") {
                const mappedLeft = root.anchorItem.mapToItem(null, 0, 0)
                return mappedLeft.x - root.width - root.popupGap
            }

            const mappedCenter = root.anchorItem.mapToItem(null, root.anchorItem.width / 2, 0)
            return mappedCenter.x - root.width / 2
        }

        rect.y: {
            if (!root.anchorItem)
                return 0

            const _ = root.anchorItem.x + root.anchorItem.y + root.anchorItem.height
                + root.anchorItem.width + root.anchorItem.scale + root.height
            if (root.dockPosition === "top") {
                const mappedBottom = root.anchorItem.mapToItem(null, 0, root.anchorItem.height)
                return mappedBottom.y + root.popupGap
            }
            if (root.dockPosition === "bottom") {
                const mappedTop = root.anchorItem.mapToItem(null, 0, 0)
                return mappedTop.y - root.height - root.popupGap
            }

            const mappedCenter = root.anchorItem.mapToItem(null, 0, root.anchorItem.height / 2)
            return mappedCenter.y - root.height / 2
        }
    }

    Connections {
        target: root.anchorItem
        function onXChanged() { root.requestAnchorUpdate() }
        function onYChanged() { root.requestAnchorUpdate() }
        function onWidthChanged() { root.requestAnchorUpdate() }
        function onHeightChanged() { root.requestAnchorUpdate() }
        function onScaleChanged() { root.requestAnchorUpdate() }
    }

    Connections {
        target: root.anchorItem?.dockContent ?? null
        function onHoveredSlotChanged() { root.requestAnchorUpdate() }
        function onButtonHoveredChanged() { root.requestAnchorUpdate() }
    }

    function startOpenAnimation() {
        closeAnimation.stop()
        if (root.surfaceOpacity <= 0.001) {
            root.surfaceSlideX = root.slideOffsetX
            root.surfaceSlideY = root.slideOffsetY
            root.surfaceOpacity = 0.0
        }
        openAnimation.start()
    }

    function startCloseAnimation() {
        openAnimation.stop()
        closeAnimation.start()
    }

    onShowPopupChanged: {
        root.requestAnchorUpdate()
        if (root.showPopup)
            root.startOpenAnimation()
        else
            root.startCloseAnimation()
    }
    onWidthChanged: root.requestAnchorUpdate()
    onHeightChanged: root.requestAnchorUpdate()

    Component.onCompleted: {
        if (root.showPopup)
            root.startOpenAnimation()
    }

    ParallelAnimation {
        id: openAnimation
        NumberAnimation {
            target: root
            property: "surfaceOpacity"
            to: 1.0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "surfaceSlideX"
            to: 0.0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "surfaceSlideY"
            to: 0.0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    ParallelAnimation {
        id: closeAnimation
        NumberAnimation {
            target: root
            property: "surfaceOpacity"
            to: 0.0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "surfaceSlideX"
            to: root.slideOffsetX
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "surfaceSlideY"
            to: root.slideOffsetY
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
    }

    visible: root.showPopup || root.surfaceOpacity > 0.01
    color: "transparent"
    implicitWidth: root.cardWidth + root.popupPadding * 2 + root.shadowMargin * 2
    implicitHeight: contentLoader.item
        ? contentLoader.item.implicitHeight
        : Appearance.sizes.dockButtonSize * 2

    // The dock creates this popup alongside the widget so it can react to
    // hover, but the card repeater and its team logos are only needed while
    // the popup is visible. Keeping them out of the idle tree is important
    // when several monitored leagues return many games.
    Loader {
        id: contentLoader
        anchors.fill: parent
        active: root.showPopup || root.surfaceOpacity > 0.01
        sourceComponent: root.popupContent
    }

    property Component popupContent: Component {
    Rectangle {
        implicitWidth: root.cardWidth + root.popupPadding * 2 + root.shadowMargin * 2
        implicitHeight: Math.max(
            Appearance.sizes.dockButtonSize * 2,
            gamesColumn.implicitHeight + root.popupPadding * 2 + root.shadowMargin * 2
        )
        id: popupSurface
        anchors.fill: parent
        anchors.margins: root.shadowMargin
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.large
        clip: true
        opacity: root.surfaceOpacity

        transform: Translate {
            x: root.surfaceSlideX
            y: root.surfaceSlideY
        }

        Column {
            id: gamesColumn
            anchors.fill: parent
            anchors.margins: root.popupPadding
            spacing: root.cardSpacing

            Repeater {
                model: root.displayGames

                delegate: Rectangle {
                    id: gameCard
                    required property var modelData
                    required property int index

                    width: root.cardWidth
                    height: modelData?.lastPlay ? root.cardWithPlayHeight : root.cardHeight
                    radius: Appearance.rounding.normal
                    color: index === 0
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colSurfaceContainerHigh

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(gameCard)
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const selectedIndex = SportsService.allGames.indexOf(gameCard.modelData)
                            if (selectedIndex >= 0) {
                                SportsService.currentGameIndex = selectedIndex
                                SportsService.currentGame = SportsService.allGames[selectedIndex]
                            }
                        }
                    }

                    Row {
                        id: matchRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: root.cardPadding
                        height: root.cardHeight - root.cardPadding * 2
                        spacing: Appearance.sizes.elevationMargin

                        Item {
                            width: root.teamColumnWidth
                            height: parent.height

                            Column {
                                anchors.fill: parent
                                spacing: Appearance.sizes.elevationMargin * 0.5

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: Appearance.sizes.elevationMargin * 0.75

                                    StyledText {
                                        visible: gameCard.modelData?.state !== "pre"
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: gameCard.modelData?.home?.score ?? ""
                                        color: gameCard.index === 0
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colOnLayer2
                                        font.pixelSize: Appearance.font.pixelSize.huge
                                        font.weight: Font.DemiBold
                                    }

                                    Rectangle {
                                        width: root.teamLogoSize
                                        height: root.teamLogoSize
                                        radius: Appearance.rounding.full
                                        color: gameCard.index === 0
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer3

                                        StyledImage {
                                            anchors.fill: parent
                                            anchors.margins: Appearance.sizes.elevationMargin * 0.75
                                            source: gameCard.modelData?.home?.logo ?? ""
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                            cache: false
                                        }
                                    }
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    text: gameCard.modelData?.home?.name ?? ""
                                    color: gameCard.index === 0
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Column {
                            width: root.centerColumnWidth
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Appearance.sizes.elevationMargin

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: statusLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                                height: Appearance.sizes.dockButtonSize * 0.55
                                radius: Appearance.rounding.full
                                color: gameCard.index === 0
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSecondaryContainer

                                StyledText {
                                    id: statusLabel
                                    anchors.centerIn: parent
                                    text: SportsService.compactMatchStatus(
                                        gameCard.modelData?.status ?? "",
                                        gameCard.modelData?.state ?? ""
                                    )
                                    color: gameCard.index === 0
                                        ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnSecondaryContainer
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                }
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                text: gameCard.modelData?.league ?? ""
                                color: gameCard.index === 0
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        Item {
                            width: root.teamColumnWidth
                            height: parent.height

                            Column {
                                anchors.fill: parent
                                spacing: Appearance.sizes.elevationMargin * 0.5

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: Appearance.sizes.elevationMargin * 0.75

                                    Rectangle {
                                        width: root.teamLogoSize
                                        height: root.teamLogoSize
                                        radius: Appearance.rounding.full
                                        color: gameCard.index === 0
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer3

                                        StyledImage {
                                            anchors.fill: parent
                                            anchors.margins: Appearance.sizes.elevationMargin * 0.75
                                            source: gameCard.modelData?.away?.logo ?? ""
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                            cache: false
                                        }
                                    }

                                    StyledText {
                                        visible: gameCard.modelData?.state !== "pre"
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: gameCard.modelData?.away?.score ?? ""
                                        color: gameCard.index === 0
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colOnLayer2
                                        font.pixelSize: Appearance.font.pixelSize.huge
                                        font.weight: Font.DemiBold
                                    }
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    text: gameCard.modelData?.away?.name ?? ""
                                    color: gameCard.index === 0
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: Boolean(gameCard.modelData?.lastPlay)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: root.cardPadding
                        height: root.cardWithPlayHeight - root.cardHeight - root.cardPadding
                        text: gameCard.modelData?.lastPlay ?? ""
                        color: gameCard.index === 0
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                visible: root.displayGames.length === 0
                width: root.cardWidth
                height: Appearance.sizes.dockButtonSize * 2.5
                text: Translation.tr("No matches found.")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.normal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    }
}
