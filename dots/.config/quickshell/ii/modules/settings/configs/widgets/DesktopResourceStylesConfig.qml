pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.utility
import qs.modules.settings.configs.widgets

/*
 * One page for the Resource Columns and Resource Tiles widgets. The hero is
 * both real widgets, live, in their current orientation and with the metrics
 * picked below; each section picks, orders and lays out its own metrics.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets
    readonly property var columnsOptions: root.widgets.resource_columns
    readonly property var tilesOptions: root.widgets.resource_tiles
    readonly property var allMetrics: ["cpu", "ram", "swap", "disk", "gpu", "cpuTemp", "gpuTemp", "battery"]

    function placementNote(widgetId) {
        const count = Config.countWidgetInstances(widgetId);
        if (count === 0)
            return Translation.tr("Not on the desktop. Add it from Desktop Widgets; these options apply once it is there.");
        return count === 1 ? Translation.tr("On the desktop.") : Translation.tr("On the desktop %1 times.").arg(count);
    }

    // Labels and icons for the editor, without a live widget to ask.
    ResourceMetricSource {
        id: catalog
        active: false
    }

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Resource Styles Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Live preview ──
    Rectangle {
        id: stage
        Layout.fillWidth: true
        implicitHeight: previewColumn.height + stage.padding * 2
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        readonly property real padding: 20
        readonly property real innerWidth: stage.width - stage.padding * 2
        // Tall arrangements are capped, so a vertical stack of eight never fills the page.
        readonly property real maxPreviewHeight: 420

        Column {
            id: previewColumn
            x: stage.padding
            y: stage.padding
            width: stage.innerWidth
            spacing: 20

            PreviewSlot {
                sourceWidth: columnsPreview.implicitWidth
                sourceHeight: columnsPreview.implicitHeight

                ResourceColumnsWidget {
                    id: columnsPreview
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.fitScale
                }
            }

            PreviewSlot {
                sourceWidth: tilesPreview.implicitWidth
                sourceHeight: tilesPreview.implicitHeight

                ResourceTilesWidget {
                    id: tilesPreview
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.fitScale
                }
            }
        }
    }

    // ── Resource Columns ──
    ContentSection {
        title: Translation.tr("Resource Columns")
        icon: "bar_chart"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.placementNote("resource_columns")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ContentSubsectionLabel {
                text: Translation.tr("Orientation")
            }

            ConfigSelectionArray {
                currentValue: root.columnsOptions.orientation ?? "horizontal"
                onSelected: value => root.columnsOptions.orientation = value
                options: [
                    { displayName: Translation.tr("Columns"), icon: "view_column", value: "horizontal" },
                    { displayName: Translation.tr("Rows"), icon: "view_stream", value: "vertical" }
                ]
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: root.columnsOptions.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: root.columnsOptions.widgetSize = value
            }

            ConfigSwitch {
                buttonIcon: "label"
                text: Translation.tr("Labels")
                checked: root.columnsOptions.showLabels ?? true
                onCheckedChanged: root.columnsOptions.showLabels = checked
                StyledToolTip {
                    text: Translation.tr("Name each metric under its figure.")
                }
            }

            MetricsEditor {
                Layout.fillWidth: true
                options: root.columnsOptions
            }
        }
    }

    // ── Resource Tiles ──
    ContentSection {
        title: Translation.tr("Resource Tiles")
        icon: "grid_view"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.placementNote("resource_tiles")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ContentSubsectionLabel {
                text: Translation.tr("Orientation")
            }

            ConfigSelectionArray {
                currentValue: root.tilesOptions.orientation ?? "horizontal"
                onSelected: value => root.tilesOptions.orientation = value
                options: [
                    { displayName: Translation.tr("Row"), icon: "view_column", value: "horizontal" },
                    { displayName: Translation.tr("Column"), icon: "view_stream", value: "vertical" }
                ]
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: root.tilesOptions.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: root.tilesOptions.widgetSize = value
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "interests"
                    text: Translation.tr("Ornament")
                    checked: root.tilesOptions.showOrnament ?? true
                    onCheckedChanged: root.tilesOptions.showOrnament = checked
                    StyledToolTip {
                        text: Translation.tr("Park each metric's shape, large and faint, in the corner of its tile.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "notes"
                    text: Translation.tr("Details")
                    checked: root.tilesOptions.showDetail ?? true
                    onCheckedChanged: root.tilesOptions.showDetail = checked
                    StyledToolTip {
                        text: Translation.tr("Show a second line such as used and total memory, or the temperature.")
                    }
                }
            }

            MetricsEditor {
                Layout.fillWidth: true
                options: root.tilesOptions
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }

    // A full-width row of the stage that scales one widget down to fit it.
    component PreviewSlot: Item {
        property real sourceWidth: 1
        property real sourceHeight: 1
        readonly property real fitScale: Math.min(1, width / Math.max(1, sourceWidth), stage.maxPreviewHeight / Math.max(1, sourceHeight))
        width: previewColumn.width
        height: Math.round(sourceHeight * fitScale)
    }

    // The picked metrics in order (move, remove) and the ones left to add.
    component MetricsEditor: ColumnLayout {
        id: editor

        property var options
        readonly property var picked: (editor.options?.items ?? []).filter(key => root.allMetrics.indexOf(key) !== -1)
        readonly property var available: root.allMetrics.filter(key => editor.picked.indexOf(key) === -1)

        function write(list) {
            editor.options.items = list;
        }
        function move(index, delta) {
            const list = editor.picked.slice();
            const target = index + delta;
            if (target < 0 || target >= list.length)
                return;
            const item = list.splice(index, 1)[0];
            list.splice(target, 0, item);
            editor.write(list);
        }
        function remove(index) {
            if (editor.picked.length <= 1)
                return;
            const list = editor.picked.slice();
            list.splice(index, 1);
            editor.write(list);
        }
        function add(key) {
            editor.write(editor.picked.concat([key]));
        }

        spacing: 4

        ContentSubsectionLabel {
            text: Translation.tr("Shown resources")
        }

        Repeater {
            model: editor.picked

            delegate: Rectangle {
                id: row
                required property string modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 10

                    MaterialShapeWrappedMaterialSymbol {
                        implicitSize: 32
                        padding: 0
                        shape: catalog.shape(row.modelData)
                        text: catalog.icon(row.modelData)
                        iconSize: 18
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: catalog.label(row.modelData)
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        elide: Text.ElideRight
                    }

                    EditorIconButton {
                        symbol: "arrow_upward"
                        enabled: row.index > 0
                        tip: Translation.tr("Move earlier")
                        onClicked: editor.move(row.index, -1)
                    }
                    EditorIconButton {
                        symbol: "arrow_downward"
                        enabled: row.index < editor.picked.length - 1
                        tip: Translation.tr("Move later")
                        onClicked: editor.move(row.index, 1)
                    }
                    EditorIconButton {
                        symbol: "close"
                        enabled: editor.picked.length > 1
                        tip: Translation.tr("Remove")
                        onClicked: editor.remove(row.index)
                    }
                }
            }
        }

        ContentSubsectionLabel {
            visible: editor.available.length > 0
            text: Translation.tr("Add")
        }

        Flow {
            Layout.fillWidth: true
            visible: editor.available.length > 0
            spacing: 6

            Repeater {
                model: editor.available

                delegate: RippleButton {
                    id: chip
                    required property string modelData

                    implicitHeight: 36
                    implicitWidth: chipRow.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: editor.add(chip.modelData)

                    contentItem: Item {
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "add"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: catalog.label(chip.modelData)
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    component EditorIconButton: RippleButton {
        id: iconButton
        property string symbol
        property string tip
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        contentItem: MaterialSymbol {
            text: iconButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: iconButton.tip
        }
    }
}
