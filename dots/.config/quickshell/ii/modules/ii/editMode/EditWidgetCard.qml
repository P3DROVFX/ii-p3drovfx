import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "EditWidgetGlyphs.js" as EditWidgetGlyphs

/**
 * One widget in Edit Mode's catalogue: its own shape and glyph, its name set
 * large, and the count control. A click adds one, a drag places it where it
 * is let go.
 *
 * Calm until engaged: the idle card and its shape sit on neutral surfaces,
 * hover morphs the shape and lights the plus, and a placed widget turns the
 * card secondary and its shape primary.
 */
EditDragArea {
    id: root

    readonly property real padding: 14
    readonly property real gap: 14
    readonly property real shapeSize: 46
    readonly property real glyphSize: 22
    readonly property real minHeight: 68
    readonly property real textSpacing: 0
    readonly property real titleSize: Appearance.font.pixelSize.hugeass
    readonly property var titleAxesIdle: ({ "wght": 560, "wdth": 88, "ROND": 100 })
    readonly property var titleAxesEngaged: ({ "wght": 720, "wdth": 100, "ROND": 100 })
    readonly property real draggedOpacity: 0.45
    readonly property real actionInset: 4
    readonly property real hostRadius: Appearance.rounding.verylarge
    readonly property real hostPadding: 14
    readonly property real radiusIdle: Math.max(Appearance.rounding.verysmall, root.hostRadius - root.hostPadding)
    readonly property real radiusPressed: Math.min(root.height / 2, Appearance.rounding.large * 2)
    // Idle → hover partners; each widget keeps the pair its id hashes to.
    readonly property var shapePairs: [
        ["Cookie7Sided", "Cookie12Sided"],
        ["Clover4Leaf", "Clover8Leaf"],
        ["Sunny", "VerySunny"],
        ["SoftBurst", "Burst"],
        ["Pentagon", "Cookie6Sided"],
        ["Gem", "Cookie9Sided"],
        ["Puffy", "PuffyDiamond"],
        ["Ghostish", "Flower"],
        ["Cookie4Sided", "SoftBoom"]
    ]

    property var widget: ({})
    property int count: 0
    property string caption: ""
    property bool highlighted: hover.hovered

    signal increment()
    signal decrement()

    readonly property bool placed: root.count > 0
    readonly property string glyph: EditWidgetGlyphs.glyphFor(root.widget, WidgetsRegistry.allWidgets)

    property real boldness: root.highlighted || root.placed ? 1 : 0
    Behavior on boldness {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    function axis(name) {
        const from = root.titleAxesIdle[name];
        return Math.round(from + (root.titleAxesEngaged[name] - from) * Math.max(0, Math.min(1, root.boldness)));
    }
    readonly property var shapePair: {
        const id = root.widget?.widgetId ?? "";
        let hash = 0;
        for (let i = 0; i < id.length; i++)
            hash = (hash * 31 + id.charCodeAt(i)) | 0;
        return root.shapePairs[Math.abs(hash) % root.shapePairs.length];
    }

    readonly property color colCard: root.placed
        ? (root.pressed ? Appearance.colors.colSecondaryContainerActive
            : root.highlighted ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colSecondaryContainer)
        : (root.pressed ? Appearance.colors.colSurfaceContainerHighestActive
            : root.highlighted ? Appearance.colors.colSurfaceContainerHighest
            : Appearance.colors.colSurfaceContainerHigh)
    readonly property color colContent: root.placed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
    readonly property color colSubContent: root.placed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
    readonly property color colShape: root.placed ? Appearance.colors.colPrimary
        : root.highlighted ? Appearance.colors.colSecondaryContainer
        : Appearance.colors.colSurfaceContainerHighest
    readonly property color colGlyph: root.placed ? Appearance.colors.colOnPrimary
        : root.highlighted ? Appearance.colors.colOnSecondaryContainer
        : Appearance.colors.colOnSurfaceVariant

    implicitHeight: Math.max(root.minHeight, textColumn.implicitHeight + root.padding * 2)
    opacity: root.dragActive ? root.draggedOpacity : 1

    Behavior on opacity {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    HoverHandler {
        id: hover
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.pressed ? root.radiusPressed : root.radiusIdle
        color: root.colCard

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(surface)
        }
        Behavior on radius {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(surface)
        }
    }

    MaterialShapeWrappedMaterialSymbol {
        id: glyphShape
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: root.shapeSize
        shape: glyphShape.getShape(root.highlighted || root.placed ? root.shapePair[1] : root.shapePair[0])
        text: root.glyph
        iconSize: root.glyphSize
        fill: root.placed ? 1 : 0
        color: root.colShape
        colSymbol: root.colGlyph

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(glyphShape)
        }
        Behavior on colSymbol {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(glyphShape)
        }
    }

    Column {
        id: textColumn
        anchors.left: glyphShape.right
        anchors.leftMargin: root.gap
        width: root.width - root.padding - root.shapeSize - root.gap * 2 - action.settledWidth - action.anchors.rightMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.textSpacing

        StyledText {
            width: parent.width
            visible: root.caption !== ""
            text: root.caption
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: root.placed ? root.colContent : Appearance.colors.colPrimary
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: root.widget?.name ?? root.widget?.widgetId ?? ""
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": root.axis("wght"), "wdth": root.axis("wdth"), "ROND": root.axis("ROND") })
            font.pixelSize: root.titleSize
            color: root.colContent
            elide: Text.ElideRight
        }
    }

    EditWidgetCountAction {
        id: action
        anchors.right: parent.right
        anchors.rightMargin: root.padding - root.actionInset
        anchors.verticalCenter: parent.verticalCenter
        count: root.count
        highlighted: root.highlighted
        colContent: root.colContent
        onIncrement: root.increment()
        onDecrement: root.decrement()
    }
}
