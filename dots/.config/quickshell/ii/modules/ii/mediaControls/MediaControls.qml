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
    property list<real> visualizerPoints: mediaControlsLoader.active ? CavaService.visualizerPoints : []
    readonly property bool targetHovered: GlobalStates.mediaWidgetHovered
    property bool popupHovered: false
    property bool stickyActive: false
    property bool openedViaHover: false

    Timer {
        id: hoverGraceTimer
        interval: 100 + Math.max(0, Config.options?.bar?.tooltips?.closeDelay ?? 0)
        repeat: false
        onTriggered: {
            if (!GlobalStates.mediaControlsPinned && !root.targetHovered && !root.popupHovered) {
                root.stickyActive = false;
                GlobalStates.mediaControlsOpen = false;
            }
        }
    }

    function evaluateHoverState() {
        if (!root.openedViaHover || GlobalStates.mediaControlsPinned)
            return;
        if (root.targetHovered || root.popupHovered) {
            root.stickyActive = true;
            hoverGraceTimer.stop();
        } else if (root.stickyActive && !hoverGraceTimer.running) {
            hoverGraceTimer.start();
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
                hoverGraceTimer.stop();
            }
        }
        function onMediaControlsPinnedChanged() {
            if (!GlobalStates.mediaControlsPinned)
                root.evaluateHoverState();
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



    Loader {
        id: mediaControlsLoader
        active: GlobalStates.mediaControlsOpen
        onActiveChanged: {
            if (!mediaControlsLoader.active) {
                hoverGraceTimer.stop();
                root.popupHovered = false;
                root.stickyActive = false;
            }
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: playerColumnLayout.implicitWidth * panelWindow.layoutScale
            implicitHeight: playerColumnLayout.implicitHeight * panelWindow.layoutScale
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
            readonly property real layoutScale: {
                if (!screen || screen.height <= 0)
                    return 1.0;
                var baseScale = Math.max(0.75, Math.min(1.5, screen.height / 1080.0));
                var userMultiplier = Config.options?.bar?.tooltips?.popupScaleMultiplier ?? 1.0;
                var scale = baseScale * userMultiplier;
                var safeHeight = screen.height - barThickness - Appearance.sizes.elevationMargin * 2 - 40;
                var safeWidth = screen.width * 0.9;
                var contentHeight = playerColumnLayout.implicitHeight + 20;
                var contentWidth = playerColumnLayout.implicitWidth + 20;
                if (contentHeight > 0 && contentHeight * scale > safeHeight)
                    scale = Math.min(scale, Math.max(0.5, safeHeight / contentHeight));
                if (contentWidth > 0 && contentWidth * scale > safeWidth)
                    scale = Math.min(scale, Math.max(0.5, safeWidth / contentWidth));
                return scale;
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
                            return Math.max(0, (screen.height - panelWindow.implicitHeight) / 2);
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
                            return Math.max(0, (screen.width - panelWindow.implicitWidth) / 2);
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
                item: scaledContent
            }

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.mediaControlsOpen = false;
                }
            }

            Item {
                id: scaledContent
                anchors.centerIn: parent
                width: playerColumnLayout.implicitWidth * panelWindow.layoutScale
                height: playerColumnLayout.implicitHeight * panelWindow.layoutScale
                scale: 1.0

                HoverHandler {
                    onHoveredChanged: root.popupHovered = hovered
                }

                ColumnLayout {
                    id: playerColumnLayout
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    scale: panelWindow.layoutScale
                    spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

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
