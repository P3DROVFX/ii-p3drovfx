import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * The page's main pane: the curve chart with its two handles, the shape and preset chips,
 * and the error line. Edits live in FanControl.draftCurve until the page's Apply FAB sends them.
 */
Rectangle {
    id: root

    // The status file is re-parsed every tick, so the object is new each time: follow its
    // text, which only notifies when the stored curve really changes (a save, another session).
    readonly property string storedJson: JSON.stringify(FanControl.config.curve)
    readonly property var stored: JSON.parse(root.storedJson)
    readonly property var draft: FanControl.draftCurve ?? root.stored
    readonly property bool dirty: FanControl.curveDirty
    // a save landed: the draft is now the stored curve
    onStoredJsonChanged: if (FanControl.draftCurve !== null && root.sameCurve(FanControl.draftCurve, root.stored)) FanControl.discardDraft()
    readonly property bool canEdit: FanControl.daemonInstalled && FanControl.controllable && FanControl.config.enabled

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    implicitHeight: content.implicitHeight + 40

    readonly property var shapes: [
        { "id": -2, "symbol": "north_east", "label": Translation.tr("Early") },
        { "id": 0, "symbol": "trending_up", "label": Translation.tr("Linear") },
        { "id": 2, "symbol": "show_chart", "label": Translation.tr("Late") },
        { "id": 4, "symbol": "bolt", "label": Translation.tr("Last moment") }
    ]
    readonly property var presets: [
        { "symbol": "volume_off", "label": Translation.tr("Silent"),
          "curve": { "tStart": 65, "tMax": 90, "minPct": FanControl.additive ? 0 : 20, "maxPct": 100, "steepness": 2 } },
        { "symbol": "balance", "label": Translation.tr("Balanced"),
          "curve": { "tStart": 60, "tMax": 80, "minPct": 40, "maxPct": 100, "steepness": 2 } },
        { "symbol": "ac_unit", "label": Translation.tr("Cool"),
          "curve": { "tStart": 50, "tMax": 75, "minPct": 50, "maxPct": 100, "steepness": 0 } },
        { "symbol": "mode_fan", "label": Translation.tr("Full speed"),
          "curve": { "tStart": 30, "tMax": 32, "minPct": 100, "maxPct": 100, "steepness": 0 } }
    ]

    function sameCurve(a, b) {
        return FanControl.sameCurve(a, b);
    }

    function describe(c) {
        if (c.minPct >= 100)
            return Translation.tr("Always at full speed");
        const floor = FanControl.additive && c.minPct === 0
            ? Translation.tr("Firmware speed until %1°").arg(c.tStart)
            : Translation.tr("%1% until %2°").arg(c.minPct).arg(c.tStart);
        return Translation.tr("%1, %2% at %3°").arg(floor).arg(c.maxPct).arg(c.tMax);
    }

    readonly property string subtitle: {
        if (!FanControl.controllable)
            return Translation.tr("This machine exposes no fan control to Linux");
        if (!FanControl.config.enabled)
            return Translation.tr("Firmware controls the fans");
        if (graph.activeHandle === "start")
            return Translation.tr("Start · the floor holds until %1°").arg(root.draft.tStart);
        if (graph.activeHandle === "end")
            return Translation.tr("End · %1% from %2°").arg(root.draft.maxPct).arg(root.draft.tMax);
        return root.describe(root.draft) + (root.dirty ? " · " + Translation.tr("not applied") : "");
    }

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        spacing: 16

        // ── header ──
        GridLayout {
            Layout.fillWidth: true
            readonly property bool narrow: root.width < 560
            columns: narrow ? 1 : 2
            columnSpacing: 16
            rowSpacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    text: "mode_fan"
                    iconSize: 24
                    padding: 12
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Fan curve")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.subtitle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            // Custom curve vs firmware: a connected two-segment group
            RowLayout {
                Layout.preferredWidth: parent.narrow ? -1 : 248
                Layout.fillWidth: parent.narrow
                spacing: 3
                enabled: FanControl.daemonInstalled && FanControl.controllable && !FanControl.busy

                ModeSegment {
                    first: true
                    current: !FanControl.config.enabled
                    symbol: "memory"
                    label: Translation.tr("Firmware")
                    activeShape: MaterialShape.Shape.Cookie6Sided
                    onClicked: FanControl.apply(Object.assign({}, FanControl.config, { "enabled": false }))
                }
                ModeSegment {
                    first: false
                    current: FanControl.config.enabled
                    symbol: "tune"
                    label: Translation.tr("Custom")
                    activeShape: MaterialShape.Shape.Cookie9Sided
                    onClicked: FanControl.apply(Object.assign({}, FanControl.config, { "enabled": true, "curve": root.draft }))
                }
            }
        }

        // ── chart ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(Math.max(240, Math.min(360, width * 0.42)))
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            FanCurveGraph {
                id: graph
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 14
                curve: root.draft
                editable: root.canEdit
                liveTemp: FanControl.hottest > 0 ? FanControl.hottest : -1
                // the daemon's value includes hysteresis; show it only while the draft is the applied curve
                livePct: root.dirty ? -1 : FanControl.appliedPct
                yCaption: FanControl.additive ? Translation.tr("% boost") : "%"
                onEdited: c => FanControl.draftCurve = c
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: FanControl.additive
            text: Translation.tr("On this machine the curve is a boost added to the firmware's own speed: it can push the fans up, never below what the firmware picks. The band on the right is the safety zone, where the fans always run at full speed.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        // ── rise shape ──
        ChipGroup {
            caption: Translation.tr("Rise between the handles")
            Repeater {
                model: root.shapes
                delegate: ColorsChip {
                    required property var modelData
                    symbol: modelData.symbol
                    label: modelData.label
                    enabled: root.canEdit
                    chosen: root.draft.steepness === modelData.id
                    onClicked: FanControl.draftCurve = Object.assign({}, root.draft, { "steepness": modelData.id })
                }
            }
        }

        // ── presets ──
        ChipGroup {
            caption: Translation.tr("Presets")
            Repeater {
                model: root.presets
                delegate: ColorsChip {
                    required property var modelData
                    symbol: modelData.symbol
                    label: modelData.label
                    enabled: root.canEdit
                    chosen: root.sameCurve(root.draft, modelData.curve)
                    onClicked: FanControl.draftCurve = Object.assign({}, modelData.curve)
                }
            }
        }

        // ── error (Revert / Apply are the page's FABs) ──
        StyledText {
            Layout.fillWidth: true
            text: FanControl.lastError
            visible: text.length > 0
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.WordWrap
        }
    }

    component ChipGroup: ColumnLayout {
        id: group
        property string caption: ""
        default property alias chips: chipFlow.data
        Layout.fillWidth: true
        spacing: 8
        StyledText {
            text: group.caption
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurfaceVariant
        }
        Flow {
            id: chipFlow
            Layout.fillWidth: true
            spacing: 8
        }
    }

    component ModeSegment: RippleButton {
        id: segment

        required property bool first
        required property bool current
        required property string symbol
        required property string label
        required property var activeShape

        readonly property real outer: Math.min(height / 2, Appearance.rounding.full)
        property real inner: segment.current ? segment.outer : Appearance.rounding.verysmall
        Behavior on inner {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        readonly property color colContent: segment.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitWidth: segmentRow.implicitWidth + 32
        implicitHeight: 48
        opacity: enabled ? 1 : 0.5

        topLeftRadius: segment.first ? segment.outer : segment.inner
        bottomLeftRadius: segment.first ? segment.outer : segment.inner
        topRightRadius: segment.first ? segment.inner : segment.outer
        bottomRightRadius: segment.first ? segment.inner : segment.outer

        toggled: segment.current
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
        colRipple: Appearance.colors.colSecondaryContainerActive

        contentItem: Item {
            RowLayout {
                id: segmentRow
                anchors.centerIn: parent
                spacing: 8

                MaterialShapeWrappedMaterialSymbol {
                    text: segment.symbol
                    iconSize: 18
                    padding: 5
                    fill: segment.current ? 1 : 0
                    shape: segment.current ? segment.activeShape : MaterialShape.Shape.Circle
                    color: segment.current ? Appearance.colors.colOnPrimary : "transparent"
                    colSymbol: segment.current ? Appearance.colors.colPrimary : segment.colContent
                }
                StyledText {
                    text: segment.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: segment.colContent
                }
            }
        }
    }
}
