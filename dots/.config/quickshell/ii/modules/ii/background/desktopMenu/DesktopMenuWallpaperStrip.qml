import QtQuick
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The desktop menu's recent wallpapers: the last `Wallpapers.recentLimit`
 * applied, three on show at a time - one expanded, one beside it, one
 * peeking at the edge. The wheel, or a drag, walks the expanded one through
 * the list; a click applies the wallpaper it lands on.
 *
 * While the history is short (a fresh install has one entry, or none), the
 * rest of the strip is filled with random picks from the user's wallpaper
 * folder - the selector's default one, not whatever folder it last browsed.
 *
 * Every tile is placed by hand rather than by a Row: a Row still spends its
 * spacing on the zero-width tiles outside the window, and the tiles have to
 * slide and resize as one when the expanded index moves, which is a Behavior
 * on each tile's x and width, not a relayout.
 */
Item {
    id: root

    readonly property var recents: Wallpapers.recentWallpapers
    // Drawn once per open (reset()), so the strip does not reshuffle under
    // the pointer; the recents always come first.
    property var fillers: []
    readonly property var paths: {
        const recents = Array.from(root.recents);
        const extra = root.fillers.filter(p => !recents.includes(p));
        return recents.concat(extra).slice(0, Wallpapers.recentLimit);
    }
    readonly property int count: root.paths.length
    readonly property string currentPath: FileUtils.trimFileProtocol(String(Config.options?.background?.wallpaperPath ?? ""))

    // The expanded tile. Put back on the current wallpaper each time the
    // menu opens (reset()), so the strip starts on what is on screen.
    property int expanded: 0
    function reset(): void {
        const i = root.paths.indexOf(root.currentPath);
        root.expanded = i >= 0 ? i : 0;
        root.drawFillers();
    }

    // ── Random fill ──────────────────────────────────────────────────────────
    readonly property string folder: FileUtils.trimFileProtocol(Wallpapers.defaultFolder.toString())
    function drawFillers(): void {
        const missing = Wallpapers.recentLimit - root.recents.length;
        if (missing <= 0 || root.folder === "") {
            root.fillers = [];
            return;
        }
        if (fillerProbe.running)
            return;
        // One `-iname` per extension, OR-ed; the folder and the count ride
        // as positional arguments so no path is ever spliced into the script.
        const names = Wallpapers.extensions.map(ext => `-iname '*.${ext}'`).join(" -o ");
        fillerProbe.command = ["bash", "-c",
            `find "$1" -maxdepth 1 -type f \\( ${names} \\) -print0 2>/dev/null | shuf -z -n "$2" | tr '\\0' '\\n'`,
            "_", root.folder, String(Wallpapers.recentLimit)];
        fillerProbe.running = true;
    }
    Process {
        id: fillerProbe
        stdout: StdioCollector {
            onStreamFinished: {
                root.fillers = text.split("\n").filter(line => line.length > 0);
                // The strip may have opened empty; start it on the current
                // wallpaper if the draw brought it in.
                const i = root.paths.indexOf(root.currentPath);
                if (i >= 0 && root.expanded === 0)
                    root.expanded = i;
            }
        }
    }

    readonly property real spacing: 4
    readonly property real tileRadius: Appearance.rounding.windowRounding - 8
    readonly property real peekWidth: 28
    implicitHeight: 112

    // The window of three: starts at the expanded tile until the end of the
    // list, where it stops and the expanded tile walks to its far side.
    readonly property int windowStart: Math.max(0, Math.min(root.expanded, root.count - 3))
    readonly property int windowSize: Math.min(3, root.count)

    // Widths by role. With fewer than three there is nothing to peek at, so
    // the expanded tile and its neighbour share the width.
    readonly property real largeWidth: {
        if (root.windowSize <= 1)
            return root.width;
        if (root.windowSize === 2)
            return Math.round((root.width - root.spacing) * 0.64);
        return root.width - 2 * root.spacing - root.peekWidth - root.mediumWidth;
    }
    readonly property real mediumWidth: root.windowSize === 2
        ? root.width - root.spacing - Math.round((root.width - root.spacing) * 0.64)
        : Math.round((root.width - 2 * root.spacing - root.peekWidth) * 0.36)

    function tileWidth(index: int): real {
        if (index < root.windowStart || index >= root.windowStart + root.windowSize)
            return 0;
        if (index === root.expanded)
            return root.largeWidth;
        if (root.windowSize < 3)
            return root.mediumWidth;
        // Of the other two, the one after the expanded tile is the neighbour
        // and the one before it peeks; at the end both sit before it, and
        // the nearer one is the neighbour.
        if (index > root.expanded)
            return index === root.expanded + 1 ? root.mediumWidth : root.peekWidth;
        return (root.expanded === root.windowStart + 2 && index === root.expanded - 1)
            ? root.mediumWidth : root.peekWidth;
    }
    function tileX(index: int): real {
        if (index < root.windowStart)
            return 0;
        if (index >= root.windowStart + root.windowSize)
            return root.width;
        let x = 0;
        for (let i = root.windowStart; i < index; i++)
            x += root.tileWidth(i) + root.spacing;
        return x;
    }

    function step(direction: int): void {
        root.expanded = Math.max(0, Math.min(root.count - 1, root.expanded + direction));
    }

    // A wheel notch is 120; a touchpad sends many small deltas, so they are
    // summed until they make one.
    property real _wheelAccum: 0
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const d = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)
                ? event.angleDelta.x : event.angleDelta.y;
            root._wheelAccum += d;
            while (Math.abs(root._wheelAccum) >= 120) {
                root.step(root._wheelAccum > 0 ? -1 : 1);
                root._wheelAccum -= root._wheelAccum > 0 ? 120 : -120;
            }
        }
    }

    Repeater {
        model: root.paths

        delegate: ClippingRectangle {
            id: tile
            required property string modelData
            required property int index
            readonly property bool isExpanded: tile.index === root.expanded
            readonly property bool isCurrent: tile.modelData === root.currentPath

            x: root.tileX(tile.index)
            width: root.tileWidth(tile.index)
            height: root.height
            visible: tile.width > 0.5
            radius: Math.min(root.tileRadius, tile.width / 2)
            color: Appearance.colors.colLayer2

            Behavior on x {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(tile)
            }
            Behavior on width {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(tile)
            }

            ThumbnailImage {
                // Sized to the expanded tile, never to the animated width:
                // the thumbnail size follows the item, and a width that
                // sweeps through every value would request every size.
                anchors.centerIn: parent
                width: root.largeWidth
                height: root.height
                sourcePath: tile.modelData
                thumbnailService: Wallpapers
                fillMode: Image.PreserveAspectCrop
            }

            // The tiles not in focus sit back a little.
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: tile.isExpanded ? 0 : (root.hoveredIndex === tile.index ? 0.12 : 0.28)
                Behavior on opacity {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tile)
                }
            }

            // What is on screen now.
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 8
                width: 30
                height: 30
                radius: width / 2
                color: Appearance.colors.colSecondaryContainer
                opacity: tile.isCurrent && tile.width >= 56 ? 0.92 : 0
                Behavior on opacity {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tile)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "check"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

        }
    }

    // ── Pointer ──────────────────────────────────────────────────────────────
    // One area over the whole strip rather than one per tile: a press that
    // turns into a drag scrolls, and a drag can start on one tile and end on
    // another. A release that never became a drag is the click.
    readonly property real dragStep: 56
    readonly property int hoveredIndex: stripMouse.containsMouse && !stripMouse.dragging
        ? root.indexAt(stripMouse.mouseX) : -1

    function indexAt(x: real): int {
        for (let i = 0; i < root.count; i++) {
            const w = root.tileWidth(i);
            const left = root.tileX(i);
            if (w > 0 && x >= left && x < left + w)
                return i;
        }
        return -1;
    }

    // Applying puts the strip back on its first tile: the wallpaper just set
    // becomes the newest recent, and that is where it is shown.
    function apply(index: int): void {
        const path = root.paths[index];
        if (!path)
            return;
        root.expanded = 0;
        if (path !== root.currentPath)
            Wallpapers.select(path);
    }

    MouseArea {
        id: stripMouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: stripMouse.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        property real pressX: 0
        property real stepAnchorX: 0
        property bool dragging: false

        onPressed: mouse => {
            stripMouse.pressX = mouse.x;
            stripMouse.stepAnchorX = mouse.x;
            stripMouse.dragging = false;
        }
        onPositionChanged: mouse => {
            if (!stripMouse.pressed)
                return;
            if (!stripMouse.dragging && Math.abs(mouse.x - stripMouse.pressX) < 6)
                return;
            stripMouse.dragging = true;
            // Content follows the hand: dragging left brings the next one in.
            while (mouse.x - stripMouse.stepAnchorX <= -root.dragStep) {
                root.step(1);
                stripMouse.stepAnchorX -= root.dragStep;
            }
            while (mouse.x - stripMouse.stepAnchorX >= root.dragStep) {
                root.step(-1);
                stripMouse.stepAnchorX += root.dragStep;
            }
        }
        onReleased: mouse => {
            const wasDrag = stripMouse.dragging;
            stripMouse.dragging = false;
            if (!wasDrag)
                root.apply(root.indexAt(mouse.x));
        }
        onCanceled: stripMouse.dragging = false
    }
}
