import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects

StyledFlickable {
    id: root
    
    property var unavailableDevices: []
    property var tempUnavailableDevices: []
    property int activePlaybackDragIndex: -1
    property int activeRecordingDragIndex: -1

    readonly property int activeDeviceIndex: {
        const activeNode = isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
        if (!activeNode) return -1;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].id === activeNode.id) return i;
        }
        return -1;
    }

    Process {
        id: unavailableDevicesProc
        running: true
        command: ["sh", "-c", "pactl list sinks sources | awk '/Name:/ {name=$2} /not available/ {print name}'"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.length > 0) {
                    root.tempUnavailableDevices.push(line);
                }
            }
        }
        onExited: {
            root.unavailableDevices = root.tempUnavailableDevices;
            root.tempUnavailableDevices = [];
        }
    }
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property list<var> devices: isSink ? Audio.outputDevices : Audio.inputDevices
    readonly property bool hasApps: appPwNodes.length > 0
    readonly property bool hasDevices: devices.length > 0

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.topMargin: -16
    Layout.bottomMargin: 0
    Layout.leftMargin: 0
    Layout.rightMargin: 0

    contentHeight: mainLayout.implicitHeight + 36
    clip: true

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Item {
            id: maskRoot
            width: root.width
            height: root.height

            property color topFadeColor: root.atYBeginning ? "white" : "transparent"
            property color bottomFadeColor: root.atYEnd ? "white" : "transparent"

            Behavior on topFadeColor {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }
            Behavior on bottomFadeColor {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: Math.min(46, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: maskRoot.topFadeColor
                        }
                        GradientStop {
                            position: 1.0
                            color: "white"
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(0, parent.height - Math.min(46, parent.height / 2) - Math.min(56, parent.height / 2))
                    color: "white"
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(56, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: "white"
                        }
                        GradientStop {
                            position: 1.0
                            color: maskRoot.bottomFadeColor
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        width: root.width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
        spacing: 16

        VolumeDialogMedia {
            id: mediaWidget
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            visible: root.isSink && (Config.options.sidebar.volumeDialogMediaWidget ?? true) && MprisController.activePlayer !== null && MprisController.players.length > 0
        }

        // Section 1 Group (Title + List)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.hasDevices

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.normal
                font.bold: true
                color: Appearance.colors.colSubtext
                text: root.isSink ? Translation.tr("Device Output") : Translation.tr("Device Input")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: ScriptModel {
                        values: root.devices
                    }
                    delegate: VolumeDeviceEntry {
                        Layout.fillWidth: true
                        required property var modelData
                        node: modelData
                        isSink: root.isSink
                        totalCount: root.devices.length
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            visible: !root.hasDevices

            PagePlaceholder {
                icon: "speaker_group"
                title: Translation.tr("No devices")
                shown: !root.hasDevices
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }

        // Section 2 Group (Title + List)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.hasApps

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.normal
                font.bold: true
                color: Appearance.colors.colSubtext
                text: root.isSink ? Translation.tr("Program Playback") : Translation.tr("Program Recording")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: ScriptModel {
                        values: root.appPwNodes
                    }
                    delegate: VolumeProgramEntry {
                        Layout.fillWidth: true
                        required property var modelData
                        node: modelData
                        isSink: root.isSink
                        totalCount: root.appPwNodes.length
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            visible: !root.hasApps

            PagePlaceholder {
                icon: "widgets"
                title: Translation.tr("No applications")
                shown: !root.hasApps
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
    }

    component VolumeDeviceEntry: Item {
        id: devEntry
        required property PwNode node
        required property bool isSink
        required property int index
        required property int totalCount

        PwObjectTracker {
            objects: [devEntry.node]
        }

        implicitHeight: 56
        height: implicitHeight
        
        readonly property bool isBlocked: node ? (root.unavailableDevices.indexOf(node.name) !== -1) : false
        opacity: isBlocked ? 0.45 : 1.0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        readonly property bool isActive: {
            if (!node)
                return false;
            if (isSink) {
                return node.id === Pipewire.defaultAudioSink?.id;
            } else {
                return node.id === Pipewire.defaultAudioSource?.id;
            }
        }

        readonly property bool isFirst: index === 0
        readonly property bool isLast: index === totalCount - 1
        readonly property bool isPrevActive: index === root.activeDeviceIndex - 1
        readonly property bool isNextActive: index === root.activeDeviceIndex + 1

        readonly property real rFull: height / 2
        readonly property real rOuter: Appearance?.rounding?.large ?? 23
        readonly property real rInner: Appearance?.rounding?.verysmall ?? 4

        readonly property real topLeftRadius: isActive ? rFull : (isNextActive ? rFull : (isFirst ? rOuter : rInner))
        readonly property real topRightRadius: isActive ? rFull : (isNextActive ? rFull : (isFirst ? rOuter : rInner))
        readonly property real bottomLeftRadius: isActive ? rFull : (isPrevActive ? rFull : (isLast ? rOuter : rInner))
        readonly property real bottomRightRadius: isActive ? rFull : (isPrevActive ? rFull : (isLast ? rOuter : rInner))

        readonly property real checkmarkCircleWidth: 56
        readonly property real spacingBetween: 8
        readonly property real targetWidth: isActive ? (parent.width - checkmarkCircleWidth - spacingBetween) : parent.width

        Rectangle {
            id: checkmarkCircle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: devEntry.isActive ? devEntry.checkmarkCircleWidth : 0
            height: devEntry.checkmarkCircleWidth
            radius: width / 2
            color: Appearance.colors.colSecondaryContainer
            opacity: devEntry.isActive ? 1.0 : 0.0
            scale: devEntry.isActive ? 1.0 : 0.0
            visible: width > 0

            Behavior on width {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutBack
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "check"
                iconSize: 32
                color: Appearance.colors.colPrimary
            }
        }

        Rectangle {
            id: mainRect
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: devEntry.targetWidth
            height: parent.implicitHeight
            
            topLeftRadius: devEntry.topLeftRadius
            topRightRadius: devEntry.topRightRadius
            bottomLeftRadius: devEntry.bottomLeftRadius
            bottomRightRadius: devEntry.bottomRightRadius
            
            color: devEntry.isActive ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.35) : Appearance.colors.colSurfaceContainerHighest

            Behavior on width {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutQuad
                }
            }

            Behavior on topLeftRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            Behavior on topRightRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            Behavior on bottomLeftRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            Behavior on bottomRightRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }

            layer.enabled: true
            layer.samples: 8
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: mainRect.width
                    height: mainRect.height
                    topLeftRadius: mainRect.topLeftRadius
                    topRightRadius: mainRect.topRightRadius
                    bottomLeftRadius: mainRect.bottomLeftRadius
                    bottomRightRadius: mainRect.bottomRightRadius
                }
            }

            Rectangle {
                id: fillRect
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                property real displayVol: devEntry.node?.audio?.volume ?? 0
                Behavior on displayVol {
                    enabled: !mainMouseArea.pressed
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }

                width: devEntry.isActive ? (mainRect.width * Math.min(1.0, displayVol)) : 0
                color: devEntry.node?.audio?.muted ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                visible: devEntry.isActive

                Behavior on width {
                    enabled: !mainMouseArea.pressed
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: devEntry.isActive ? 20 : 16
                anchors.rightMargin: 16
                spacing: 12

                MouseArea {
                    id: iconMouseArea
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter
                    cursorShape: devEntry.isBlocked ? Qt.ArrowCursor : (devEntry.isActive ? Qt.PointingHandCursor : Qt.ArrowCursor)
                    enabled: !devEntry.isBlocked

                    onClicked: {
                        if (devEntry.isActive && devEntry.node && devEntry.node.audio) {
                            devEntry.node.audio.muted = !devEntry.node.audio.muted;
                        } else {
                            devEntry.activateDevice();
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: {
                            if (devEntry.node?.audio?.muted) {
                                return devEntry.isSink ? "volume_off" : "mic_off";
                            }
                            if (devEntry.isSink) {
                                let vol = devEntry.node?.audio?.volume ?? 0;
                                if (vol === 0) return "volume_mute";
                                if (vol <= 0.5) return "volume_down";
                                return "volume_up";
                            } else {
                                return "mic";
                            }
                        }
                        iconSize: 22
                        color: devEntry.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                    }
                }

                StyledText {
                    id: deviceNameText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: devEntry.isActive ? Appearance.colors.colOnPrimary : devEntry.node?.audio?.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnSurface
                    text: Audio.friendlyDeviceName(devEntry.node)
                    font.bold: devEntry.isActive
                    opacity: (devEntry.isActive && mainMouseArea.pressed) ? 0.0 : 1.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }
            }

            StyledText {
                id: percentageText
                anchors.verticalCenter: parent.verticalCenter
                x: {
                    let insideX = fillRect.width - width - 12;
                    let minSafeX = (devEntry.isActive ? 20 : 16) + 24 + 12;
                    if (insideX < minSafeX) {
                        return mainRect.width - width - 16;
                    }
                    return insideX;
                }
                font.pixelSize: Appearance.font.pixelSize.small
                font.bold: true
                color: devEntry.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                text: Math.round((devEntry.node?.audio?.volume ?? 0) * 100) + "%"
                opacity: (devEntry.isActive && mainMouseArea.pressed) ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }

            MouseArea {
                id: mainMouseArea
                anchors.fill: parent
                z: -1
                cursorShape: devEntry.isBlocked ? Qt.ArrowCursor : Qt.PointingHandCursor
                enabled: !devEntry.isBlocked

                onPressed: mouse => {
                    root.interactive = false;
                    if (devEntry.isActive) {
                        updateVolume(mouse.x);
                    } else {
                        devEntry.activateDevice();
                    }
                }

                onReleased: {
                    root.interactive = true;
                }

                onCanceled: {
                    root.interactive = true;
                }

                onPositionChanged: mouse => {
                    if (devEntry.isActive) {
                        updateVolume(mouse.x);
                    }
                }

                function updateVolume(mouseX) {
                    let percentage = Math.max(0, Math.min(1.0, mouseX / mainRect.width));
                    if (devEntry.node && devEntry.node.audio) {
                        devEntry.node.audio.volume = percentage;
                    }
                }
            }
        }

        function activateDevice() {
            if (!node)
                return;
            if (isSink) {
                Audio.setDefaultSink(devEntry.node);
            } else {
                Audio.setDefaultSource(devEntry.node);
            }
        }
    }

    component VolumeProgramEntry: Item {
        id: progEntry
        required property PwNode node
        required property bool isSink
        required property int index
        required property int totalCount

        PwObjectTracker {
            objects: [progEntry.node]
        }

        implicitHeight: 56
        height: implicitHeight

        readonly property bool isFirst: index === 0
        readonly property bool isLast: index === totalCount - 1

        readonly property int activeDragIndex: progEntry.isSink ? root.activePlaybackDragIndex : root.activeRecordingDragIndex
        readonly property bool isDragged: activeDragIndex === progEntry.index
        readonly property bool isPrevDragged: activeDragIndex === progEntry.index + 1
        readonly property bool isNextDragged: activeDragIndex === progEntry.index - 1

        readonly property real rFull: height / 2
        readonly property real rOuter: Appearance?.rounding?.large ?? 23
        readonly property real rInner: Appearance?.rounding?.verysmall ?? 4

        readonly property real topLeftRadius: isDragged ? rFull : (isNextDragged ? rFull : (isFirst ? rOuter : rInner))
        readonly property real topRightRadius: isDragged ? rFull : (isNextDragged ? rFull : (isFirst ? rOuter : rInner))
        readonly property real bottomLeftRadius: isDragged ? rFull : (isPrevDragged ? rFull : (isLast ? rOuter : rInner))
        readonly property real bottomRightRadius: isDragged ? rFull : (isPrevDragged ? rFull : (isLast ? rOuter : rInner))

        Rectangle {
            id: mainRect
            anchors.fill: parent
            
            topLeftRadius: progEntry.topLeftRadius
            topRightRadius: progEntry.topRightRadius
            bottomLeftRadius: progEntry.bottomLeftRadius
            bottomRightRadius: progEntry.bottomRightRadius
            
            color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.35)

            Behavior on topLeftRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            Behavior on topRightRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            Behavior on bottomLeftRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            Behavior on bottomRightRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

            layer.enabled: true
            layer.samples: 8
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: mainRect.width
                    height: mainRect.height
                    topLeftRadius: mainRect.topLeftRadius
                    topRightRadius: mainRect.topRightRadius
                    bottomLeftRadius: mainRect.bottomLeftRadius
                    bottomRightRadius: mainRect.bottomRightRadius
                }
            }

            Rectangle {
                id: fillRect
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                property real displayVol: progEntry.node?.audio?.volume ?? 0
                Behavior on displayVol {
                    enabled: !progMouseArea.pressed
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }

                width: mainRect.width * Math.min(1.0, displayVol)
                color: progEntry.node?.audio?.muted ? Appearance.colors.colSubtext : Appearance.colors.colSecondaryContainer

                Behavior on width {
                    enabled: !progMouseArea.pressed
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                MouseArea {
                    id: iconMouseArea
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (progEntry.node && progEntry.node.audio) {
                            progEntry.node.audio.muted = !progEntry.node.audio.muted;
                        }
                    }

                    Item {
                        anchors.fill: parent

                        StyledImage {
                            id: appIcon
                            anchors.fill: parent
                            visible: source !== ""
                            source: {
                                if (!progEntry.node)
                                    return "";
                                const _ = TaskbarApps.iconThemeRevision;
                                let icon;
                                icon = AppSearch.guessIcon(progEntry.node.properties["application.icon-name"] ?? "");
                                if (AppSearch.iconExists(icon))
                                    return Quickshell.iconPath(icon, "image-missing");
                                icon = AppSearch.guessIcon(progEntry.node.properties["node.name"] ?? "");
                                if (AppSearch.iconExists(icon))
                                    return Quickshell.iconPath(icon, "image-missing");
                                return "";
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: appIcon.source === ""
                            text: progEntry.isSink ? "widgets" : "mic"
                            iconSize: 20
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "#80000000"
                            visible: progEntry.node?.audio?.muted ?? false
                            radius: 4

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: progEntry.isSink ? "volume_off" : "mic_off"
                                iconSize: 14
                                color: "white"
                            }
                        }
                    }
                }

                StyledText {
                    id: appNameText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: progEntry.node?.audio?.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnSecondaryContainer
                    text: {
                        if (!progEntry.node)
                            return "";
                        const app = Audio.appNodeDisplayName(progEntry.node);
                        const media = progEntry.node.properties["media.name"];
                        return media !== undefined ? `${app} • ${media}` : app;
                    }
                    opacity: progMouseArea.pressed ? 0.0 : 1.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }
            }

            StyledText {
                id: percentageText
                anchors.verticalCenter: parent.verticalCenter
                x: {
                    let insideX = fillRect.width - width - 12;
                    let minSafeX = 16 + 24 + 12;
                    if (insideX < minSafeX) {
                        return mainRect.width - width - 16;
                    }
                    return insideX;
                }
                font.pixelSize: Appearance.font.pixelSize.small
                font.bold: true
                color: Appearance.colors.colOnSecondaryContainer
                text: Math.round((progEntry.node?.audio?.volume ?? 0) * 100) + "%"
                opacity: progMouseArea.pressed ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }

            MouseArea {
                id: progMouseArea
                anchors.fill: parent
                z: -1
                cursorShape: Qt.PointingHandCursor

                onPressed: mouse => {
                    root.interactive = false;
                    updateVolume(mouse.x);
                }

                onReleased: {
                    root.interactive = true;
                }

                onCanceled: {
                    root.interactive = true;
                }

                onPositionChanged: mouse => {
                    updateVolume(mouse.x);
                }

                function updateVolume(mouseX) {
                    let percentage = Math.max(0, Math.min(1.0, mouseX / mainRect.width));
                    if (progEntry.node && progEntry.node.audio) {
                        progEntry.node.audio.volume = percentage;
                    }
                }
            }

            Connections {
                target: progMouseArea
                function onPressedChanged() {
                    if (progMouseArea.pressed) {
                        if (progEntry.isSink) {
                            root.activePlaybackDragIndex = progEntry.index;
                        } else {
                            root.activeRecordingDragIndex = progEntry.index;
                        }
                    } else {
                        if (progEntry.isSink) {
                            if (root.activePlaybackDragIndex === progEntry.index) {
                                root.activePlaybackDragIndex = -1;
                            }
                        } else {
                            if (root.activeRecordingDragIndex === progEntry.index) {
                                root.activeRecordingDragIndex = -1;
                            }
                        }
                    }
                }
            }
        }
    }
}
