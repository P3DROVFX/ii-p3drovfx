import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Disk usage: how full the chosen disk is (ResourceUsage, the resources
 * popup's backend; the mount is `resources.diskMount`). The gauge is a pie —
 * the used slice — not a ring: rings already mean time and quotas on this dock.
 * Square: the used share in digits over the pie, drawn faint. Wide: the pie as
 * the badge, the used share large, what is free and where as the caption.
 * Past 90 % the slice turns error. A click opens the mount in the file manager.
 */
UtilityTile {
    id: tile

    // The disk is polled only while someone shows it.
    Component.onCompleted: ResourceUsage.requestMetric("disk", true)
    Component.onDestruction: ResourceUsage.requestMetric("disk", false)

    readonly property string mount: Config.options?.resources?.diskMount ?? "/"
    readonly property bool ready: ResourceUsage.diskTotal > 1
    readonly property real fraction: tile.ready ? Math.max(0, Math.min(1, ResourceUsage.diskUsedPercentage)) : 0
    readonly property int percent: Math.round(tile.fraction * 100)
    readonly property bool full: tile.fraction >= 0.9
    readonly property color sliceColor: tile.full ? ClockStyle.colError : ClockStyle.colPrimary

    function bytes(value) {
        const units = ["B", "KB", "MB", "GB", "TB", "PB"];
        let v = Math.max(0, Number(value) || 0);
        let i = 0;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
    }

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: tile.ready
        ? Translation.tr("%1 · %2 used of %3 · %4 free").arg(tile.mount).arg(tile.bytes(ResourceUsage.diskUsed))
            .arg(tile.bytes(ResourceUsage.diskTotal)).arg(tile.bytes(ResourceUsage.diskFree))
        : Translation.tr("Disk usage")

    function activate() {
        Quickshell.execDetached(["xdg-open", tile.mount]);
        return true;
    }

    // The used slice from 12 o'clock, clockwise, over the whole disc.
    component Pie: Item {
        id: pie
        property color colSlice: tile.sliceColor
        property color colRest: ColorUtils.applyAlpha(tile.contentColor, 0.12)
        readonly property real r: Math.min(pie.width, pie.height) / 2
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: pie.colRest
                strokeColor: "transparent"
                PathAngleArc {
                    centerX: pie.width / 2
                    centerY: pie.height / 2
                    radiusX: pie.r
                    radiusY: pie.r
                    startAngle: 0
                    sweepAngle: 360
                }
            }
            ShapePath {
                fillColor: pie.colSlice
                strokeColor: "transparent"
                startX: pie.width / 2
                startY: pie.height / 2
                PathAngleArc {
                    centerX: pie.width / 2
                    centerY: pie.height / 2
                    radiusX: pie.r
                    radiusY: pie.r
                    startAngle: -90
                    sweepAngle: 360 * tile.fraction
                    moveToStart: false
                }
                PathLine {
                    x: pie.width / 2
                    y: pie.height / 2
                }
            }
        }
    }

    // ── Square: the share over a faint pie ──────────────────────────────
    Item {
        anchors.fill: parent
        visible: !tile.wide

        Pie {
            anchors.centerIn: parent
            width: Math.round(tile.side * 0.8)
            height: width
            colSlice: ColorUtils.applyAlpha(tile.sliceColor, 0.32)
            colRest: ColorUtils.applyAlpha(tile.contentColor, 0.08)
        }
        RowLayout {
            anchors.centerIn: parent
            spacing: 0
            TileValue {
                Layout.alignment: Qt.AlignBaseline
                text: tile.ready ? String(tile.percent) : "—"
                color: tile.full ? ClockStyle.colError : tile.contentColor
                font.pixelSize: Math.round(tile.side * 0.38)
            }
            TileValue {
                Layout.alignment: Qt.AlignBaseline
                visible: tile.ready
                text: "%"
                color: tile.captionColor
                font.variableAxes: ClockStyle.axesDigits
                font.pixelSize: Math.round(tile.side * 0.2)
            }
        }
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        anchors.rightMargin: tile.pad * 2
        visible: tile.wide
        spacing: tile.pad

        Pie {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2
            RowLayout {
                spacing: 1
                TileValue {
                    Layout.alignment: Qt.AlignBaseline
                    text: tile.ready ? String(tile.percent) : "—"
                    color: tile.full ? ClockStyle.colError : tile.contentColor
                    font.pixelSize: tile.valueSize
                }
                TileValue {
                    Layout.alignment: Qt.AlignBaseline
                    visible: tile.ready
                    text: "%"
                    color: tile.captionColor
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: Math.round(tile.valueSize * 0.55)
                }
            }
            TileCaption {
                Layout.fillWidth: true
                text: tile.ready ? Translation.tr("%1 free · %2").arg(tile.bytes(ResourceUsage.diskFree)).arg(tile.mount)
                    : tile.mount
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }
    }
}
