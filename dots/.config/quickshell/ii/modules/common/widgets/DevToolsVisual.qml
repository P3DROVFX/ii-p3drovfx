pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common

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
    readonly property string qrStyle: root.visual?.style ?? QrCode.style
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

    function copyQr() {
        QrCode.copyImage(root.visual, root.qrStyle, {
            decoration: root.visual?.decoration ?? QrCode.decoration
        }, (ok, message) => root.notice(message));
    }

    function saveQr() {
        QrCode.savePng(root.visual, root.qrStyle, "", {
            decoration: root.visual?.decoration ?? QrCode.decoration
        }, (ok, path, message) => root.notice(message));
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.sizes.elevationMargin / 2

        // ── QR: Pixel/Blob/Classic via shared StyledQrCode ──
        RowLayout {
            visible: root.kind === "qr"
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin

            StyledQrCode {
                readonly property real availSide: Math.min(root.maxQrSide, root.width > 0 ? root.width * 0.6 : root.maxQrSide)
                matrix: root.kind === "qr" ? root.visual : null
                style: root.qrStyle
                decoration: root.visual?.decoration ?? QrCode.decoration
                implicitSize: Math.max(120, Math.round(availSide))
                snapClassicSize: true
                radius: Appearance.rounding.small
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
