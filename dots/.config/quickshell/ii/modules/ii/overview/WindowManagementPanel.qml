pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property int categoryIndex: 0
    property int targetIndex: -1
    property string targetAddress: ""
    property int focusArea: 2 // 0 windows, 1 categories, 2 actions
    property int lastWorkspaceId: -1
    property string noticeText: ""

    readonly property bool supportsSectionToggle: true
    readonly property int actionColumns: Math.max(1, Config.options.search.modules.windowManagement.columns)
    // Five rows must fit beside the target picker and the footer. The compact
    // action row keeps its icon, name and one hint on a single baseline.
    readonly property real actionCardHeight: Appearance.sizes.elevationMargin * 5.5
    readonly property var categories: [
        { id: "all", label: Translation.tr("All"), icon: "apps" },
        { id: "tiling", label: Translation.tr("Tiling"), icon: "grid_view" },
        { id: "window", label: Translation.tr("Window"), icon: "select_window" },
        { id: "workspace", label: Translation.tr("Workspace"), icon: "view_carousel" },
        { id: "monitor", label: Translation.tr("Monitor"), icon: "desktop_windows" }
    ]
    readonly property string selectedCategory: root.categories[root.categoryIndex]?.id ?? "all"
    readonly property var openWindows: root.availableWindows()
    readonly property var targetWindow: root.targetIndex >= 0 && root.targetIndex < root.openWindows.length
        ? root.openWindows[root.targetIndex]
        : null
    readonly property var rows: root.filteredActions()
    readonly property var selectedAction: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length
        ? root.rows[root.selectedIndex]
        : null
    readonly property string targetLabel: root.targetWindow
        ? String(root.targetWindow.title ?? root.targetWindow.class ?? root.targetAddress)
        : Translation.tr("No target window")
    readonly property string targetSubtitle: root.targetWindow
        ? Translation.tr("%1 · workspace %2").arg(String(root.targetWindow.class ?? Translation.tr("Application"))).arg(String(root.targetWindow.workspace?.id ?? "?"))
        : Translation.tr("Open an application in the current workspace")
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : (root.targetWindow
            ? Translation.tr("Target: %1 · %2 open windows").arg(root.targetLabel).arg(String(root.openWindows.length))
            : Translation.tr("No window is available for management"))

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function availableWindows(): var {
        const workspaceId = Number(HyprlandData.activeWorkspace?.id ?? -1);
        return Array.from(HyprlandData.windowList ?? [])
            .filter(window => String(window?.address ?? "").length > 0
                && window?.mapped !== false
                && window?.hidden !== true)
            .sort((left, right) => {
                const leftCurrent = Number(left?.workspace?.id ?? -2) === workspaceId ? 0 : 1;
                const rightCurrent = Number(right?.workspace?.id ?? -2) === workspaceId ? 0 : 1;
                if (leftCurrent !== rightCurrent)
                    return leftCurrent - rightCurrent;
                return Number(left?.focusHistoryID ?? 9999) - Number(right?.focusHistoryID ?? 9999);
            });
    }

    function normalizedAddress(value): string {
        const address = String(value ?? "").trim();
        if (address.length === 0)
            return "";
        return address.startsWith("0x") ? address : "0x" + address;
    }

    function reconcileTarget(preferCurrentWorkspace = false) {
        const windows = root.openWindows;
        if (windows.length === 0) {
            root.targetIndex = -1;
            root.targetAddress = "";
            return;
        }
        const workspaceId = Number(HyprlandData.activeWorkspace?.id ?? -1);
        let index = -1;
        if (!preferCurrentWorkspace) {
            const currentAddress = root.normalizedAddress(root.targetAddress || GlobalStates.searchTargetWindowAddress);
            index = windows.findIndex(window => root.normalizedAddress(window?.address) === currentAddress);
        }
        if (index < 0)
            index = windows.findIndex(window => Number(window?.workspace?.id ?? -2) === workspaceId);
        if (index < 0)
            index = 0;
        root.selectTarget(index);
    }

    function selectTarget(index) {
        if (root.openWindows.length === 0)
            return;
        root.targetIndex = Math.max(0, Math.min(index, root.openWindows.length - 1));
        root.targetAddress = root.normalizedAddress(root.openWindows[root.targetIndex]?.address);
        targetStrip.positionViewAtIndex(root.targetIndex, ListView.Contain);
    }

    function visibleByConfig(action) {
        if (action.category === "tiling")
            return Config.options.search.modules.windowManagement.showTilingPresets;
        if (action.category === "workspace")
            return Config.options.search.modules.windowManagement.showWorkspaceMoves;
        if (action.category === "monitor")
            return Config.options.search.modules.windowManagement.showMonitorMoves;
        return true;
    }

    function filteredActions() {
        const terms = root.searchQuery.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
        return WindowActionRegistry.actions.filter(action => {
            if (!root.visibleByConfig(action))
                return false;
            if (root.selectedCategory !== "all" && action.category !== root.selectedCategory)
                return false;
            const text = [action.name, action.category, ...(action.keywords ?? [])].join(" ").toLocaleLowerCase();
            return terms.every(term => text.includes(term));
        });
    }

    function clampSelection() {
        root.selectedIndex = root.rows.length === 0
            ? -1
            : Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
    }

    function toggleSection(): bool {
        root.focusArea = (root.focusArea + 1) % 3;
        return true;
    }

    function navigateUp(): bool {
        if (root.focusArea === 2 && root.selectedIndex >= root.actionColumns) {
            root.selectedIndex -= root.actionColumns;
            actionGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
        } else if (root.focusArea > 0) {
            root.focusArea--;
        }
        return true;
    }

    function navigateDown(): bool {
        if (root.focusArea < 2) {
            root.focusArea++;
        } else if (root.selectedIndex + root.actionColumns < root.rows.length) {
            root.selectedIndex += root.actionColumns;
            actionGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
        }
        return true;
    }

    function navigateLeft(): bool {
        if (root.focusArea === 0) {
            root.selectTarget(root.targetIndex - 1);
        } else if (root.focusArea === 1) {
            root.categoryIndex = (root.categoryIndex - 1 + root.categories.length) % root.categories.length;
            root.selectedIndex = 0;
        } else if (root.selectedIndex > 0) {
            root.selectedIndex--;
            actionGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
        }
        return true;
    }

    function navigateRight(): bool {
        if (root.focusArea === 0) {
            root.selectTarget(root.targetIndex + 1);
        } else if (root.focusArea === 1) {
            root.categoryIndex = (root.categoryIndex + 1) % root.categories.length;
            root.selectedIndex = 0;
        } else if (root.selectedIndex >= 0 && root.selectedIndex < root.rows.length - 1) {
            root.selectedIndex++;
            actionGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
        }
        return true;
    }

    function runSelected(keepOpen) {
        if (!root.targetWindow) {
            root.noticeText = Translation.tr("Select an open window first");
            noticeTimer.restart();
            return false;
        }
        if (!WindowActionRegistry.execute(root.selectedAction, root.targetAddress)) {
            root.noticeText = Translation.tr("This action could not be dispatched");
            noticeTimer.restart();
            return false;
        }
        root.noticeText = Translation.tr("%1 applied to %2").arg(String(root.selectedAction?.name ?? Translation.tr("Action"))).arg(root.targetLabel);
        noticeTimer.restart();
        if (!keepOpen)
            GlobalStates.overviewOpen = false;
        return true;
    }

    function activateSelected(): bool { return root.runSelected(false); }
    function secondaryActivateSelected(): bool { return root.runSelected(true); }
    function copyDispatchSelected(): bool {
        if (!root.selectedAction || !WindowActionRegistry.validTarget(root.targetAddress))
            return false;
        Quickshell.clipboardText = root.selectedAction.expression(root.targetAddress);
        root.noticeText = Translation.tr("Dispatch copied");
        noticeTimer.restart();
        return true;
    }
    function focusInput(): bool { return false; }

    onRowsChanged: root.clampSelection()
    onOpenWindowsChanged: Qt.callLater(() => root.reconcileTarget(false))
    onCategoryIndexChanged: root.clampSelection()

    Component.onCompleted: {
        root.lastWorkspaceId = Number(HyprlandData.activeWorkspace?.id ?? -1);
        Qt.callLater(() => root.reconcileTarget(false));
    }

    Connections {
        target: HyprlandData
        function onActiveWorkspaceChanged() {
            const workspaceId = Number(HyprlandData.activeWorkspace?.id ?? -1);
            const changed = workspaceId !== root.lastWorkspaceId;
            root.lastWorkspaceId = workspaceId;
            Qt.callLater(() => root.reconcileTarget(changed));
        }
    }

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Window Management")
        icon: "splitscreen"
        accent: true
        statusText: root.statusText
        showStatus: true
        primaryHint: ({ label: Translation.tr("Run"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Section"), actionId: "section", keys: ["Tab"] },
            { label: Translation.tr("Keep open"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Copy dispatch"), actionId: "copyDispatch", keys: ["Ctrl", "Shift", "K"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin / 2

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: targetHeroContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                radius: Appearance.rounding.large
                color: root.focusArea === 0
                    ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colSurfaceContainerHigh

                RowLayout {
                    id: targetHeroContent
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin
                    spacing: Appearance.sizes.elevationMargin

                    Rectangle {
                        implicitWidth: Appearance.sizes.elevationMargin * 4
                        implicitHeight: implicitWidth
                        radius: Appearance.rounding.normal
                        color: root.targetWindow ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colErrorContainer

                        StyledImage {
                            anchors.centerIn: parent
                            width: parent.width - Appearance.sizes.elevationMargin
                            height: width
                            source: root.targetWindow
                                ? Quickshell.iconPath(AppSearch.guessIcon(String(root.targetWindow.class ?? "")), "image-missing")
                                : ""
                            fillMode: Image.PreserveAspectFit
                            visible: root.targetWindow !== null
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: root.targetWindow === null
                            text: "select_window"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.elevationMargin / 4
                        StyledText {
                            Layout.fillWidth: true
                            text: root.targetLabel
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: root.focusArea === 0 ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.targetSubtitle
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.focusArea === 0 ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                        }
                    }

                    MaterialSymbol {
                        text: "keyboard_arrow_left"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: Translation.tr("Choose target")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    MaterialSymbol {
                        text: "keyboard_arrow_right"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            ListView {
                id: targetStrip
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.elevationMargin * 3
                orientation: ListView.Horizontal
                spacing: Appearance.sizes.elevationMargin / 2
                clip: true
                model: root.openWindows

                delegate: RippleButton {
                    required property int index
                    required property var modelData
                    implicitWidth: targetChipContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: targetStrip.height
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.targetIndex === index ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: root.targetIndex === index ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: root.targetIndex === index ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: {
                        root.focusArea = 0;
                        root.selectTarget(index);
                    }

                    RowLayout {
                        id: targetChipContent
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin / 2
                        StyledImage {
                            Layout.preferredWidth: Appearance.font.pixelSize.normal
                            Layout.preferredHeight: Appearance.font.pixelSize.normal
                            source: Quickshell.iconPath(AppSearch.guessIcon(String(modelData.class ?? "")), "image-missing")
                            fillMode: Image.PreserveAspectFit
                        }
                        StyledText {
                            text: String(modelData.title ?? modelData.class ?? Translation.tr("Window"))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.targetIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Layout.maximumWidth: targetStrip.width / Math.max(2, root.actionColumns)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                Repeater {
                    model: root.categories
                    delegate: RippleButton {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Appearance.sizes.elevationMargin * 3
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.categoryIndex === index
                            ? (root.focusArea === 1 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer)
                            : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: root.categoryIndex === index ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: root.categoryIndex === index ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: {
                            root.focusArea = 1;
                            root.categoryIndex = index;
                            root.selectedIndex = 0;
                        }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Appearance.sizes.elevationMargin / 4
                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.small
                                color: root.categoryIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            }
                            StyledText {
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.categoryIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            }
                        }
                    }
                }
            }

            GridView {
                id: actionGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: width / root.actionColumns
                cellHeight: root.actionCardHeight
                model: root.rows

                delegate: Item {
                    required property int index
                    required property var modelData
                    width: actionGrid.cellWidth
                    height: actionGrid.cellHeight

                    RippleButton {
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin / 4
                        buttonRadius: root.selectedIndex === index && root.focusArea === 2
                            ? Appearance.rounding.large
                            : Appearance.rounding.normal
                        colBackground: root.selectedIndex === index
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: root.selectedIndex === index ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: root.selectedIndex === index ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: {
                            root.focusArea = 2;
                            root.selectedIndex = index;
                        }
                        onDoubleClicked: root.activateSelected()

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            spacing: Appearance.sizes.elevationMargin / 2
                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.large
                                color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name
                                elide: Text.ElideRight
                                font.weight: Font.DemiBold
                                color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            }
                            KeyHint {
                                visible: modelData.keyHint.length > 0
                                keys: modelData.keyHint
                                surface: root.selectedIndex === index ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                                onSurface: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            }

                            ConfiguredKeyHint {
                                // Native action shortcuts already occupy the row. Enter is
                                // shown here only for actions without one (and in the footer
                                // for every selected action), so hints cannot overlap.
                                visible: modelData.keyHint.length === 0
                                    && root.selectedIndex === index
                                    && Config.options.search.appearance.showKeyHints
                                actionId: "activate"
                                fallbackKeys: ["↵"]
                                surface: Appearance.colors.colPrimaryContainer
                                onSurface: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.rows.length === 0
                    spacing: Appearance.sizes.elevationMargin / 2
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.targetWindow ? "search_off" : "select_window"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: root.targetWindow ? Translation.tr("No actions match this filter") : Translation.tr("No open windows found")
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
