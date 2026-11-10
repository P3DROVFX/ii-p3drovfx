pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Search every IANA city and add it, in the side sheet. The catalog exists only while
 * this sheet does: it is asked for when the sheet is built and dropped with it.
 */
ClockSheet {
    id: root

    property date now: new Date()

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real rowHeight: 60

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
    subtitle: Translation.tr("%1 cities").arg(String(WorldClockService.clocks.length))
    scrollable: false

    Component.onCompleted: {
        WorldClockService.loadCatalog();
        Qt.callLater(searchField.focusInput);
    }
    Component.onDestruction: WorldClockService.releaseCatalog()

    ClockFormField {
        id: searchField
        symbol: "search"
        shapeKind: MaterialShape.Shape.Cookie9Sided
        caption: Translation.tr("Search")
        placeholder: Translation.tr("City, region or UTC offset")
        onAccepted: {
            if (root.results.length > 0) {
                WorldClockService.addClock(root.results[0].tz);
                root.close();
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

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

            TouchpadScrollHandler {
                flickable: list
            }

            delegate: RippleButton {
                id: row
                required property int index
                readonly property var zone: root.results[row.index] ?? ({ tz: "", city: "", region: "", offsetMins: 0 })
                readonly property bool added: WorldClockService.contains(row.zone.tz)

                width: list.width
                implicitHeight: root.rowHeight
                buttonRadius: Appearance.rounding.small
                buttonRadiusPressed: Appearance.rounding.normal
                colBackground: row.added ? ClockStyle.colSecondaryContainer : ClockStyle.colField
                colBackgroundHover: row.added ? ClockStyle.colSecondaryContainerHover : ClockStyle.colFieldHover
                colRipple: ClockStyle.colSurfaceActive
                onClicked: {
                    if (!row.added)
                        WorldClockService.addClock(row.zone.tz);
                    root.close();
                }

                contentItem: RowLayout {
                    spacing: ClockStyle.gap

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.leftMargin: 4
                        text: row.added ? "check" : "location_on"
                        iconSize: 16
                        padding: 8
                        fill: row.added ? 1 : 0
                        shape: row.added ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
                        color: row.added ? ClockStyle.colTertiary : ClockStyle.colPrimaryContainer
                        colSymbol: row.added ? ClockStyle.colOnTertiary : ClockStyle.colOnPrimaryContainer
                        rotation: row.hovered ? 20 : 0
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
                        font.pixelSize: ClockStyle.textLarge + 2
                        color: row.added ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                    }
                }
            }
        }
    }
}
