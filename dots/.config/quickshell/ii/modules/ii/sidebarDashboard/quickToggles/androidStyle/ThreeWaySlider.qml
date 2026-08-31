pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarDashboard

Item {
    id: root

    required property string toggleType
    required property var toggleModel

    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations

    DashboardEntranceProgress {
        id: entranceProgress
        animationSpec: Appearance.animation.elementMove
        animationsEnabled: root.entranceAnimationsEnabled
        trigger: root.entranceTrigger
        baseDelayRatio: 0.1
    }

    DashboardEntranceProgress {
        id: knobEntranceProgress
        animationSpec: Appearance.animation.elementMove
        animationsEnabled: root.entranceAnimationsEnabled
        trigger: root.entranceTrigger
        baseDelayRatio: 1.1
    }

    readonly property real margin: 4
    readonly property real knobSize: root.height - (margin * 2)

    readonly property real posLeft: margin
    readonly property real posCenter: (root.width - knobSize) / 2
    readonly property real posRight: root.width - knobSize - margin

    readonly property real thresholdLeftCenter: (posLeft + posCenter) / 2
    readonly property real thresholdCenterRight: (posCenter + posRight) / 2

    // Current state index based on the underlying service
    readonly property int currentStateIndex: {
        if (toggleType === "soundcoreAnc") {
            let activeDev = EarbudsControlService.activeDevice;
            let mode = activeDev ? EarbudsControlService.currentNoiseMode(activeDev) : "off";
            if (mode === "anc") return 0;
            if (mode === "off") return 1;
            if (mode === "transparency" || mode === "adaptive") return 2;
            return 1;
        } else if (toggleType === "powerProfile") {
            let prof = PowerProfiles.profile;
            if (prof === PowerProfile.PowerSaver) return 0;
            if (prof === PowerProfile.Balanced) return 1;
            if (prof === PowerProfile.Performance) return 2;
            return 1;
        } else if (toggleType === "keyboardBacklight") {
            let val = KeyboardBacklight.currentValue;
            let max = KeyboardBacklight.maxValue;
            if (val === 0) return 0;
            if (val >= max) return 2;
            return 1;
        }
        return 1;
    }

    // Local override state to prevent snapback during async service updates
    property int localOverrideIndex: -1
    readonly property int activeVisualIndex: localOverrideIndex !== -1 ? localOverrideIndex : currentStateIndex

    onCurrentStateIndexChanged: {
        localOverrideIndex = -1;
    }

    Timer {
        id: overrideResetTimer
        interval: 800
        repeat: false
        onTriggered: localOverrideIndex = -1
    }

    // Interactive dragging state
    property bool isDraggingKnob: false
    property real knobDragX: posCenter

    // Calculate hover index dynamically during drag
    readonly property int hoverIndex: {
        let xVal = isDraggingKnob ? knobDragX : targetX;
        if (xVal < thresholdLeftCenter) return 0;
        if (xVal > thresholdCenterRight) return 2;
        return 1;
    }

    readonly property real targetX: {
        if (activeVisualIndex === 0) return posLeft;
        if (activeVisualIndex === 1) return posCenter;
        return posRight;
    }

    readonly property bool isToggled: {
        if (toggleType === "soundcoreAnc") return hoverIndex !== 1;
        if (toggleType === "powerProfile") return hoverIndex !== 1;
        if (toggleType === "keyboardBacklight") return hoverIndex !== 0;
        return false;
    }

    function applyStateIndex(idx) {
        if (toggleType === "soundcoreAnc") {
            let activeDev = EarbudsControlService.activeDevice;
            if (!activeDev) return;
            let targetMode = "off";
            if (idx === 0) targetMode = "anc";
            else if (idx === 1) targetMode = "off";
            else if (idx === 2) targetMode = "transparency";
            EarbudsControlService.setNoiseMode(activeDev, targetMode);
        } else if (toggleType === "powerProfile") {
            if (idx === 0) PowerProfiles.profile = PowerProfile.PowerSaver;
            else if (idx === 1) PowerProfiles.profile = PowerProfile.Balanced;
            else if (idx === 2) PowerProfiles.profile = PowerProfile.Performance;
        } else if (toggleType === "keyboardBacklight") {
            let max = KeyboardBacklight.maxValue;
            if (idx === 0) KeyboardBacklight.setValue(0);
            else if (idx === 1) KeyboardBacklight.setValue(Math.max(1, Math.round(max / 2)));
            else if (idx === 2) KeyboardBacklight.setValue(max);
        }
    }

    function getIconForIndex(idx) {
        if (toggleType === "soundcoreAnc") {
            if (idx === 0) return "noise_control_off";
            if (idx === 1) return "hearing";
            if (idx === 2) return "visibility";
        } else if (toggleType === "powerProfile") {
            if (idx === 0) return "energy_savings_leaf";
            if (idx === 1) return "airwave";
            if (idx === 2) return "local_fire_department";
        } else if (toggleType === "keyboardBacklight") {
            if (idx === 0) return "backlight_high_off";
            if (idx === 1) return "backlight_high";
            if (idx === 2) return "brightness_6";
        }
        return toggleModel?.icon ?? "close";
    }

    // Capsule pill background
    Rectangle {
        id: bgPill
        anchors.fill: parent
        radius: height / 2
        color: Appearance.colors.colLayer2
        border.width: 0
        opacity: entranceProgress.progress
        scale: 0.85 + 0.15 * entranceProgress.progress

        // Left, Center, and Right Dots (Position indicators)
        Rectangle {
            id: dotLeft
            width: 6
            height: 6
            radius: 3
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.left
            anchors.horizontalCenterOffset: root.posLeft + (root.knobSize / 2)
            opacity: (root.hoverIndex === 0 ? 0.0 : 1.0) * entranceProgress.progress
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        Rectangle {
            id: dotCenter
            width: 6
            height: 6
            radius: 3
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: (root.hoverIndex === 1 ? 0.0 : 1.0) * entranceProgress.progress
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        Rectangle {
            id: dotRight
            width: 6
            height: 6
            radius: 3
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.right
            anchors.horizontalCenterOffset: -(root.posLeft + (root.knobSize / 2))
            opacity: (root.hoverIndex === 2 ? 0.0 : 1.0) * entranceProgress.progress
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    // Draggable Knob (Active/Inactive Indicator)
    Rectangle {
        id: knob
        width: root.knobSize
        height: root.knobSize
        radius: width / 2
        y: root.margin
        x: (root.isDraggingKnob ? root.knobDragX : root.targetX)
            - 50 * (1 - knobEntranceProgress.progress)

        color: Appearance.colors.colPrimary
        opacity: entranceProgress.progress
        scale: 0.7 + 0.3 * knobEntranceProgress.progress
        rotation: -20 * (1 - knobEntranceProgress.progress)

        Behavior on x {
            enabled: !root.isDraggingKnob
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        // Active State Icon inside Knob
        MaterialSymbol {
            id: knobIcon
            anchors.centerIn: parent
            iconSize: 22
            color: Appearance.colors.colOnPrimary
            text: root.getIconForIndex(root.hoverIndex)
        }
    }

    // Mouse area for slide drag and tap snapping
    MouseArea {
        id: dragArea
        anchors.fill: parent
        preventStealing: true
        cursorShape: root.isDraggingKnob ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        onPressed: (mouse) => {
            // Disable Flickables upwards to prevent sidebar page swiping
            let p = parent;
            while (p) {
                if (p.toString().includes("Flickable") || p.interactive !== undefined) {
                    p.interactive = false;
                }
                p = p.parent;
            }
            root.isDraggingKnob = true;
            root.knobDragX = Math.max(root.posLeft, Math.min(root.posRight, mouse.x - root.knobSize / 2));
        }

        onPositionChanged: (mouse) => {
            if (root.isDraggingKnob) {
                root.knobDragX = Math.max(root.posLeft, Math.min(root.posRight, mouse.x - root.knobSize / 2));
            }
        }

        onReleased: (mouse) => {
            // Re-enable parent Flickables
            let p = parent;
            while (p) {
                if (p.toString().includes("Flickable") || p.interactive !== undefined) {
                    p.interactive = true;
                }
                p = p.parent;
            }
            root.localOverrideIndex = root.hoverIndex;
            overrideResetTimer.restart();
            root.isDraggingKnob = false;
            root.applyStateIndex(root.hoverIndex);
        }

        onCanceled: {
            let p = parent;
            while (p) {
                if (p.toString().includes("Flickable") || p.interactive !== undefined) {
                    p.interactive = true;
                }
                p = p.parent;
            }
            root.isDraggingKnob = false;
        }
    }
}
