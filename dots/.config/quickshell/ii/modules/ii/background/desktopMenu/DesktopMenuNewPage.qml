import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode
import qs.modules.ii.background.shortcuts

/**
 * The desktop menu's "New" page: lets the user create a new folder
 * or a new text file directly inside ~/Desktop at the click coordinates.
 */
ColumnLayout {
    id: root

    signal backRequested()
    signal dismissRequested()

    required property string screenName
    property real targetX: 100
    property real targetY: 100

    spacing: 8

    // The page change, 0 -> 1, driven by the card.
    property real reveal: 1
    function slice(index: int): real {
        const t = (root.reveal - index * 0.14) / 0.72;
        return Math.max(0, Math.min(1, t));
    }

    component MenuRow: EditPanelRow {
        Layout.fillWidth: true
        hostRadius: Appearance.rounding.windowRounding
        hostPadding: 8
        trailingKind: "none"
    }

    // ── Header ───────────────────────────────────────────────────────────────
    EditMenuPageHeader {
        title: Translation.tr("New")
        opacity: root.slice(0)
        transform: Translate { x: (1 - root.slice(0)) * 16 }
        onBackRequested: root.backRequested()
    }

    // ── Rows ─────────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        opacity: root.slice(1)
        transform: Translate { x: (1 - root.slice(1)) * 16 }

        MenuRow {
            first: true
            last: false
            symbol: "create_new_folder"
            title: Translation.tr("New folder")
            subtitle: Translation.tr("Create a folder in ~/Desktop")
            onActivated: {
                DesktopShortcuts.createFolder(root.screenName, root.targetX, root.targetY);
                root.dismissRequested();
            }
        }

        MenuRow {
            first: false
            last: true
            symbol: "note_add"
            title: Translation.tr("New text file")
            subtitle: Translation.tr("Create a text file in ~/Desktop")
            onActivated: {
                DesktopShortcuts.createFile(root.screenName, root.targetX, root.targetY);
                root.dismissRequested();
            }
        }
    }
}
