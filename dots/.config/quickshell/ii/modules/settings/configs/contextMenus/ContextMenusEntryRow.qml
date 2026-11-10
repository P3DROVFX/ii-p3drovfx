import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One entry of a menu in the editor: the handle that reorders it, its glyph and name,
 * what kind of entry it is, and the buttons that act on it - into the icon bar, edit
 * (a custom command), take it out. A separator is a thin row of its own so it can be
 * moved like any entry.
 *
 * Every row is its own card (the keyboard layout list's rule): a grouped-list radius
 * re-rounds as rows are dragged past each other.
 */
RippleButton {
    id: root

    required property int index
    property var info: ({})
    property bool inBar: false
    property bool draggable: true
    /// The copy under the pointer: the handle held, no buttons.
    property bool ghost: false

    signal dragStarted(real y)
    signal dragMoved(real y)
    signal dragEnded
    signal barToggled
    signal editRequested
    signal removeRequested

    readonly property bool isSeparator: root.info.separator === true
    readonly property bool canBar: !root.isSeparator && root.info.block !== true && root.info.header !== true

    implicitHeight: root.isSeparator ? 40 : 54
    buttonRadius: Appearance.rounding.normal
    scale: 1
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    pointingHandCursor: false

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        MouseArea {
            id: handle
            visible: root.draggable
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 22
            implicitHeight: 40
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            // Without this the page's own flick takes the drag away as soon as it moves.
            preventStealing: true

            onPressed: mouse => root.dragStarted(handle.mapToItem(root, mouse.x, mouse.y).y)
            onPositionChanged: mouse => {
                if (handle.pressed)
                    root.dragMoved(handle.mapToItem(root, mouse.x, mouse.y).y);
            }
            onReleased: root.dragEnded()
            onCanceled: root.dragEnded()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "drag_indicator"
                iconSize: 20
                color: Appearance.colors.colSubtext
                opacity: root.hovered || handle.containsMouse || root.ghost ? 1 : 0.35

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        // A separator: the line it draws, and its name over it.
        Item {
            visible: root.isSeparator
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Appearance.colors.colOutlineVariant
            }
            Rectangle {
                anchors.centerIn: parent
                width: sepLabel.implicitWidth + 16
                height: sepLabel.implicitHeight + 4
                radius: height / 2
                color: Appearance.colors.colLayer2
                StyledText {
                    id: sepLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Separator")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle {
            visible: !root.isSeparator
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 34
            implicitHeight: 34
            radius: width / 2
            color: root.info.custom ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSecondaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.info.symbol ?? ""
                iconSize: 19
                color: root.info.custom ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSecondaryContainer
            }
        }

        ColumnLayout {
            visible: !root.isSeparator
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.info.title ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                text: root.info.kind ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: root.info.custom ? Appearance.font.family.monospace : Appearance.font.family.main
                color: Appearance.colors.colSubtext
            }
        }

        // An entry this panel family never draws, said in a word.
        Rectangle {
            visible: (root.info.onlyIn ?? "") !== ""
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: onlyInLabel.implicitWidth + 20
            implicitHeight: 24
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiaryContainer

            StyledText {
                id: onlyInLabel
                anchors.centerIn: parent
                text: root.info.onlyIn ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnTertiaryContainer
            }
        }

        ContextMenusRowAction {
            visible: !root.ghost && !root.isSeparator
            symbol: "toolbar"
            active: root.inBar
            enabled: root.canBar
            tooltip: root.info.header ? Translation.tr("Always drawn on top of the menu")
                : !root.canBar ? Translation.tr("Entries from the app cannot go in the icon bar")
                : root.inBar ? Translation.tr("In the icon bar (compact style) - click to list it")
                : Translation.tr("Put it in the icon bar (compact style)")
            onClicked: root.barToggled()
        }
        ContextMenusRowAction {
            visible: !root.ghost && root.info.custom === true
            symbol: "edit"
            tooltip: Translation.tr("Edit")
            onClicked: root.editRequested()
        }
        ContextMenusRowAction {
            visible: !root.ghost
            symbol: root.info.custom || root.info.userSeparator ? "delete" : "close"
            hoverTint: Appearance.colors.colError
            tooltip: root.info.custom ? Translation.tr("Delete this command")
                : root.isSeparator ? Translation.tr("Remove the separator")
                : Translation.tr("Take it out of the menu (it can be added back)")
            onClicked: root.removeRequested()
        }
    }
}
