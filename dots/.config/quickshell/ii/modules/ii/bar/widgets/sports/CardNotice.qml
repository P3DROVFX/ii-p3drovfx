import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Booking notice for the bar sports widget: a quiet panel slides in from the
// bar's edge with the card, the player and the minute, then slides back out.
// The host keeps this in a Loader that is only active while a notice plays.
Item {
    id: root
    clip: true

    property var card: null
    property bool vertical: false
    // Bottom (horizontal) or right (vertical) bar: enter from the far edge.
    property bool fromFarEdge: false

    signal finished()

    readonly property bool isRed: card?.red === true
    readonly property color colPanel: isRed ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
    readonly property color colOnPanel: isRed ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
    // The card itself is the one thing that must read as a real card.
    readonly property color colCard: isRed ? "#d32f2f" : "#f6c915"

    readonly property real inset: 4
    readonly property real thickness: (vertical ? width : height) - inset * 2
    readonly property real length: (vertical ? height : width) - inset * 2
    readonly property real edgeStart: (fromFarEdge ? 1 : -1) * (thickness + inset * 2)

    readonly property string playerText: {
        const name = String(card?.player ?? "");
        return name !== "" ? name : String(card?.teamName ?? "");
    }
    readonly property string detailText: {
        const minute = String(card?.minute ?? "");
        const team = String(card?.teamName ?? "");
        const label = isRed ? Translation.tr("Red card") : Translation.tr("Yellow card");
        const parts = [minute, String(card?.player ?? "") !== "" ? team : label].filter(part => part !== "");
        return parts.join(" · ");
    }

    property real edgeOffset: edgeStart
    property real cardPop: 0
    property real textProgress: 0

    function play() {
        timeline.stop();
        timeline.start();
    }

    onCardChanged: if (card) play()
    Component.onCompleted: if (card) play()

    SequentialAnimation {
        id: timeline
        ScriptAction {
            script: {
                root.edgeOffset = root.edgeStart;
                root.cardPop = 0;
                root.textProgress = 0;
            }
        }
        NumberAnimation { target: root; property: "edgeOffset"; to: 0; duration: 360; easing.type: Easing.OutCubic }
        ParallelAnimation {
            NumberAnimation { target: root; property: "cardPop"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            SequentialAnimation {
                PauseAnimation { duration: 90 }
                NumberAnimation { target: root; property: "textProgress"; to: 1; duration: 320; easing.type: Easing.OutCubic }
            }
        }
        PauseAnimation { duration: 3200 }
        NumberAnimation { target: root; property: "edgeOffset"; to: root.edgeStart; duration: 300; easing.type: Easing.InCubic }
        ScriptAction { script: root.finished() }
    }

    // The mask is sampled in the panel's own space, so it only needs its size.
    Rectangle {
        id: panelMask
        width: panel.width
        height: panel.height
        radius: Math.min(width, height) / 2
        visible: false
        layer.enabled: true
    }

    Item {
        id: panel
        x: root.inset
        y: root.inset
        width: root.vertical ? root.thickness : root.length
        height: root.vertical ? root.length : root.thickness
        transform: Translate {
            x: root.vertical ? root.edgeOffset : 0
            y: root.vertical ? 0 : root.edgeOffset
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: panelMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Rectangle {
            anchors.fill: parent
            color: root.colPanel
        }

        // The card, held up with a tilt.
        Rectangle {
            id: cardGlyph
            readonly property real glyphHeight: Math.round(Math.min(root.thickness * 0.62, 22))
            width: Math.round(glyphHeight * 0.72)
            height: glyphHeight
            radius: Math.max(2, Math.round(glyphHeight * 0.12))
            color: root.colCard
            // Outlined in the panel's ink so a red card still reads on a red panel.
            border.width: 1.5
            border.color: Qt.alpha(root.colOnPanel, 0.7)
            x: root.vertical ? (parent.width - width) / 2 : root.thickness * 0.42
            y: root.vertical ? root.thickness * 0.42 : (parent.height - height) / 2
            scale: root.cardPop
            rotation: -30 + 20 * root.cardPop
        }

        // Player and minute; turned along the bar when it is vertical.
        Item {
            id: textBox
            readonly property real start: (root.vertical ? cardGlyph.y + cardGlyph.height : cardGlyph.x + cardGlyph.width) + root.thickness * 0.3
            readonly property real span: Math.max(0, (root.vertical ? parent.height : parent.width) - start - root.thickness * 0.4)
            width: span
            height: root.thickness
            rotation: root.vertical ? -90 : 0
            x: root.vertical ? (parent.width - width) / 2 : start
            y: root.vertical ? start + span / 2 - height / 2 : 0
            opacity: root.textProgress

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: -1
                transform: Translate { x: (1 - root.textProgress) * 14 }

                StyledText {
                    width: parent.width
                    text: root.playerText
                    elide: Text.ElideRight
                    // Turned text starts at the card, not at the far end.
                    horizontalAlignment: root.vertical ? Text.AlignRight : Text.AlignLeft
                    color: root.colOnPanel
                    font.pixelSize: Math.round(Math.min(root.thickness * 0.34, 14))
                    font.variableAxes: ({ "wght": 800, "wdth": 100, "ROND": 0 })
                }

                StyledText {
                    width: parent.width
                    text: root.detailText
                    elide: Text.ElideRight
                    // Turned text starts at the card, not at the far end.
                    horizontalAlignment: root.vertical ? Text.AlignRight : Text.AlignLeft
                    color: root.colOnPanel
                    opacity: 0.8
                    font.pixelSize: Math.round(Math.min(root.thickness * 0.26, 11))
                    font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 0 })
                }
            }
        }
    }
}
