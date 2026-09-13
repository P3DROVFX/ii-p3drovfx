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
                    visible: !TouchGestureService.binaryExists
                    Layout.fillWidth: true
                    icon: "terminal"
                    title: Translation.tr("Compile Rust Helper Daemon")
                    text: Translation.tr("To compile and install the native touch listener daemon, run this command in your terminal (requires Rust toolchain and cargo). After compiling, restart Quickshell to start the daemon:")
                    codeSnippet: "cd " + Directories.scriptPath + "/touchGestures/touch_gestures_src && cargo build --release && cp target/release/touch_gestures ../touch_gestures"
                    snippetWrapMode: Text.Wrap
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
            icon: "mouse"
            title: Translation.tr("Touchpad & Scrolling")
            tooltip: Translation.tr("Enhanced touchpad scroll acceleration.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "speed"
                    text: Translation.tr("Faster touchpad scrolling")
                    checked: Config.options.interactions.scrolling.fasterTouchpadScroll ?? false
                    onCheckedChanged: {
                        Config.options.interactions.scrolling.fasterTouchpadScroll = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Enables accelerated smooth scrolling across menus, panels, and lists when using a touchpad.")
                    }
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
