pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.easyEffects.components
import qs.modules.ii.easyEffects.tabs

/**
 * The app inside the window, built from the clock app's frame so the two read as one
 * family — the bar across the top, the rail on the left (Settings at its foot), the
 * current tab, side sheets on the right for the effect editor and the pickers — with this
 * app's own pieces (EasyEffectsStyle and the components beside it) for everything inside.
 *
 * Only the visible tab exists. The editor (the preset being edited) belongs to this
 * item and goes with the window.
 */
FocusScope {
    id: root

    signal closeRequested()

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property var appState: Persistent.states.easyEffectsApp
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    readonly property bool railExpanded: root.canExpandRail && (root.appState?.railExpanded ?? true)
    readonly property real railWidth: root.railExpanded ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real sheetWidth: root.compact
        ? root.width - ClockStyle.paneGap * 2
        : Math.max(EasyEffectsStyle.sheetWidthMin, Math.min(EasyEffectsStyle.sheetWidth, root.width * 0.32))
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap)
        - (sidePanel.open && !root.compact ? root.sheetWidth + ClockStyle.paneGap : 0))
    /// A bar too narrow for labelled buttons: the pipeline switch and Import go icon-only
    /// so the device strip keeps some room.
    readonly property bool tightBar: root.width < 1100
    readonly property bool wide: root.pageLayoutWidth >= ClockStyle.mediumMax
    /// Where a page's hero stands beside its content instead of above it.
    readonly property bool heroBeside: root.pageLayoutWidth >= EasyEffectsStyle.heroSideMin

    // ── Tabs ────────────────────────────────────────────────────────────
    readonly property var tabs: [
        { id: "presets", icon: "library_music", label: Translation.tr("Presets") },
        { id: "effects", icon: "instant_mix", label: Translation.tr("Effects") },
        { id: "devices", icon: "speaker_group", label: Translation.tr("Devices") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        presets: presetsComponent,
        effects: effectsComponent,
        devices: devicesComponent
    })
    readonly property var badges: ({
        presets: "",
        effects: editor.dirty ? "•" : "",
        devices: ""
    })

    property string currentTab: ""
    property bool settingsOpen: false

    readonly property bool shown: root.Window.window?.visible ?? true

    EasyEffectsEditor {
        id: editor
        pipeline: root.appState?.pipeline === "input" ? "input" : "output"
        // Looking at a device that isn't playing: the app works on the preset it starts with.
        detached: !deviceView.isCurrent
        detachedPreset: deviceView.saved
    }

    DeviceView {
        id: deviceView
        pipeline: editor.pipeline
    }

    onShownChanged: {
        EasyEffects.hold("app", root.shown);
        if (root.shown) {
            EasyEffects.refreshPresets();
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            sidePanel.closeNow();
            root.settingsOpen = false;
        }
    }

    Component.onCompleted: {
        root.currentTab = root.initialTab();
        EasyEffects.hold("app", root.shown);
        EasyEffects.refreshPresets();
    }

    Component.onDestruction: EasyEffects.hold("app", false)

    function initialTab(): string {
        const pending = GlobalStates.easyEffectsAppPendingTab;
        GlobalStates.easyEffectsAppPendingTab = "";
        if (root.tabIds.includes(pending))
            return pending;
        const start = Config.options.easyEffects?.startTab ?? "last";
        if (start !== "last" && root.tabIds.includes(start))
            return start;
        const last = root.appState?.tab ?? "presets";
        return root.tabIds.includes(last) ? last : "presets";
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        if (tabId !== root.currentTab)
            sidePanel.closeNow();
        root.currentTab = tabId;
        root.appState.tab = tabId;
    }

    function setPipeline(pipeline: string): void {
        if (editor.pipeline === pipeline)
            return;
        sidePanel.closeNow();
        root.appState.pipeline = pipeline;
    }

    function toggleSettings(): void {
        sidePanel.closeNow();
        root.settingsOpen = !root.settingsOpen;
    }

    Connections {
        target: GlobalStates
        function onEasyEffectsAppPendingTabChanged() {
            const pending = GlobalStates.easyEffectsAppPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.easyEffectsAppPendingTab = "";
            root.selectTab(pending);
        }
    }

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.toggleSettings();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_S && editor.dirty) {
            editor.save();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && sidePanel.open) {
            sidePanel.close();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.settingsOpen) {
            root.settingsOpen = false;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: EasyEffectsStyle.colBackground
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        EasyEffectsTopBar {
            Layout.fillWidth: true
            title: root.settingsOpen ? Translation.tr("EasyEffects settings")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: {
                if (root.settingsOpen)
                    return "";
                if (!EasyEffects.available)
                    return Translation.tr("EasyEffects isn't installed");
                if (!EasyEffects.running)
                    return EasyEffects.starting ? Translation.tr("Starting EasyEffects…") : Translation.tr("EasyEffects isn't running");
                const device = deviceView.label;
                const preset = editor.presetName.length > 0 ? editor.presetName : Translation.tr("no preset");
                return `${device} · ${preset}${EasyEffects.bypassed && deviceView.isCurrent ? " · " + Translation.tr("bypassed") : ""}`;
            }
            showBack: root.settingsOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railExpanded
            onBackRequested: root.settingsOpen = false
            onRailToggled: root.appState.railExpanded = !root.appState.railExpanded
            onCloseRequested: root.closeRequested()
            centerActive: root.currentTab === "presets" && !root.settingsOpen && deviceView.devices.length > 1

            // Which device the Presets page is about: the connected ones, scrolling sideways
            // when they don't fit.
            center: [
                Flickable {
                    id: deviceScroll
                    anchors.fill: parent
                    contentWidth: deviceRow.implicitWidth
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => deviceScroll.contentX = Math.max(0, Math.min(deviceScroll.contentWidth - deviceScroll.width,
                            deviceScroll.contentX - (event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y)))
                    }

                    Row {
                        id: deviceRow
                        height: deviceScroll.height
                        spacing: EasyEffectsStyle.gapSmall

                        Repeater {
                            model: deviceView.devices

                            DeviceChip {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                symbol: deviceView.symbolFor(modelData)
                                label: Audio.friendlyDeviceName(modelData)
                                preset: deviceView.savedFor(modelData)
                                selected: modelData === deviceView.node
                                playing: modelData === deviceView.current
                                maxWidth: EasyEffectsStyle.sheetWidth
                                onTriggered: {
                                    deviceView.look(modelData === deviceView.current ? "" : modelData.name);
                                    // Bring the chip into view.
                                    const left = x;
                                    const right = x + width;
                                    if (left < deviceScroll.contentX)
                                        deviceScroll.contentX = left;
                                    else if (right > deviceScroll.contentX + deviceScroll.width)
                                        deviceScroll.contentX = right - deviceScroll.width;
                                }
                            }
                        }
                    }
                }
            ]

            // Output / input: which pipeline every tab works on.
            EasyEffectsSegmented {
                visible: !root.settingsOpen && root.currentTab !== "devices"
                compact: root.compact || root.tightBar
                current: editor.pipeline
                options: [
                    { id: "output", icon: "speaker", label: Translation.tr("Output") },
                    { id: "input", icon: "mic", label: Translation.tr("Input") }
                ]
                onChosen: id => root.setPipeline(id)
            }

            // The presets page's file actions: the page itself owns what they do.
            EasyEffectsButton {
                visible: root.currentTab === "presets" && !root.settingsOpen && EasyEffects.available
                symbol: "upload_file"
                label: Translation.tr("Import")
                iconOnly: root.compact || root.tightBar
                onClicked: pageLoader.item?.importPreset?.()
            }

            EasyEffectsButton {
                visible: root.currentTab === "presets" && !root.settingsOpen && EasyEffects.available
                iconOnly: true
                symbol: "folder_open"
                label: Translation.tr("Open folder")
                onClicked: Qt.openUrlExternally(`file://${EasyEffects.presetsDir}/${editor.pipeline}`)
            }

            EasyEffectsButton {
                visible: EasyEffects.available && !EasyEffects.running
                variant: "filled"
                symbol: "play_arrow"
                label: EasyEffects.starting ? Translation.tr("Starting…") : Translation.tr("Start")
                enabled: !EasyEffects.starting
                onClicked: EasyEffects.start()
            }

            EasyEffectsButton {
                visible: EasyEffects.running
                iconOnly: true
                variant: EasyEffects.bypassed ? "filled" : "tonal"
                symbol: EasyEffects.bypassed ? "graphic_eq" : "do_not_disturb_on"
                label: EasyEffects.bypassed ? Translation.tr("Turn effects back on") : Translation.tr("Bypass all effects")
                onClicked: EasyEffects.toggleBypass()
            }

            EasyEffectsButton {
                visible: EasyEffects.available
                iconOnly: true
                symbol: "open_in_new"
                label: Translation.tr("Open EasyEffects' own window")
                onClicked: EasyEffects.openNativeWindow()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ClockRail {
                Layout.fillHeight: true
                Layout.preferredWidth: root.railWidth
                Layout.rightMargin: ClockStyle.paneGap
                visible: !root.compact
                tabs: root.tabs
                currentTab: root.currentTab
                expanded: root.railExpanded
                settingsOpen: root.settingsOpen
                settingsTooltip: Translation.tr("EasyEffects settings")
                rowHeight: EasyEffectsStyle.railRowHeight
                paneRadius: EasyEffectsStyle.radiusPane
                iconSize: EasyEffectsStyle.iconLarge
                labelSize: EasyEffectsStyle.textBody
                badges: root.badges
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: root.toggleSettings()

                Behavior on Layout.preferredWidth {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !(root.compact && sidePanel.open)
                spacing: ClockStyle.paneGap

                Item {
                    id: pageArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Loader {
                        id: pageLoader
                        anchors.fill: parent
                        focus: !root.settingsOpen && !sidePanel.open
                        visible: !root.settingsOpen
                        sourceComponent: EasyEffects.available
                            ? (root.tabComponents[root.currentTab] ?? null) : notInstalledComponent
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.settingsOpen
                        visible: active
                        z: 10
                        sourceComponent: EasyEffectsSettingsPage {
                            compact: root.compact
                            layoutWidth: root.pageLayoutWidth
                        }
                    }
                }

                ClockNavigation {
                    Layout.fillWidth: true
                    visible: root.compact
                    tabs: root.tabs
                    currentTab: root.currentTab
                    onSelected: tabId => root.selectTab(tabId)
                }
            }

            Item {
                id: sheetSlot
                Layout.fillHeight: true
                Layout.preferredWidth: sidePanel.open ? root.sheetWidth + (root.compact ? 0 : ClockStyle.paneGap) : 0
                visible: Layout.preferredWidth > 1
                clip: true

                Behavior on Layout.preferredWidth {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                ClockSidePanel {
                    id: sidePanel
                    anchors {
                        top: parent.top
                        bottom: parent.bottom
                        right: parent.right
                    }
                    width: root.sheetWidth
                }
            }
        }
    }

    Component {
        id: notInstalledComponent

        Item {
            ClockEmptyState {
                anchors.centerIn: parent
                symbol: "graphic_eq"
                title: Translation.tr("EasyEffects isn't installed")
                subtitle: Translation.tr("Install EasyEffects (the easyeffects package or the Flathub app) to use presets and effects here.")
            }
        }
    }

    Component {
        id: presetsComponent
        PresetsTab {
            editor: editor
            view: deviceView
            panels: sidePanel
            compact: root.compact
            wide: root.wide
            layoutWidth: root.pageLayoutWidth
            heroBeside: root.heroBeside
            onEditRequested: root.selectTab("effects")
        }
    }

    Component {
        id: effectsComponent
        EffectsTab {
            editor: editor
            panels: sidePanel
            compact: root.compact
            wide: root.wide
            layoutWidth: root.pageLayoutWidth
        }
    }

    Component {
        id: devicesComponent
        DevicesTab {
            panels: sidePanel
            compact: root.compact
            wide: root.wide
            layoutWidth: root.pageLayoutWidth
        }
    }
}
