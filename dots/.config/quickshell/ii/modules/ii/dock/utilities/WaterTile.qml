import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Water: one glass at a time, the goal of the day, and the week on the card.
 * A click adds a glass (the menu takes one back). Square: the tile is the
 * glass — water rises to the share of the goal, the count stands in it. Wide:
 * the glass, "3 / 8" over the millilitres, and the last seven days as bars.
 */
UtilityTile {
    id: tile

    readonly property int glasses: WaterReminderService.glassesDrunk
    readonly property int goal: Math.max(1, WaterReminderService.dailyGoal)
    readonly property real level: Math.min(1, tile.glasses / tile.goal)
    readonly property bool reached: tile.glasses >= tile.goal
    readonly property int glassMl: Config.options?.dock?.utilities?.water?.glassMl ?? 250
    readonly property var week: { WaterReminderService.history; tile.glasses; return WaterReminderService.week(); }

    function activate() {
        WaterReminderService.drink(1);
        return true;
    }
    function menuAction(actionId) {
        if (actionId === "undo")
            WaterReminderService.drink(-1);
    }

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: Translation.tr("Water · %1 of %2 glasses · click to add one").arg(tile.glasses).arg(tile.goal)
    panelSubtitle: Translation.tr("%1 of %2 glasses · %3 ml").arg(tile.glasses).arg(tile.goal).arg(tile.glasses * tile.glassMl)
    menuActions: [
        { id: "undo", icon: "undo", text: Translation.tr("Take one back"), visible: tile.glasses > 0 }
    ]

    // The glass: a well that fills from the bottom, the count standing in it.
    component Glass: Item {
        id: glass
        property real cornerRadius: 10
        Rectangle {
            anchors.fill: parent
            radius: glass.cornerRadius
            color: ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.14)
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * tile.level
            visible: height > 1
            color: ClockStyle.colPrimary
            bottomLeftRadius: Math.min(glass.cornerRadius, height)
            bottomRightRadius: Math.min(glass.cornerRadius, height)
            topLeftRadius: tile.level >= 0.999 ? glass.cornerRadius : Math.min(3, height / 2)
            topRightRadius: tile.level >= 0.999 ? glass.cornerRadius : Math.min(3, height / 2)
            Behavior on height {
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }
        }
        TileValue {
            anchors.centerIn: parent
            visible: !tile.reached
            text: String(tile.glasses)
            // Ink that reads over both the empty well and the water.
            color: tile.level > 0.5 ? ClockStyle.colOnPrimary : ClockStyle.colPrimary
            font.pixelSize: Math.round(glass.height * 0.5)
        }
        TileSymbol {
            anchors.centerIn: parent
            visible: tile.reached
            text: "water_full"
            iconSize: Math.round(glass.height * 0.52)
            fill: 1
            color: ClockStyle.colOnPrimary
        }
    }

    // ── Square ──────────────────────────────────────────────────────────
    Glass {
        visible: !tile.wide
        anchors.fill: parent
        anchors.margins: Math.round(tile.side * 0.1)
        cornerRadius: Math.max(4, tile.radius - Math.round(tile.side * 0.1))
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        anchors.rightMargin: tile.pad * 1.5
        visible: tile.wide
        spacing: tile.pad

        Glass {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            cornerRadius: Math.max(4, tile.radius - tile.pad)
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: -2
            RowLayout {
                spacing: 1
                TileValue {
                    Layout.alignment: Qt.AlignBaseline
                    text: String(tile.glasses)
                    color: tile.contentColor
                    font.pixelSize: tile.valueSize
                }
                TileValue {
                    Layout.alignment: Qt.AlignBaseline
                    text: "/" + tile.goal
                    color: tile.captionColor
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: Math.round(tile.valueSize * 0.62)
                }
            }
            TileCaption {
                text: Translation.tr("%1 ml").arg(tile.glasses * tile.glassMl)
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }

        // The week: one bar per day against the goal; today in primary.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Math.round(tile.pad * 0.5)
            Layout.bottomMargin: Math.round(tile.pad * 0.5)
            spacing: Math.max(2, Math.round(tile.height * 0.05))
            Repeater {
                model: tile.week
                delegate: Item {
                    id: day
                    required property var modelData
                    required property int index
                    readonly property bool today: day.index === 6
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, Math.round(tile.height * 0.12))
                        height: Math.max(width, parent.height * Math.min(1, day.modelData.glasses / tile.goal))
                        radius: width / 2
                        color: day.modelData.glasses === 0 ? ColorUtils.applyAlpha(tile.contentColor, 0.12)
                            : day.today ? ClockStyle.colPrimary
                            : day.modelData.glasses >= tile.goal ? ClockStyle.colTertiary
                            : ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.45)
                        Behavior on height {
                            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }
}
