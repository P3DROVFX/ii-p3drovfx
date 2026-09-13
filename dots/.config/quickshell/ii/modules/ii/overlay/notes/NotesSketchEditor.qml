pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.draw
import qs.modules.common.widgets
import "../../../common/draw/StrokeGeometry.js" as StrokeGeometry

/**
 * Drawing inside a note.
 *
 * Notes could already *hold* a drawing — the tablet's live-draw sheet saves into one —
 * but the only way to make one was to draw on the whole screen first and file it
 * afterwards. This is the other direction: open a note, draw in it, close it.
 *
 * A sheet rather than the whole panel. The note is a document, and a document has edges;
 * drawing to the panel's edges would mean the saved picture changed shape with the
 * window, and a note reopened at a different size would letterbox its own drawing. So the
 * sheet keeps a fixed aspect — the existing drawing's, when there is one, so a second
 * edit lands exactly on the first.
 */
Item {
    id: root

    /// Absolute path of the drawing already attached to this note, or "".
    property string existingSketch: ""

    signal saved(string path)
    signal cancelled()

    readonly property bool busy: root.pendingPath.length > 0
    property string pendingPath: ""
    property string statusText: ""

    // ── The strokes, which the editor owns until it is saved ────────────────
    property var strokes: []
    readonly property bool hasInk: root.strokes.length > 0
        || root.existingSketch.length > 0

    property string inkColor: ""
    property real inkWidth: 0
    property bool eraser: false

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

    function reset() {
        root.strokes = [];
        root.pendingPath = "";
        root.statusText = "";
        root.eraser = false;
        // The darkest ink in the palette, rather than its first entry.
        //
        // Live draw starts on white because it draws over a wallpaper; a note is a light
        // sheet, and starting there with white ink would look exactly like a pen that
        // does not work. Measured rather than hard-coded to a hex, so a palette somebody
        // edited still opens with something you can see.
        root.inkColor = root.palette.reduce((darkest, candidate) =>
            Qt.color(candidate).hslLightness < Qt.color(darkest).hslLightness
                ? candidate : darkest, root.palette[0]);
        root.inkWidth = Math.max(1, root.opts?.width ?? 4);
    }

    Component.onCompleted: root.reset()

    function addStroke(stroke) {
        root.strokes = root.strokes.concat([stroke]);
    }

    function undo() {
        if (root.strokes.length === 0)
            return;
        root.strokes = root.strokes.slice(0, root.strokes.length - 1);
    }

    function eraseAt(x, y, radius) {
        const kept = root.strokes.filter(stroke => !StrokeGeometry.strokeHitBy(stroke, x, y, radius));
        if (kept.length !== root.strokes.length)
            root.strokes = kept;
    }

    function clearAll() {
        root.strokes = [];
    }

    // ── Saving ──────────────────────────────────────────────────────────────
    /**
     * Grabs the sheet — paper, the drawing that was already there, and the new strokes —
     * as one image.
     *
     * The whole sheet rather than the canvas alone, because an edit continues the
     * previous drawing rather than replacing it, and the previous drawing is a file
     * underneath rather than strokes we could re-paint.
     */
    function save() {
        if (root.busy)
            return;
        NotesService.ensureSketchDir();
        const path = NotesService.newSketchPath();
        root.pendingPath = path;
        root.statusText = Translation.tr("Saving…");
        const grabbed = sheet.grabToImage(result => {
            const ok = result.saveToFile(`file://${path}`);
            root.pendingPath = "";
            if (ok) {
                root.saved(path);
            } else {
                root.statusText = Translation.tr("Could not write the drawing.");
            }
        });
        if (!grabbed) {
            root.pendingPath = "";
            root.statusText = Translation.tr("Could not write the drawing.");
        }
    }

    // ── Layout ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.normal
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Item {
            id: sheetArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            /**
             * The paper.
             *
             * Its aspect follows the drawing already in the note, so a second edit lands
             * exactly on the first instead of letterboxing it. A note with no drawing yet
             * gets 3:2, which is a page rather than whatever shape the window happens to
             * be.
             */
            readonly property real sheetAspect: {
                const w = backgroundImage.implicitWidth;
                const h = backgroundImage.implicitHeight;
                if (backgroundImage.status === Image.Ready && w > 0 && h > 0)
                    return w / h;
                return 1.5;
            }

            Rectangle {
                id: sheet
                anchors.centerIn: parent
                width: Math.min(sheetArea.width, sheetArea.height * sheetArea.sheetAspect)
                height: Math.min(sheetArea.height, sheetArea.width / sheetArea.sheetAspect)
                radius: Appearance.rounding.small
                // Opaque, and not a theme layer that might be translucent: this rectangle
                // is what the saved PNG is painted on, and a note whose drawing came out
                // half-transparent would look broken everywhere it was shown.
                color: Appearance.m3colors.m3surfaceContainerLowest
                clip: true

                Image {
                    id: backgroundImage
                    anchors.fill: parent
                    source: root.existingSketch.length > 0 ? `file://${root.existingSketch}` : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: root.existingSketch.length > 0
                }

                DrawSurface {
                    id: ink
                    anchors.fill: parent
                    strokes: root.strokes
                    // Always drawing: a sketch editor has nothing else to be, which is
                    // why it has no pencil toggle either.
                    drawing: true
                    color: root.inkColor
                    strokeWidth: root.inkWidth
                    usePressure: root.usePressure
                    smoothing: root.smoothing
                    eraser: root.eraser

                    onStrokeFinished: stroke => root.addStroke(stroke)
                    onEraseRequested: (x, y) => root.eraseAt(x, y, ink.eraserRadius)
                }
            }
        }

        DrawToolbar {
            Layout.alignment: Qt.AlignHCenter
            palette: root.palette
            currentColor: root.inkColor
            strokeWidth: root.inkWidth
            eraser: root.eraser
            usePressure: root.usePressure
            pressureAvailable: ink.penSeen
            canUndo: root.strokes.length > 0
            statusText: root.statusText

            onColorPicked: colorValue => {
                root.inkColor = colorValue;
                root.eraser = false;
            }
            onWidthPicked: widthValue => root.inkWidth = widthValue
            onEraserToggled: root.eraser = !root.eraser
            onPressureToggled: {
                if (Config.ready)
                    Config.options.tablet.liveDraw.pressure = !Config.options.tablet.liveDraw.pressure;
            }
            onUndoRequested: root.undo()
            onClearRequested: root.clearAll()

            trailingContent: [
                DrawToolButton {
                    symbol: "close"
                    tooltipText: Translation.tr("Discard this drawing")
                    onTriggered: root.cancelled()
                },
                DrawToolButton {
                    symbol: "check"
                    emphasised: true
                    enabled: root.hasInk && !root.busy
                    tooltipText: Translation.tr("Keep it in this note")
                    onTriggered: root.save()
                }
            ]
        }
    }
}
