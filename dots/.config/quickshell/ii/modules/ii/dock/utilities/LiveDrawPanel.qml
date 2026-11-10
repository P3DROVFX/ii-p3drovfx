import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * The pen, set up before it touches the screen: the ink, the thickness, and what to do
 * with what is already drawn.
 *
 * The hero is the switch itself — a large card that says what the overlay is doing and
 * turns it on or off, primary while the tools are out. Picking an ink or a thickness
 * here also takes the pen out: choosing a red marker is the start of drawing with one.
 */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property bool out: LiveDraw.trayOpen
    readonly property int sheets: LiveDraw.sheetCount
    readonly property string currentInk: LiveDraw.color.length > 0 ? LiveDraw.color : (LiveDraw.palette[0] ?? "")
    readonly property real currentWidth: LiveDraw.width > 0 ? LiveDraw.width : (Config.options?.tablet?.liveDraw?.width ?? 4)

    readonly property var thicknesses: [
        { width: 2, label: Translation.tr("Fine") },
        { width: 4, label: Translation.tr("Pen") },
        { width: 8, label: Translation.tr("Marker") },
        { width: 16, label: Translation.tr("Brush") }
    ]

    function openWith(apply) {
        LiveDraw.ensureTools();
        apply();
        panel.host?.closePanel();
        if (!LiveDraw.trayOpen)
            LiveDraw.open();
    }

    spacing: 8

    // ── The switch ──────────────────────────────────────────────────────
    RippleButton {
        id: hero
        Layout.fillWidth: true
        implicitHeight: 88
        buttonRadius: panel.out ? ClockStyle.radiusNormal : ClockStyle.radiusLarge
        buttonRadiusPressed: ClockStyle.radiusSmall
        colBackground: panel.out ? ClockStyle.colPrimary : ClockStyle.colPrimaryContainer
        colBackgroundHover: panel.out ? ClockStyle.colPrimaryHover : ClockStyle.colPrimaryContainerHover
        colRipple: panel.out ? ClockStyle.colPrimaryActive : ClockStyle.colPrimaryContainerActive
        readonly property color ink: panel.out ? ClockStyle.colOnPrimary : ClockStyle.colOnPrimaryContainer
        onClicked: {
            panel.host?.closePanel();
            LiveDraw.toggle();
        }

        Behavior on buttonRadius {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 18
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    shape: panel.out ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie7Sided
                    implicitSize: 60
                    padding: 14
                    iconSize: 30
                    text: "draw"
                    fill: panel.out ? 1 : 0
                    color: panel.out ? ClockStyle.colOnPrimary : ClockStyle.colPrimary
                    colSymbol: panel.out ? ClockStyle.colPrimary : ClockStyle.colOnPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: panel.out ? Translation.tr("Stop drawing") : Translation.tr("Draw on screen")
                        color: hero.ink
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                        font.pixelSize: Appearance.font.pixelSize.huge
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: panel.out
                            ? Translation.tr("Ink stays on its workspace")
                            : Translation.tr("Over every app, for recordings")
                        color: ColorUtils.applyAlpha(hero.ink, 0.78)
                        font.pixelSize: ClockStyle.textSmall
                        elide: Text.ElideRight
                    }
                }

                MaterialSymbol {
                    text: panel.out ? "close" : "arrow_forward"
                    iconSize: 22
                    color: hero.ink
                }
            }
        }
    }

    // ── Ink ─────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: inkColumn.implicitHeight + 24
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField

        ColumnLayout {
            id: inkColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            StyledText {
                text: Translation.tr("Ink")
                color: ClockStyle.colOnSurfaceVariant
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Bold
            }

            // The chosen ink is the rounded square; the rest are circles. The shape is
            // the selection — no ring around it.
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: LiveDraw.palette
                    delegate: RippleButton {
                        id: swatch
                        required property string modelData
                        readonly property bool selected: !LiveDraw.eraser && panel.currentInk === swatch.modelData
                        implicitWidth: 34
                        implicitHeight: 34
                        buttonRadius: swatch.selected ? ClockStyle.radiusSmall : 17
                        buttonRadiusPressed: ClockStyle.radiusSmall
                        colBackground: swatch.modelData
                        colBackgroundHover: swatch.modelData
                        colRipple: ColorUtils.applyAlpha(ColorUtils.getContrastingTextColor(swatch.modelData), 0.25)
                        onClicked: panel.openWith(() => {
                            LiveDraw.color = swatch.modelData;
                            LiveDraw.eraser = false;
                        })

                        Behavior on buttonRadius {
                            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                        }

                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: swatch.selected
                            text: "check"
                            iconSize: 18
                            color: ColorUtils.getContrastingTextColor(swatch.modelData)
                        }
                    }
                }
            }

            // Thickness: four steps, each showing its own stroke.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: panel.thicknesses
                    delegate: RippleButton {
                        id: step
                        required property var modelData
                        readonly property bool selected: Math.round(panel.currentWidth) === step.modelData.width
                        Layout.fillWidth: true
                        implicitHeight: 52
                        buttonRadius: step.selected ? ClockStyle.radiusNormal : ClockStyle.radiusSmall
                        buttonRadiusPressed: ClockStyle.radiusSmall
                        // Primary, not a container tone: in some schemes the containers sit
                        // within a shade of the field and the choice did not show.
                        colBackground: step.selected ? ClockStyle.colPrimary : ClockStyle.colSurfaceHighest
                        colBackgroundHover: step.selected ? ClockStyle.colPrimaryHover : ClockStyle.colSurfaceHover
                        colRipple: step.selected ? ClockStyle.colPrimaryActive : ClockStyle.colSurfaceActive
                        onClicked: panel.openWith(() => {
                            LiveDraw.width = step.modelData.width;
                            if (Config.ready)
                                Config.options.tablet.liveDraw.width = step.modelData.width;
                        })

                        Behavior on buttonRadius {
                            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                        }

                        contentItem: Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 34
                                    implicitHeight: 16
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width
                                        height: Math.min(16, step.modelData.width)
                                        radius: height / 2
                                        // The step's own thickness, in the label's colour: the ink
                                        // may be the very colour of the chip.
                                        color: step.selected ? ClockStyle.colOnPrimary : ClockStyle.colOnSurface
                                    }
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: step.modelData.label
                                    color: step.selected ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant
                                    font.pixelSize: ClockStyle.textSmall
                                    font.weight: step.selected ? Font.Bold : Font.Medium
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── What is already drawn ───────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        ClockButton {
            Layout.fillWidth: true
            enabled: panel.sheets > 0
            symbol: "note_add"
            label: Translation.tr("Save to Notes")
            onClicked: {
                GlobalStates.liveDrawSaveRequest++;
                panel.host?.closePanel();
            }
        }
        ClockButton {
            enabled: panel.sheets > 0
            danger: true
            symbol: "ink_eraser"
            label: Translation.tr("Rub everything out")
            iconOnly: true
            onClicked: LiveDraw.clearAll()
        }
    }
}
