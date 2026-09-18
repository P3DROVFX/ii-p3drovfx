pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles
import "../../../common/quickToggles/androidStyle/QuickToggleCatalog.js" as QuickToggleCatalog
import "../../../common/quickToggles/androidStyle/QuickToggleLayout.js" as QuickToggleLayout

/**
 * The island's dashboard: the sidebar's quick-toggle grid, on a single page.
 *
 * It is the same AndroidQuickPanel the sidebar uses - same tiles, same resize, same
 * reorder, same tray - hosted with its own layout object
 * (`dynamicIsland.dashboard.quickToggles`). What differs is the frame: one page, a
 * grid of `columns` x `rows` that the island sizes itself around, and an edit toolbar
 * that changes those two numbers instead of managing pages.
 *
 * The island declares its size from `targetWidth`/`targetHeight`, which are computed
 * from the grid and never from the animated surface, so the two never chase each other.
 */
Item {
    id: dashboard

    /** Room the island can give (screen minus margins), set by the island. */
    property real availableWidth: 1600
    property real availableHeight: 900

    property bool editMode: false

    readonly property var layout: Config.options.dynamicIsland.dashboard.quickToggles
    readonly property int columns: Math.max(1, dashboard.layout.columns)
    readonly property int rows: Math.max(1, dashboard.layout.rows)

    // Grid metrics. The sidebar derives its cell width from a fixed panel width; here
    // the panel width is derived from the cell, so adding a column adds exactly one.
    readonly property real cellWidth: 96
    readonly property real cellHeight: panel.baseCellHeight
    readonly property real cellSpacing: panel.spacing
    readonly property real framePadding: 8

    readonly property real gridWidth: dashboard.columns * dashboard.cellWidth + (dashboard.columns - 1) * dashboard.cellSpacing
    readonly property real gridHeight: dashboard.rows * dashboard.cellHeight + (dashboard.rows - 1) * dashboard.cellSpacing
    readonly property real panelWidth: dashboard.gridWidth + 2 * panel.padding

    /** How many columns and rows fit on this screen; the edit toolbar stops there. */
    readonly property int maxColumns: Math.max(1, Math.floor(
        (dashboard.availableWidth - 2 * (dashboard.framePadding + panel.padding) + dashboard.cellSpacing)
        / (dashboard.cellWidth + dashboard.cellSpacing)))
    readonly property int maxRows: Math.max(1, Math.floor(
        (dashboard.availableHeight - 2 * (dashboard.framePadding + panel.padding) - editBarHeight - dashboard.cellHeight
            + dashboard.cellSpacing)
        / (dashboard.cellHeight + dashboard.cellSpacing)))
    readonly property real editBarHeight: 44

    readonly property real targetWidth: dashboard.panelWidth + 2 * dashboard.framePadding
    /**
     * At rest the island hugs the grid's full capacity. Editing adds the toolbar and the
     * tray under it, as far as the screen allows; past that the tray scrolls.
     */
    readonly property real targetHeight: Math.min(dashboard.availableHeight,
        dashboard.editMode
            ? Math.max(dashboard.gridHeight + 2 * panel.padding, panel.implicitHeight) + 2 * dashboard.framePadding
            : dashboard.gridHeight + 2 * panel.padding + 2 * dashboard.framePadding)

    // ── Layout upkeep ────────────────────────────────────────────────────────
    /** Rows the current tiles need at a given column count. */
    function rowsNeeded(columnCount) {
        const pages = QuickToggleCatalog.normalizePages(dashboard.layout.pages, columnCount, {});
        const page = pages.length > 0 ? pages[0] : [];
        return QuickToggleLayout.pack(page, columnCount, dashboard.cellWidth, dashboard.cellHeight,
            dashboard.cellSpacing).rowsUsed;
    }

    function setColumns(value) {
        const next = Math.max(1, Math.min(dashboard.maxColumns, value));
        if (next === dashboard.columns || dashboard.rowsNeeded(next) > dashboard.rows)
            return;
        dashboard.layout.columns = next;
    }

    function setRows(value) {
        const next = Math.max(1, Math.min(dashboard.maxRows, value));
        if (next === dashboard.rows || dashboard.rowsNeeded(dashboard.columns) > next)
            return;
        dashboard.layout.rows = next;
    }

    readonly property bool canShrinkColumns: dashboard.columns > 1 && dashboard.rowsNeeded(dashboard.columns - 1) <= dashboard.rows
    readonly property bool canGrowColumns: dashboard.columns < dashboard.maxColumns
    readonly property bool canShrinkRows: dashboard.rows > 1 && dashboard.rowsNeeded(dashboard.columns) <= dashboard.rows - 1
    readonly property bool canGrowRows: dashboard.rows < dashboard.maxRows

    /**
     * The toolbar is the only way into edit mode, so a layout without it (an old config,
     * a hand edit) gets it back at the front instead of locking the grid.
     */
    function ensureToolbar() {
        const pages = dashboard.layout.pages;
        const first = (pages && pages.length > 0) ? pages[0] : [];
        for (let i = 0; i < first.length; i++) {
            if (first[i] && first[i].type === "dashboardToolbar")
                return;
        }
        const repaired = [[QuickToggleCatalog.item("dashboardToolbar", "dashboardToolbar", undefined, undefined, dashboard.columns)]
            .concat(first)];
        dashboard.layout.pages = repaired;
    }

    Component.onCompleted: dashboard.ensureToolbar()

    // Leaving the dashboard leaves edit mode; a half-finished drag is cancelled with it.
    Component.onDestruction: dashboard.editMode = false

    AndroidQuickPanel {
        id: panel
        anchors.top: parent.top
        anchors.topMargin: dashboard.framePadding
        anchors.horizontalCenter: parent.horizontalCenter
        width: dashboard.panelWidth

        layoutOverride: dashboard.layout
        familyId: "island"
        pagingEnabled: false
        showFixedSliders: false
        maxRows: dashboard.rows
        editMode: dashboard.editMode
        maxContentHeight: dashboard.availableHeight - 2 * dashboard.framePadding
        color: "transparent"

        onEditModeToggleRequested: dashboard.editMode = !dashboard.editMode

        editToolbar: Component {
            RowLayout {
                implicitHeight: dashboard.editBarHeight
                spacing: 6

                GridStepper {
                    icon: "view_column"
                    label: Translation.tr("Columns")
                    value: dashboard.columns
                    canDecrease: dashboard.canShrinkColumns
                    canIncrease: dashboard.canGrowColumns
                    onDecrease: dashboard.setColumns(dashboard.columns - 1)
                    onIncrease: dashboard.setColumns(dashboard.columns + 1)
                }

                GridStepper {
                    icon: "table_rows"
                    label: Translation.tr("Rows")
                    value: dashboard.rows
                    canDecrease: dashboard.canShrinkRows
                    canIncrease: dashboard.canGrowRows
                    onDecrease: dashboard.setRows(dashboard.rows - 1)
                    onIncrease: dashboard.setRows(dashboard.rows + 1)
                }

                Item {
                    Layout.fillWidth: true
                }

                RippleButton {
                    Layout.preferredHeight: 34
                    Layout.preferredWidth: doneRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: dashboard.editMode = false
                    contentItem: RowLayout {
                        id: doneRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "check"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Done")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }

    component GridStepper: Rectangle {
        id: stepper
        required property string icon
        required property string label
        required property int value
        property bool canDecrease: true
        property bool canIncrease: true
        signal decrease()
        signal increase()

        Layout.preferredHeight: 34
        implicitWidth: stepperRow.implicitWidth + 8
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer2

        RowLayout {
            id: stepperRow
            anchors.centerIn: parent
            spacing: 2

            StepButton {
                symbol: "remove"
                enabled: stepper.canDecrease
                onClicked: stepper.decrease()
            }
            MaterialSymbol {
                text: stepper.icon
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.minimumWidth: 44
                horizontalAlignment: Text.AlignHCenter
                text: stepper.label + " " + stepper.value
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            StepButton {
                symbol: "add"
                enabled: stepper.canIncrease
                onClicked: stepper.increase()
            }
        }
    }

    component StepButton: RippleButton {
        id: step
        required property string symbol
        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        opacity: step.enabled ? 1 : 0.4
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: step.symbol
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer2
        }
    }
}
