import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.editMode
import "utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * The (+) tile's catalogue: everything the dock can carry, as tiles that add
 * or take off with one click. An added tile fills with the primary
 * container and its icon's shape morphs from a circle to a cookie - the
 * state is the shape, not a ring around it.
 *
 * Its height is arithmetic (rows × tile, not a positioner's answer): the
 * popup's surface is sized from it before the first polish.
 */
Item {
    id: root

    property DockEditController controller: null
    signal appsRequested()

    readonly property int columns: 3
    readonly property real tileHeight: 92
    readonly property real tileSpacing: 6
    readonly property real labelHeight: 34
    readonly property real appsRowHeight: 58
    readonly property real maxHeight: 460

    readonly property var sections: {
        const out = [
            { "title": Translation.tr("Widgets"), "items": root.controller.nativeWidgets.map(entry => ({
                "id": entry.id, "symbol": entry.symbol, "title": entry.title })) },
            { "title": Translation.tr("Buttons"), "items": root.controller.buttons.map(entry => ({
                "id": entry.id, "symbol": entry.symbol, "title": entry.title })).concat([
                { "id": "widgetStack", "symbol": "stacks", "title": Translation.tr("Widget stack") }]) }
        ];
        for (const group of DockUtilityCatalog.groups) {
            out.push({ "title": Translation.tr(group.title), "items": DockUtilityCatalog.kindsInGroup(group.id).map(entry => ({
                "id": DockUtilityCatalog.orderKey(entry.kind), "symbol": entry.symbol, "title": Translation.tr(entry.title),
                "description": Translation.tr(entry.description) })) });
        }
        return out;
    }

    function sectionHeight(section) {
        const rows = Math.ceil(section.items.length / root.columns);
        return root.labelHeight + rows * root.tileHeight + Math.max(0, rows - 1) * root.tileSpacing;
    }
    readonly property real contentHeight: root.appsRowHeight
        + root.sections.reduce((total, section) => total + root.sectionHeight(section), 0) + 4

    implicitHeight: Math.min(root.maxHeight, root.contentHeight)

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: root.contentHeight
        clip: true

        Column {
            width: flick.width

            EditPanelRow {
                width: parent.width
                height: root.appsRowHeight
                implicitHeight: root.appsRowHeight
                symbol: "apps"
                title: Translation.tr("Apps")
                subtitle: Translation.tr("Pin any installed app")
                trailingKind: "chevron"
                onActivated: root.appsRequested()
            }

            Repeater {
                model: root.sections

                delegate: Column {
                    id: section
                    required property var modelData
                    width: parent.width
                    height: root.sectionHeight(section.modelData)

                    StyledText {
                        width: parent.width
                        height: root.labelHeight
                        leftPadding: 8
                        verticalAlignment: Text.AlignBottom
                        bottomPadding: 8
                        text: section.modelData.title
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    Grid {
                        columns: root.columns
                        spacing: root.tileSpacing

                        Repeater {
                            model: section.modelData.items

                            delegate: AddTile {
                                required property var modelData
                                width: (section.width - root.tileSpacing * (root.columns - 1)) / root.columns
                                height: root.tileHeight
                                entry: modelData
                            }
                        }
                    }
                }
            }
        }
    }

    component AddTile: Rectangle {
        id: tile

        property var entry: ({})
        readonly property bool added: root.controller.isAdded(tile.entry.id)
        readonly property string waiting: tile.added ? root.controller.waitingReason(tile.entry.id) : ""
        readonly property bool hovered: hover.hovered
        readonly property bool pressed: tap.pressed

        radius: tile.pressed ? Appearance.rounding.normal : Appearance.rounding.large
        color: tile.added
            ? ColorUtils.mix(tile.hovered ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer,
                Appearance.colors.colPrimary, 0.84)
            : (tile.hovered ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colSurfaceContainerHigh)
        scale: tile.pressed ? 0.96 : 1

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on radius {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialShapeWrappedMaterialSymbol {
            id: glyph
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            implicitSize: 40
            iconSize: 22
            padding: 9
            text: tile.entry.symbol ?? "widgets"
            shape: tile.added ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
            color: tile.added ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
            colSymbol: tile.added ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            fill: tile.added ? 1 : 0
        }

        StyledText {
            id: name
            anchors.top: glyph.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            horizontalAlignment: Text.AlignHCenter
            text: tile.entry.title ?? ""
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: tile.added ? Font.DemiBold : Font.Normal
            color: tile.added ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
        }

        StyledText {
            anchors.top: name.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            horizontalAlignment: Text.AlignHCenter
            visible: tile.waiting !== ""
            text: tile.waiting
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.3)
        }

        // The corner says what a click does: + adds, the check takes off.
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            width: 20
            height: 20
            radius: 10
            color: tile.added ? Appearance.colors.colPrimary : "transparent"
            opacity: tile.added || tile.hovered ? 1 : 0

            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: tile.added ? (tile.hovered ? "remove" : "check") : "add"
                iconSize: 15
                color: tile.added ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            }
        }

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: tap
            onTapped: root.controller.toggle(tile.entry.id)
        }

        StyledToolTip {
            text: tile.entry.description ?? ""
            extraVisibleCondition: (tile.entry.description ?? "") !== "" && tile.hovered
        }
    }
}
