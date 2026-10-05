import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * The colour history: the chosen colour large with its code in HEX, RGB and
 * HSL (each row copies), and every colour picked so far as swatches.
 */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var colors: panel.tile?.colors ?? []
    property string chosen: panel.colors.length > 0 ? panel.colors[0] : ""

    readonly property color chosenColor: panel.chosen !== "" ? panel.chosen : "transparent"
    readonly property var formats: {
        if (panel.chosen === "")
            return [];
        const c = Qt.color(panel.chosen);
        const r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255);
        const h = Math.round(Math.max(0, c.hslHue) * 360), s = Math.round(c.hslSaturation * 100), l = Math.round(c.hslLightness * 100);
        return [
            { label: "HEX", value: panel.chosen },
            { label: "RGB", value: `rgb(${r}, ${g}, ${b})` },
            { label: "HSL", value: `hsl(${h}, ${s}%, ${l}%)` }
        ];
    }

    spacing: 8

    // The chosen colour as the hero: its HEX in large digits, inked in
    // contrast; a click copies it.
    RippleButton {
        id: hero
        Layout.fillWidth: true
        visible: panel.chosen !== ""
        implicitHeight: 104
        buttonRadius: ClockStyle.radiusLarge
        buttonRadiusPressed: ClockStyle.radiusNormal
        colBackground: panel.chosenColor
        colBackgroundHover: panel.chosenColor
        colRipple: ColorUtils.applyAlpha(hero.ink, 0.2)
        readonly property color ink: ColorUtils.getContrastingTextColor(panel.chosen || "#000000")
        readonly property bool justCopied: (panel.tile?.copied ?? "") === panel.chosen
        onClicked: panel.tile?.copy(panel.chosen)
        contentItem: Item {
            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: panel.chosen.slice(1)
                color: hero.ink
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: 52
            }
            MaterialSymbol {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: hero.justCopied ? "check" : "content_copy"
                iconSize: 22
                color: hero.ink
            }
        }
    }

    Repeater {
        model: panel.formats.slice(1)
        delegate: RippleButton {
            id: formatRow
            required property var modelData
            required property int index
            readonly property bool justCopied: (panel.tile?.copied ?? "") === formatRow.modelData.value
            Layout.fillWidth: true
            implicitHeight: 44
            buttonRadius: ClockStyle.radiusSmall
            colBackground: formatRow.justCopied ? ClockStyle.colPrimaryContainer : ClockStyle.colField
            colBackgroundHover: ClockStyle.colFieldHover
            colRipple: ClockStyle.colSurfaceActive
            onClicked: panel.tile?.copy(formatRow.modelData.value)
            contentItem: Item {
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10
                    StyledText {
                        Layout.preferredWidth: 32
                        text: formatRow.modelData.label
                        color: ClockStyle.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: formatRow.modelData.value
                        color: formatRow.justCopied ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: ClockStyle.textNormal
                        elide: Text.ElideRight
                    }
                    MaterialSymbol {
                        text: formatRow.justCopied ? "check" : "content_copy"
                        iconSize: 16
                        color: formatRow.justCopied ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                    }
                }
            }
        }
    }

    // ── History ─────────────────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        visible: panel.colors.length > 0
        spacing: 6
        Repeater {
            model: panel.colors
            delegate: RippleButton {
                id: swatch
                required property string modelData
                readonly property bool selected: panel.chosen === swatch.modelData
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: swatch.selected ? ClockStyle.radiusSmall : 18
                buttonRadiusPressed: ClockStyle.radiusSmall
                colBackground: swatch.modelData
                colBackgroundHover: swatch.modelData
                colRipple: ColorUtils.applyAlpha("#ffffff", 0.3)
                onClicked: panel.chosen = swatch.modelData
                StyledToolTip {
                    text: swatch.modelData
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.colors.length === 0
        implicitHeight: 72
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("Picked colors show up here")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        ClockButton {
            Layout.fillWidth: true
            variant: "filled"
            symbol: "colorize"
            label: Translation.tr("Pick a color")
            onClicked: {
                panel.host?.closePanel();
                panel.tile?.pick();
            }
        }
        ClockButton {
            visible: panel.colors.length > 0
            symbol: "delete_sweep"
            label: Translation.tr("Clear")
            iconOnly: true
            onClicked: panel.tile?.clear()
        }
    }
}
