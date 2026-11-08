pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.health.components
import qs.services

/**
 * The Dev tools page's Photo Compressor workspace (DevToolsRegistry
 * "image_compress", a page-only tool: Search never offers it).
 *
 * A photo comes from the picker, a drop anywhere on the workspace or a path
 * on the clipboard. Every change of format, quality, scale or metadata
 * re-encodes it into a cache file (scripts/images/compress_image.py,
 * debounced, stale runs killed), so the size shown before saving is the real
 * one, and saving copies that same file. The preview compares the original
 * and the encoded result side by side across a draggable divider.
 *
 * The encoder streams its stages (read, prepare, encode); the bar jumps to
 * each and, through the encode stage, crawls toward 95% over the time the
 * last run of that format took per megapixel. A snackbar reports what
 * finished: a save (with "Show"), an encode the user had to wait for, and
 * every failure.
 *
 * The hero of CheatsheetDevTools reads hasImage/busy/originalSize/
 * estimatedSize and calls pick()/save()/copy()/clear()/pasteFromClipboard().
 */
Item {
    id: root

    property string sourcePath: ""
    property bool compact: false
    signal notice(string message)

    readonly property bool hasImage: root.sourcePath.length > 0 && root.info !== null
    readonly property bool busy: encodeProc.running || debounce.running || infoProc.running
    readonly property real originalSize: root.info?.size ?? 0
    readonly property real estimatedSize: root.result?.size ?? 0
    readonly property bool resultReady: root.result !== null && !root.busy && root.errorText.length === 0

    property var info: null
    property var result: null
    property string errorText: ""
    property string previewPath: ""
    property string outputDir: ""
    property string lastSavedPath: ""

    property string format: Persistent.states.cheatsheet.devToolsImageFormat ?? "keep"
    property int quality: Persistent.states.cheatsheet.devToolsImageQuality ?? 80
    property int scale: Persistent.states.cheatsheet.devToolsImageScale ?? 100
    property bool keepMetadata: Persistent.states.cheatsheet.devToolsImageKeepMetadata ?? false

    // Progress of the current encode, 0..1, and its stage name.
    property real progress: 0
    property string stage: ""
    readonly property string stageLabel: root.stage === "read" ? Translation.tr("Reading the photo")
        : root.stage === "prepare" ? Translation.tr("Preparing")
        : root.stage === "encode" ? Translation.tr("Encoding %1").arg(root.formatLabel(root.effectiveFormat))
        : root.stage === "info" ? Translation.tr("Opening")
        : Translation.tr("Waiting")
    readonly property string progressText: `${root.stageLabel}… ${Math.round(root.progress * 100)}%`
    /// Learned encode cost per megapixel, ms, by format; seeded with this
    /// machine's measurements on a 30 MP photo.
    property var msPerMegapixel: ({ jpeg: 20, webp: 80, avif: 190, jxl: 100, png: 230, gif: 30, jp2: 190, tiff: 40, bmp: 10, qoi: 80 })
    property real encodeStartedAt: 0

    property real split: 0.5
    property bool actualSize: false

    readonly property string scriptPath: `${Directories.scriptPath}/images/compress_image.py`
    readonly property string cacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/devtools/photo-compressor`)

    readonly property var formats: [
        { id: "keep", label: Translation.tr("Original") },
        { id: "jpeg", label: "JPEG" },
        { id: "webp", label: "WebP" },
        { id: "avif", label: "AVIF" },
        { id: "jxl", label: "JPEG XL" },
        { id: "png", label: "PNG" },
        { id: "gif", label: "GIF" },
        { id: "jp2", label: "JPEG 2000" },
        { id: "tiff", label: "TIFF" },
        { id: "bmp", label: "BMP" },
        { id: "qoi", label: "QOI" }
    ]
    readonly property var extensions: ({ jpeg: "jpg", webp: "webp", avif: "avif", jxl: "jxl", png: "png", gif: "gif", jp2: "jp2", tiff: "tif", bmp: "bmp", qoi: "qoi" })
    readonly property var mimeTypes: ({ jpeg: "image/jpeg", webp: "image/webp", avif: "image/avif", jxl: "image/jxl", png: "image/png", gif: "image/gif", jp2: "image/jp2", tiff: "image/tiff", bmp: "image/bmp", qoi: "image/qoi" })
    readonly property var imagePattern: /\.(png|jpe?g|jfif|webp|gif|bmp|avif|heic|heif|jxl|tiff?|qoi|jp2|j2k|tga)$/i

    readonly property string effectiveFormat: root.format !== "keep" ? root.format : root.keepFormat
    /// The encoder the "Original" chip stands for.
    readonly property string keepFormat: {
        const fmt = String(root.info?.format ?? "").toLowerCase();
        const ext = root.sourcePath.split(".").pop().toLowerCase();
        const map = { jpeg: "jpeg", mpo: "jpeg", png: "png", webp: "webp", gif: "gif", tiff: "tiff", bmp: "bmp", qoi: "qoi", jpeg2000: "jp2" };
        if (map[fmt])
            return map[fmt];
        if (ext === "avif" || ext === "jxl")
            return ext;
        return "jpeg";
    }
    readonly property bool losslessFormat: ["tiff", "bmp", "qoi"].indexOf(root.effectiveFormat) !== -1
    readonly property bool paletteFormat: root.effectiveFormat === "png" || root.effectiveFormat === "gif"
    readonly property string extension: root.extensions[root.effectiveFormat] ?? "img"
    readonly property string sourceDir: root.sourcePath.substring(0, root.sourcePath.lastIndexOf("/"))
    readonly property string sourceStem: {
        const name = root.sourcePath.substring(root.sourcePath.lastIndexOf("/") + 1);
        const dot = name.lastIndexOf(".");
        return dot > 0 ? name.substring(0, dot) : name;
    }
    readonly property string targetDir: root.outputDir.length > 0 ? root.outputDir : root.sourceDir
    readonly property string targetName: `${root.sourceStem}-compressed.${root.extension}`

    readonly property real savedFraction: root.originalSize > 0 && root.estimatedSize > 0
        ? 1 - root.estimatedSize / root.originalSize : 0

    function formatBytes(bytes) {
        const value = Number(bytes ?? 0);
        if (value <= 0)
            return "—";
        const units = ["B", "KB", "MB", "GB"];
        let size = value;
        let unit = 0;
        while (size >= 1024 && unit < units.length - 1) {
            size /= 1024;
            unit++;
        }
        return `${size >= 100 || unit === 0 ? Math.round(size) : size.toFixed(1)} ${units[unit]}`;
    }

    function formatLabel(id) {
        return String(root.formats.find(f => f.id === id)?.label ?? id);
    }

    function warn(message) {
        snackbar.show(message, "", null, true);
        root.notice(message);
    }

    function megapixels() {
        const s = root.scale / 100;
        return Math.max(0.05, (root.info?.width ?? 0) * (root.info?.height ?? 0) * s * s / 1e6);
    }

    function setProgress(value, stageName) {
        crawl.stop();
        root.stage = stageName;
        root.progress = value;
        if (stageName === "encode") {
            root.encodeStartedAt = Date.now();
            crawl.from = value;
            crawl.duration = Math.max(300, (root.msPerMegapixel[root.effectiveFormat] ?? 100) * root.megapixels());
            crawl.start();
        }
    }

    function savingsLabel() {
        if (root.estimatedSize <= 0 || root.originalSize <= 0)
            return "—";
        const percent = Math.round(Math.abs(root.savedFraction) * 100);
        return root.savedFraction >= 0 ? `−${percent}%` : `+${percent}%`;
    }

    function qualityCaption() {
        if (root.losslessFormat)
            return Translation.tr("Lossless format: the slider does not apply");
        if (root.paletteFormat)
            return root.quality >= 100
                ? Translation.tr("100% keeps it lossless")
                : Translation.tr("≈ %1 colours").arg(String(Math.max(2, Math.min(256, Math.round(256 * Math.pow(root.quality / 100, 2))))));
        if (root.effectiveFormat === "avif" || root.effectiveFormat === "jp2")
            return Translation.tr("Slower encoder: the estimate takes a moment");
        return Translation.tr("Higher keeps more detail");
    }

    function pathFromUrl(value) {
        let text = String(value ?? "").trim();
        if (text.startsWith("file://"))
            text = decodeURIComponent(text.substring(7));
        return text;
    }

    function load(path) {
        const clean = root.pathFromUrl(path);
        if (!clean.startsWith("/") || !root.imagePattern.test(clean)) {
            root.warn(Translation.tr("Not an image file: %1").arg(clean.substring(clean.lastIndexOf("/") + 1)));
            return false;
        }
        root.sourcePath = clean;
        return true;
    }

    function pick() {
        if (!pickProc.running)
            pickProc.running = true;
    }

    function pickFolder() {
        if (!folderProc.running)
            folderProc.running = true;
    }

    function pasteFromClipboard() {
        const lines = String(Quickshell.clipboardText ?? "").split("\n").map(line => line.trim()).filter(line => line.length > 0);
        if (lines.length === 0 || !root.load(lines[0]))
            root.warn(Translation.tr("The clipboard holds no image path"));
    }

    function clear() {
        encodeProc.running = false;
        root.sourcePath = "";
    }

    function save() {
        if (!root.resultReady || saveProc.running)
            return false;
        saveProc.command = ["bash", "-c",
            'mkdir -p -- "$2" || exit 1; n="$2/$3.$4"; i=1; while [ -e "$n" ]; do n="$2/$3-$i.$4"; i=$((i+1)); done; cp -- "$1" "$n" && printf %s "$n"',
            "save", root.previewPath, root.targetDir, `${root.sourceStem}-compressed`, root.extension];
        saveProc.running = true;
        return true;
    }

    function copy() {
        if (!root.resultReady)
            return false;
        Quickshell.execDetached(["bash", "-c", 'wl-copy --type "$1" < "$2"', "copy", root.mimeTypes[root.effectiveFormat] ?? "image/png", root.previewPath]);
        snackbar.show(Translation.tr("Compressed image copied to the clipboard"), "", null, false);
        root.notice(Translation.tr("Compressed image copied to the clipboard"));
        return true;
    }

    function setFormat(value) {
        root.format = value;
        if (Persistent.ready)
            Persistent.states.cheatsheet.devToolsImageFormat = value;
        root.requestEncode();
    }

    function setQuality(value) {
        const next = Math.max(1, Math.min(100, Math.round(value)));
        if (next === root.quality)
            return;
        root.quality = next;
        qualitySlider.value = next;
        if (Persistent.ready)
            Persistent.states.cheatsheet.devToolsImageQuality = next;
        root.requestEncode();
    }

    function setScale(value) {
        root.scale = value;
        if (Persistent.ready)
            Persistent.states.cheatsheet.devToolsImageScale = value;
        root.requestEncode();
    }

    function setKeepMetadata(value) {
        root.keepMetadata = value;
        if (Persistent.ready)
            Persistent.states.cheatsheet.devToolsImageKeepMetadata = value;
        root.requestEncode();
    }

    // ── Encoding: debounced, one run at a time, stale runs restarted ─────
    property int requestSeq: 0
    property int runningSeq: -1
    property int slot: 0

    function requestEncode() {
        if (!root.hasImage)
            return;
        root.requestSeq++;
        root.setProgress(0, "");
        debounce.restart();
    }

    function startEncode() {
        if (!root.hasImage)
            return;
        if (encodeProc.running) {
            // onExited sees the stale run and starts the fresh one.
            encodeProc.running = false;
            return;
        }
        root.slot = 1 - root.slot;
        const target = `${root.cacheDir}/preview-${root.slot}.${root.extension}`;
        const args = ["python3", root.scriptPath, "encode", root.sourcePath, target,
            "--format", root.effectiveFormat, "--quality", String(root.quality), "--scale", String(root.scale)];
        if (root.keepMetadata)
            args.push("--keep-metadata");
        encodeProc.target = target;
        encodeProc.gotResult = false;
        encodeProc.command = args;
        root.setProgress(0.02, "read");
        root.runningSeq = root.requestSeq;
        encodeProc.running = true;
    }

    onSourcePathChanged: {
        encodeProc.running = false;
        root.info = null;
        root.result = null;
        root.errorText = "";
        root.previewPath = "";
        root.lastSavedPath = "";
        root.split = 0.5;
        root.setProgress(0, "");
        if (root.sourcePath.length === 0)
            return;
        root.setProgress(0.02, "info");
        infoProc.command = ["python3", root.scriptPath, "info", root.sourcePath];
        infoProc.running = true;
    }

    Component.onCompleted: {
        if (root.sourcePath.length > 0 && root.info === null && !infoProc.running) {
            infoProc.command = ["python3", root.scriptPath, "info", root.sourcePath];
            infoProc.running = true;
        }
    }
    Component.onDestruction: Quickshell.execDetached(["rm", "-rf", "--", root.cacheDir])

    // Through the encode stage nothing reports in; ease toward 95% over the
    // learned duration so the bar keeps moving without ever claiming done.
    // Steps, not a per-frame animation: StyledProgressBar's 400 ms Behavior
    // restarted every frame and the bar crawled far behind the percentage.
    Timer {
        id: crawl
        property real duration: 1000
        property real from: 0.4
        interval: 450
        repeat: true
        onTriggered: {
            const t = Math.min(1, (Date.now() - root.encodeStartedAt) / crawl.duration);
            root.progress = crawl.from + (0.95 - crawl.from) * (1 - Math.pow(1 - t, 3));
        }
    }

    Timer {
        id: debounce
        interval: 280
        onTriggered: root.startEncode()
    }

    Process {
        id: infoProc
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text.trim());
                } catch (error) {
                    parsed = { ok: false, error: Translation.tr("Could not read this image") };
                }
                if (!parsed.ok) {
                    const reason = String(parsed.error ?? "");
                    root.sourcePath = "";
                    root.warn(Translation.tr("Could not open the image: %1").arg(reason));
                    return;
                }
                root.info = parsed;
                root.requestEncode();
            }
        }
    }

    Process {
        id: encodeProc
        property string target: ""
        property bool gotResult: false
        // One JSON object per line: stages first, the result last.
        stdout: SplitParser {
            onRead: line => {
                if (root.runningSeq !== root.requestSeq)
                    return;
                let parsed = null;
                try {
                    parsed = JSON.parse(String(line).trim());
                } catch (error) {
                    return;
                }
                if (parsed.progress !== undefined) {
                    root.setProgress(Number(parsed.progress), String(parsed.stage ?? ""));
                    return;
                }
                encodeProc.gotResult = true;
                if (parsed.ok) {
                    const elapsed = Date.now() - root.encodeStartedAt;
                    if (root.encodeStartedAt > 0 && elapsed > 0) {
                        const learned = Object.assign({}, root.msPerMegapixel);
                        learned[root.effectiveFormat] = elapsed / root.megapixels();
                        root.msPerMegapixel = learned;
                    }
                    root.setProgress(1, "done");
                    root.result = parsed;
                    root.errorText = "";
                    root.previewPath = encodeProc.target;
                    // Only when the wait was felt: slider steps would flood it.
                    if (elapsed >= 1500)
                        snackbar.show(Translation.tr("Ready: %1 · %2 (%3)").arg(root.formatLabel(root.effectiveFormat)).arg(root.formatBytes(parsed.size)).arg(root.savingsLabel()), "", null, false);
                } else {
                    root.setProgress(0, "");
                    root.result = null;
                    root.errorText = String(parsed.error ?? Translation.tr("Encoding failed"));
                    root.warn(Translation.tr("%1 encoding failed: %2").arg(root.formatLabel(root.effectiveFormat)).arg(root.errorText));
                }
            }
        }
        stderr: StdioCollector {
            id: encodeErr
        }
        onExited: (exitCode, exitStatus) => {
            if (root.runningSeq !== root.requestSeq) {
                if (!debounce.running)
                    Qt.callLater(root.startEncode);
                return;
            }
            // Died without a result line (crash, OOM kill): still say so.
            if (!encodeProc.gotResult) {
                root.setProgress(0, "");
                root.result = null;
                const tail = String(encodeErr.text ?? "").trim().split("\n").pop();
                root.errorText = tail.length > 0 ? tail : Translation.tr("The encoder stopped (exit code %1)").arg(String(exitCode));
                root.warn(Translation.tr("%1 encoding failed: %2").arg(root.formatLabel(root.effectiveFormat)).arg(root.errorText));
            }
        }
    }

    Process {
        id: pickProc
        command: ["python3", `${Directories.scriptPath}/image_picker.py`,
            "--title", Translation.tr("Choose a photo to compress"),
            "--folder", root.sourceDir.length > 0 ? root.sourceDir : FileUtils.trimFileProtocol(Directories.pictures),
            "--filters", JSON.stringify([Translation.tr("Images") + " (*.jpg *.jpeg *.jfif *.png *.webp *.avif *.heic *.heif *.jxl *.gif *.bmp *.tif *.tiff *.qoi *.jp2 *.tga)"])]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                try {
                    root.load(JSON.parse(text.trim()));
                } catch (error) {}
            }
        }
    }

    Process {
        id: folderProc
        command: ["python3", `${Directories.scriptPath}/image_picker.py`, "--directory",
            "--title", Translation.tr("Save compressed photos to"),
            "--folder", root.targetDir]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                try {
                    root.outputDir = root.pathFromUrl(JSON.parse(text.trim()));
                } catch (error) {}
            }
        }
    }

    Process {
        id: saveProc
        stdout: StdioCollector {
            id: saveOut
        }
        stderr: StdioCollector {
            id: saveErr
        }
        onExited: (exitCode, exitStatus) => {
            const saved = String(saveOut.text ?? "").trim();
            if (exitCode !== 0 || saved.length === 0) {
                const reason = String(saveErr.text ?? "").trim().split("\n").pop();
                root.warn(Translation.tr("Could not save the image: %1").arg(reason.length > 0 ? reason : Translation.tr("exit code %1").arg(String(exitCode))));
                return;
            }
            root.lastSavedPath = saved;
            const message = Translation.tr("Saved %1 · %2").arg(saved.substring(saved.lastIndexOf("/") + 1)).arg(root.formatBytes(root.estimatedSize));
            snackbar.show(message, Translation.tr("Show"), () => Quickshell.execDetached(["xdg-open", saved.substring(0, saved.lastIndexOf("/"))]), false);
            root.notice(message);
        }
    }

    // Drops land anywhere on the workspace, not only on the empty state.
    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: dragEvent => {
            const urls = Array.from(dragEvent.urls ?? []);
            if (urls.length > 0 && !urls.some(url => root.imagePattern.test(root.pathFromUrl(url))))
                dragEvent.accepted = false;
        }
        onDropped: dropEvent => {
            const path = Array.from(dropEvent.urls ?? []).map(url => root.pathFromUrl(url)).find(p => root.imagePattern.test(p));
            if (!path) {
                dropEvent.accepted = false;
                return;
            }
            root.load(path);
            dropEvent.acceptProposedAction();
        }
    }

    component SectionLabel: StyledText {
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    GridLayout {
        anchors.fill: parent
        columns: root.compact ? 1 : 2
        columnSpacing: ClockStyle.paneGap
        rowSpacing: ClockStyle.paneGap

        // ── Preview: drop zone, then original | compressed ──────────────
        Rectangle {
            id: previewPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.compact ? 120 : 200
            Layout.verticalStretchFactor: 3
            radius: ClockStyle.radiusCard
            color: drop.containsDrag ? ClockStyle.colPrimaryContainer : ClockStyle.colPane
            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            // A slim bar along the top edge, so the progress is visible even
            // with the settings pane scrolled away (stacked layout).
            StyledProgressBar {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 4
                anchors.leftMargin: ClockStyle.radiusCard
                anchors.rightMargin: ClockStyle.radiusCard
                z: 4
                visible: root.busy && root.sourcePath.length > 0
                valueBarHeight: 3
                value: root.progress
            }

            // What finished, or failed: above the zoom chips.
            HealthSnackbar {
                id: snackbar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: ClockStyle.gapLarge
                anchors.bottomMargin: root.hasImage ? ClockStyle.gapLarge + 48 : ClockStyle.gapLarge
                z: 6
            }

            // Empty: the whole pane is the picker.
            MouseArea {
                anchors.fill: parent
                visible: !root.hasImage
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pick()
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - ClockStyle.gapHuge * 2, 420)
                visible: !root.hasImage
                spacing: ClockStyle.gap

                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: infoProc.running ? "hourglass_top" : drop.containsDrag ? "download" : "add_photo_alternate"
                    title: infoProc.running ? Translation.tr("Reading the photo…")
                        : drop.containsDrag ? Translation.tr("Drop to compress")
                        : Translation.tr("Drop a photo here or click to choose")
                    subtitle: Translation.tr("JPEG, PNG, WebP, AVIF, HEIC, JPEG XL, GIF, TIFF… · Ctrl+O to browse, Ctrl+Shift+V for a copied path")
                    shape: "Cookie9Sided"
                }
            }

            Item {
                id: viewport
                anchors.fill: parent
                anchors.margins: ClockStyle.gapLarge
                visible: root.hasImage
                clip: true

                readonly property real dpr: root.Window.window?.devicePixelRatio ?? 1
                readonly property size fitSize: Qt.size(Math.ceil(viewport.width * viewport.dpr), Math.ceil(viewport.height * viewport.dpr))

                Flickable {
                    id: flick
                    anchors.fill: parent
                    interactive: root.actualSize
                    contentWidth: root.actualSize ? (root.info?.width ?? 0) / viewport.dpr : width
                    contentHeight: root.actualSize ? (root.info?.height ?? 0) / viewport.dpr : height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Rectangle {
                        width: flick.contentWidth
                        height: flick.contentHeight
                        radius: root.actualSize ? 0 : ClockStyle.radiusLarge
                        color: ClockStyle.colField

                        Image {
                            id: originalImage
                            anchors.fill: parent
                            source: root.hasImage ? `file://${root.sourcePath}` : ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize: root.actualSize ? Qt.size(root.info?.width ?? 0, root.info?.height ?? 0) : viewport.fitSize
                            asynchronous: true
                            autoTransform: true
                            cache: false
                            smooth: !root.actualSize
                            mipmap: !root.actualSize
                        }

                        // The compressed half, cut at the divider in viewport space.
                        Item {
                            x: Math.max(0, Math.min(parent.width, root.split * flick.width + flick.contentX))
                            width: parent.width - x
                            height: parent.height
                            clip: true

                            Image {
                                id: compressedImage
                                x: -parent.x
                                width: originalImage.width
                                height: originalImage.height
                                source: root.previewPath.length > 0 ? `file://${root.previewPath}` : ""
                                fillMode: Image.PreserveAspectFit
                                sourceSize: root.actualSize ? Qt.size(root.info?.width ?? 0, root.info?.height ?? 0) : viewport.fitSize
                                asynchronous: true
                                cache: false
                                retainWhileLoading: true
                                smooth: !root.actualSize
                                mipmap: !root.actualSize
                            }
                        }
                    }

                    TouchpadScrollHandler {
                        flickable: flick
                    }
                }

                // Divider and its handle.
                Rectangle {
                    x: Math.round(root.split * viewport.width) - 1
                    width: 2
                    height: viewport.height
                    color: ClockStyle.colPrimary
                    visible: root.previewPath.length > 0
                }

                Rectangle {
                    id: handle
                    visible: root.previewPath.length > 0
                    width: 36
                    height: 36
                    radius: 18
                    x: root.split * viewport.width - width / 2
                    y: (viewport.height - height) / 2
                    color: dividerDrag.active || handleHover.hovered ? ClockStyle.colPrimaryHover : ClockStyle.colPrimary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "compare_arrows"
                        iconSize: ClockStyle.iconSmall + 2
                        color: ClockStyle.colOnPrimary
                    }

                    HoverHandler {
                        id: handleHover
                        cursorShape: Qt.SplitHCursor
                    }
                }

                // Grab the divider anywhere along its line, not only the knob.
                Item {
                    x: root.split * viewport.width - 14
                    width: 28
                    height: viewport.height
                    visible: root.previewPath.length > 0

                    HoverHandler {
                        cursorShape: Qt.SplitHCursor
                    }
                    DragHandler {
                        id: dividerDrag
                        target: null
                        xAxis.enabled: true
                        yAxis.enabled: false
                        property real startSplit: 0.5
                        onActiveChanged: if (active) startSplit = root.split
                        onTranslationChanged: root.split = Math.max(0, Math.min(1, startSplit + translation.x / Math.max(1, viewport.width)))
                    }
                }

                // Side captions.
                Row {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: ClockStyle.gapSmall

                    Rectangle {
                        implicitWidth: leftCaption.implicitWidth + ClockStyle.gapLarge
                        implicitHeight: leftCaption.implicitHeight + ClockStyle.gapSmall
                        radius: ClockStyle.radiusFull
                        color: ClockStyle.colSurfaceHighest
                        opacity: root.split > 0.12 ? 0.92 : 0
                        StyledText {
                            id: leftCaption
                            anchors.centerIn: parent
                            text: Translation.tr("Original · %1").arg(root.formatBytes(root.originalSize))
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                        }
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: ClockStyle.gapSmall
                    visible: root.previewPath.length > 0 || root.busy
                    implicitWidth: rightCaption.implicitWidth + ClockStyle.gapLarge
                    implicitHeight: rightCaption.implicitHeight + ClockStyle.gapSmall
                    radius: ClockStyle.radiusFull
                    color: ClockStyle.colPrimary
                    opacity: root.split < 0.88 ? 0.95 : 0
                    StyledText {
                        id: rightCaption
                        anchors.centerIn: parent
                        text: root.busy ? root.progressText
                            : Translation.tr("%1 · %2").arg((root.formats.find(f => f.id === root.effectiveFormat)?.label ?? "").toString()).arg(root.formatBytes(root.estimatedSize))
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnPrimary
                    }
                }

                // Zoom: fit or one image pixel per screen pixel.
                Row {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: ClockStyle.gapSmall
                    spacing: 6

                    ClockFormChip {
                        label: Translation.tr("Fit")
                        selected: !root.actualSize
                        onTriggered: root.actualSize = false
                    }
                    ClockFormChip {
                        label: "1:1"
                        selected: root.actualSize
                        onTriggered: {
                            root.actualSize = true;
                            Qt.callLater(() => {
                                flick.contentX = Math.max(0, (flick.contentWidth - flick.width) / 2);
                                flick.contentY = Math.max(0, (flick.contentHeight - flick.height) / 2);
                            });
                        }
                    }
                }
            }
        }

        // ── Settings: format, quality, size, metadata, destination ──────
        Rectangle {
            // Stacked, the two panes share the height 3:2 and the settings scroll.
            Layout.fillHeight: true
            Layout.fillWidth: root.compact
            Layout.preferredWidth: root.compact ? -1 : 340
            Layout.minimumHeight: 120
            Layout.verticalStretchFactor: 2
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            StyledFlickable {
                id: settingsFlick
                anchors.fill: parent
                anchors.margins: ClockStyle.gapLarge
                contentWidth: width
                contentHeight: settingsColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: settingsColumn
                    width: settingsFlick.width
                    spacing: ClockStyle.gap

                    // The estimate, first: it is what the controls below change.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: estimateColumn.implicitHeight + ClockStyle.gapLarge * 2
                        radius: ClockStyle.radiusLarge
                        color: root.errorText.length > 0 ? ClockStyle.colErrorContainer
                            : root.savedFraction < 0 ? ClockStyle.colTertiaryContainer
                            : ClockStyle.colSecondaryContainer
                        readonly property color fg: root.errorText.length > 0 ? ClockStyle.colOnErrorContainer
                            : root.savedFraction < 0 ? ClockStyle.colOnTertiaryContainer
                            : ClockStyle.colOnSecondaryContainer
                        id: estimateCard
                        Behavior on color {
                            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                        }

                        ColumnLayout {
                            id: estimateColumn
                            anchors.fill: parent
                            anchors.margins: ClockStyle.gapLarge
                            spacing: 2

                            SectionLabel {
                                text: Translation.tr("Size after saving")
                                color: estimateCard.fg
                                opacity: 0.85
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ClockStyle.gapSmall

                                StyledText {
                                    text: !root.hasImage ? "—"
                                        : root.errorText.length > 0 ? Translation.tr("Failed")
                                        : root.formatBytes(root.estimatedSize)
                                    font.family: ClockStyle.fontMain
                                    font.variableAxes: ClockStyle.axesDigitsBold
                                    font.pixelSize: 30
                                    color: estimateCard.fg
                                    opacity: root.busy ? 0.55 : 1
                                    Behavior on opacity {
                                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Rectangle {
                                    visible: root.hasImage && root.estimatedSize > 0 && root.errorText.length === 0
                                    implicitWidth: savingLabel.implicitWidth + ClockStyle.gapLarge
                                    implicitHeight: savingLabel.implicitHeight + ClockStyle.gapSmall
                                    radius: ClockStyle.radiusFull
                                    color: ColorUtils.applyAlpha(estimateCard.fg, 0.14)
                                    StyledText {
                                        id: savingLabel
                                        anchors.centerIn: parent
                                        text: root.savingsLabel()
                                        font.pixelSize: ClockStyle.textNormal
                                        font.weight: Font.Bold
                                        color: estimateCard.fg
                                    }
                                }
                            }

                            // Progress: the stage and its percentage over a wavy bar.
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                Layout.bottomMargin: 4
                                visible: root.busy && root.sourcePath.length > 0
                                spacing: 4

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.progressText
                                    font.pixelSize: ClockStyle.textSmall
                                    font.weight: Font.DemiBold
                                    color: estimateCard.fg
                                    elide: Text.ElideRight
                                }
                                StyledProgressBar {
                                    Layout.fillWidth: true
                                    valueBarHeight: 6
                                    value: root.progress
                                    wavy: true
                                    animateWave: parent.visible
                                    highlightColor: estimateCard.fg
                                    trackColor: ColorUtils.applyAlpha(estimateCard.fg, 0.2)
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: !(root.busy && root.sourcePath.length > 0)
                                wrapMode: Text.Wrap
                                font.pixelSize: ClockStyle.textSmall
                                color: estimateCard.fg
                                opacity: 0.85
                                text: {
                                    if (!root.hasImage || !root.info)
                                        return Translation.tr("Choose a photo to see the real encoded size");
                                    if (root.errorText.length > 0)
                                        return root.errorText;
                                    const from = Translation.tr("from %1 · %2×%3").arg(root.formatBytes(root.originalSize)).arg(String(root.info.width)).arg(String(root.info.height));
                                    if (!root.result)
                                        return from;
                                    const dims = root.result.width !== root.info.width || root.result.height !== root.info.height
                                        ? ` → ${root.result.width}×${root.result.height}` : "";
                                    const larger = root.savedFraction < 0 ? " · " + Translation.tr("larger than the original") : "";
                                    return from + dims + larger;
                                }
                            }
                        }
                    }

                    SectionLabel {
                        text: Translation.tr("Format")
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: root.formats
                            delegate: ClockFormChip {
                                required property var modelData
                                label: modelData.id === "keep" && root.hasImage
                                    ? Translation.tr("Original (%1)").arg((root.formats.find(f => f.id === root.keepFormat)?.label ?? "").toString())
                                    : modelData.label
                                selected: root.format === modelData.id
                                onTriggered: root.setFormat(modelData.id)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: ClockStyle.gapSmall
                        SectionLabel {
                            Layout.fillWidth: true
                            text: root.paletteFormat ? Translation.tr("Quality · colours") : Translation.tr("Quality")
                        }
                        StyledText {
                            text: root.losslessFormat ? "—" : `${Math.round(qualitySlider.value)}%`
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: 20
                            color: ClockStyle.colOnSurface
                        }
                    }
                    StyledSlider {
                        id: qualitySlider
                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.M
                        enabled: !root.losslessFormat
                        opacity: enabled ? 1 : 0.4
                        from: 1
                        to: 100
                        stepSize: 1
                        value: root.quality
                        usePercentTooltip: false
                        // Every step re-arms the encode debounce: it runs once the hand rests.
                        onMoved: root.setQuality(value)
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: !root.losslessFormat
                        Repeater {
                            model: [95, 80, 60, 40]
                            delegate: ClockFormChip {
                                required property int modelData
                                label: `${modelData}%`
                                selected: root.quality === modelData
                                onTriggered: root.setQuality(modelData)
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.qualityCaption()
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }

                    SectionLabel {
                        Layout.topMargin: ClockStyle.gapSmall
                        text: Translation.tr("Dimensions")
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [100, 75, 50, 25]
                            delegate: ClockFormChip {
                                required property int modelData
                                label: root.info && modelData < 100
                                    ? `${modelData}% · ${Math.round(root.info.width * modelData / 100)}px`
                                    : `${modelData}%`
                                selected: root.scale === modelData
                                onTriggered: root.setScale(modelData)
                            }
                        }
                    }

                    ClockFormChip {
                        Layout.topMargin: ClockStyle.gapSmall
                        label: Translation.tr("Keep EXIF metadata (camera, GPS)")
                        symbol: root.keepMetadata ? "check_box" : "check_box_outline_blank"
                        selected: root.keepMetadata
                        onTriggered: root.setKeepMetadata(!root.keepMetadata)
                    }

                    SectionLabel {
                        Layout.topMargin: ClockStyle.gapSmall
                        text: Translation.tr("Save to")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.hasImage ? `${root.targetDir}/${root.targetName}` : Translation.tr("Next to the original")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colOnSurfaceVariant
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 3
                        elide: Text.ElideMiddle
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        ClockFormChip {
                            label: Translation.tr("Change folder")
                            symbol: "folder_open"
                            onTriggered: root.pickFolder()
                        }
                        ClockFormChip {
                            visible: root.outputDir.length > 0
                            label: Translation.tr("Next to original")
                            symbol: "undo"
                            onTriggered: root.outputDir = ""
                        }
                        ClockFormChip {
                            visible: root.lastSavedPath.length > 0
                            label: Translation.tr("Show saved file")
                            symbol: "folder_special"
                            onTriggered: Quickshell.execDetached(["xdg-open", root.lastSavedPath.substring(0, root.lastSavedPath.lastIndexOf("/"))])
                        }
                    }
                }

                TouchpadScrollHandler {
                    flickable: settingsFlick
                }
            }
        }
    }
}
