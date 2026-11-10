pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * World clocks shown in the bar's clock popup and the Clock app. Each city is a
 * row with its live time, an inline-editable name and the offset to local time;
 * cities are added from a search over the IANA catalog (WorldClockService),
 * which is only loaded while the search field is in use.
 */
Rectangle {
    id: root

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    implicitHeight: content.implicitHeight + 40

    readonly property date now: DateTime.clock.date
    readonly property var clocks: WorldClockService.clocks
    readonly property string query: searchBox.text.trim().toLowerCase()
    readonly property var results: {
        if (root.query.length === 0)
            return [];
        const compact = root.query.replace(/\s+/g, "");
        return WorldClockService.catalog.filter(zone => !WorldClockService.contains(zone.tz)
            && (zone.tz.toLowerCase().replace(/_/g, " ").includes(root.query)
                || zone.city.toLowerCase().includes(root.query)
                || zone.abbreviation.toLowerCase() === compact
                || WorldClockService.utcOffsetLabel(zone.offsetMins).toLowerCase().includes(compact))).slice(0, 5);
    }
    property bool catalogHeld: false

    function addResult(zone) {
        if (!zone)
            return;
        WorldClockService.addClock(zone.tz);
        searchBox.text = "";
    }

    function rowCorner(index, count, top) {
        const outer = Appearance.rounding.large;
        const inner = Appearance.rounding.verysmall;
        if (top)
            return index === 0 ? outer : inner;
        return index === count - 1 ? outer : inner;
    }

    Component.onCompleted: WorldClockService.retain()
    Component.onDestruction: {
        WorldClockService.release();
        if (root.catalogHeld)
            WorldClockService.releaseCatalog();
    }
    onClocksChanged: WorldClockService.refresh()

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        spacing: 16

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                text: "public"
                iconSize: 24
                padding: 12
                shape: MaterialShape.Shape.Cookie12Sided
                color: Appearance.colors.colTertiaryContainer
                colSymbol: Appearance.colors.colOnTertiaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: Translation.tr("World clocks")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.clocks.length === 0
                        ? Translation.tr("Add cities to see their time in the clock popup")
                        : Translation.tr("%1 cities · shown in the clock popup and the Clock app").arg(root.clocks.length)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // the cities
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.clocks.length > 0
            spacing: 3

            Repeater {
                model: root.clocks
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string tz: String(modelData?.tz ?? "")
                    readonly property string meridiem: WorldClockService.meridiem(row.tz, root.now)
                    readonly property string relative: WorldClockService.relativeOffsetLabel(row.tz, root.now)

                    Layout.fillWidth: true
                    implicitHeight: 76
                    color: rowHover.hovered || nameInput.activeFocus ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHighest
                    topLeftRadius: root.rowCorner(row.index, root.clocks.length, true)
                    topRightRadius: root.rowCorner(row.index, root.clocks.length, true)
                    bottomLeftRadius: root.rowCorner(row.index, root.clocks.length, false)
                    bottomRightRadius: root.rowCorner(row.index, root.clocks.length, false)
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                    HoverHandler { id: rowHover }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 20
                            rightMargin: 12
                        }
                        spacing: 16

                        // live time
                        RowLayout {
                            Layout.preferredWidth: 112
                            Layout.minimumWidth: 112
                            Layout.maximumWidth: 112
                            spacing: 4
                            StyledText {
                                text: WorldClockService.formatHourMinute(row.tz, root.now)
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: 30
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                visible: row.meridiem.length > 0
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 5
                                text: row.meridiem
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        // name + details
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: nameInput.implicitHeight

                                StyledTextInput {
                                    id: nameInput
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    text: String(row.modelData?.name ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnSurface
                                    clip: true
                                    onEditingFinished: {
                                        if (text.trim() !== String(row.modelData?.name ?? "").trim())
                                            WorldClockService.renameClock(row.index, text);
                                    }
                                }
                                StyledText {
                                    anchors.verticalCenter: nameInput.verticalCenter
                                    visible: nameInput.text.length === 0
                                    text: WorldClockService.cityFromZone(row.tz)
                                    font: nameInput.font
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: [
                                    WorldClockService.regionFromZone(row.tz),
                                    WorldClockService.dayRelationLabel(row.tz, root.now),
                                    row.relative.length > 0 ? row.relative : Translation.tr("Same time")
                                ].filter(part => part.length > 0).join(" · ")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        RippleButton {
                            implicitWidth: 40
                            implicitHeight: 40
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestActive
                            colRipple: Appearance.colors.colSurfaceContainerHighestActive
                            onClicked: nameInput.forceActiveFocus()
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "edit"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip {
                                text: Translation.tr("Rename")
                            }
                        }
                        RippleButton {
                            implicitWidth: 40
                            implicitHeight: 40
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestActive
                            colRipple: Appearance.colors.colSurfaceContainerHighestActive
                            onClicked: WorldClockService.removeClock(row.index)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "delete"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip {
                                text: Translation.tr("Remove")
                            }
                        }
                    }
                }
            }
        }

        // add a city
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            FilledField {
                id: searchBox
                Layout.fillWidth: true
                symbol: WorldClockService.catalogLoading ? "progress_activity" : "add_location_alt"
                placeholder: Translation.tr("Add a city · search by city, region or UTC offset")
                attachedBelow: root.results.length > 0
                onAccepted: root.addResult(root.results[0])
                onFocusedChanged: {
                    if (focused && !root.catalogHeld) {
                        root.catalogHeld = true;
                        WorldClockService.loadCatalog();
                    }
                }
            }

            Repeater {
                model: root.results
                delegate: RippleButton {
                    id: result
                    required property var modelData
                    required property int index
                    readonly property bool last: index === root.results.length - 1

                    Layout.fillWidth: true
                    implicitHeight: 52
                    buttonRadius: Appearance.rounding.verysmall
                    bottomLeftRadius: result.last ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomRightRadius: result.last ? Appearance.rounding.large : Appearance.rounding.verysmall
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.addResult(modelData)

                    contentItem: Item {
                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 20
                                rightMargin: 18
                            }
                            spacing: 12
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: result.modelData.city
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: result.modelData.region
                                    visible: text.length > 0
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }
                            StyledText {
                                text: WorldClockService.utcOffsetLabel(result.modelData.offsetMins)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "add"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }
    }
}
