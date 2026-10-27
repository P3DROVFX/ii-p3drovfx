pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Daily Limits (2x1): how much is left of each limit set in Usage → Daily
 * limits. One row per limit that applies today - the app (or the screen for
 * the total), the time left in condensed digits, and a bar that fills as the
 * budget is spent, turning to the warning colour in its last minutes and
 * folding into a stripe once spent. With no limits yet, the rows are today's
 * biggest apps against the biggest one, and the header offers to set one.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "wellbeing_limits"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 16
    readonly property int maxRows: 3

    readonly property var rules: {
        void ScreenTimeLimits.revision;
        return ScreenTimeLimits.limits.filter(rule => ScreenTimeLimits.appliesToday(rule)).slice(0, root.maxRows);
    }
    readonly property bool hasRules: root.rules.length > 0
    readonly property var topApps: ScreenTimeLimits.todayApps().slice(0, root.maxRows)
    // Rows in one shape: { key, name, used, budget (0 = none), state }.
    readonly property var rows: root.hasRules
        ? root.rules.map(rule => ({
            key: rule.kind === "total" ? "" : String((rule.keys ?? [])[0] ?? ""),
            name: rule.kind === "total" ? Translation.tr("All apps")
                : (rule.name || AppStats.displayName(String((rule.keys ?? [])[0] ?? ""))),
            used: ScreenTimeLimits.usedFor(rule),
            budget: ScreenTimeLimits.budgetFor(rule),
            state: ScreenTimeLimits.stateFor(rule)
        }))
        : root.topApps.map(app => ({
            key: app.key, name: AppStats.displayName(app.key), used: app.seconds,
            budget: root.topApps[0]?.seconds ?? 1, state: "none"
        }))

    Component.onCompleted: ScreenTimeLimits.watch(true)
    Component.onDestruction: ScreenTimeLimits.watch(false)

    function fillColor(state) {
        if (state === "warn")
            return WidgetColorScheme.warningColor;
        if (state === "reached" || state === "ignored")
            return WidgetColorScheme.subtextColorOnBg;
        return WidgetColorScheme.accentColor;
    }

    // ── Header ──
    Item {
        id: header
        x: root.padding
        y: root.padding
        width: root.designWidth - root.padding * 2
        height: 34

        MaterialSymbol {
            id: headerGlyph
            anchors.verticalCenter: parent.verticalCenter
            text: "hourglass_top"
            iconSize: 22
            fill: 1
            color: WidgetColorScheme.accentColor
        }
        StyledText {
            anchors.left: headerGlyph.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: root.hasRules ? Translation.tr("Daily limits") : Translation.tr("Today's apps")
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.variableAxes: Appearance.font.variableAxes.titleRounded
        }
        WidgetButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: actionLabel.implicitWidth + 50
            height: 32
            symbol: root.hasRules ? "tune" : "add"
            symbolSize: 16
            label: root.hasRules ? Translation.tr("Edit") : Translation.tr("Set a limit")
            labelSize: Appearance.font.pixelSize.smaller
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: if (root.actionsEnabled) GlobalStates.openUsageApp("limits")

            StyledText {
                id: actionLabel
                visible: false
                text: parent.label
                font.pixelSize: parent.labelSize
            }
        }
    }

    // ── Rows ──
    Column {
        x: root.padding
        anchors.top: header.bottom
        anchors.topMargin: 10
        width: root.designWidth - root.padding * 2
        spacing: 8

        Repeater {
            model: root.rows

            delegate: Item {
                id: row
                required property var modelData
                readonly property real progress: row.modelData.budget > 0 ? Math.min(1, row.modelData.used / row.modelData.budget) : 0
                readonly property bool spent: row.modelData.state === "reached" || row.modelData.state === "ignored"
                width: parent.width
                height: 50

                Rectangle {
                    id: iconPlate
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: Appearance.rounding.normal
                    color: WidgetColorScheme.pillBgColor

                    WellbeingAppIcon {
                        anchors.centerIn: parent
                        visible: row.modelData.key.length > 0
                        appKey: row.modelData.key
                        size: 28
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: row.modelData.key.length === 0
                        text: "desktop_windows"
                        iconSize: 22
                        color: WidgetColorScheme.textColorOnBg
                    }
                }

                StyledText {
                    id: nameText
                    anchors.left: iconPlate.right
                    anchors.leftMargin: 12
                    anchors.right: valueText.left
                    anchors.rightMargin: 8
                    y: 4
                    elide: Text.ElideRight
                    text: row.modelData.name
                    color: WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
                }

                StyledText {
                    id: valueText
                    anchors.right: parent.right
                    anchors.baseline: nameText.baseline
                    text: row.modelData.state === "none"
                        ? ScreenTimeLimits.formatSeconds(row.modelData.used)
                        : row.spent ? Translation.tr("Time's up")
                        : Translation.tr("%1 left").arg(ScreenTimeLimits.formatSeconds(row.modelData.budget - row.modelData.used))
                    color: row.modelData.state === "warn" ? WidgetColorScheme.warningColor : WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 15
                    font.variableAxes: ({ "wght": 750, "wdth": 70, "ROND": 100 })
                }

                // The budget: a track that fills; spent, it folds into a stripe.
                Rectangle {
                    id: track
                    anchors.left: nameText.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    height: row.spent ? 4 : 12
                    radius: root.pill(height)
                    color: WidgetColorScheme.pillBgColor
                    Behavior on height {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }

                    Rectangle {
                        width: Math.max(track.height, track.width * row.progress)
                        height: track.height
                        radius: track.radius
                        color: root.fillColor(row.modelData.state)
                        Behavior on width {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }

    StyledText {
        visible: root.rows.length === 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 18
        text: Translation.tr("No screen time yet today")
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.normal
        font.variableAxes: ({ "wght": 450, "wdth": 100, "slnt": -10, "ROND": 100 })
    }
}
