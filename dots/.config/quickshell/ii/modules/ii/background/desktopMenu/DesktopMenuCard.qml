import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode

/**
 * The desktop's right-click menu: what the desktop offers when a click lands
 * on no widget. Four rows, deliberately (decision D6): the wallpaper picker,
 * the catalogue for whatever was clicked, the layout editor, and Settings.
 */
Item {
    id: root

    signal dismissRequested()

    // Whether the click was on the bar rather than the desktop. It decides two
    // rows: a bar is not a place to pick a wallpaper from, and the catalogue
    // row opens the bar's widgets instead of the desktop's.
    property bool onBar: false

    readonly property real padding: 6
    implicitWidth: 236
    implicitHeight: card.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // Clicks on the card's own padding must not reach the closer behind it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: column.implicitHeight + root.padding * 2
        radius: Appearance.rounding.windowRounding
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: root.padding
            spacing: 2

            EditMenuRow {
                visible: !root.onBar
                cardPadding: root.padding
                symbol: "wallpaper"
                label: Translation.tr("Wallpaper & style")
                onClicked: {
                    root.dismissRequested();
                    GlobalStates.wallpaperSelectorOpen = true;
                }
            }
            EditMenuRow {
                cardPadding: root.padding
                symbol: "widgets"
                label: root.onBar ? Translation.tr("Bar widgets") : Translation.tr("Desktop widgets")
                onClicked: {
                    root.dismissRequested();
                    const section = root.onBar ? "bar" : "widgets";
                    GlobalStates.openEditCatalogue(section, GlobalStates.desktopMenuScreenName);
                }
            }
            EditMenuRow {
                cardPadding: root.padding
                symbol: GlobalStates.editMode ? "done" : "edit"
                label: GlobalStates.editMode ? Translation.tr("Done editing") : Translation.tr("Edit layout")
                onClicked: {
                    root.dismissRequested();
                    if (GlobalStates.editMode)
                        GlobalStates.closeEditMode();
                    else
                        GlobalStates.openEditMode();
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }

            EditMenuRow {
                cardPadding: root.padding
                symbol: "settings"
                label: Translation.tr("Settings")
                onClicked: {
                    root.dismissRequested();
                    GlobalStates.openSettings();
                }
            }
        }
    }
}
