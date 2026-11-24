pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Reusable QR code card supporting Pixel, Blob, and Classic styles.
 *
 * Accepts either an explicit `matrix` ({ size, version, rows }) or `text`
 * (encoded via QrCode.encode). Pixel and Blob render via debounced,
 * double-buffered asynchronous SVG Images; Classic renders via Canvas.
 */
Rectangle {
    id: root

    /// Pre-built matrix ({ size, version, rows } or { modules, size, version }).
    property var matrix: null
    /// Plain text to encode when `matrix` is not provided.
    property string text: ""
    /// Error correction level used when encoding `text` ("L" | "M" | "Q" | "H").
    property string ecc: "M"
    /// QR style: "pixel" | "blob" | "classic" (defaults to global QrCode.style).
    property string style: QrCode.style
    /// Pixel outer cookie/dots decoration (defaults to global QrCode.decoration).
    property bool decoration: QrCode.decoration
    /// Target side length in logical pixels.
    property real implicitSize: 200
    /// When true in Classic mode, snaps the card size to an integer multiple of (size + 4) modules.
    property bool snapClassicSize: false
    /// Shows a loading indicator over the card when true.
    property bool busy: false
    /// Debounce delay in ms before rebuilding the SVG preview.
    property int debounceInterval: 150

    readonly property var resolvedMatrix: {
        if (root.matrix && ((root.matrix.rows?.length ?? 0) > 0 || (root.matrix.modules?.length ?? 0) > 0))
            return root.matrix;
        if (root.text.length > 0)
            return QrCode.encode(root.text, root.ecc);
        return null;
    }
    readonly property int matrixSize: root.resolvedMatrix?.size ?? root.resolvedMatrix?.rows?.length ?? root.resolvedMatrix?.modules?.length ?? 21
    readonly property bool hasMatrix: root.resolvedMatrix !== null
    readonly property string effectiveStyle: (root.style === "blob" || root.style === "classic") ? root.style : "pixel"
    readonly property bool isStyled: root.effectiveStyle === "pixel" || root.effectiveStyle === "blob"
    readonly property var resolvedColors: root.isStyled
        ? QrCode.colors(root.effectiveStyle)
        : ({ background: "#FFFFFF", canvasBg: "#FFFFFF", primary: "#000000" })

    readonly property int _classicModules: root.matrixSize + 4
    readonly property int _classicModulePx: Math.max(1, Math.floor(root.implicitSize / root._classicModules))
    readonly property int _classicSnappedSide: root._classicModules * root._classicModulePx
    readonly property int _svgTargetSide: Math.max(1, Math.round(root.implicitSize))

    implicitWidth: (root.snapClassicSize && !root.isStyled) ? root._classicSnappedSide : Math.max(1, Math.round(root.implicitSize))
    implicitHeight: (root.snapClassicSize && !root.isStyled) ? root._classicSnappedSide : Math.max(1, Math.round(root.implicitSize))
    radius: Appearance.rounding.small
    color: root.effectiveStyle === "pixel"
        ? (root.resolvedColors?.canvasBg ?? "#FFFFFF")
        : (root.effectiveStyle === "blob"
            ? (root.resolvedColors?.background ?? "#FFFFFF")
            : "white")

    property string _sourceA: ""
    property string _sourceB: ""
    property int _activeSlot: 0
    property int _pendingSlot: -1
    property bool _hasDisplayed: false

    function _rebuildStyledPreview() {
        if (!root.isStyled || !root.hasMatrix) {
            root._sourceA = "";
            root._sourceB = "";
            root._pendingSlot = -1;
            root._hasDisplayed = false;
            return;
        }
        const displayColors = root.effectiveStyle === "pixel"
            ? { canvasBg: "transparent" }
            : { background: "transparent", cardBackground: root.resolvedColors.background };
        const svg = QrCode.svg(root.resolvedMatrix, root.effectiveStyle, {
            decoration: root.decoration,
            sizePx: 800,
            colors: displayColors
        });
        const uri = svg.length > 0 ? ("data:image/svg+xml;utf8," + encodeURIComponent(svg)) : "";
        if (uri.length === 0) {
            root._sourceA = "";
            root._sourceB = "";
            root._pendingSlot = -1;
            root._hasDisplayed = false;
            return;
        }
        const currentImg = root._activeSlot === 0 ? imageA : imageB;
        const currentUri = root._activeSlot === 0 ? root._sourceA : root._sourceB;
        if (root._hasDisplayed && currentUri === uri && currentImg.status === Image.Ready) {
            root._pendingSlot = -1;
            return;
        }
        const target = root._hasDisplayed ? (1 - root._activeSlot) : 0;
        root._pendingSlot = target;
        if (target === 0) {
            root._sourceA = uri;
            if (imageA.status === Image.Ready && root._pendingSlot === 0) {
                root._activeSlot = 0;
                root._hasDisplayed = true;
                root._pendingSlot = -1;
            }
        } else {
            root._sourceB = uri;
            if (imageB.status === Image.Ready && root._pendingSlot === 1) {
                root._activeSlot = 1;
                root._hasDisplayed = true;
                root._pendingSlot = -1;
            }
        }
    }

    function _schedulePreview() {
        if (!root.isStyled || !root.hasMatrix) {
            previewDebounce.stop();
            root._rebuildStyledPreview();
            if (!root.isStyled && root.hasMatrix)
                classicCanvas.requestPaint();
            return;
        }
        previewDebounce.restart();
    }

    onResolvedMatrixChanged: root._schedulePreview()
    onEffectiveStyleChanged: root._schedulePreview()
    onDecorationChanged: root._schedulePreview()
    onResolvedColorsChanged: root._schedulePreview()
    Component.onCompleted: root._schedulePreview()

    Timer {
        id: previewDebounce
        interval: root.debounceInterval
        repeat: false
        onTriggered: root._rebuildStyledPreview()
    }

    Image {
        id: imageA
        anchors.fill: parent
        visible: root.isStyled && root.hasMatrix
        opacity: (root._hasDisplayed && root._activeSlot === 0) ? 1 : 0
        z: root._activeSlot === 0 ? 1 : 0
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(root._svgTargetSide, root._svgTargetSide)
        source: root._sourceA
        onStatusChanged: {
            if (status === Image.Ready && root._pendingSlot === 0) {
                root._activeSlot = 0;
                root._hasDisplayed = true;
                root._pendingSlot = -1;
            }
        }
    }

    Image {
        id: imageB
        anchors.fill: parent
        visible: root.isStyled && root.hasMatrix
        opacity: (root._hasDisplayed && root._activeSlot === 1) ? 1 : 0
        z: root._activeSlot === 1 ? 1 : 0
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(root._svgTargetSide, root._svgTargetSide)
        source: root._sourceB
        onStatusChanged: {
            if (status === Image.Ready && root._pendingSlot === 1) {
                root._activeSlot = 1;
                root._hasDisplayed = true;
                root._pendingSlot = -1;
            }
        }
    }

    Canvas {
        id: classicCanvas
        anchors.fill: parent
        visible: !root.isStyled && root.hasMatrix
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const mat = root.resolvedMatrix;
            if (!mat)
                return;
            const rows = mat.rows;
            const modules = mat.modules;
            const n = rows ? rows.length : (modules ? modules.length : 0);
            if (n === 0)
                return;
            const px = Math.max(1, Math.floor(Math.min(width, height) / (n + 4)));
            const ox = Math.floor((width - px * n) / 2);
            const oy = Math.floor((height - px * n) / 2);
            ctx.fillStyle = "#000000";
            for (let y = 0; y < n; y++) {
                if (rows) {
                    const row = rows[y];
                    for (let x = 0; x < n; x++) {
                        if (row[x] === "1")
                            ctx.fillRect(ox + x * px, oy + y * px, px, px);
                    }
                } else {
                    const modRow = modules[y];
                    for (let x = 0; x < n; x++) {
                        if (modRow[x])
                            ctx.fillRect(ox + x * px, oy + y * px, px, px);
                    }
                }
            }
        }
        onWidthChanged: if (visible) requestPaint()
        onHeightChanged: if (visible) requestPaint()
    }

    MaterialLoadingIndicator {
        anchors.centerIn: parent
        visible: root.busy
        loading: visible
        implicitSize: Math.min(44, Math.max(24, Math.round(root.implicitSize * 0.22)))
    }
}
