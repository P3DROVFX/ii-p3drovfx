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
 *
 * The bar and the dock ask for the same menu. Where the click landed decides
 * the rows: a bar is not a place to pick a wallpaper from, the bar's
 * catalogue row opens the bar's widgets instead of the desktop's, and the
 * dock keeps only its own way into the mode - its page in the catalogue -
 * because the dock's icons already carry their own menu.
 */
Item {
    id: root

    signal dismissRequested()

    // "desktop", "bar" or "dock".
    property string origin: "desktop"
    readonly property bool onBar: root.origin === "bar"
    readonly property bool onDock: root.origin === "dock"

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
                    GlobalStates.openEditCatalogue("style", GlobalStates.desktopMenuScreenName);
                }
            }
            EditMenuRow {
                visible: !root.onDock
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
                visible: PanelFamily.touchFirst && !root.onBar && !root.onDock
                cardPadding: root.padding
                symbol: "apps"
                label: Translation.tr("Home screen apps")
                onClicked: {
                    root.dismissRequested();
                    GlobalStates.openEditCatalogue("apps", GlobalStates.desktopMenuScreenName);
                }
            }
            // From the dock, the mode opens on the dock's own page: what was
            // clicked is what gets edited, the same rule as the rows above.
            EditMenuRow {
                cardPadding: root.padding
                symbol: GlobalStates.editMode ? "done" : (root.onDock ? (PanelFamily.touchFirst ? "dock_to_bottom" : "dock") : "edit")
                label: GlobalStates.editMode ? Translation.tr("Done editing")
                    : root.onDock ? (PanelFamily.touchFirst ? Translation.tr("Edit taskbar") : Translation.tr("Edit dock"))
                    : Translation.tr("Edit layout")
                onClicked: {
                    root.dismissRequested();
                    if (GlobalStates.editMode) {
                        GlobalStates.closeEditMode();
                        return;
                    }
                    if (root.onDock) {
                        GlobalStates.openEditCatalogue("dock", GlobalStates.desktopMenuScreenName, "appearance");
                        return;
                    }
                    GlobalStates.openEditMode(GlobalStates.desktopMenuScreenName);
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
                    GlobalStates.openSettingsFromEditMode("");
                }
            }
        }
    }
}
