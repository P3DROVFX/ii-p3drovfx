pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Search every IANA city and add it. The catalog exists only while this sheet is open:
 * it is asked for on open and dropped on close.
 */
ClockSheet {
    id: root

    property date now: new Date()

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real rowHeight: ClockStyle.topBarHeight
    readonly property real listHeight: Math.max(root.rowHeight * 3, root.height * 0.5)

    readonly property string query: searchField.text.trim().toLowerCase()
    readonly property var results: {
        const catalog = WorldClockService.catalog;
        if (root.query.length === 0)
            return catalog;
        const compact = root.query.replace(/\s+/g, "");
        return catalog.filter(zone => zone.tz.toLowerCase().replace(/_/g, " ").includes(root.query)
            || zone.city.toLowerCase().includes(root.query)
            || zone.abbreviation.toLowerCase() === compact
            || WorldClockService.utcOffsetLabel(zone.offsetMins).toLowerCase().includes(compact));
    }

    function zonedLabel(zone): string {
        const date = new Date(root.now.getTime() + (zone.offsetMins + root.now.getTimezoneOffset()) * 60000);
        return ClockFormat.dateTime(date);
    }

    title: Translation.tr("Add a city")
    scrollable: false
    maxHeightRatio: 0.92

    onOpenedChanged: {
        if (root.opened) {
            WorldClockService.loadCatalog();
            searchField.text = "";
            searchField.forceActiveFocus();
        }
    }
    Component.onDestruction: WorldClockService.releaseCatalog()

    MaterialTextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search a city, region or UTC offset")
        onAccepted: {
            if (root.results.length > 0) {
                WorldClockService.addClock(root.results[0].tz);
                root.close();
            }
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: root.listHeight

        MaterialLoadingIndicator {
            anchors.centerIn: parent
            loading: WorldClockService.catalogLoading
            visible: WorldClockService.catalogLoading
        }

        StyledText {
            anchors.centerIn: parent
            visible: !WorldClockService.catalogLoading && root.results.length === 0
            text: Translation.tr("No city matches")
            color: ClockStyle.colSubtext
        }

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: 2
            model: root.results.length
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: RippleButton {
                id: row
                required property int index
                readonly property var zone: root.results[row.index] ?? ({ tz: "", city: "", region: "", offsetMins: 0 })
                readonly property bool added: WorldClockService.contains(row.zone.tz)

                width: list.width
                implicitHeight: root.rowHeight
                buttonRadius: ClockStyle.radiusNormal
                buttonRadiusPressed: ClockStyle.radiusSmall
                colBackground: row.added ? ClockStyle.colSecondaryContainer : "transparent"
                colBackgroundHover: row.added ? ClockStyle.colSecondaryContainerHover : ClockStyle.colSurfaceHover
                colRipple: ClockStyle.colSurfaceActive
                onClicked: {
                    if (!row.added)
                        WorldClockService.addClock(row.zone.tz);
                    root.close();
                }

                contentItem: RowLayout {
                    spacing: ClockStyle.gapLarge

                    MaterialSymbol {
                        Layout.leftMargin: ClockStyle.gapSmall
                        text: row.added ? "check_circle" : "location_on"
                        fill: row.added ? 1 : 0
                        iconSize: ClockStyle.iconNormal
                        color: row.added ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.zone.city
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal + 1
                            color: ClockStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: row.zone.region + " · " + WorldClockService.utcOffsetLabel(row.zone.offsetMins)
                                + (row.zone.abbreviation && !/^[+-]/.test(row.zone.abbreviation) ? " · " + row.zone.abbreviation : "")
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textSmall
                            color: ClockStyle.colSubtext
                        }
                    }

                    StyledText {
                        Layout.rightMargin: ClockStyle.gapSmall
                        text: root.zonedLabel(row.zone)
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: ClockStyle.textTitle
                        color: ClockStyle.colOnSurface
                    }
                }
            }
        }
    }
}
