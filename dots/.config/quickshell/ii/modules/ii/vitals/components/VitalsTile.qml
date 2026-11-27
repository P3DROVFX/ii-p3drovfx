import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A clickable tile: icon and name on top, when the value is from on the right, and the
 * body below (the default slot, sized to what is left). The whole tile is a button that
 * opens the type's page.
 *
 * The entrance animates this holder, not the button inside, so the button keeps its own
 * hover and press scale. Old data keeps the surface and fades the content
 * (`emphasis`, see VitalsStyle.emphasis).
 */
Item {
    id: root

    property string symbol: ""
    property string title: ""
    /// When the value is from ("13:05", "Yesterday", "13 Jul"); empty hides it.
    property string asOf: ""
    property real emphasis: 1
    /// The page's one primary-container tile.
    property bool hero: false
    property int entranceIndex: 0

    readonly property color colContent: root.hero ? VitalsStyle.colOnHero : VitalsStyle.colOnTile
    readonly property color colContentVariant: root.hero ? VitalsStyle.colOnHero : VitalsStyle.colOnTileVariant
    /// The body's size, for content that sizes itself from the space it gets.
    readonly property real bodyWidth: body.width
    readonly property real bodyHeight: body.height
    default property alias content: body.data

    signal clicked()

    StaggeredEntrance {
        index: root.entranceIndex
        active: !ClockStyle.reducedMotion
    }

    RippleButton {
        id: button
        anchors.fill: parent
        padding: VitalsStyle.tilePadding
        topPadding: VitalsStyle.tilePadding - 2
        buttonRadius: VitalsStyle.radiusTile
        colBackground: root.hero ? VitalsStyle.colHero : VitalsStyle.colTile
        colBackgroundHover: root.hero ? VitalsStyle.colHeroHover : VitalsStyle.colTileHover
        colRipple: root.hero ? VitalsStyle.colHeroActive : VitalsStyle.colTileActive
        onClicked: root.clicked()

        contentItem: ColumnLayout {
            spacing: ClockStyle.gapSmall
            opacity: root.emphasis

            Behavior on opacity {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: root.symbol
                    iconSize: ClockStyle.iconSmall + 2
                    fill: 1
                    color: root.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: root.colContent
                }

                StyledText {
                    visible: root.asOf.length > 0
                    text: root.asOf
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colContentVariant
                    opacity: 0.8
                }
            }

            Item {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
