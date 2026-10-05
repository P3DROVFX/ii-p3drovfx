pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.core
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.island
import "../island/IslandCatalog.js" as Catalog

/**
 * Every island activity, with the island itself on top of them.
 *
 * The stage never scrolls away: it shows the activity under the pointer (a try-on),
 * or the one last pressed, drawn by its real face at its real size; with nothing
 * chosen it is the island at rest. Under it, one filter at a time and the activities
 * as tiles - glyph, name, where it shows right now, switch.
 *
 * The switches write the same floatingNotch flags as always. Search indexes the
 * proxy in sections/DynamicIslandActivitiesSection.qml, which keeps the plain
 * switches for the results.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var fn: Config.options.bar.floatingNotch
    readonly property bool islandOn: IslandPolicy.enabled

    // ── Which activity is on the stage ─────────────────────────────────
    property string selectedId: ""
    property string hoverId: ""
    /** The presentation chosen for the pressed activity; "" = where it lives first. */
    property string chosenPresentation: ""
    property string filter: "all"

    readonly property string stageId: root.hoverId !== "" ? root.hoverId : root.selectedId
    readonly property var stageEntry: Catalog.byId(root.stageId)
    readonly property string stagePresentation: {
        if (root.stageId === "")
            return "island";
        if (root.hoverId === "" && root.chosenPresentation !== ""
                && stage.presentationsOf(root.stageId).indexOf(root.chosenPresentation) !== -1)
            return root.chosenPresentation;
        return stage.defaultPresentationOf(root.stageId);
    }

    function select(id) {
        root.chosenPresentation = "";
        root.selectedId = root.selectedId === id ? "" : id;
    }

    // A sweep across the grid should not flash every tile on the stage.
    Timer {
        id: hoverDwell
        property string pending: ""
        interval: 110
        onTriggered: root.hoverId = hoverDwell.pending
    }
    Timer {
        id: hoverRelease
        interval: 260
        onTriggered: root.hoverId = ""
    }
    function tileHovered(id, hovered) {
        if (hovered) {
            hoverRelease.stop();
            hoverDwell.pending = id;
            hoverDwell.restart();
        } else if (hoverDwell.pending === id) {
            hoverDwell.stop();
            hoverDwell.pending = "";
            hoverRelease.restart();
        }
    }

    // ── Config ──────────────────────────────────────────────────────────
    function available(entry) {
        if (entry.needs === "easyEffects")
            return EasyEffects.available;
        return true;
    }
    function isOn(entry) {
        return root.fn[entry.key] !== true;
    }
    function setOn(entry, on) {
        root.fn[entry.key] = !on;
        const widgets = Config.options.dynamicIsland?.widgets;
        if (entry.widget && widgets && widgets[entry.widget])
            widgets[entry.widget].enable = on;
    }
    readonly property var entries: Catalog.activities.filter(entry => root.available(entry))
    function entriesOf(group) {
        return root.entries.filter(entry => entry.group === group);
    }
    function onCount(list) {
        let n = 0;
        for (let i = 0; i < list.length; i++) {
            if (root.isOn(list[i]))
                n++;
        }
        return n;
    }
    readonly property int totalOn: {
        // Read every flag so the count follows them.
        let n = 0;
        for (let i = 0; i < root.entries.length; i++) {
            if (root.fn[root.entries[i].key] !== true)
                n++;
        }
        return n;
    }

    /** Where an activity shows right now, in a few words. */
    function whereOf(entry) {
        const id = entry.id;
        if (stage.bubblesOn && stage.bubbleable(id))
            return Translation.tr("In a bubble beside the island");
        const tier = IslandRegistry.tierOf(id);
        if ((tier === "live" || tier === "ambient") && stage.restSupports(id))
            return Translation.tr("Beside the clock");
        if (!stage.hasFace(id) && stage.restSupports(id))
            return Translation.tr("Beside the clock");
        if (entry.group === "announce")
            return Translation.tr("Flashes in the centre");
        if (entry.group === "alert")
            return Translation.tr("Takes the centre");
        return Translation.tr("In the centre");
    }

    function presentationOptions(id) {
        const list = stage.presentationsOf(id);
        const options = [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] === "island")
                options.push({ value: "island", label: Translation.tr("Centre"), icon: "crop_landscape", shape: "Cookie4Sided" });
            else if (list[i] === "glance")
                options.push(stage.bubblesOn && stage.bubbleable(id)
                    ? { value: "glance", label: Translation.tr("Bubble"), icon: "bubble_chart", shape: "Sunny" }
                    : { value: "glance", label: Translation.tr("Beside clock"), icon: "view_column", shape: "Sunny" });
            else if (list[i] === "card")
                options.push({ value: "card", label: Translation.tr("Card"), icon: "open_in_full", shape: "Square" });
        }
        return options;
    }

    readonly property var tierLabels: ({
        "transient": "Announcement",
        "live": "Live activity",
        "ambient": "Ambient",
        "interrupt": "Interruption",
        "idle": "Resting face"
    })

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin

            RippleButton {
                visible: root.showBackButton
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Island Activities & Glances")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            // The count, in big condensed digits: the one number this page is about.
            RowLayout {
                spacing: 6
                StyledText {
                    text: root.totalOn
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                    font.pixelSize: Math.round(Appearance.font.pixelSize.huge * 1.5)
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("of %1\non").arg(root.entries.length)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    lineHeight: 0.9
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── The stage ────────────────────────────────────────────────────
        Rectangle {
            id: stagePane
            Layout.fillWidth: true
            implicitHeight: stageColumn.implicitHeight + 24
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            readonly property bool narrow: width < 620

            ColumnLayout {
                id: stageColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 14

                IslandPreviewStage {
                    id: stage
                    Layout.fillWidth: true
                    // As short as what is on it, with room for the pills in its corners. The
                    // floor holds every compact face, so trying one on from the grid never
                    // moves the grid under the pointer; only a card (chosen above) grows it.
                    minHeight: 140
                    bottomRoom: 50
                    Layout.preferredHeight: Math.min(stage.preferredHeight, Math.max(stage.minHeight, root.height * 0.45))
                    Behavior on Layout.preferredHeight {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    activityId: root.stageId
                    presentation: root.stagePresentation
                    restSideIds: ["weather", "batteryGlance"].filter(id => root.fn[Catalog.byId(id).key] !== true)
                    activityOn: !root.stageEntry || root.isOn(root.stageEntry)
                    islandOn: root.islandOn

                    // Overlays: what the stage shows is real or an example; how to open the card.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 12
                        visible: root.stageId !== ""
                        height: 30
                        width: dataRow.implicitWidth + 22
                        radius: height / 2
                        color: Appearance.colors.colSurfaceContainerHigh
                        RowLayout {
                            id: dataRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                visible: !stage.showsExample
                                width: 7
                                height: 7
                                radius: 3.5
                                color: Appearance.colors.colPrimary
                            }
                            MaterialSymbol {
                                visible: stage.showsExample
                                text: "science"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                text: stage.showsExample ? Translation.tr("Example")
                                    : stage.plan.kind === "rest" ? Translation.tr("Live · shows while active")
                                    : Translation.tr("Live")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        readonly property bool wanted: root.stageId !== ""
                            && stage.presentationsOf(root.stageId).indexOf("card") !== -1
                            && root.stagePresentation !== "card"
                        opacity: wanted && !stage.peeking ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        height: 30
                        width: hintRow.implicitWidth + 22
                        radius: height / 2
                        color: Appearance.colors.colSurfaceContainerHigh
                        RowLayout {
                            id: hintRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "touch_app"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                text: Translation.tr("Rest the pointer on it to open its card")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }

                // What is on the stage, and how else it can show.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 4
                    columns: stagePane.narrow ? 1 : 2
                    columnSpacing: 16
                    rowSpacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        MaterialShapeWrappedMaterialSymbol {
                            id: stageGlyph
                            Layout.alignment: Qt.AlignTop
                            text: root.stageEntry ? root.stageEntry.icon : (root.islandOn ? "water_drop" : "water_drop")
                            iconSize: 24
                            padding: 12
                            fill: 1
                            shape: root.stageEntry ? stageGlyph.getShape(root.stageEntry.shape) : MaterialShape.Shape.Cookie9Sided
                            color: Appearance.colors.colPrimaryContainer
                            colSymbol: Appearance.colors.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                StyledText {
                                    id: stageTitle
                                    Layout.fillWidth: true
                                    // The natural width, measured apart: the elided text's own
                                    // implicit width shrinks with it and would keep it elided.
                                    Layout.maximumWidth: Math.ceil(stageTitleMetrics.advanceWidth) + 2
                                    TextMetrics {
                                        id: stageTitleMetrics
                                        font: stageTitle.font
                                        text: stageTitle.text
                                    }
                                    text: root.stageEntry ? Translation.tr(root.stageEntry.label)
                                        : (root.islandOn ? Translation.tr("The island at rest") : Translation.tr("The island is off"))
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                                // The tier, in a different voice from the title: small caps-ish, wide.
                                StyledText {
                                    visible: root.stageEntry !== null
                                    text: root.stageEntry ? Translation.tr(root.tierLabels[IslandRegistry.tierOf(root.stageId)] ?? "").toUpperCase() : ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Black
                                    font.letterSpacing: 1.2
                                    color: Appearance.colors.colTertiary
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: implicitWidth
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (!root.islandOn)
                                        return Translation.tr("Turn the island on in the page before to see these on it.");
                                    if (!root.stageEntry)
                                        return Translation.tr("Point at an activity below to try it on the island; press it to keep it here.");
                                    return Translation.tr(root.stageEntry.tip);
                                }
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: stagePane.narrow ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
                        Layout.fillWidth: stagePane.narrow
                        spacing: 8

                        IslandSegmentedToggle {
                            id: presentationToggle
                            Layout.fillWidth: stagePane.narrow
                            Layout.preferredWidth: stagePane.narrow ? -1 : Math.max(implicitWidth, 300)
                            visible: options.length > 1
                            options: root.stageId !== "" ? root.presentationOptions(root.stageId) : []
                            currentValue: root.stagePresentation
                            onSelected: value => {
                                // Choosing a presentation keeps the activity on the stage.
                                if (root.selectedId !== root.stageId)
                                    root.selectedId = root.stageId;
                                root.chosenPresentation = value;
                            }
                        }

                        RippleButton {
                            Layout.alignment: Qt.AlignRight
                            visible: root.stageEntry !== null && !root.isOn(root.stageEntry)
                            implicitHeight: 40
                            implicitWidth: turnOnRow.implicitWidth + 32
                            buttonRadius: height / 2
                            buttonRadiusPressed: Appearance.rounding.small
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            onClicked: root.setOn(root.stageEntry, true)
                            contentItem: Item {
                                RowLayout {
                                    id: turnOnRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "power_settings_new"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    StyledText {
                                        text: Translation.tr("Turn on")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Filters: one set at a time ───────────────────────────────────
        Flow {
            id: chipRow
            Layout.fillWidth: true
            spacing: 8

            ColorsChip {
                // A glyph on every chip keeps the widths still when the check takes its place.
                symbol: "apps"
                label: Translation.tr("All")
                chosen: root.filter === "all"
                count: root.totalOn
                onClicked: root.filter = "all"
            }
            Repeater {
                model: Catalog.groups
                delegate: ColorsChip {
                    required property var modelData
                    symbol: modelData.icon
                    label: Translation.tr(modelData.label)
                    chosen: root.filter === modelData.id
                    count: {
                        void root.totalOn;
                        return root.onCount(root.entriesOf(modelData.id));
                    }
                    onClicked: root.filter = modelData.id
                }
            }
        }

        // ── The activities ───────────────────────────────────────────────
        StyledFlickable {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: groupsColumn.implicitHeight + 40
            flickableDirection: Flickable.VerticalFlick

            readonly property real gap: 10
            readonly property real minTile: 212

            Column {
                id: groupsColumn
                width: grid.width
                spacing: 22

                Repeater {
                    model: root.filter === "all" ? Catalog.groups : Catalog.groups.filter(g => g.id === root.filter)

                    delegate: Column {
                        id: groupBlock
                        required property var modelData
                        readonly property var list: root.entriesOf(groupBlock.modelData.id)
                        readonly property int maxCols: Math.max(1, Math.floor((grid.width + grid.gap) / (grid.minTile + grid.gap)))
                        readonly property int rows: Math.max(1, Math.ceil(groupBlock.list.length / groupBlock.maxCols))
                        readonly property int cols: Math.max(1, Math.ceil(groupBlock.list.length / groupBlock.rows))
                        readonly property real tileWidth: Math.floor((grid.width - (groupBlock.cols - 1) * grid.gap) / groupBlock.cols)

                        width: grid.width
                        spacing: 10
                        visible: groupBlock.list.length > 0

                        RowLayout {
                            width: parent.width
                            spacing: 10
                            MaterialSymbol {
                                text: groupBlock.modelData.icon
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr(groupBlock.modelData.label)
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr(groupBlock.modelData.hint)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: grid.gap
                            move: Transition {
                                NumberAnimation {
                                    properties: "x,y"
                                    duration: Appearance.animation.elementMove.duration
                                    easing.type: Appearance.animation.elementMove.type
                                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                }
                            }

                            Repeater {
                                model: groupBlock.list

                                delegate: IslandActivityTile {
                                    id: tile
                                    required property var modelData
                                    required property int index
                                    width: groupBlock.tileWidth
                                    entry: tile.modelData
                                    activityOn: root.fn[tile.modelData.key] !== true
                                    selected: root.selectedId === tile.modelData.id
                                    whereText: {
                                        void stage.bubblesOn;
                                        return root.whereOf(tile.modelData);
                                    }
                                    chipLabel: tile.modelData.id === "workspaces" ? Translation.tr("Bubble")
                                        : tile.modelData.id === "notification" ? Translation.tr("One line") : ""
                                    chipChosen: tile.modelData.id === "workspaces" ? root.fn.disableWorkspacesBubble !== true
                                        : tile.modelData.id === "notification" ? Config.options.dynamicIsland.widgets.notification.oneLine === true
                                        : false
                                    onClicked: root.select(tile.modelData.id)
                                    onHoveredChanged: root.tileHovered(tile.modelData.id, tile.hovered)
                                    onToggledByUser: value => root.setOn(tile.modelData, value)
                                    onChipToggled: value => {
                                        if (tile.modelData.id === "workspaces")
                                            root.fn.disableWorkspacesBubble = !value;
                                        else if (tile.modelData.id === "notification")
                                            Config.options.dynamicIsland.widgets.notification.oneLine = value;
                                    }

                                    StaggeredEntrance {
                                        index: tile.index
                                        active: !Appearance.reducedMotion
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
