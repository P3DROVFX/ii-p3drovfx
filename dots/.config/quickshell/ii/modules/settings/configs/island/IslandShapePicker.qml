pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.styles.notch

/**
 * The island's three shells as cards, each with its own silhouette drawn by the
 * island's `NotchShape`: the notch flat against the top edge, flaring into it, the
 * sculpted notch whose sides are one long S, and the island floating free as a pill. The chosen one fills with the secondary
 * container and wears the primary ring; pointing at one tries it on the page's
 * live island (`tried`). A shell the bar cannot host says why.
 */
Item {
    id: root

    property string currentValue: "notch"
    property bool notchBlocked: false
    property string notchBlockedText: ""
    property color islandColor: Appearance.colors.colLayer0
    /** The shell under the pointer, "" when none. */
    readonly property string tried: notchCard.hovered && !root.notchBlocked ? "notch"
        : sculptedCard.hovered && !root.notchBlocked ? "sculpted"
        : islandCard.hovered ? "island" : ""
    /** Room around each card for the chosen one's ring, kept inside the picker's own box. */
    readonly property real ringGap: 2
    readonly property real ringWidth: 2.5
    readonly property real ringRoom: root.ringGap + root.ringWidth

    signal selected(string value)

    readonly property int gap: 12
    // Three across while each card keeps room for its silhouette; one per row below.
    readonly property int columns: width >= 720 ? 3 : 1
    readonly property real cardWidth: Math.floor((width - (root.columns - 1) * root.gap) / root.columns)
    /** Narrow cards put the silhouette above the text instead of beside it. */
    readonly property bool tall: root.columns > 1 && root.cardWidth < 330
    readonly property real cardHeight: root.tall ? 210 : 148
    implicitHeight: Math.ceil(3 / root.columns) * (root.cardHeight + root.gap) - root.gap

    function cardX(index) {
        return (index % root.columns) * (root.cardWidth + root.gap);
    }
    function cardY(index) {
        return Math.floor(index / root.columns) * (root.cardHeight + root.gap);
    }

    ShapeCard {
        id: notchCard
        x: root.cardX(0)
        y: root.cardY(0)
        value: "notch"
        title: Translation.tr("Notch")
        summary: root.notchBlocked ? root.notchBlockedText : Translation.tr("Flat against the top edge, flaring into it like the screen grew it")
        blocked: root.notchBlocked
    }

    ShapeCard {
        id: sculptedCard
        x: root.cardX(1)
        y: root.cardY(1)
        value: "sculpted"
        title: Translation.tr("Sculpted")
        summary: root.notchBlocked ? root.notchBlockedText : Translation.tr("A wider notch whose sides melt into the edge in one long curve")
        blocked: root.notchBlocked
    }

    ShapeCard {
        id: islandCard
        x: root.cardX(2)
        y: root.cardY(2)
        value: "island"
        title: Translation.tr("Island")
        summary: Translation.tr("A pill floating free of every edge; also sits in a Float or Rect bar")
        blocked: false
    }

    // The ring stands off the card, so the card sits inset by the ring's room inside a
    // box of the full size: drawn outside the box, the page edge cut it off.
    component ShapeCard: Item {
        id: shell

        required property string value
        required property string title
        required property string summary
        required property bool blocked
        readonly property alias hovered: card.hovered
        readonly property bool chosen: root.currentValue === shell.value
        property real inset: shell.chosen ? root.ringRoom : 0
        Behavior on inset {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        width: root.cardWidth
        height: root.cardHeight

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.verylarge + root.ringRoom
            color: "transparent"
            border.width: root.ringWidth
            border.color: Appearance.colors.colPrimary
            opacity: shell.chosen ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        CardButton {
            id: card
            anchors.fill: parent
            // Edge to edge with the page's other blocks while unchosen; chosen, it draws
            // in by the ring's room and the ring takes the edge.
            anchors.margins: shell.inset
            value: shell.value
            title: shell.title
            summary: shell.summary
            blocked: shell.blocked
        }
    }

    component CardButton: RippleButton {
        id: card

        required property string value
        required property string title
        required property string summary
        required property bool blocked

        readonly property bool chosen: root.currentValue === card.value
        readonly property color colContent: card.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
        enabled: !card.blocked
        opacity: 1
        buttonRadius: Appearance.rounding.verylarge
        buttonRadiusPressed: Appearance.rounding.large
        colBackground: card.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
        colBackgroundHover: card.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
        colRipple: card.chosen ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer1Active
        onClicked: root.selected(card.value)

        contentItem: Item {
            // The screen's top edge, and the shell hanging from it.
            Rectangle {
                id: edge
                x: 14
                y: 14
                width: root.tall ? parent.width - 28 : Math.min(196, parent.width * 0.42)
                height: root.tall ? 74 : parent.height - 28
                radius: Appearance.rounding.large
                color: card.chosen ? ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colOnSecondaryContainer, 0.88)
                    : Appearance.colors.colLayer2
                clip: true
                opacity: card.blocked ? 0.5 : 1

                // The hover swells the shell a little, the way the island takes a hold.
                readonly property real swell: card.hovered && !card.blocked ? 1 : 0
                property real swellLive: edge.swell
                Behavior on swellLive {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                NotchShape {
                    readonly property bool pill: card.value === "island"
                    readonly property bool wave: card.value === "sculpted"
                    // Kept clear of the frame's rounded corners, which the wide S reaches.
                    readonly property real bodyWidth: Math.min(124, edge.width * 0.62,
                        edge.width - 2 * (shoulder + edge.radius)) * (1 + 0.12 * edge.swellLive)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: pill ? 10 : 0
                    width: Math.round(bodyWidth + 2 * shoulder)
                    height: Math.round(26 + 6 * edge.swellLive)
                    // The sculpted S at the island's own proportions (NotchIsland.sculptWing).
                    shoulder: pill ? 0 : wave ? 33 : 7
                    attached: !pill
                    sculpted: wave
                    foot: 26
                    topRadius: pill ? height / 2 : 0
                    bottomRadius: height / 2
                    color: root.islandColor

                    // The clock, so the silhouette reads as the island and not a bar.
                    Row {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 0
                        spacing: 5
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Appearance.colors.colPrimary
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 5
                            radius: 2.5
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.7
                        }
                    }
                }
            }

            // Placed rather than anchored: the two arrangements swap at run time, and a
            // conditional anchor released to `undefined` keeps its old offset.
            ColumnLayout {
                x: root.tall ? 18 : edge.x + edge.width + 18
                y: root.tall ? edge.y + edge.height + 12 : Math.round((parent.height - height) / 2)
                width: parent.width - x - 18
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: card.title
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: card.colContent
                        elide: Text.ElideRight
                    }
                    MaterialShapeWrappedMaterialSymbol {
                        text: card.blocked ? "lock" : "check"
                        iconSize: 16
                        padding: 5
                        fill: 1
                        shape: card.chosen ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                        color: card.chosen ? Appearance.colors.colPrimary : "transparent"
                        colSymbol: card.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        opacity: card.chosen || card.blocked ? 1 : 0
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.summary
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: card.colContent
                    opacity: 0.78
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }
}
