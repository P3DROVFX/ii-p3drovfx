pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.draw
import qs.modules.common.widgets
import qs.modules.ii.notes
import "../../../common/draw/StrokeGeometry.js" as StrokeGeometry

/**
 * Drawing inside a note.
 *
 * The engine is the tablet's, untouched: `DrawSurface` reads stylus pressure through a
 * `PointHandler`, thins and smooths the samples, and turns pressure into width with a
 * floor. None of that arithmetic is reimplemented here — only what the drawing *is* and
 * where it goes.
 *
 * What is new is that the **strokes are kept**, not just the picture. The first version
 * saved a PNG and a second edit drew on top of a flat image: nothing could be undone
 * across sessions, and the drawing could never be re-exported at another size. Now the
 * strokes live in a sidecar beside the image, so an edit genuinely continues the drawing.
 * The image stays because it is what every other surface shows — the list, the widgets,
 * the reader.
 *
 * A sheet with edges, not the whole pane. A note is a document and a document has a
 * shape; drawing to the pane's edges would mean the saved picture changed shape with the
 * window, and the same note reopened at another size would letterbox its own drawing.
 */
Item {
    id: root

    /// The note and the block being drawn into.
    required property string noteId
    required property var block
    property var editor: null

    signal finished()

    readonly property string existingImage: root.block && root.block.asset.length > 0
        ? NotesService.assetPath(root.noteId, root.block.asset)
        : ""
    readonly property string strokesName: root.block ? String(root.block.strokes ?? "") : ""

    // ── The ink ───────────────────────────────────────────────────────────

    property var strokes: []
    property var undone: []
    property bool strokesLoaded: false
    /// True when the note holds a picture whose strokes were never kept — a drawing from
    /// before this existed, or one filed in from the tablet's live draw. It is shown
    /// underneath and left alone; the new strokes go on top.
    readonly property bool paintingOverImage: root.existingImage.length > 0 && !root.strokesLoaded

    readonly property bool hasInk: root.strokes.length > 0 || root.existingImage.length > 0

    property string tool: "pen"
    property string inkColor: ""
    property real inkWidth: 4

    readonly property var opts: Config.options?.tablet?.liveDraw ?? null
    readonly property var palette: {
        const configured = root.opts?.palette ?? [];
        const list = [];
        for (const entry of configured) {
            const value = String(entry ?? "").trim();
            if (value.length > 0)
                list.push(value);
        }
        return list.length > 0 ? list : ["#111111", "#ffffff"];
    }
    readonly property bool usePressure: root.opts?.pressure ?? true
    readonly property real smoothing: Math.max(0, Math.min(0.95, (root.opts?.smoothing ?? 55) / 100))

    function reset(): void {
        root.strokes = [];
        root.undone = [];
        root.tool = "pen";
        // The ink that shows up best against this sheet, measured — not the darkest.
        //
        // "Darkest in the palette" was the first rule, and it is only right half the time:
        // the sheet is a theme surface, so in a dark theme the darkest ink is invisible and
        // the pen looks broken. Comparing lightness against the paper works in both, and
        // keeps working when somebody edits the palette.
        const paper = Qt.color(Appearance.m3colors.m3surfaceContainerHigh).hslLightness;
        root.inkColor = root.palette.reduce((best, candidate) =>
            Math.abs(Qt.color(candidate).hslLightness - paper)
                > Math.abs(Qt.color(best).hslLightness - paper) ? candidate : best,
            root.palette[0]);
        root.inkWidth = Math.max(1, root.opts?.width ?? 4);
    }

    function addStroke(stroke): void {
        root.strokes = root.strokes.concat([stroke]);
        // A new stroke ends the redo line, the way it does in every editor: the future you
        // undid is not the future you are in any more.
        root.undone = [];
    }

    function undo(): void {
        if (root.strokes.length === 0)
            return;
        root.undone = root.undone.concat([root.strokes[root.strokes.length - 1]]);
        root.strokes = root.strokes.slice(0, -1);
    }

    function redo(): void {
        if (root.undone.length === 0)
            return;
        root.strokes = root.strokes.concat([root.undone[root.undone.length - 1]]);
        root.undone = root.undone.slice(0, -1);
    }

    function eraseAt(x, y, radius): void {
        const kept = root.strokes.filter(stroke => !StrokeGeometry.strokeHitBy(stroke, x, y, radius));
        if (kept.length !== root.strokes.length) {
            root.strokes = kept;
            root.undone = [];
        }
    }

    function clearAll(): void {
        root.strokes = [];
        root.undone = [];
    }

    // ── Loading what is already there ─────────────────────────────────────

    Component.onCompleted: {
        root.reset();
        if (root.strokesName.length > 0)
            NotesService.readStrokes(root.noteId, root.strokesName);
    }

    Connections {
        target: NotesService
        function onAssetRead(noteId, name, contents) {
            if (noteId !== root.noteId || name !== root.strokesName)
                return;
            if (contents === null)
                return;
            root.strokes = Array.from(contents.strokes ?? []);
            root.strokesLoaded = true;
        }
        function onAssetsReady(noteId) {
            if (noteId === root.noteId && root.saving)
                root.writeImage();
        }
    }

    // ── Saving ────────────────────────────────────────────────────────────

    /**
     * True for the one frame the picture is captured in.
     *
     * The saved file has to be **ink on transparency**, not ink on a slab. The tablet's
     * own live draw has always saved that way, which is why the migrated sketches have an
     * alpha channel and sit on whatever is behind them — and why baking this sheet's
     * surface into the file put every drawing in a black box. So the sheet's fill and its
     * paper are taken away for the grab and put back immediately afterwards.
     */
    property bool grabbing: false

    property bool saving: false
    property string statusText: ""
    property string pendingImage: ""
    property string pendingStrokes: ""

    function save(): void {
        if (root.saving)
            return;
        root.saving = true;
        root.statusText = Translation.tr("Saving…");
        root.pendingImage = NotesService.newInkAsset();
        root.pendingStrokes = NotesService.newStrokesName();
        // The folder first, and only when it answers. Writing the grab to a path inside a
        // folder that a fired-and-forgotten mkdir had not created yet is a race whose
        // loser is the drawing.
        NotesService.prepareAssets(root.noteId);
    }

    /**
     * Grabs the sheet — paper, whatever picture was already there, and the new strokes —
     * as one image.
     *
     * The whole sheet rather than the ink alone, because the previous drawing may be a
     * file underneath rather than strokes that could be repainted, and because the paper
     * is part of what the note looks like.
     *
     * `grabToImage` and `result.saveToFile`, never `Canvas.save`: that resolves its
     * filename against the component's base URL, and under Quickshell every base URL is a
     * `qs:` URL, so it fails with "no file name specified" for a perfectly valid absolute
     * path.
     */
    function writeImage(): void {
        // One frame with the surface hidden, then the capture. Setting the flag and
        // grabbing in the same turn would capture the frame that is already on screen.
        root.grabbing = true;
        grabTimer.restart();
    }

    Timer {
        id: grabTimer
        interval: 32
        onTriggered: root.captureImage()
    }

    function captureImage(): void {
        const path = NotesService.assetPath(root.noteId, root.pendingImage);
        const grabbed = sheet.grabToImage(result => {
            root.grabbing = false;
            if (!result.saveToFile(`file://${path}`)) {
                root.saving = false;
                root.statusText = Translation.tr("Could not write the drawing.");
                return;
            }
            NotesService.writeStrokes(root.noteId, root.pendingStrokes, root.strokes);
            root.editor.apply([{
                op: "update",
                id: root.block.id,
                patch: {
                    asset: root.pendingImage,
                    strokes: root.pendingStrokes,
                    aspect: sheet.width / Math.max(1, sheet.height)
                }
            }]);
            root.saving = false;
            root.statusText = "";
            root.finished();
        });
        if (!grabbed) {
            root.grabbing = false;
            root.saving = false;
            root.statusText = Translation.tr("Could not write the drawing.");
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Item {
            id: sheetArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            /// The paper's shape follows the drawing already in the note, so a second edit
            /// lands exactly on the first. A note with no drawing yet gets 3:2, which is a
            /// page rather than whatever shape the window happens to be.
            readonly property real sheetAspect: {
                if (root.block && root.block.aspect > 0)
                    return root.block.aspect;
                const w = backgroundImage.implicitWidth;
                const h = backgroundImage.implicitHeight;
                if (backgroundImage.status === Image.Ready && w > 0 && h > 0)
                    return w / h;
                return 1.5;
            }

            readonly property real fitWidth: Math.min(sheetArea.width, sheetArea.height * sheetArea.sheetAspect)

            Rectangle {
                id: sheet
                x: (sheetArea.width - width) / 2 + pan.x
                y: (sheetArea.height - height) / 2 + pan.y
                width: sheetArea.fitWidth * zoom.factor
                height: width / sheetArea.sheetAspect
                radius: Appearance.rounding.small
                // The surface the reading pane uses, so what you draw on is what you will
                // see the drawing on afterwards. It is *not* baked into the saved file —
                // see `grabbing` below.
                color: root.grabbing ? "transparent" : Appearance.m3colors.m3surfaceContainerHigh
                clip: true

                NotesPaper {
                    anchors.fill: parent
                    paperStyle: root.block && root.block.paper !== undefined ? root.block.paper : "grid"
                    paperSpacing: 26 * zoom.factor
                    paperStrength: 0.45
                    // Out of the way for the capture. A grid baked into the file would
                    // follow the drawing everywhere, including onto a note whose own page
                    // is plain.
                    visible: !root.grabbing && paperStyle !== "plain"
                }

                Image {
                    id: backgroundImage
                    anchors.fill: parent
                    source: root.paintingOverImage ? `file://${root.existingImage}` : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: root.paintingOverImage
                }

                DrawSurface {
                    id: ink
                    anchors.fill: parent
                    strokes: root.strokes
                    // Always drawing: a sketch surface has nothing else to be, which is
                    // why it has no pencil toggle either.
                    drawing: true
                    color: root.inkColor
                    strokeWidth: root.tool === "marker" ? root.inkWidth * 2.5 : root.inkWidth
                    usePressure: root.usePressure
                    smoothing: root.smoothing
                    eraser: root.tool === "eraser"
                    excludeItem: tray

                    onStrokeFinished: stroke => root.addStroke(stroke)
                    onEraseRequested: (x, y) => root.eraseAt(x, y, ink.eraserRadius)
                }
            }

            /// Zoom and pan, for drawing detail. Ctrl and the wheel rather than the wheel
            /// alone: the wheel on its own belongs to the note this sheet is inside.
            QtObject {
                id: zoom
                property real factor: 1
            }

            QtObject {
                id: pan
                property real x: 0
                property real y: 0
            }

            WheelHandler {
                acceptedModifiers: Qt.ControlModifier
                onWheel: event => {
                    const next = zoom.factor * (event.angleDelta.y > 0 ? 1.12 : 1 / 1.12);
                    zoom.factor = Math.max(1, Math.min(6, next));
                    if (zoom.factor === 1) {
                        pan.x = 0;
                        pan.y = 0;
                    }
                }
            }

            // Panning is the middle button, so a left drag is always ink. A zoomed sheet
            // that moved when you tried to draw on it would be unusable.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
                enabled: zoom.factor > 1

                property point origin: Qt.point(0, 0)

                onPressed: mouse => origin = Qt.point(mouse.x - pan.x, mouse.y - pan.y)
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    pan.x = mouse.x - origin.x;
                    pan.y = mouse.y - origin.y;
                }
            }
        }

        NotesInkToolbar {
            id: tray
            Layout.alignment: Qt.AlignHCenter
            palette: root.palette
            currentColor: root.inkColor
            strokeWidth: root.inkWidth
            tool: root.tool
            usePressure: root.usePressure
            pressureAvailable: ink.penSeen
            canUndo: root.strokes.length > 0
            canRedo: root.undone.length > 0
            statusText: root.statusText

            onColorPicked: colour => {
                root.inkColor = colour;
                if (root.tool === "eraser")
                    root.tool = "pen";
            }
            onWidthPicked: width => root.inkWidth = width
            onToolPicked: tool => root.tool = tool
            onPressureToggled: {
                if (Config.ready)
                    Config.options.tablet.liveDraw.pressure = !Config.options.tablet.liveDraw.pressure;
            }
            onUndoRequested: root.undo()
            onRedoRequested: root.redo()
            onClearRequested: root.clearAll()
            onCancelRequested: root.finished()
            onSaveRequested: root.save()
        }
    }
}
