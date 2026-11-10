import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A widget category, or a query's answer, as a gallery of cards under a
 * summary. The page reports gestures; the drawer owns what they do.
 *
 * The empty state is a SIBLING of the list: a child of a ListView is parented
 * into its content item, which is zero-sized when the model is empty.
 */
Item {
    id: root

    readonly property real cardGap: 6
    readonly property real headerGap: 10
    readonly property real captionInset: 12
    readonly property real captionTop: 4
    readonly property real emptyShapeSize: 72
    readonly property real emptyGlyphSize: 34
    readonly property string emptyShape: "Cookie7Sided"

    property var items: []
    property var group: null
    property bool searching: false
    property bool lockTab: false
    property int staggerStep: 0
    property var countOf: widgetId => 0
    property var captionOf: widget => ""

    readonly property string hoveredId: list.hoveredId

    signal addOne(string widgetId)
    signal removeOne(string widgetId)
    signal dragBegan(var widget)
    signal dragMoved(real sceneX, real sceneY)
    signal dragDropped(string widgetId, real sceneX, real sceneY)
    signal dragCancelled()

    StyledListView {
        id: list

        property string hoveredId: ""

        anchors.fill: parent
        staggerStep: root.staggerStep
        clip: true
        spacing: root.cardGap
        model: root.items

        header: Item {
            width: list.width
            height: (root.searching ? resultsLine.implicitHeight + root.captionTop : summary.implicitHeight) + root.headerGap
            visible: root.items.length > 0

            EditWidgetCatalogHeader {
                id: summary
                width: parent.width
                visible: !root.searching
                symbol: root.group?.icon ?? "widgets"
                items: root.items
                countOf: root.countOf
                hoveredId: list.hoveredId
                lockTab: root.lockTab
            }

            StyledText {
                id: resultsLine
                x: root.captionInset
                y: root.captionTop
                width: parent.width - root.captionInset * 2
                visible: root.searching
                text: root.items.length === 1
                    ? Translation.tr("1 widget")
                    : Translation.tr("%1 widgets").arg(root.items.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        delegate: EditWidgetCard {
            id: card
            required property var modelData
            required property int index

            width: list.width
            widget: card.modelData
            count: root.countOf(card.modelData.widgetId)
            caption: root.searching ? root.captionOf(card.modelData) : ""
            draggable: true
            dragOwner: list

            onHighlightedChanged: {
                if (card.highlighted)
                    list.hoveredId = card.modelData.widgetId;
                else if (list.hoveredId === card.modelData.widgetId)
                    list.hoveredId = "";
            }
            Component.onDestruction: {
                if (list.hoveredId === card.modelData?.widgetId)
                    list.hoveredId = "";
            }

            onActivated: root.addOne(card.modelData.widgetId)
            onIncrement: root.addOne(card.modelData.widgetId)
            onDecrement: root.removeOne(card.modelData.widgetId)
            onDragBegan: root.dragBegan(card.modelData)
            onDragMovedTo: (x, y) => root.dragMoved(x, y)
            onDragFinished: (x, y) => root.dragDropped(card.modelData.widgetId, x, y)
            onDragCancelled: root.dragCancelled()
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: root.headerGap
        visible: list.count === 0

        MaterialShapeWrappedMaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: root.emptyShapeSize
            shape: getShape(root.emptyShape)
            text: "search_off"
            iconSize: root.emptyGlyphSize
            color: Appearance.colors.colSecondaryContainer
            colSymbol: Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("No matches")
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurface
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Try a shorter name or another word")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
            wrapMode: Text.Wrap
        }
    }
}
