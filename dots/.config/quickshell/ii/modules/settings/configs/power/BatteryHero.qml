import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Hero of the Power page: the pack as a slab filled to its level, the level as the one big
 * number, and beside it today's charge by hour. The chart is the door to the full battery
 * history (the App usage Battery tab, as a sub-page): `detailsRequested`.
 */
Item {
    id: root

    signal detailsRequested()

    readonly property bool wide: width >= 620
    readonly property real slabWidth: root.wide ? Math.round(Math.max(220, Math.min(320, width * 0.34))) : width
    readonly property real heroHeight: Math.round(Math.max(260, Math.min(340, width / 2.6)))

    implicitHeight: root.wide ? root.heroHeight : root.heroHeight + 12 + chartCard.implicitHeight

    // ── status words ──
    readonly property real remainingSeconds: Battery.isCharging ? Battery.timeToFullEffective : Battery.timeToEmpty

    function formatDuration(seconds) {
        if (!(seconds > 0))
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        if (h === 0)
            return Translation.tr("%1 min").arg(m);
        return m === 0 ? Translation.tr("%1 h").arg(h) : Translation.tr("%1 h %2 min").arg(h).arg(m);
    }

    readonly property string stateWord: {
        if (Battery.chargeLimitReached)
            return Translation.tr("Holding");
        if (Battery.isCharging)
            return Translation.tr("Charging");
        if (Battery.fullOnAc)
            return Translation.tr("Full");
        if (Battery.drainingOnAc)
            return Translation.tr("Draining on AC");
        if (Battery.isPluggedIn)
            return Translation.tr("Plugged in");
        return Translation.tr("On battery");
    }

    readonly property string stateDetail: {
        const d = root.formatDuration(root.remainingSeconds);
        if (Battery.chargeLimitReached)
            return Translation.tr("Kept at %1 % to spare the cells").arg(Battery.chargeLimit);
        if (Battery.isCharging)
            return d ? Translation.tr("%1 until full").arg(d) : Translation.tr("Estimating…");
        if (Battery.isPluggedIn)
            return Translation.tr("Running on the adapter");
        return d ? Translation.tr("%1 left").arg(d) : Translation.tr("Estimating…");
    }

    // ── the slab ──
    Rectangle {
        id: slab
        x: 0
        y: 0
        width: root.slabWidth
        height: root.heroHeight
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1
        clip: true

        readonly property real level: Math.max(0, Math.min(1, Battery.percentage))
        readonly property bool alert: Battery.isLowAndUnplugged

        // the charge, rising from the bottom
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(parent.radius, parent.height * slab.level)
            radius: Appearance.rounding.verylarge
            topLeftRadius: slab.level > 0.97 ? Appearance.rounding.verylarge : Appearance.rounding.small
            topRightRadius: topLeftRadius
            color: slab.alert ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer
            Behavior on height { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }

        // charge limit notch on the right edge
        Rectangle {
            visible: Battery.chargeLimitActive
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: Math.round(parent.height * (1 - Battery.chargeLimit / 100)) - height / 2
            height: 24
            width: limitText.implicitWidth + 16
            radius: height / 2
            color: Appearance.colors.colPrimary
            StyledText {
                id: limitText
                anchors.centerIn: parent
                text: Translation.tr("limit %1").arg(Battery.chargeLimit)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colOnPrimary
            }
        }

        ColumnLayout {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 22
            }
            spacing: 0

            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: Battery.isCharging ? "bolt" : (Battery.isPluggedIn ? "power" : "battery_android_full")
                    iconSize: Appearance.font.pixelSize.large
                    fill: 1
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: root.stateWord
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
            }

            Row {
                Layout.topMargin: -6
                spacing: 0
                StyledText {
                    text: String(Battery.percent)
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 780, "wdth": 35, "ROND": 100 })
                    font.pixelSize: Math.round(Math.min(150, root.heroHeight * 0.46))
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Math.round(root.heroHeight * 0.07)
                    text: "%"
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 600, "wdth": 60, "ROND": 100 })
                    font.pixelSize: Math.round(Math.min(48, root.heroHeight * 0.15))
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.7
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.stateDetail
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
        }

        // health figures, bottom-left, over the fill
        Flow {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 16
            }
            spacing: 6

            FigurePill {
                visible: Math.abs(Battery.energyRate) > 0.05
                symbol: Battery.isCharging ? "arrow_upward" : "arrow_downward"
                label: `${Math.abs(Battery.energyRate).toFixed(1)} W`
            }
            FigurePill {
                visible: Battery.health > 0
                symbol: "favorite"
                label: Translation.tr("%1 % health").arg(Math.round(Battery.health))
            }
            FigurePill {
                visible: Battery.cycles >= 0
                symbol: "autorenew"
                label: Translation.tr("%1 cycles").arg(Battery.cycles)
            }
        }
    }

    // ── today ──
    BatteryTodayCard {
        id: chartCard
        x: root.wide ? slab.width + 12 : 0
        y: root.wide ? 0 : slab.height + 12
        width: root.wide ? root.width - slab.width - 12 : root.width
        height: root.wide ? root.heroHeight : implicitHeight
        onClicked: root.detailsRequested()
    }

    component FigurePill: Rectangle {
        id: pill
        property string symbol
        property string label
        implicitHeight: 30
        implicitWidth: pillRow.implicitWidth + 20
        radius: height / 2
        color: Appearance.colors.colSurfaceContainerHigh
        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                text: pill.symbol
                iconSize: Appearance.font.pixelSize.normal
                fill: 1
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                text: pill.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }
        }
    }
}
