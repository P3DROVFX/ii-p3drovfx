import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * The usage overlay: per-app screen time and energy, on Super+U.
 *
 * Same shape as the cheatsheet — one centred surface on the overlay layer, held
 * open by a focus grab and dismissed by anything that takes focus away. The whole
 * window is torn down on close rather than merely hidden, so the histogram and the
 * app list cost nothing while it is shut.
 */
Scope {
    id: root

    property bool activeState: false
    // The surface is destroyed on close, so what was being looked at is held out
    // here. Granularity and metric are keys rather than indexes: the config stores
    // them by name, and a reordered tab row must not silently change what opens.
    property string granularity: "day"
    property string metricKey: "fg"
    /// Which half of the overlay is on screen: "apps" or "battery". The battery
    /// view exists only on a machine that has one.
    property string view: "apps"
    property int periodOffset: 0
    property string selectedKey: ""
    // What the next opening starts on, written only by `resolveView`. Kept apart
    // from the two above because the panel writes those back as it is built, which
    // would otherwise overwrite the view being asked for before it is applied.
    property string pendingGranularity: "day"
    property string pendingMetric: "fg"
    property string pendingView: "apps"

    /// Which view a fresh opening starts on. Always the current period — going back
    /// is deliberate, and reopening days later onto a stale month would read as
    /// missing data.
    function resolveView() {
        const opts = Config.options.appStats;
        const remembered = opts?.rememberLastView ?? true;
        root.pendingGranularity = (remembered ? opts?.lastGranularity : opts?.defaultGranularity) ?? "day";
        root.pendingMetric = (remembered ? opts?.lastMetric : opts?.defaultMetric) ?? "fg";
        // A remembered battery view on a machine that no longer has one — a dock
        // pulled, or a config carried to a desktop — would open on nothing.
        root.pendingView = (Battery.available && remembered ? opts?.lastView : "apps") ?? "apps";
        root.granularity = root.pendingGranularity;
        root.metricKey = root.pendingMetric;
        root.view = root.pendingView;
        root.periodOffset = 0;
        if (!(opts?.keepSelection ?? false))
            root.selectedKey = "";
    }

    function rememberView() {
        if (!(Config.options.appStats?.rememberLastView ?? true))
            return;
        Config.options.appStats.lastGranularity = root.granularity;
        Config.options.appStats.lastMetric = root.metricKey;
        Config.options.appStats.lastView = root.view;
    }

    Connections {
        target: GlobalStates

        function onUsageOpenChanged() {
            if (GlobalStates.usageOpen && !root.activeState) {
                root.requestOpen();
            } else if (!GlobalStates.usageOpen && root.activeState) {
                root.requestClose();
            }
        }
    }

    // Outlives the close animation, so the surface is not destroyed mid-fade.
    Timer {
        id: closeTimer
        interval: 400
        onTriggered: root.activeState = false
    }

    function requestOpen() {
        closeTimer.stop();
        AppStats.checkInstall();
        root.resolveView();
        root.activeState = true;
        GlobalStates.usageOpen = true;
    }

    function requestClose() {
        GlobalStates.usageOpen = false;
        closeTimer.start();
    }

    function requestToggle() {
        if (GlobalStates.usageOpen) {
            root.requestClose();
        } else {
            root.requestOpen();
        }
    }

    Loader {
        id: usageLoader
        active: root.activeState

        sourceComponent: PanelWindow {
            id: usageRoot

            visible: usageLoader.active
            color: "transparent"
            exclusiveZone: 0
            implicitWidth: usageBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: usageBackground.height + Appearance.sizes.elevationMargin * 2

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.namespace: "quickshell:usage"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.usageOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Clicks outside the panel belong to whatever is underneath.
            mask: Region {
                item: usageInputMask
            }

            function hide() {
                root.requestClose();
            }

            // Registering the grab immediately would catch the keypress that opened
            // the overlay and close it again.
            Timer {
                id: registerGrabTimer
                interval: 150
                onTriggered: GlobalFocusGrab.addDismissable(usageRoot)
            }

            Component.onCompleted: registerGrabTimer.start()

            Component.onDestruction: {
                registerGrabTimer.stop();
                GlobalFocusGrab.removeDismissable(usageRoot);
            }

            Connections {
                target: GlobalFocusGrab

                function onDismissed() {
                    usageRoot.hide();
                }
            }

            onVisibleChanged: {
                if (visible)
                    initialFocusTimer.restart();
            }

            Timer {
                id: initialFocusTimer
                interval: 50
                onTriggered: usageBackground.forceActiveFocus()
            }

            Item {
                id: usageInputMask
                anchors.centerIn: parent
                width: usageBackground.width
                height: usageBackground.height
            }

            Item {
                id: dialogWrap
                anchors.fill: parent
                transformOrigin: Item.Center
                scale: usageBackground.animateIn && GlobalStates.usageOpen ? 1.0 : 0.94
                opacity: usageBackground.animateIn && GlobalStates.usageOpen ? 1.0 : 0.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                StyledRectangularShadow {
                    target: usageBackground
                }

                Rectangle {
                    id: usageBackground

                    property real padding: 20
                    property bool animateIn: false
                    readonly property real maxBgWidth: usageRoot.screen ? usageRoot.screen.width * 0.95 : 1900
                    readonly property real maxBgHeight: usageRoot.screen ? usageRoot.screen.height * 0.80 : 1000

                    anchors.centerIn: parent
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.windowRounding
                    implicitWidth: Math.min(maxBgWidth, usageColumnLayout.implicitWidth + padding * 2)
                    implicitHeight: Math.min(maxBgHeight, usageColumnLayout.implicitHeight + padding * 2)

                    // Held back one frame so the panel is laid out before it moves.
                    Timer {
                        id: animDelayTimer
                        interval: 80
                        running: true
                        onTriggered: usageBackground.animateIn = true
                    }

                    // Escape belongs to the window; everything else is the content's
                    // to claim, so range, metric and the app list stay reachable
                    // without leaving the keyboard the overlay was opened from.
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            usageRoot.hide();
                            event.accepted = true;
                            return;
                        }
                        const target = usageBatteryLoader.item ?? usageContent;
                        event.accepted = target.handleKey(event.key);
                    }

                    RippleButton {
                        id: closeButton

                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        scale: usageBackground.animateIn ? 1.0 : 0.0
                        onClicked: usageRoot.hide()

                        anchors {
                            top: parent.top
                            right: parent.right
                            topMargin: 20
                            rightMargin: 20
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.5
                            }
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.title
                            text: "close"
                            rotation: closeButton.isHovered ? 90 : 0

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.5
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: usageColumnLayout

                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - parent.padding * 2)
                        height: Math.min(implicitHeight, parent.height - parent.padding * 2)
                        spacing: 12

                        // The tabs name the overlay, so there is no title beside
                        // them. Anchored rather than laid out: centred on the
                        // window, not on whatever space the note beside them left.
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: viewTabs.visible ? viewTabs.implicitHeight : soleTitle.implicitHeight

                            // Only on a machine with a pack to draw. A desktop has
                            // one view, and a lone tab is not a choice.
                            SecondaryTabBar {
                                id: viewTabs

                                visible: Battery.available && AppStats.binaryPresent
                                width: 360
                                anchors.horizontalCenter: parent.horizontalCenter
                                currentIndex: root.view === "battery" ? 1 : 0

                                onCurrentIndexChanged: {
                                    const nextView = viewTabs.currentIndex === 1 ? "battery" : "apps";
                                    if (root.view !== nextView) {
                                        root.view = nextView;
                                        root.rememberView();
                                    }
                                }

                                Repeater {
                                    model: [Translation.tr("App usage"), Translation.tr("Battery")]

                                    delegate: SecondaryTabButton {
                                        required property string modelData

                                        buttonText: modelData
                                    }
                                }
                            }

                            // With one view there is nothing to switch, so the name
                            // is stated instead of dressed up as a choice.
                            StyledText {
                                id: soleTitle

                                visible: !viewTabs.visible
                                anchors.centerIn: parent
                                text: Translation.tr("App usage")
                                font.pixelSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colOnLayer0
                            }

                            // The energy source decides whether watt-hours are real
                            // counters or a battery-drain guess, so it is stated
                            // rather than left for the user to infer.
                            StyledText {
                                visible: AppStats.running && root.view === "apps"
                                text: {
                                    switch (AppStats.source) {
                                    case "rapl":
                                        return Translation.tr("Energy from RAPL counters");
                                    case "battery":
                                        return Translation.tr("Energy estimated from battery drain");
                                    default:
                                        return Translation.tr("Energy unavailable");
                                    }
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext

                                anchors {
                                    right: parent.right
                                    rightMargin: 52
                                    verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Nothing was ever collected without the daemon, so the panel
                        // says how to get one instead of drawing an empty chart.
                        Loader {
                            readonly property real calculatedWidth: usageRoot.screen ? usageRoot.screen.width * 0.92 : 1700
                            readonly property real calculatedHeight: usageRoot.screen ? usageRoot.screen.height * 0.62 : 650

                            active: !AppStats.binaryPresent
                            visible: active
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: Math.min(1100, Math.max(760, calculatedWidth))
                            Layout.preferredHeight: Math.min(700, Math.max(460, calculatedHeight))

                            sourceComponent: UsageSetup {}
                        }

                        UsageContent {
                            id: usageContent

                            readonly property real calculatedWidth: usageRoot.screen ? usageRoot.screen.width * 0.92 : 1700
                            readonly property real calculatedHeight: usageRoot.screen ? usageRoot.screen.height * 0.62 : 650

                            visible: AppStats.binaryPresent && root.view === "apps"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: Math.min(1500, Math.max(900, calculatedWidth))
                            Layout.preferredHeight: Math.min(700, Math.max(460, calculatedHeight))

                            initialGranularity: root.pendingGranularity
                            initialMetric: root.pendingMetric
                            periodOffset: root.periodOffset
                            selectedKey: root.selectedKey

                            onPeriodOffsetChanged: root.periodOffset = usageContent.periodOffset
                            onSelectedKeyChanged: root.selectedKey = usageContent.selectedKey
                            onGranularityChanged: {
                                root.granularity = usageContent.granularity;
                                root.rememberView();
                            }
                            onMetricChanged: {
                                root.metricKey = usageContent.metric.key;
                                root.rememberView();
                            }
                        }

                        // Built only once asked for: a machine on AC all week never
                        // opens it, and it parses the same day files the app view
                        // has just been through.
                        Loader {
                            id: usageBatteryLoader

                            readonly property real calculatedWidth: usageRoot.screen ? usageRoot.screen.width * 0.92 : 1700
                            readonly property real calculatedHeight: usageRoot.screen ? usageRoot.screen.height * 0.62 : 650

                            active: AppStats.binaryPresent && Battery.available && root.view === "battery"
                            visible: active
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: Math.min(1500, Math.max(900, calculatedWidth))
                            Layout.preferredHeight: Math.min(700, Math.max(460, calculatedHeight))

                            sourceComponent: UsageBattery {
                                initialGranularity: root.pendingGranularity
                                periodOffset: root.periodOffset

                                onPeriodOffsetChanged: root.periodOffset = periodOffset
                                onGranularityChanged: {
                                    root.granularity = granularity;
                                    root.rememberView();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "usage"

        function toggle(): void {
            root.requestToggle();
        }

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }
    }

    GlobalShortcut {
        name: "usageToggle"
        description: "Toggles the app usage overlay on press"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "usageOpen"
        description: "Opens the app usage overlay on press"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "usageClose"
        description: "Closes the app usage overlay on press"
        onPressed: root.requestClose()
    }
}
