pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Choosing apps by window class, inside a side sheet: a search row, then the apps worth
 * offering — today's, the week's, whatever has a window open, and on a search every
 * installed app — each a filled row that turns secondary when picked.
 *
 * Keys are window classes because that is what AppStats records and what a limit is
 * matched against; an installed app is offered under its StartupWMClass.
 */
ColumnLayout {
    id: root

    property var selected: []
    property int maxRows: 8
    property string query: search.text.trim().toLowerCase()

    signal toggled(string key)

    spacing: 6

    readonly property var weekKeys: {
        const summary = AppStats.summarize(AppStats.recentDates(7), { headless: false });
        return summary.apps.filter(r => r.fg > 0).map(r => r.key);
    }

    readonly property var candidates: {
        const seen = ({});
        const out = [];
        const today = ({});
        for (const e of ScreenTimeLimits.todayApps())
            today[e.key] = e.seconds;
        const add = key => {
            if (!key || seen[key] || key === AppStats.systemKey)
                return;
            seen[key] = true;
            out.push({ key: key, seconds: today[key] ?? 0, name: AppStats.displayName(key) });
        };
        for (const key of root.selected)
            add(key);
        for (const key in today)
            add(key);
        for (const key of root.weekKeys)
            add(key);
        for (const key of ScreenTimeLimits.openKeys())
            add(key);
        if (root.query.length > 0) {
            for (const entry of DesktopEntries.applications.values) {
                if (entry.noDisplay)
                    continue;
                const key = String(entry.startupClass || entry.id || "").replace(/\.desktop$/, "");
                if (String(entry.name).toLowerCase().includes(root.query) || key.toLowerCase().includes(root.query))
                    add(key);
            }
        }
        // Picked apps stay in view whatever the search, so they can be unpicked.
        const q = root.query;
        const filtered = q.length === 0 ? out : out.filter(c => root.selected.includes(c.key) || c.name.toLowerCase().includes(q) || c.key.toLowerCase().includes(q));
        return filtered.slice(0, Math.max(root.maxRows, root.selected.length));
    }

    ClockFormField {
        id: search
        symbol: "search"
        shapeKind: MaterialShape.Shape.Cookie12Sided
        caption: Translation.tr("Apps")
        placeholder: Translation.tr("Search apps")
    }

    Repeater {
        model: root.candidates

        Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool picked: root.selected.includes(row.modelData.key)

            Layout.fillWidth: true
            implicitHeight: 52
            // One grouped shape: outer corners large, the joins between rows small.
            topLeftRadius: row.index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
            topRightRadius: topLeftRadius
            bottomLeftRadius: row.index === root.candidates.length - 1 ? Appearance.rounding.small : Appearance.rounding.verysmall
            bottomRightRadius: bottomLeftRadius
            color: row.picked ? ClockStyle.colSecondaryContainer
                : rowPointer.containsMouse ? ClockStyle.colFieldHover : ClockStyle.colField

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            MouseArea {
                id: rowPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggled(row.modelData.key)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                LimitsAppIcon {
                    size: 28
                    appKey: row.modelData.key
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: row.picked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.seconds > 0
                            ? Translation.tr("%1 today").arg(ScreenTimeLimits.formatSeconds(row.modelData.seconds))
                            : row.modelData.key
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: row.picked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                        opacity: 0.85
                        elide: Text.ElideRight
                    }
                }

                // Picked: a filled cookie with a check; not picked: a faint plus.
                Item {
                    implicitWidth: 28
                    implicitHeight: 28

                    MaterialShapeWrappedMaterialSymbol {
                        anchors.centerIn: parent
                        visible: row.picked
                        implicitSize: 28
                        text: "check"
                        iconSize: 16
                        padding: 6
                        shape: MaterialShape.Shape.Cookie7Sided
                        color: ClockStyle.colOnSecondaryContainer
                        colSymbol: ClockStyle.colSecondaryContainer
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: !row.picked
                        width: 26
                        height: 26
                        radius: 13
                        color: ColorUtils.applyAlpha(ClockStyle.colOnSurface, rowPointer.containsMouse ? 0.14 : 0.08)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "add"
                            iconSize: 16
                            color: ClockStyle.colOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    StyledText {
        visible: root.candidates.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 4
        horizontalAlignment: Text.AlignHCenter
        text: Translation.tr("No app matches")
        font.pixelSize: Appearance.font.pixelSize.small
        color: ClockStyle.colSubtext
    }
}
