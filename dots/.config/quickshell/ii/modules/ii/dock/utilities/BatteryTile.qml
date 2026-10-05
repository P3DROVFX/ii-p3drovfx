import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Battery: the charge and how long it still lasts. Square: the percentage in
 * condensed digits standing on a thick level bar. Wide: the percentage large,
 * the state over the time left (or to full), the bar along the card's foot.
 * Charging takes the primary family, low the error one.
 */
UtilityTile {
    id: tile

    readonly property bool available: Battery.available
    readonly property int percent: Battery.percent
    readonly property bool charging: Battery.isCharging
    readonly property bool plugged: Battery.isPluggedIn
    readonly property bool low: Battery.isLow && !tile.plugged

    function duration(seconds) {
        const minutes = Math.max(1, Math.round(seconds / 60));
        const hours = Math.floor(minutes / 60);
        if (hours === 0)
            return Translation.tr("%1 min").arg(minutes);
        return Translation.tr("%1 h %2 min").arg(hours).arg(minutes % 60);
    }
    readonly property string stateText: !tile.available ? Translation.tr("No battery")
        : tile.charging ? Translation.tr("Charging")
        : tile.plugged ? Translation.tr("Plugged in")
        : tile.low ? Translation.tr("Low") : Translation.tr("On battery")
    readonly property string timeText: !tile.available ? ""
        : tile.charging ? (Battery.timeToFull > 0 ? Translation.tr("Full in %1").arg(tile.duration(Battery.timeToFull)) : "")
        : tile.plugged ? (Battery.chargeLimitReached ? Translation.tr("Held at %1%").arg(Battery.chargeLimit) : (Battery.isFullyCharged ? Translation.tr("Full") : ""))
        : (Battery.timeToEmpty > 0 ? Translation.tr("%1 left").arg(tile.duration(Battery.timeToEmpty)) : "")

    surfaceColor: tile.low ? ClockStyle.colErrorContainer
        : tile.charging ? ClockStyle.colPrimaryContainer
        : ClockStyle.colSurfaceHigh
    contentColor: tile.low ? ClockStyle.colOnErrorContainer
        : tile.charging ? ClockStyle.colOnPrimaryContainer
        : ClockStyle.colOnSurface
    readonly property color barColor: tile.low ? ClockStyle.colError : ClockStyle.colPrimary

    tooltipText: tile.available
        ? Translation.tr("Battery · %1%").arg(tile.percent) + " · " + tile.stateText + (tile.timeText ? " · " + tile.timeText : "")
        : Translation.tr("No battery")
    panelSubtitle: tile.stateText + (tile.timeText ? " · " + tile.timeText : "")
    panelWidth: 320

    // The level as a thick pill; the fill keeps rounded ends at every level.
    component LevelBar: Rectangle {
        radius: height / 2
        color: ColorUtils.applyAlpha(tile.contentColor, 0.14)
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: Math.max(parent.height, parent.width * tile.percent / 100)
            radius: height / 2
            color: tile.barColor
            Behavior on width {
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }
        }
    }

    // ── Square ──────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: Math.round(tile.side * 0.14)
        visible: !tile.wide

        TileValue {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Math.round(tile.side * 0.06)
            text: tile.available ? String(tile.percent) : "—"
            color: tile.contentColor
            font.pixelSize: Math.round(tile.side * (tile.percent >= 100 ? 0.36 : 0.42))
        }
        // Charging: a bolt tucked into the corner instead of a second line.
        TileSymbol {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -Math.round(tile.side * 0.08)
            anchors.topMargin: -Math.round(tile.side * 0.08)
            visible: tile.charging || tile.plugged
            text: tile.charging ? "bolt" : "power"
            iconSize: Math.round(tile.side * 0.24)
            fill: 1
            color: tile.charging ? ClockStyle.colPrimary : tile.captionColor
        }
        LevelBar {
            visible: tile.available
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(4, Math.round(tile.side * 0.1))
        }
    }

    // ── Wide ────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.leftMargin: tile.pad * 2
        anchors.rightMargin: tile.pad * 2
        anchors.topMargin: tile.pad
        anchors.bottomMargin: tile.pad
        visible: tile.wide

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: bar.top
            anchors.bottomMargin: Math.round(tile.pad * 0.4)
            spacing: tile.pad

            RowLayout {
                spacing: 0
                TileValue {
                    Layout.alignment: Qt.AlignBaseline
                    text: tile.available ? String(tile.percent) : "—"
                    color: tile.contentColor
                    font.pixelSize: Math.round(tile.height * 0.5)
                }
                TileValue {
                    Layout.alignment: Qt.AlignBaseline
                    visible: tile.available
                    text: "%"
                    color: tile.captionColor
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: Math.round(tile.height * 0.26)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: -1
                RowLayout {
                    spacing: 2
                    TileSymbol {
                        visible: tile.charging || tile.plugged
                        text: tile.charging ? "bolt" : "power"
                        iconSize: Math.round(tile.captionSize * 1.3)
                        fill: 1
                        color: tile.charging ? ClockStyle.colPrimary : tile.captionColor
                    }
                    TileCaption {
                        text: tile.stateText
                        color: tile.captionColor
                        font.pixelSize: tile.captionSize
                    }
                }
                TileText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: tile.timeText
                    color: tile.contentColor
                    font.pixelSize: Math.round(tile.height * 0.24)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }
        LevelBar {
            id: bar
            visible: tile.available
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(4, Math.round(tile.height * 0.1))
        }
    }
}
