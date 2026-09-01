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

    readonly property real edgeMargin: Math.max(12, Appearance.sizes.elevationMargin)
    readonly property real cardPadding: Math.max(12, Appearance.sizes.elevationMargin)
    readonly property real rowSpacing: Math.max(4, Math.round(Appearance.sizes.elevationMargin * 0.45))
    readonly property real rowHeight: Math.max(Appearance.sizes.minimumTouchTarget,
        Math.min(72, Math.round(root.height * 0.072)))
    readonly property real menuWidth: Math.max(320, Math.min(420, Math.round(root.width * 0.27)))
    readonly property real headerHeight: root.headerText.length > 0 ? root.rowHeight : 0
    readonly property real maximumMenuHeight: Math.max(root.rowHeight * 2,
        root.height - root.edgeMargin * 2)

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
        x: Math.max(root.edgeMargin, Math.min(root.width - card.width - root.edgeMargin,
            root.originX - card.width / 2))
        y: Math.max(root.edgeMargin, Math.min(root.height - card.height - root.edgeMargin,
            root.originY))
        width: root.menuWidth
        height: Math.min(root.maximumMenuHeight,
            root.cardPadding * 2 + root.headerHeight
                + (root.headerHeight > 0 ? root.rowSpacing : 0)
                + actionsColumn.implicitHeight)

        radius: Appearance.rounding.large
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
            anchors.fill: parent
            anchors.margins: root.cardPadding
            spacing: root.rowSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.headerHeight
                visible: root.headerText.length > 0
                spacing: 14

                IconImage {
                    visible: root.headerIconPath.length > 0
                    implicitSize: Math.round(root.rowHeight * 0.52)
                    source: root.headerIconPath
                }

                MaterialSymbol {
                    visible: root.headerSymbol.length > 0
                    text: root.headerSymbol
                    iconSize: Math.round(root.rowHeight * 0.46)
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }

            StyledFlickable {
                id: actionsFlickable

                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: actionsColumn.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                interactive: contentHeight > height

                ColumnLayout {
                    id: actionsColumn
                    width: actionsFlickable.width
                    spacing: root.rowSpacing

                    Repeater {
                        model: root.actions

                        delegate: RippleButton {
                            id: actionButton
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: root.rowHeight
                            useDynamicRadius: true
                            toggled: actionButton.modelData.checked ?? false
                            colBackground: (actionButton.modelData.destructive ?? false)
                                ? Appearance.colors.colErrorContainer
                                : Appearance.colors.colLayer2
                            colBackgroundHover: (actionButton.modelData.destructive ?? false)
                                ? Appearance.colors.colErrorContainerHover
                                : Appearance.colors.colLayer2Hover
                            colBackgroundActive: (actionButton.modelData.destructive ?? false)
                                ? Appearance.colors.colErrorContainerActive
                                : Appearance.colors.colLayer2Active
                            colBackgroundToggled: Appearance.colors.colPrimaryContainer
                            colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                            colBackgroundToggledActive: Appearance.colors.colPrimaryContainerActive
                            colRipple: (actionButton.modelData.destructive ?? false)
                                ? Appearance.colors.colErrorContainerActive
                                : Appearance.colors.colLayer2Active

                            readonly property color contentColor: (actionButton.modelData.destructive ?? false)
                                ? Appearance.colors.colOnErrorContainer
                                : (actionButton.toggled
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer2)

                            releaseAction: () => {
                                // Closed first: an action that opens another surface must not have
                                // this one still sitting on top of it.
                                root.close();
                                actionButton.modelData.trigger?.();
                            }

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                spacing: 16

                                MaterialSymbol {
                                    text: actionButton.modelData.symbol ?? "chevron_right"
                                    iconSize: Math.round(root.rowHeight * 0.38)
                                    color: actionButton.contentColor
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: actionButton.modelData.label ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: actionButton.contentColor
                                    elide: Text.ElideRight
                                }

                                MaterialSymbol {
                                    visible: actionButton.toggled
                                    text: "check"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: actionButton.contentColor
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
