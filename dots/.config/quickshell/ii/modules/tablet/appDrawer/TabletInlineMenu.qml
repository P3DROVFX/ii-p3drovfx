pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A menu drawn inside the surface that opened it, growing out of the item it belongs to.
 *
 * Deliberately not a PopupWindow. The drawer is an Overlay layer that holds exclusive
 * keyboard focus while it is open, and stacking a second surface with its own focus grab on
 * top of that is a fight over input for something Android draws in the launcher itself. An
 * in-surface menu also inherits the drawer's own dismissal, so there is one way out of the
 * drawer rather than two that can disagree.
 *
 * Serves both the sort control and the long-press app menu, which is why the actions are a
 * plain list of `{ symbol, label, checked, destructive, trigger }` rather than fixed rows.
 */
Item {
    id: root

    /// One entry per row: `{ symbol, label, checked, destructive, trigger }`.
    property var actions: []
    property string headerText: ""
    property string headerIconPath: ""
    property string headerSymbol: ""
    property bool opened: false

    /// Where the menu grows from, in this item's coordinates.
    property real originX: 0
    property real originY: 0

    readonly property real rowHeight: Math.max(Appearance.sizes.minimumTouchTarget, 48)
    readonly property real menuWidth: 260

    visible: root.opened || card.opacity > 0.01
    enabled: root.opened

    function openAt(x, y, actionList, header, iconPath, symbol) {
        root.actions = actionList ?? [];
        root.headerText = header ?? "";
        root.headerIconPath = iconPath ?? "";
        root.headerSymbol = symbol ?? "";
        root.originX = x;
        root.originY = y;
        root.opened = true;
    }

    function close() {
        root.opened = false;
    }

    // Dismissal is a tap anywhere else, which is the only gesture available without a
    // second surface to grab focus with.
    MouseArea {
        anchors.fill: parent
        enabled: root.opened
        onClicked: root.close()
    }

    Rectangle {
        id: card

        // Clamped so a tile near an edge still gets a whole menu rather than a clipped one.
        x: Math.max(8, Math.min(root.width - card.width - 8, root.originX - card.width / 2))
        y: Math.max(8, Math.min(root.height - card.height - 8, root.originY))
        width: root.menuWidth
        implicitHeight: menuColumn.implicitHeight + Appearance.sizes.elevationMargin

        radius: Appearance.rounding.normal
        color: Config.options.appearance.transparency.popups
            ? Appearance.colors.colLayer1
            : Appearance.m3colors.m3surfaceContainer

        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : 0.85
        // Grows out of the item that opened it, the way an Android long-press menu does.
        transformOrigin: Item.Top

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
        }

        ColumnLayout {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Appearance.sizes.elevationMargin / 2
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Appearance.sizes.elevationMargin / 2
                visible: root.headerText.length > 0
                spacing: 10

                IconImage {
                    visible: root.headerIconPath.length > 0
                    implicitSize: Appearance.font.pixelSize.larger
                    source: root.headerIconPath
                }

                MaterialSymbol {
                    visible: root.headerSymbol.length > 0
                    text: root.headerSymbol
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerText
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: Appearance.sizes.elevationMargin / 4
                visible: root.headerText.length > 0
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            Repeater {
                model: root.actions

                delegate: RippleButton {
                    id: actionButton
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: root.rowHeight
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colBackgroundActive: Appearance.colors.colLayer1Active
                    colRipple: Appearance.colors.colLayer1Active

                    readonly property color contentColor: (actionButton.modelData.destructive ?? false)
                        ? Appearance.colors.colError
                        : Appearance.colors.colOnLayer1

                    releaseAction: () => {
                        // Closed first: an action that opens another surface must not have
                        // this one still sitting on top of it.
                        root.close();
                        actionButton.modelData.trigger?.();
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        MaterialSymbol {
                            text: actionButton.modelData.symbol ?? "chevron_right"
                            iconSize: Appearance.font.pixelSize.larger
                            color: actionButton.contentColor
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: actionButton.modelData.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: actionButton.contentColor
                            elide: Text.ElideRight
                        }

                        MaterialSymbol {
                            visible: actionButton.modelData.checked ?? false
                            text: "check"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }
}
