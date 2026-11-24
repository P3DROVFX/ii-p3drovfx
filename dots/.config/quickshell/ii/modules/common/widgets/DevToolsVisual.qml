pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * The picture of a Dev tools result, read from the `visual` entry of the
 * tool's meta (devtools.js): a QR matrix, colour swatches or a contrast
 * sample. The cheatsheet page and the Search Tools panel both show it, so a
 * tool that returns `visual` gets its preview in either place.
 */
Item {
    id: root

    property var visual: null
    /// Largest side of the QR code, in pixels.
    property real maxQrSide: 240
    /// Toast text for the host (copied, saved, failed).
    signal notice(string message)

    readonly property string kind: root.visual?.kind ?? ""
    readonly property bool hasVisual: root.kind === "qr" || root.kind === "swatches" || root.kind === "contrast"

    visible: root.hasVisual
    implicitWidth: content.implicitWidth
    implicitHeight: root.hasVisual ? content.implicitHeight : 0

    function hexLuminance(hex) {
        const value = String(hex).replace("#", "");
        const channel = i => {
            const c = parseInt(value.substr(i, 2), 16) / 255;
            return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        };
        return 0.2126 * channel(0) + 0.7152 * channel(2) + 0.0722 * channel(4);
    }

    function qrCommand(target) {
        const rows = (root.visual?.rows ?? []).join(",");
        return ["python3", `${Directories.scriptPath}/images/qr_png.py`, rows, target];
    }

    function copyQr() {
        const command = root.qrCommand("-");
        Quickshell.execDetached(["bash", "-c", '"$@" | wl-copy --type image/png', "qr"].concat(command));
        root.notice(Translation.tr("QR code copied as an image"));
    }

    function saveQr() {
        const folder = FileUtils.trimFileProtocol(Directories.pictures);
        const stamp = new Date().toISOString().replace(/[:T]/g, "-").slice(0, 19);
        const path = `${folder}/qr-${stamp}.png`;
        saveProc.savedPath = path;
        saveProc.command = root.qrCommand(path);
        saveProc.running = true;
    }

    Process {
        id: saveProc
        property string savedPath: ""
        onExited: (exitCode, exitStatus) => root.notice(exitCode === 0
            ? Translation.tr("Saved %1").arg(saveProc.savedPath)
            : Translation.tr("Could not save the QR code (python3 with Pillow is needed)"))
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.sizes.elevationMargin / 2

        // ── QR: dark modules on white, whatever the theme, so phones read it ──
        RowLayout {
            visible: root.kind === "qr"
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin

            Rectangle {
                id: qrPaper
                readonly property int modules: (root.visual?.size ?? 21) + 4
                readonly property int modulePx: Math.max(1, Math.floor(Math.min(root.maxQrSide, root.width * 0.6) / modules))
                implicitWidth: modules * modulePx
                implicitHeight: modules * modulePx
                radius: Appearance.rounding.small
                color: "white"

                Canvas {
                    id: qrCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.fillStyle = "#000000";
                        const rows = root.visual?.rows ?? [];
                        const px = qrPaper.modulePx;
                        for (let y = 0; y < rows.length; y++) {
                            const row = rows[y];
                            for (let x = 0; x < row.length; x++) {
                                if (row[x] === "1")
                                    ctx.fillRect((x + 2) * px, (y + 2) * px, px, px);
                            }
                        }
                    }
                    Connections {
                        target: root
                        function onVisualChanged() {
                            if (root.kind === "qr")
                                qrCanvas.requestPaint();
                        }
                    }
                    onWidthChanged: requestPaint()
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                spacing: Appearance.sizes.elevationMargin / 2

                Repeater {
                    model: [
                        { symbol: "content_copy", label: Translation.tr("Copy image"), action: "copy" },
                        { symbol: "download", label: Translation.tr("Save PNG"), action: "save" }
                    ]
                    delegate: RippleButton {
                        id: qrAction
                        required property var modelData
                        implicitHeight: Appearance.sizes.elevationMargin * 2.4
                        implicitWidth: qrActionRow.implicitWidth + Appearance.sizes.elevationMargin * 1.5
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: qrAction.modelData.action === "copy" ? root.copyQr() : root.saveQr()

                        RowLayout {
                            id: qrActionRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: qrAction.modelData.symbol
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: qrAction.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
                StyledText {
                    Layout.maximumWidth: 220
                    text: Translation.tr("Version %1 · %2 modules").arg(String(root.visual?.version ?? "")).arg(String(root.visual?.size ?? ""))
                    visible: root.visual?.version !== undefined
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── Swatches: click one to copy its hex ──
        Flow {
            visible: root.kind === "swatches"
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.kind === "swatches" ? (root.visual?.items ?? []) : []
                delegate: Rectangle {
                    id: swatch
                    required property var modelData
                    readonly property bool darkInk: root.hexLuminance(modelData.color) > 0.18
                    width: Math.max(76, swatchText.implicitWidth + 12)
                    height: 52
                    radius: Appearance.rounding.small
                    color: modelData.color

                    Column {
                        id: swatchText
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        StyledText {
                            text: swatch.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: swatch.darkInk ? "#000000" : "#FFFFFF"
                        }
                        StyledText {
                            text: swatch.modelData.color
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: swatch.darkInk ? "#000000" : "#FFFFFF"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.clipboardText = swatch.modelData.color;
                            root.notice(Translation.tr("Copied %1").arg(swatch.modelData.color));
                        }
                    }
                }
            }
        }

        // ── Contrast: the pair as it reads ──
        Rectangle {
            visible: root.kind === "contrast"
            Layout.fillWidth: true
            implicitHeight: contrastRow.implicitHeight + Appearance.sizes.elevationMargin * 1.6
            radius: Appearance.rounding.small
            color: root.visual?.background ?? "transparent"

            RowLayout {
                id: contrastRow
                anchors.fill: parent
                anchors.margins: Appearance.sizes.elevationMargin * 0.8
                spacing: Appearance.sizes.elevationMargin

                StyledText {
                    text: "Aa"
                    font.pixelSize: Appearance.font.pixelSize.huge * 1.4
                    font.weight: Font.Bold
                    color: root.visual?.foreground ?? "black"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("The quick brown fox jumps over the lazy dog")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: root.visual?.foreground ?? "black"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Small print at 12px stays readable only with enough contrast")
                        elide: Text.ElideRight
                        font.pixelSize: 12
                        color: root.visual?.foreground ?? "black"
                    }
                }
                StyledText {
                    text: root.visual?.ratio ?? ""
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.numbers
                    color: root.visual?.foreground ?? "black"
                }
            }
        }
    }
}
