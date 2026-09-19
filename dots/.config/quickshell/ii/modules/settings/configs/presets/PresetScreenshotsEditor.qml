import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The pictures a preset ships: take new ones, add some from disk, reorder and
 * remove them. Holds a list of file paths and nothing else; whoever embeds it
 * decides when that list is published.
 */
ColumnLayout {
    id: root
    spacing: 12

    // Absolute file paths, in the order they will ship. The first one is the
    // picture the store shows on the preset's card.
    property var shots: []
    // preset_store.py's MAX_SCREENSHOTS / MAX_SCREENSHOT_BYTES.
    property int maxShots: 6
    property real maxBytes: 8 * 1024 * 1024
    property bool interactive: true

    property bool capturing: false
    readonly property bool picking: pickerProc.running
    property string notice: ""
    property string lastCapturedMonitor: ""

    readonly property bool full: root.shots.length >= root.maxShots
    // Cards take the screen's shape, so a capture fills its card uncropped.
    readonly property real cellAspect: {
        const screen = (root.QsWindow.window as QsWindow)?.screen ?? null;
        return screen && screen.height > 0 ? screen.width / screen.height : 16 / 10;
    }
    property int lightboxIndex: -1
    readonly property string shotDirectory: FileUtils.trimFileProtocol(`${Directories.state}/preset-screenshots`)
    // Where the file picker opens: the screenshot folder the shell saves into,
    // else the usual one. The picker script falls back further if neither exists.
    readonly property string pickerDirectory: Config.options.screenSnip.savePath.length > 0
        ? FileUtils.trimFileProtocol(Config.options.screenSnip.savePath)
        : `${FileUtils.trimFileProtocol(Directories.home)}/Pictures/Screenshots`

    function add(paths) {
        let next = root.shots.slice();
        let skipped = 0;
        for (const path of paths) {
            if (next.indexOf(path) !== -1)
                continue;
            if (next.length >= root.maxShots) {
                skipped++;
                continue;
            }
            next.push(path);
        }
        root.shots = next;
        if (skipped > 0)
            root.notice = Translation.tr("A preset can ship at most %1 screenshots, so %2 were left out.")
                .arg(root.maxShots).arg(skipped);
    }

    function removeAt(index) {
        let next = root.shots.slice();
        next.splice(index, 1);
        root.shots = next;
    }

    function move(index, delta) {
        const target = index + delta;
        if (delta === 0 || target < 0 || target >= root.shots.length)
            return;
        let next = root.shots.slice();
        const [shot] = next.splice(index, 1);
        next.splice(target, 0, shot);
        root.shots = next;
    }

    // The grid runs on a ListModel mirrored from `shots`, so a reorder moves the
    // existing delegates instead of rebuilding them and re-decoding every image.
    onShotsChanged: root.syncModel()
    Component.onCompleted: root.syncModel()

    function syncModel() {
        for (let i = 0; i < root.shots.length; i++) {
            const path = root.shots[i];
            if (i < shotModel.count && shotModel.get(i).path === path)
                continue;
            let found = -1;
            for (let j = i + 1; j < shotModel.count; j++) {
                if (shotModel.get(j).path === path) {
                    found = j;
                    break;
                }
            }
            if (found !== -1)
                shotModel.move(found, i, 1);
            else
                shotModel.insert(i, { "path": path });
        }
        if (shotModel.count > root.shots.length)
            shotModel.remove(root.shots.length, shotModel.count - root.shots.length);
        if (root.lightboxIndex >= root.shots.length)
            root.lightboxIndex = root.shots.length - 1;
    }

    function urlFor(path) {
        return path.startsWith("file://") ? path : `file://${path}`;
    }

    ListModel {
        id: shotModel
    }

    ScreenshotLightbox {
        sources: root.shots.map(path => root.urlFor(path))
        index: Math.max(0, root.lightboxIndex)
        shown: root.lightboxIndex >= 0
        onCloseRequested: root.lightboxIndex = -1
        onStepRequested: delta => {
            const count = root.shots.length;
            root.lightboxIndex = (root.lightboxIndex + delta + count) % count;
        }
    }

    // ── Capture ──────────────────────────────────────────────────────────────
    // Settings steps aside for the grab and comes back once grim is done.

    function capture() {
        if (root.capturing || root.full)
            return;
        root.capturing = true;
        root.notice = "";
        captureTimeout.restart();
        root.lastCapturedMonitor = (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            ? Hyprland.focusedMonitor.name
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
        GlobalStates.settingsSuspendedForScreenshot = true;
        GlobalStates.settingsOpen = false;
        captureDelay.restart();
    }

    function _endCapture() {
        captureTimeout.stop();
        root.capturing = false;
        GlobalStates.settingsOpen = true;
        GlobalStates.settingsSuspendedForScreenshot = false;
    }

    Timer {
        id: captureDelay
        interval: 400
        onTriggered: {
            const monitor = root.lastCapturedMonitor;
            const target = `${root.shotDirectory}/${Date.now()}.png`;
            const onScreen = monitor.length > 0 ? `-o '${StringUtils.shellSingleQuoteEscape(monitor)}' ` : "";
            captureProc.target = target;
            captureProc.command = ["bash", "-c",
                `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.shotDirectory)}' && `
                + `exec grim ${onScreen}'${StringUtils.shellSingleQuoteEscape(target)}'`];
            captureProc.running = true;
        }
    }

    Timer {
        id: captureTimeout
        interval: 8000
        onTriggered: {
            if (!root.capturing)
                return;
            captureProc.running = false;
            root._endCapture();
            root.notice = Translation.tr("Screenshot capture timed out.");
        }
    }

    Process {
        id: captureProc
        property string target: ""
        stderr: StdioCollector {
            id: captureStderr
        }
        onExited: (code, status) => {
            if (!root.capturing)
                return;
            root._endCapture();
            if (code !== 0) {
                const err = captureStderr.text ? captureStderr.text.trim() : "";
                root.notice = err.length > 0
                    ? err
                    : Translation.tr("The screenshot could not be taken. Is grim installed?");
                return;
            }
            root.add([captureProc.target]);
        }
    }

    // ── Pick from disk ───────────────────────────────────────────────────────
    // Prints "<bytes>\t<path>" per picked file so the size cap is checked here,
    // before anything is pushed.

    Process {
        id: pickerProc
        command: ["bash", "-c", `
            dir="$1"
            [ -d "$dir" ] || dir="$(xdg-user-dir PICTURES 2>/dev/null)/Screenshots"
            [ -d "$dir" ] || dir="$HOME/Pictures/Screenshots"
            [ -d "$dir" ] || dir="$HOME"
            if command -v kdialog >/dev/null 2>&1; then
                out=$(kdialog --getopenfilename "$dir/" "*.png *.jpg *.jpeg *.webp *.gif *.bmp|Images" \\
                    --multiple --separate-output 2>/dev/null)
            elif command -v zenity >/dev/null 2>&1; then
                out=$(zenity --file-selection --multiple --separator='|' --filename="$dir/" \\
                    --file-filter='Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp' 2>/dev/null | tr '|' '\\n')
            else
                echo __no_picker__
                exit 0
            fi
            printf '%s\\n' "$out" | while IFS= read -r f; do
                [ -f "$f" ] && printf '%s\\t%s\\n' "$(stat -c %s -- "$f")" "$f"
            done
        `, "_", root.pickerDirectory]
        stdout: StdioCollector {
            id: pickerOut
            onStreamFinished: {
                const raw = String(pickerOut.text ?? "").trim();
                if (raw === "__no_picker__") {
                    root.notice = Translation.tr("No file dialog is installed. Install kdialog or zenity.");
                    return;
                }
                let accepted = [];
                let refused = [];
                for (const line of raw.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab <= 0)
                        continue;
                    const size = Number(line.slice(0, tab));
                    const path = line.slice(tab + 1);
                    if (!/\.(png|jpe?g|webp|gif|bmp)$/i.test(path) || size > root.maxBytes)
                        refused.push(FileUtils.fileNameForPath(path));
                    else
                        accepted.push(path);
                }
                root.notice = "";
                root.add(accepted);
                if (refused.length > 0)
                    root.notice = Translation.tr("Skipped %1: only images up to %2 MB can be published.")
                        .arg(refused.join(", ")).arg(Math.floor(root.maxBytes / (1024 * 1024)));
            }
        }
    }

    // ── UI ───────────────────────────────────────────────────────────────────

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        RippleButtonWithIcon {
            materialIcon: "photo_camera"
            mainText: root.capturing ? Translation.tr("Capturing…") : Translation.tr("Take screenshot")
            buttonRadius: Appearance.rounding.small
            enabled: root.interactive && !root.capturing && !root.full
            onClicked: root.capture()
        }

        RippleButtonWithIcon {
            materialIcon: "add_photo_alternate"
            mainText: root.picking ? Translation.tr("Choosing…") : Translation.tr("Add from file")
            buttonRadius: Appearance.rounding.small
            enabled: root.interactive && !root.picking && !root.full
            onClicked: {
                root.notice = "";
                pickerProc.running = true;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        StyledText {
            text: `${root.shots.length}/${root.maxShots}`
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.notice.length > 0
        text: root.notice
        color: Appearance.colors.colError
        font.pixelSize: Appearance.font.pixelSize.small
        wrapMode: Text.Wrap
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.shots.length > 1
        text: Translation.tr("Drag to reorder, click to view full size.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnSurfaceVariant
    }

    // Slots are laid out by hand rather than by a Flow so a card can be lifted
    // out and the others slide into the gap it leaves.
    Item {
        id: grid
        Layout.fillWidth: true
        implicitHeight: grid.rows * (grid.cellHeight + grid.gap) - grid.gap
        visible: shotModel.count > 0

        readonly property int gap: 10
        readonly property int columns: Math.max(1, Math.min(3, Math.floor((grid.width + grid.gap) / (260 + grid.gap))))
        readonly property int rows: Math.ceil(shotModel.count / grid.columns)
        readonly property real cellWidth: (grid.width - grid.gap * (grid.columns - 1)) / grid.columns
        readonly property real cellHeight: Math.round(grid.cellWidth / root.cellAspect)

        property int dragFrom: -1
        property int dragTo: -1

        function slotX(slot) {
            return (slot % grid.columns) * (grid.cellWidth + grid.gap);
        }

        function slotY(slot) {
            return Math.floor(slot / grid.columns) * (grid.cellHeight + grid.gap);
        }

        function slotAt(x, y) {
            const column = Math.max(0, Math.min(grid.columns - 1, Math.floor(x / (grid.cellWidth + grid.gap))));
            const row = Math.max(0, Math.min(grid.rows - 1, Math.floor(y / (grid.cellHeight + grid.gap))));
            return Math.min(shotModel.count - 1, row * grid.columns + column);
        }

        // Where a card sits while another is being dragged over the grid.
        function visualSlot(index) {
            const from = grid.dragFrom;
            const to = grid.dragTo;
            if (from < 0 || to < 0 || index === from)
                return index;
            if (from < to && index > from && index <= to)
                return index - 1;
            if (from > to && index >= to && index < from)
                return index + 1;
            return index;
        }

        Repeater {
            model: shotModel

            delegate: Item {
                id: card
                required property string path
                required property int index

                readonly property bool dragging: grid.dragFrom === card.index && cardMouse.dragging
                property real dragX: 0
                property real dragY: 0

                width: grid.cellWidth
                height: grid.cellHeight
                x: card.dragging ? card.dragX : grid.slotX(grid.visualSlot(card.index))
                y: card.dragging ? card.dragY : grid.slotY(grid.visualSlot(card.index))
                z: card.dragging ? 10 : 0
                scale: card.dragging ? 1.03 : 1

                Behavior on x {
                    enabled: !card.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    enabled: !card.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledRectangularShadow {
                    target: cardClip
                    // Through opacity, so the shadow's own transparency gate still applies.
                    opacity: card.dragging ? 1 : 0
                }

                ClippingRectangle {
                    id: cardClip
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainerHigh

                    Image {
                        anchors.fill: parent
                        source: root.urlFor(card.path)
                        asynchronous: true
                        retainWhileLoading: true
                        fillMode: Image.PreserveAspectCrop
                        // Width only, rounded up to a bucket: decoding follows neither
                        // the aspect-derived height nor every pixel of a window resize.
                        sourceSize.width: Math.ceil(grid.cellWidth
                            * ((root.QsWindow.window as QsWindow)?.devicePixelRatio ?? 1) / 128) * 128
                    }
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    enabled: root.interactive
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: cardMouse.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    property bool dragging: false
                    property point pressPoint

                    onPressed: mouse => {
                        cardMouse.pressPoint = mapToItem(grid, mouse.x, mouse.y);
                        cardMouse.dragging = false;
                    }

                    onPositionChanged: mouse => {
                        if (!cardMouse.pressed)
                            return;
                        const point = mapToItem(grid, mouse.x, mouse.y);
                        const dx = point.x - cardMouse.pressPoint.x;
                        const dy = point.y - cardMouse.pressPoint.y;
                        if (!cardMouse.dragging) {
                            if (Math.hypot(dx, dy) < 8 || shotModel.count < 2)
                                return;
                            grid.dragFrom = card.index;
                            grid.dragTo = card.index;
                            cardMouse.dragging = true;
                        }
                        card.dragX = grid.slotX(card.index) + dx;
                        card.dragY = grid.slotY(card.index) + dy;
                        grid.dragTo = grid.slotAt(card.dragX + card.width / 2, card.dragY + card.height / 2);
                    }

                    onReleased: {
                        if (!cardMouse.dragging) {
                            root.lightboxIndex = card.index;
                            return;
                        }
                        const from = grid.dragFrom;
                        const to = grid.dragTo;
                        cardMouse.dragging = false;
                        grid.dragFrom = -1;
                        grid.dragTo = -1;
                        root.move(from, to - from);
                    }

                    onCanceled: {
                        cardMouse.dragging = false;
                        grid.dragFrom = -1;
                        grid.dragTo = -1;
                    }
                }

                Rectangle {
                    visible: card.index === 0
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 8
                    implicitWidth: coverLabel.implicitWidth + 14
                    implicitHeight: coverLabel.implicitHeight + 6
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer

                    StyledText {
                        id: coverLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Cover")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                ShotButton {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    visible: !card.dragging
                    symbol: "close"
                    symbolColor: Appearance.colors.colError
                    onClicked: root.removeAt(card.index)

                    StyledToolTip {
                        text: Translation.tr("Remove")
                    }
                }
            }
        }
    }

    component ShotButton: RippleButton {
        id: shotButton
        property string symbol
        property color symbolColor: Appearance.colors.colOnSurface

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        enabled: root.interactive
        opacity: enabled ? 1 : 0.4
        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.2)

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: shotButton.symbol
            iconSize: 18
            color: shotButton.symbolColor
        }
    }
}
