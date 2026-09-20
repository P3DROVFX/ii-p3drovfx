import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets

Item {
    id: touchRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var opts: (Config.options && Config.options.interactions && Config.options.interactions.touchGestures)
        ? Config.options.interactions.touchGestures
        : null

    Component.onCompleted: {
        TouchGestureService.checkBinary();
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Master & Daemon Status ────────────────────────────────────────────
        ContentSection {
            icon: "touch_app"
            title: Translation.tr("Touchscreen Gestures")
            tooltip: Translation.tr("Native touchscreen swipe gestures, helper daemon status and visual feedback.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                TouchGestureStatusCard {
                    Layout.fillWidth: true
                }

                ConfigSwitch {
                    buttonIcon: "touch_app"
                    text: Translation.tr("Enable touchscreen gestures")
                    checked: (touchRoot.opts && touchRoot.opts.enable) ? true : false
                    onCheckedChanged: {
                        if (Config.ready && touchRoot.opts && checked !== touchRoot.opts.enable) {
                            touchRoot.opts.enable = checked;
                        }
                    }
                }

                ConfigSwitch {
                    buttonIcon: "visibility"
                    text: Translation.tr("Show visual feedback indicator during gestures")
                    checked: (touchRoot.opts && touchRoot.opts.visualFeedback !== undefined) ? touchRoot.opts.visualFeedback : true
                    onCheckedChanged: {
                        if (Config.ready && touchRoot.opts && checked !== touchRoot.opts.visualFeedback) {
                            touchRoot.opts.visualFeedback = checked;
                        }
                    }
                }

                HelperCodeBox {
                    // Also shown when the daemon is behind its sources: an update
                    // replaces those and carries the built binary across, so gestures
                    // can keep running last month's code without a sign of it.
                    visible: !TouchGestureService.binaryExists || TouchGestureService.helperOutdated
                        || TouchGestureService.building || TouchGestureService.buildResult === "failed"
                    Layout.fillWidth: true
                    icon: "terminal"
                    title: TouchGestureService.helperOutdated ? Translation.tr("Update the gesture daemon")
                        : Translation.tr("Compile Rust Helper Daemon")
                    text: TouchGestureService.helperState === "stale" ? Translation.tr("The daemon on this machine was built from an older version of its source. Gestures keep working as they are; rebuilding takes about a minute and the daemon restarts itself onto the new binary.")
                        : (TouchGestureService.helperState === "unknown" ? Translation.tr("The daemon was built before the shell started recording what it was built from, so there is no way to tell whether it is current. Rebuilding settles it.")
                        : Translation.tr("To compile and install the native touch listener daemon, run this command in your terminal (requires Rust toolchain and cargo), or press the button:"))
                    codeSnippet: Directories.rustHelpersScriptPath + " build touch_gestures"
                    snippetWrapMode: Text.Wrap

                    actionText: TouchGestureService.helperOutdated ? Translation.tr("Rebuild it now") : Translation.tr("Build it now")
                    actionIcon: "build"
                    actionBusy: TouchGestureService.building
                    busyText: Translation.tr("Building…")
                    statusIsError: TouchGestureService.buildResult === "failed" || !TouchGestureService.cargoAvailable
                    statusText: {
                        if (!TouchGestureService.cargoAvailable)
                            return Translation.tr("Rust and cargo are not installed, so the build cannot run here.");
                        if (TouchGestureService.building)
                            return Translation.tr("Compiling — this takes about a minute the first time.");
                        if (TouchGestureService.buildResult === "failed")
                            return Translation.tr("The build failed: %1").arg(
                                TouchGestureService.buildOutput.split("\n").slice(-3).join(" "));
                        return "";
                    }
                    onActionClicked: TouchGestureService.buildHelper()

                    Component.onCompleted: TouchGestureService.refreshHelperState()
                }

                HelperCodeBox {
                    visible: !TouchGestureService.binaryExists
                    Layout.fillWidth: true
                    icon: "vpn_key"
                    title: Translation.tr("Linux Input Group Permissions")
                    text: Translation.tr("If the helper reports permission denied when reading /dev/input, add your user to the input group and restart your session:")
                    codeSnippet: "sudo usermod -aG input $USER"
                    snippetWrapMode: Text.Wrap
                }
            }
        }

        // ── Device & Output Mapping ───────────────────────────────────────────
        ContentSection {
            icon: "devices"
            title: Translation.tr("Device & Output Mapping")
            tooltip: Translation.tr("Select input hardware, coordinate rotation and monitor targeting.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    icon: "touch_app"
                    title: Translation.tr("Touchscreen device")
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: (touchRoot.opts && touchRoot.opts.deviceId) ? touchRoot.opts.deviceId : "auto"
                        onSelected: function(newValue) {
                            if (Config.ready && touchRoot.opts) touchRoot.opts.deviceId = newValue;
                        }
                        options: {
                            var list = [{
                                displayName: Translation.tr("Automatic"),
                                icon: "auto_awesome",
                                value: "auto"
                            }];
                            if (TouchGestureService.devices) {
                                for (var i = 0; i < TouchGestureService.devices.length; ++i) {
                                    var dev = TouchGestureService.devices[i];
                                    list.push({
                                        displayName: dev.name ? dev.name : dev.deviceId,
                                        icon: dev.kind === "pen" ? "stylus" : "touch_app",
                                        value: dev.deviceId
                                    });
                                }
                            }
                            return list;
                        }
                    }
                }

                ConfigSwitch {
                    buttonIcon: "stylus"
                    text: Translation.tr("Let the stylus trigger gestures")
                    checked: (touchRoot.opts && touchRoot.opts.includeStylus) ? true : false
                    enabled: !touchRoot.opts || touchRoot.opts.deviceId === "auto"
                    onCheckedChanged: {
                        if (Config.ready && touchRoot.opts && checked !== touchRoot.opts.includeStylus) {
                            touchRoot.opts.includeStylus = checked;
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("A pen also moves the pointer, so an edge swipe with it can drag or resize the window underneath at the same time. Ignored when a device is picked explicitly above.")
                    }
                }

                ContentSubsection {
                    icon: "monitor"
                    title: Translation.tr("Target monitor")
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: (touchRoot.opts && touchRoot.opts.targetMonitor) ? touchRoot.opts.targetMonitor : "auto"
                        onSelected: function(newValue) {
                            if (Config.ready && touchRoot.opts) touchRoot.opts.targetMonitor = newValue;
                        }
                        options: {
                            var list = [{
                                displayName: Translation.tr("Automatic / focused"),
                                icon: "center_focus_strong",
                                value: "auto"
                            }];
                            for (var i = 0; i < Quickshell.screens.length; ++i) {
                                var scr = Quickshell.screens[i];
                                list.push({
                                    displayName: scr.name,
                                    icon: "monitor",
                                    value: scr.name
                                });
                            }
                            return list;
                        }
                    }
                }

                ContentSubsection {
                    icon: "screen_rotation"
                    title: Translation.tr("Coordinate rotation")
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: (touchRoot.opts && touchRoot.opts.transform) ? touchRoot.opts.transform : "auto"
                        onSelected: function(newValue) {
                            if (Config.ready && touchRoot.opts) touchRoot.opts.transform = newValue;
                        }
                        options: [
                            { displayName: Translation.tr("Automatic"), icon: "auto_awesome", value: "auto" },
                            { displayName: "0°", icon: "crop_portrait", value: "0" },
                            { displayName: "90°", icon: "crop_landscape", value: "90" },
                            { displayName: "180°", icon: "crop_portrait", value: "180" },
                            { displayName: "270°", icon: "crop_landscape", value: "270" }
                        ]
                    }
                }
            }
        }

        // ── Gestures & Sensitivity Navigation ─────────────────────────────────
        ContentSection {
            icon: "swipe"
            title: Translation.tr("Gestures & Calibration")
            tooltip: Translation.tr("Swipe assignments, corner zones, recognition distances and detection sliders.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "swipe"
                    title: Translation.tr("Gesture bindings & edge zones")
                    description: Translation.tr("Left, right, top, bottom edges and corner drag actions")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/TouchEdgeGesturesConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "tune"
                    title: Translation.tr("Sensitivity & detection calibration")
                    description: Translation.tr("Detection thresholds, presets, travel distance, velocity and angle tolerance")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/TouchSensitivityConfig.qml"))
                }
            }
        }

        // ── Behavior & Context ────────────────────────────────────────────────
        ContentSection {
            icon: "security"
            title: Translation.tr("Behavior & Context")
            tooltip: Translation.tr("Fullscreen suppression and reset options.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Disable gestures in fullscreen applications")
                    checked: (touchRoot.opts && touchRoot.opts.disableInFullscreen) ? true : false
                    onCheckedChanged: {
                        if (Config.ready && touchRoot.opts) touchRoot.opts.disableInFullscreen = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "movie"
                    text: Translation.tr("Disable gestures in Media Mode")
                    checked: (touchRoot.opts && touchRoot.opts.disableInMediaMode !== undefined) ? touchRoot.opts.disableInMediaMode : true
                    onCheckedChanged: {
                        if (Config.ready && touchRoot.opts) touchRoot.opts.disableInMediaMode = checked;
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 8

                    RippleButtonWithIcon {
                        buttonRadius: Appearance.rounding.small
                        materialIcon: "restart_alt"
                        mainText: Translation.tr("Restore default bindings")
                        onClicked: {
                            if (Config.ready && touchRoot.opts && touchRoot.opts.bindings) {
                                touchRoot.opts.bindings.leftEdge = "sidebarLeft";
                                touchRoot.opts.bindings.rightEdge = "sidebarRight";
                                touchRoot.opts.bindings.topEdge = "cheatsheet";
                                touchRoot.opts.bindings.bottomEdge = "overview";
                                touchRoot.opts.bindings.topLeftCorner = "none";
                                touchRoot.opts.bindings.topRightCorner = "none";
                                touchRoot.opts.bindings.bottomLeftCorner = "none";
                                touchRoot.opts.bindings.bottomRightCorner = "osk";
                            }
                        }
                    }

                    RippleButtonWithIcon {
                        visible: TouchGestureService.binaryExists
                        buttonRadius: Appearance.rounding.small
                        materialIcon: "delete"
                        colText: Appearance.colors.colError
                        mainText: Translation.tr("Delete compiled binary")
                        onClicked: {
                            TouchGestureService.deleteBinary();
                        }
                    }
                }
            }
        }

        // ── Touchpad & Scrolling ──────────────────────────────────────────────
        ContentSection {
            id: scrollingSection
            icon: "mouse"
            title: Translation.tr("Touchpad & Scrolling")
            tooltip: Translation.tr("How far lists move for each touchpad swipe and mouse wheel notch.")

            readonly property var opts: Config.options?.interactions?.scrolling ?? null
            readonly property var defaults: ({
                    "fasterTouchpadScroll": false,
                    "touchpadScrollFactor": 450,
                    "mouseScrollFactor": 120,
                    "uniformMouseWheel": false,
                    "mouseScrollDeltaThreshold": 120
                })
            // Changes are saved in one batch once they settle: Config re-reads its
            // own file right after a save and drops anything changed in between.
            property var pendingWrites: ({})

            function queueWrite(key, value) {
                const next = Object.assign({}, scrollingSection.pendingWrites);
                next[key] = value;
                scrollingSection.pendingWrites = next;
                writeTimer.restart();
            }

            function flushWrites() {
                if (!scrollingSection.opts)
                    return;
                const writes = scrollingSection.pendingWrites;
                for (const key of Object.keys(writes))
                    scrollingSection.opts[key] = writes[key];
                scrollingSection.pendingWrites = ({});
            }

            function resetDefaults() {
                writeTimer.stop();
                scrollingSection.pendingWrites = Object.assign({}, scrollingSection.defaults);
                scrollingSection.flushWrites();
            }

            Timer {
                id: writeTimer
                interval: 350
                onTriggered: scrollingSection.flushWrites()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    id: fasterSwitch
                    buttonIcon: "speed"
                    text: Translation.tr("Faster touchpad scrolling")
                    description: Translation.tr("Speed up touchpad scrolling in menus, panels and lists.")
                    Binding {
                        target: fasterSwitch
                        property: "checked"
                        value: scrollingSection.opts?.fasterTouchpadScroll ?? false
                        when: !writeTimer.running
                        restoreMode: Binding.RestoreNone
                    }
                    onCheckedChanged: {
                        if (Config.ready && scrollingSection.opts && checked !== scrollingSection.opts.fasterTouchpadScroll)
                            scrollingSection.queueWrite("fasterTouchpadScroll", checked);
                    }
                }

                ConfigSlider {
                    id: touchpadSpeedSlider
                    buttonIcon: "swipe_vertical"
                    text: Translation.tr("Touchpad speed")
                    // Only used while faster scrolling is on
                    enabled: fasterSwitch.checked
                    opacity: enabled ? 1 : 0.4
                    usePercentTooltip: false
                    // Shown as a share of the default speed (450)
                    from: 45
                    to: 900
                    stepSize: 22.5
                    stopIndicatorValues: [450]
                    badgeText: Math.round(value / 4.5) + "%"
                    tooltipContent: badgeText
                    Binding {
                        target: touchpadSpeedSlider
                        property: "value"
                        value: scrollingSection.opts?.touchpadScrollFactor ?? 450
                        when: !touchpadSpeedSlider.pressed && !writeTimer.running
                        restoreMode: Binding.RestoreNone
                    }
                    onMoved: scrollingSection.queueWrite("touchpadScrollFactor", Math.round(value))

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                ConfigSlider {
                    id: mouseStepSlider
                    buttonIcon: "mouse"
                    text: Translation.tr("Mouse wheel step")
                    usePercentTooltip: false
                    from: 40
                    to: 400
                    stepSize: 10
                    stopIndicatorValues: [120]
                    badgeText: Translation.tr("%1 px").arg(Math.round(value))
                    tooltipContent: badgeText
                    Binding {
                        target: mouseStepSlider
                        property: "value"
                        value: scrollingSection.opts?.mouseScrollFactor ?? 120
                        when: !mouseStepSlider.pressed && !writeTimer.running
                        restoreMode: Binding.RestoreNone
                    }
                    onMoved: scrollingSection.queueWrite("mouseScrollFactor", Math.round(value))
                }

                ConfigSwitch {
                    id: uniformSwitch
                    buttonIcon: "format_line_spacing"
                    text: Translation.tr("Same wheel step in every list")
                    description: Translation.tr("When off, some panels keep the default mouse wheel scrolling.")
                    Binding {
                        target: uniformSwitch
                        property: "checked"
                        value: scrollingSection.opts?.uniformMouseWheel ?? false
                        when: !writeTimer.running
                        restoreMode: Binding.RestoreNone
                    }
                    onCheckedChanged: {
                        if (Config.ready && scrollingSection.opts && checked !== scrollingSection.opts.uniformMouseWheel)
                            scrollingSection.queueWrite("uniformMouseWheel", checked);
                    }
                }

                // Somewhere to feel the settings, and to see which device the shell
                // thinks it is reading, which is what the threshold below decides.
                Rectangle {
                    id: scrollTestPad
                    Layout.fillWidth: true
                    implicitHeight: 168
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    property string readout: Translation.tr("Scroll here to try your settings")

                    StyledFlickable {
                        id: testFlickable
                        anchors {
                            fill: parent
                            margins: 8
                            bottomMargin: 36
                        }
                        clip: true
                        contentWidth: width
                        contentHeight: testColumn.implicitHeight
                        onWheelScrolled: (angleDelta, pixelDelta) => {
                            const isMouse = Math.abs(angleDelta) >= testFlickable.mouseScrollDeltaThreshold;
                            scrollTestPad.readout = isMouse
                                ? Translation.tr("Detected: mouse wheel · step %1").arg(Math.abs(angleDelta))
                                : Translation.tr("Detected: touchpad · step %1").arg(Math.abs(angleDelta));
                        }

                        ColumnLayout {
                            id: testColumn
                            width: testFlickable.width
                            spacing: 4

                            Repeater {
                                model: 30
                                delegate: Rectangle {
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: Appearance.rounding.small
                                    color: index % 2 === 0 ? Appearance.colors.colLayer3 : Appearance.colors.colLayer1

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 12
                                        text: Translation.tr("Row %1").arg(index + 1)
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors {
                            left: parent.left
                            bottom: parent.bottom
                            leftMargin: 16
                            bottomMargin: 10
                        }
                        text: scrollTestPad.readout
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Advanced")
                    icon: "tune"
                    collapsible: true
                    expanded: false

                    ConfigSpinBox {
                        id: thresholdSpin
                        icon: "sensors"
                        text: Translation.tr("Mouse detection threshold")
                        from: 10
                        to: 960
                        stepSize: 10
                        Binding {
                            target: thresholdSpin
                            property: "value"
                            value: scrollingSection.opts?.mouseScrollDeltaThreshold ?? 120
                            when: !writeTimer.running
                            restoreMode: Binding.RestoreNone
                        }
                        onValueChanged: {
                            if (Config.ready && scrollingSection.opts && value !== scrollingSection.opts.mouseScrollDeltaThreshold)
                                scrollingSection.queueWrite("mouseScrollDeltaThreshold", value);
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Scroll steps this size or bigger count as a mouse wheel, smaller ones as a touchpad. The test area above shows the step your device sends.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButtonWithIcon {
                    Layout.alignment: Qt.AlignRight
                    buttonRadius: Appearance.rounding.small
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Reset scrolling to defaults")
                    onClicked: scrollingSection.resetDefaults()
                }
            }
        }

        // ── Compatibility Notice ──────────────────────────────────────────────
        ContentSection {
            icon: "info"
            title: Translation.tr("Compatibility Notice")
            tooltip: Translation.tr("Hyprland touchscreen workspace integration notes.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Hyprland touchscreen workspace gestures may overlap with edge gestures. Disable the conflicting binding in ii or the Hyprland workspace touchscreen gesture if both react to the same swipe.")
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
