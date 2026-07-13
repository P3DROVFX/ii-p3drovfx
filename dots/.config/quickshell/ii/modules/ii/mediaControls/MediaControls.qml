pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland
import "../bar" as Bar
import "../bar/widgets/media"

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: filterDuplicatePlayers(realPlayers)
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
    property list<real> visualizerPoints: []

    property bool popupHovered: false
    readonly property bool targetHovered: GlobalStates.mediaWidgetHovered
    property bool stickyActive: false
    property bool openedViaHover: false

    property QtObject _timers: QtObject {
        property Timer grace: Timer {
            id: graceTimer
            interval: 400 // 400ms grace period to transit from widget to popup
            repeat: false
            onTriggered: {
                if (!GlobalStates.mediaControlsPinned) {
                    root.stickyActive = false;
                    GlobalStates.mediaControlsOpen = false;
                }
            }
        }
    }

    function evaluateHoverState() {
        if (!openedViaHover || GlobalStates.mediaControlsPinned)
            return;

        if (targetHovered || popupHovered) {
            stickyActive = true;
            _timers.grace.stop();
        } else if (stickyActive && !_timers.grace.running) {
            _timers.grace.start();
        }
    }

    onTargetHoveredChanged: evaluateHoverState()
    onPopupHoveredChanged: evaluateHoverState()

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) {
                root.openedViaHover = GlobalStates.mediaWidgetHovered;
                if (root.openedViaHover) {
                    root.stickyActive = true;
                    root.evaluateHoverState();
                }
            } else {
                root.openedViaHover = false;
                root.stickyActive = false;
                root._timers.grace.stop();
            }
        }
        function onMediaControlsPinnedChanged() {
            if (!GlobalStates.mediaControlsPinned) {
                root.evaluateHoverState();
            }
        }
    }

    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];

            // Find duplicates by trackTitle prefix
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                if (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (p1.position - p2.position <= 2 && p1.length - p2.length <= 2)) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    Process {
        id: cavaProc
        running: mediaControlsLoader.active
        onRunningChanged: {
            if (!cavaProc.running) {
                root.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                // Parse `;`-separated values into the visualizerPoints array
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
    }

    Loader {
        id: mediaControlsLoader
        active: GlobalStates.mediaControlsOpen
        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
            if (!mediaControlsLoader.active) {
                GlobalStates.mediaControlsPinned = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: playerColumnLayout.implicitWidth
            implicitHeight: playerColumnLayout.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"

            readonly property var rect: GlobalStates.mediaPopupRect
            readonly property real barThickness: {
                if (Config.options.bar.vertical) {
                    return Appearance.sizes.verticalBarWidth;
                } else {
                    return Appearance.sizes.barHeight;
                }
            }
            anchors {
                top: true
                left: !Config.options.bar.vertical || !Config.options.bar.bottom
                right: Config.options.bar.vertical && Config.options.bar.bottom
            }
            margins {
                top: {
                    if (Config.options.bar.vertical) {
                        if (rect.height === 0)
                            return 0;
                        let targetY = rect.y + (rect.height / 2) - (panelWindow.implicitHeight / 2);
                        return Math.max(0, Math.min(targetY, screen.height - panelWindow.implicitHeight));
                    } else {
                        if (!Config.options.bar.bottom) {
                            return barThickness + 2;
                        } else {
                            return screen.height - barThickness - panelWindow.implicitHeight - 2;
                        }
                    }
                }
                left: {
                    if (Config.options.bar.vertical) {
                        if (!Config.options.bar.bottom) {
                            return barThickness + 2;
                        }
                        return 0;
                    } else {
                        if (rect.width === 0)
                            return 0;
                        let targetX = rect.x + (rect.width / 2) - (panelWindow.implicitWidth / 2);
                        return Math.max(0, Math.min(targetX, screen.width - panelWindow.implicitWidth));
                    }
                }
                right: {
                    if (Config.options.bar.vertical && Config.options.bar.bottom) {
                        return barThickness + 2;
                    }
                    return 0;
                }
            }

            mask: Region {
                item: playerColumnLayout
            }

            Component.onCompleted: {
                if (!GlobalStates.mediaControlsPinned && !root.openedViaHover) {
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (!GlobalStates.mediaControlsPinned) {
                        GlobalStates.mediaControlsOpen = false;
                    }
                }
            }
            Connections {
                target: GlobalStates
                function onMediaControlsPinnedChanged() {
                    if (GlobalStates.mediaControlsPinned) {
                        GlobalFocusGrab.removeDismissable(panelWindow);
                    } else if (!root.openedViaHover) {
                        GlobalFocusGrab.addDismissable(panelWindow);
                    }
                }
            }

            ColumnLayout {
                id: playerColumnLayout
                anchors.fill: parent
                spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                HoverHandler {
                    id: popupHoverHandler
                    onHoveredChanged: {
                        root.popupHovered = hovered;
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: Loader {
                        id: delegateLoader
                        required property MprisPlayer modelData

                        sourceComponent: {
                            switch (Config.options.bar.mediaPlayer.popupStyle) {
                            case "expressive": return expressiveComp;
                            case "android": return androidComp;
                            default: return standardComp;
                            }
                        }

                        Component {
                            id: expressiveComp
                            ExpressiveMediaCard {
                                player: delegateLoader.modelData
                            }
                        }

                        Component {
                            id: androidComp
                            AndroidMediaPopup {
                                player: delegateLoader.modelData
                                visualizerPoints: root.visualizerPoints
                                implicitWidth: root.widgetWidth
                                implicitHeight: root.widgetHeight
                            }
                        }

                        Component {
                            id: standardComp
                            PlayerControl {
                                player: delegateLoader.modelData
                                visualizerPoints: root.visualizerPoints
                                implicitWidth: root.widgetWidth
                                implicitHeight: root.widgetHeight
                                radius: root.popupRounding
                            }
                        }
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
                        property real padding: 20
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            mediaControlsLoader.active = !mediaControlsLoader.active;
            if (mediaControlsLoader.active)
                Notifications.timeoutAll();
        }

        function close(): void {
            mediaControlsLoader.active = false;
        }

        function open(): void {
            mediaControlsLoader.active = true;
            Notifications.timeoutAll();
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
