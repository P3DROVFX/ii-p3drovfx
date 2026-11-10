pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Free up space: the places that grow on their own, each a toggle with its size, and
 * one button that cleans what is on. The system ones ask for the password through
 * pkexec; old journal archives and old package versions are the only things removed.
 */
ClockSheet {
    id: root

    readonly property var sizes: HealthService.system?.cleanup ?? ({})
    property var picked: ({ journal: true, pacmanCache: HealthService.packageManager === "pacman", trash: false })
    property var queue: []
    property string running: ""
    property var results: ({})

    readonly property var items: [
        { id: "journal", symbol: "receipt_long", shape: MaterialShape.Shape.Cookie7Sided, label: Translation.tr("Journal archives"),
          description: Translation.tr("Keep the last 4 weeks · %1").arg(HealthText.bytes(root.sizes.journal)), available: true },
        { id: "pacmanCache", symbol: "package_2", shape: MaterialShape.Shape.Cookie9Sided, label: Translation.tr("Package cache"),
          description: Translation.tr("Keep 2 versions of each package · %1").arg(HealthText.bytes(root.sizes.pacmanCache)),
          available: HealthService.packageManager === "pacman" },
        { id: "trash", symbol: "delete", shape: MaterialShape.Shape.Sunny, label: Translation.tr("Trash"),
          description: Translation.tr("Empty it for good · %1").arg(HealthText.bytes(root.sizes.trash)), available: true }
    ]
    readonly property int pickedCount: root.items.filter(i => i.available && root.picked[i.id]).length

    title: Translation.tr("Free up space")
    subtitle: Translation.tr("Old logs, old packages and the trash")

    function start(): void {
        root.results = {};
        root.queue = root.items.filter(i => i.available && root.picked[i.id]).map(i => i.id);
        root.next();
    }

    function next(): void {
        if (root.queue.length === 0) {
            root.running = "";
            return;
        }
        root.running = root.queue[0];
        root.queue = root.queue.slice(1);
        HealthService.cleanup(root.running);
    }

    Connections {
        target: HealthService
        function onCleanupFinished(what, ok) {
            if (what !== root.running)
                return;
            const r = Object.assign({}, root.results);
            r[what] = ok;
            root.results = r;
            root.next();
        }
    }

    Repeater {
        model: root.items

        ClockFormToggle {
            required property var modelData
            Layout.fillWidth: true
            visible: modelData.available
            symbol: modelData.symbol
            shapeKind: modelData.shape
            label: modelData.label
            description: root.results[modelData.id] === true ? Translation.tr("Cleaned")
                : root.results[modelData.id] === false ? Translation.tr("Skipped: the password was not given or it failed")
                : root.running === modelData.id ? Translation.tr("Cleaning…") : modelData.description
            checked: root.picked[modelData.id] === true
            onToggled: checked => {
                const p = Object.assign({}, root.picked);
                p[modelData.id] = checked;
                root.picked = p;
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Crash dumps are removed by systemd after 3 days on its own. Unused packages are reviewed in a terminal from the Storage page.")
        wrapMode: Text.Wrap
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Cancel")
            onClicked: root.close()
        },
        ClockSheetAction {
            primary: true
            enabled: root.pickedCount > 0 && root.running.length === 0
            label: root.running.length > 0 ? Translation.tr("Cleaning…") : HealthText.plural(root.pickedCount, Translation.tr("Clean %1 place"), Translation.tr("Clean %1 places"))
            symbol: "cleaning_services"
            onClicked: root.start()
        }
    ]
}
