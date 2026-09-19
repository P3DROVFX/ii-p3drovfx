pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles
import qs.modules.common.quickToggleDialogs.bluetoothDevices
import qs.modules.common.quickToggleDialogs.nightLight
import qs.modules.common.quickToggleDialogs.volumeMixer
import qs.modules.common.quickToggleDialogs.wifiNetworks
import qs.modules.common.quickToggleDialogs.darkMode
import qs.modules.common.quickToggleDialogs.localSend
import qs.modules.common.quickToggleDialogs.vpn
import qs.modules.common.quickToggleDialogs.tailscale
import qs.modules.common.quickToggleDialogs.kdeConnect
import qs.modules.common.quickToggleDialogs.dnsOverTls
import qs.modules.common.quickToggleDialogs.idleInhibitor
import qs.modules.common.quickToggleDialogs.screenShader
import qs.modules.ii.sidebarDashboard.modes
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
    readonly property real cellWidth: DashboardMetrics.cellWidth
    readonly property real cellHeight: panel.baseCellHeight
    readonly property real cellSpacing: panel.spacing
    readonly property real framePadding: DashboardMetrics.framePadding

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
     * The island hugs what the panel actually lays out, with the same frame on every side.
     *
     * It used to reserve the grid's full row capacity, but rows made only of sliders pack
     * shorter than a toggle row, so the island kept empty space under the last row and
     * the bottom margin came out larger than the top. Editing adds the toolbar and the
     * tray, as far as the screen allows; past that the tray scrolls.
     */
    /** The page's own height (frame included), kept while it slides out too. */
    readonly property real pageTargetHeight: Math.min(dashboard.availableHeight, Math.max(DashboardMetrics.restHeight,
        (pageLoader.item ? pageLoader.item.pageContentHeight : 0) + 2 * dashboard.framePadding))

    readonly property real targetHeight: {
        if (dashboard.openPage !== "")
            return dashboard.pageTargetHeight;
        return Math.min(dashboard.availableHeight,
            dashboard.editMode ? panel.implicitHeight + 2 * dashboard.framePadding : DashboardMetrics.restHeight);
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    /**
     * A tile's details open as a page that replaces the grid, not as a dialog over it.
     *
     * The page *is* the sidebar's dialog - same header, same content, same Details and
     * Done - presented in WindowDialog's page mode, which drops the scrim and the
     * floating card and adds a back button to the header. The grid slides out and the
     * page slides in; the island reshapes to the page's own height.
     */
    property string openPage: ""
    /** The page being drawn, which outlives `openPage` for the length of the exit. */
    property string shownPage: ""
    /** Held open while editing or while a page is up; the island reads this. */
    readonly property bool holdOpen: dashboard.editMode || dashboard.openPage !== ""
    /** Pages can take text (a Wi-Fi password), so the island takes the keyboard for them. */
    readonly property bool wantsKeyboard: dashboard.openPage !== ""

    readonly property var pageComponents: ({
        wifi: wifiPage, bluetooth: bluetoothPage, audioOutput: audioOutputPage,
        audioInput: audioInputPage, nightLight: nightLightPage, darkMode: darkModePage,
        localSend: localSendPage, vpn: vpnPage, tailscale: tailscalePage,
        kdeConnect: kdeConnectPage, dnsOverTls: dnsOverTlsPage,
        idleInhibitor: idleInhibitorPage, screenShader: screenShaderPage, modes: modesPage
    })

    // Only pages whose dialog has no title of its own need one for the bar.
    readonly property var pageTitles: ({
        audioOutput: Translation.tr("Audio output"),
        audioInput: Translation.tr("Audio input")
    })

    function showPage(id) {
        if (!dashboard.pageComponents[id])
            return;
        dashboard.editMode = false;
        dashboard.shownPage = id;
        dashboard.openPage = id;
    }

    function closePage() {
        dashboard.openPage = "";
    }

    /** Back to the grid, out of edit mode: the dashboard is kept alive while hidden. */
    function resetState() {
        dashboard.editMode = false;
        dashboard.openPage = "";
    }

    /** 0 = the grid, 1 = the page. One clock for both halves of the slide. */
    property real pageProgress: dashboard.openPage !== "" ? 1 : 0
    Behavior on pageProgress {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
    onPageProgressChanged: {
        if (dashboard.pageProgress === 0 && dashboard.openPage === "")
            dashboard.shownPage = "";
    }
    /**
     * The slide is the transition; the fade only finishes it. Both halves travel far
     * and stay mostly opaque while they move (three quarters at the midpoint), fading
     * out only as they reach the end of their travel.
     */
    readonly property real pageTravel: 110

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

    /**
     * Makes room for an addition the grid cannot hold: another row while the screen has
     * the height for it, then another column. Called by the edit controller with the
     * pages the addition would produce.
     */
    function growToFit(pages) {
        const page = (pages && pages.length > 0) ? pages[0] : [];
        for (let columnCount = dashboard.columns; columnCount <= dashboard.maxColumns; columnCount++) {
            const normalized = QuickToggleCatalog.normalizePages([page], columnCount, {});
            const needed = QuickToggleLayout.pack(normalized[0] || [], columnCount, dashboard.cellWidth,
                dashboard.cellHeight, dashboard.cellSpacing).rowsUsed;
            if (needed > dashboard.maxRows)
                continue;
            if (columnCount !== dashboard.columns)
                dashboard.layout.columns = columnCount;
            if (needed > dashboard.rows)
                dashboard.layout.rows = needed;
            return true;
        }
        return false;
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
    Component.onDestruction: {
        dashboard.editMode = false;
        dashboard.openPage = "";
    }

    AndroidQuickPanel {
        id: panel
        anchors.top: parent.top
        anchors.topMargin: dashboard.framePadding
        anchors.horizontalCenter: parent.horizontalCenter
        // Opening moves everything to the right: the grid leaves that way while the
        // page arrives from the left; going back reverses it, moving left.
        anchors.horizontalCenterOffset: dashboard.pageTravel * dashboard.pageProgress
        opacity: 1 - dashboard.pageProgress * dashboard.pageProgress
        visible: dashboard.pageProgress < 1
        enabled: dashboard.openPage === ""
        width: dashboard.panelWidth

        layoutOverride: dashboard.layout
        familyId: "island"
        pagingEnabled: false
        showFixedSliders: false
        maxRows: dashboard.rows
        growToFit: pages => dashboard.growToFit(pages)
        editMode: dashboard.editMode
        maxContentHeight: dashboard.availableHeight - 2 * dashboard.framePadding
        color: "transparent"

        onEditModeToggleRequested: dashboard.editMode = !dashboard.editMode

        onOpenWifiDialog: dashboard.showPage("wifi")
        onOpenBluetoothDialog: dashboard.showPage("bluetooth")
        onOpenAudioOutputDialog: dashboard.showPage("audioOutput")
        onOpenAudioInputDialog: dashboard.showPage("audioInput")
        onOpenNightLightDialog: dashboard.showPage("nightLight")
        onOpenDarkModeDialog: dashboard.showPage("darkMode")
        onOpenLocalSendDialog: dashboard.showPage("localSend")
        onOpenVpnDialog: dashboard.showPage("vpn")
        onOpenTailscaleDialog: dashboard.showPage("tailscale")
        onOpenKdeConnectDialog: dashboard.showPage("kdeConnect")
        onOpenDnsOverTlsDialog: dashboard.showPage("dnsOverTls")
        onOpenIdleInhibitorDialog: dashboard.showPage("idleInhibitor")
        onOpenScreenShaderDialog: dashboard.showPage("screenShader")
        onOpenModesDialog: dashboard.showPage("modes")

        editToolbar: Component {
            RowLayout {
                implicitHeight: dashboard.editBarHeight
                spacing: 8

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
                    Layout.preferredHeight: dashboard.segmentHeight
                    Layout.preferredWidth: doneRow.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    buttonRadiusPressed: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: dashboard.editMode = false
                    contentItem: RowLayout {
                        id: doneRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "check"
                            iconSize: Appearance.font.pixelSize.larger
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

    /**
     * The page is laid out at its final size from the first frame; the island's morph
     * only reveals it. Filling the animating surface instead re-laid the dialog out on
     * every frame of the resize - lists stretching, the header pushed out of view -
     * which read as the page scaling down from the top.
     */
    readonly property real pageHeight: Math.max(0, dashboard.pageTargetHeight - 2 * dashboard.framePadding)

    Loader {
        id: pageLoader
        x: dashboard.framePadding - dashboard.pageTravel * (1 - dashboard.pageProgress)
        y: dashboard.framePadding
        width: dashboard.panelWidth
        height: dashboard.pageHeight
        active: dashboard.shownPage !== ""
        sourceComponent: dashboard.pageComponents[dashboard.shownPage] ?? null
        opacity: 1 - (1 - dashboard.pageProgress) * (1 - dashboard.pageProgress)

        onLoaded: {
            const page = pageLoader.item;
            page.pageTitle = dashboard.pageTitles[dashboard.shownPage] ?? "";
            // The island is not the sidebar: Details must not close a sidebar that
            // is not open, and it leaves the page instead.
            if (page.hasOwnProperty("closeOwningSidebarOnDetails"))
                page.closeOwningSidebarOnDetails = false;
            page.show = true;
            page.forceActiveFocus();
        }

        Connections {
            target: pageLoader.item
            ignoreUnknownSignals: true
            function onDismiss() {
                dashboard.closePage();
            }
            function onDetailsRequested() {
                dashboard.closePage();
            }
        }
    }

    // Each page is the sidebar's dialog for that tile, created already in page mode:
    // set after creation, the dialog's own pop-in (scale from 0.88, rise from 40px
    // lower) was still armed and played underneath the horizontal slide.
    Component { id: wifiPage; WifiDialog { pageMode: true } }
    Component { id: bluetoothPage; BluetoothDialog { pageMode: true } }
    Component { id: audioOutputPage; VolumeDialog { pageMode: true; isSink: true } }
    Component { id: audioInputPage; VolumeDialog { pageMode: true; isSink: false } }
    Component { id: nightLightPage; NightLightDialog { pageMode: true } }
    Component { id: darkModePage; DarkModeDialog { pageMode: true } }
    Component { id: localSendPage; LocalSendDialog { pageMode: true } }
    Component { id: vpnPage; VpnDialog { pageMode: true } }
    Component { id: tailscalePage; TailscaleDialog { pageMode: true } }
    Component { id: kdeConnectPage; KdeConnectDialog { pageMode: true } }
    Component { id: dnsOverTlsPage; DnsOverTlsDialog { pageMode: true } }
    Component { id: idleInhibitorPage; IdleInhibitorDialog { pageMode: true } }
    Component { id: screenShaderPage; ScreenShaderDialog { pageMode: true } }
    Component { id: modesPage; ModesDialog { pageMode: true } }

    readonly property real segmentHeight: 36

    /**
     * A connected button group, Material 3 Expressive style: a decrease segment, the
     * value, an increase segment. The outer corners are fully round and the inner ones
     * nearly square, so the three read as one control; the increase side carries the
     * accent, as the sidebar's page bar does with its add button.
     */
    component GridStepper: RowLayout {
        id: stepper
        required property string icon
        required property string label
        required property int value
        property bool canDecrease: true
        property bool canIncrease: true
        signal decrease()
        signal increase()

        spacing: 2

        RippleButton {
            id: decreaseButton
            Layout.preferredWidth: dashboard.segmentHeight + 6
            Layout.preferredHeight: dashboard.segmentHeight
            enabled: stepper.canDecrease
            opacity: enabled ? 1 : 0.4
            topLeftRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.verysmall
            bottomRightRadius: Appearance.rounding.verysmall
            buttonRadiusPressed: dashboard.segmentHeight / 2
            colBackground: Appearance.colors.colSurfaceContainerHigh
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
            onClicked: stepper.decrease()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "remove"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurface
            }
        }

        Rectangle {
            Layout.preferredHeight: dashboard.segmentHeight
            Layout.preferredWidth: valueRow.implicitWidth + 24
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colSurfaceContainerHigh

            RowLayout {
                id: valueRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: stepper.icon
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: stepper.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    text: stepper.value
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }
            }
        }

        RippleButton {
            Layout.preferredWidth: dashboard.segmentHeight + 6
            Layout.preferredHeight: dashboard.segmentHeight
            enabled: stepper.canIncrease
            opacity: enabled ? 1 : 0.4
            topLeftRadius: Appearance.rounding.verysmall
            bottomLeftRadius: Appearance.rounding.verysmall
            topRightRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            buttonRadiusPressed: dashboard.segmentHeight / 2
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            onClicked: stepper.increase()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "add"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
