import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Hero: the hottest sensor as the one big number, who controls the fans in a chip under
 * it, and every sensor and fan beside it with a bar against its ceiling (TjMax / max RPM).
 */
Rectangle {
    id: root

    readonly property bool wide: width >= 620
    readonly property var hottestSensor: FanControl.curveTemps.reduce((best, t) => (!best || t.c > best.c) ? t : best, null)

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    implicitHeight: grid.implicitHeight + 40

    readonly property var statusChip: {
        if (!FanControl.ready)
            return { "symbol": "hourglass_top", "text": Translation.tr("Reading sensors…"), "tone": "neutral" };
        if (FanControl.status?.safety)
            return { "symbol": "local_fire_department", "text": Translation.tr("Safety zone · full speed"), "tone": "tertiary" };
        if (!FanControl.controllable)
            return { "symbol": "visibility", "text": Translation.tr("Monitoring only"), "tone": "neutral" };
        if (!FanControl.daemonRunning)
            return { "symbol": "memory", "text": Translation.tr("Firmware curve"), "tone": "neutral" };
        if (!FanControl.config.enabled)
            return { "symbol": "memory", "text": Translation.tr("Firmware curve"), "tone": "neutral" };
        return { "symbol": "mode_fan", "text": FanControl.additive
                    ? Translation.tr("Custom curve · %1% boost").arg(Math.round(FanControl.appliedPct))
                    : Translation.tr("Custom curve · %1%").arg(Math.round(FanControl.appliedPct)), "tone": "primary" };
    }

    GridLayout {
        id: grid
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        columns: root.wide ? 2 : 1
        columnSpacing: 24
        rowSpacing: 20

        // ── the number ──
        ColumnLayout {
            Layout.preferredWidth: root.wide ? Math.max(220, Math.min(320, root.width * 0.34)) : -1
            Layout.fillWidth: !root.wide
            Layout.alignment: Qt.AlignTop
            spacing: 0

            StyledText {
                text: root.hottestSensor ? Translation.tr("Hottest · %1").arg(root.hottestSensor.label) : Translation.tr("Temperature")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurfaceVariant
            }

            Row {
                spacing: 2
                StyledText {
                    id: bigDigits
                    text: root.hottestSensor ? Math.round(root.hottestSensor.c) : "--"
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                    font.pixelSize: 112
                    color: FanControl.status?.safety ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
                }
                StyledText {
                    anchors.top: parent.top
                    anchors.topMargin: 18
                    text: "°C"
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
            }

            Rectangle {
                Layout.topMargin: 4
                implicitHeight: 32
                implicitWidth: chipRow.implicitWidth + 24
                radius: height / 2
                color: root.statusChip.tone === "primary" ? Appearance.colors.colPrimaryContainer
                    : root.statusChip.tone === "tertiary" ? Appearance.colors.colTertiaryContainer
                    : Appearance.colors.colSecondaryContainer
                readonly property color colContent: root.statusChip.tone === "primary" ? Appearance.colors.colOnPrimaryContainer
                    : root.statusChip.tone === "tertiary" ? Appearance.colors.colOnTertiaryContainer
                    : Appearance.colors.colOnSecondaryContainer
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: root.statusChip.symbol
                        iconSize: Appearance.font.pixelSize.normal
                        color: parent.parent.colContent
                    }
                    StyledText {
                        text: root.statusChip.text
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: parent.parent.colContent
                    }
                }
            }

            StyledText {
                Layout.topMargin: 10
                Layout.fillWidth: true
                visible: (FanControl.caps?.product ?? "").length > 0
                text: `${FanControl.caps?.vendor ?? ""} ${FanControl.caps?.product ?? ""}`.trim()
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        // ── sensors and fans ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 6

            Repeater {
                model: FanControl.temps
                delegate: MeterRow {
                    required property var modelData
                    symbol: modelData.label.includes("GPU") ? "developer_board"
                        : modelData.drive === false ? "device_thermostat" : "memory"
                    shape: MaterialShape.Shape.Cookie6Sided
                    label: modelData.label
                    value: `${Math.round(modelData.c)}°`
                    fraction: modelData.c / FanControl.tjMax
                }
            }
            Repeater {
                model: FanControl.fans
                delegate: MeterRow {
                    required property var modelData
                    symbol: "mode_fan"
                    shape: MaterialShape.Shape.Clover4Leaf
                    label: modelData.label
                    value: Translation.tr("%1 RPM").arg(modelData.rpm)
                    // no max RPM (Framework EC): show the duty the service sent instead
                    fraction: modelData.max > 0 ? modelData.rpm / modelData.max
                        : (modelData.raw !== undefined && modelData.raw !== null ? modelData.raw / 255 : 0)
                }
            }
        }
    }

    component MeterRow: Rectangle {
        id: meter
        property string symbol
        property var shape
        property string label
        property string value
        property real fraction

        Layout.fillWidth: true
        implicitHeight: 56
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 16
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: meter.symbol
                iconSize: 18
                padding: 8
                shape: meter.shape
                color: Appearance.colors.colSecondaryContainer
                colSymbol: Appearance.colors.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: meter.label
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: meter.value
                        font.family: Appearance.font.family.main
                        font.variableAxes: ({ "wght": 700, "wdth": 75, "ROND": 100 })
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }
                }
                StyledProgressBar {
                    Layout.fillWidth: true
                    valueBarHeight: 6
                    value: Math.max(0, Math.min(1, meter.fraction))
                    highlightColor: meter.fraction >= 0.92 ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
                }
            }
        }
    }
}
