import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models.hyprland
import "../../common/models/hyprland/MonitorLayoutUtils.js" as MonitorLayoutUtils

ContentPage {
    id: page
    forceWidth: false

    MonitorConfigOption {
        id: monitorConfig
    }

    readonly property var selectedMonitor: (monitorConfig.monitors
        && monitorCanvas.selectedIndex >= 0
        && monitorCanvas.selectedIndex < monitorConfig.monitors.length)
        ? monitorConfig.monitors[monitorCanvas.selectedIndex]
        : null
    readonly property string selectedMonitorName: selectedMonitor && selectedMonitor.name ? selectedMonitor.name : ""
    readonly property var selectedCalibration: DisplayCalibration.monitorForName(selectedMonitorName)
    readonly property var selectedGpuCalibration: DisplayColorFilter.profileForMonitor(selectedMonitorName)
    readonly property int activeMonitorCount: monitorConfig.activeMonitorCount

    component MonitorRect: Rectangle {
        id: rectRoot
        objectName: "monitorRect_" + monitorIndex
        required property var monitor
        required property int monitorIndex
        required property real scaleFactor
        required property point canvasOffset
        required property var allMonitors
        required property Item canvasItem
        property bool isSelected: false

        signal dragStarted(int index)
        signal dragMoved(int index, var snap)
        signal positionCommitted(int index, int x, int y)
        signal dragCanceled()
        signal monitorClicked(int index)

        property bool pressPending: false
        property bool isDragging: false
        property real pressCanvasX: 0
        property real pressCanvasY: 0
        property real curCanvasX: 0
        property real curCanvasY: 0
        property real grabFracX: 0.5
        property real grabFracY: 0.5
        readonly property real dragThresholdPx: 5

        readonly property int logW: MonitorLayoutUtils.logicalWidth(monitor)
        readonly property int logH: MonitorLayoutUtils.logicalHeight(monitor)

        readonly property real rawLogicalX: isDragging
            ? ((curCanvasX - canvasOffset.x) / Math.max(0.005, scaleFactor) - grabFracX * logW)
            : (monitor ? (monitor.x || 0) : 0)
        readonly property real rawLogicalY: isDragging
            ? ((curCanvasY - canvasOffset.y) / Math.max(0.005, scaleFactor) - grabFracY * logH)
            : (monitor ? (monitor.y || 0) : 0)

        readonly property var snapResult: isDragging
            ? MonitorLayoutUtils.snapForDrag(allMonitors, monitorIndex, rawLogicalX, rawLogicalY, scaleFactor)
            : null

        onSnapResultChanged: {
            if (isDragging && snapResult) {
                dragMoved(monitorIndex, {
                    x: snapResult.x,
                    y: snapResult.y,
                    w: logW,
                    h: logH,
                    valid: snapResult.valid
                });
            }
        }

        x: rawLogicalX * scaleFactor + canvasOffset.x
        y: rawLogicalY * scaleFactor + canvasOffset.y
        width: logW * scaleFactor
        height: logH * scaleFactor

        radius: isDragging ? Appearance.rounding.normal : Appearance.rounding.small
        z: isDragging ? 100 : isSelected ? 2 : 1
        opacity: isDragging ? 0.85 : 1.0

        color: {
            if (monitor && monitor.disabled)
                return Appearance.colors.colLayer2;
            if (isDragging && snapResult && !snapResult.valid)
                return Qt.alpha(Appearance.m3colors.m3error, 0.55);
            if (isDragging)
                return Qt.alpha(Appearance.colors.colPrimaryContainer, 0.8);
            if (isSelected)
                return Appearance.colors.colPrimaryContainer;
            if (hoverArea.containsMouse)
                return Appearance.colors.colSecondaryContainerHover;
            return Appearance.colors.colSecondaryContainer;
        }

        border.color: {
            if (isDragging && snapResult && !snapResult.valid)
                return Appearance.m3colors.m3error;
            if (isDragging)
                return Appearance.colors.colPrimary;
            if (isSelected)
                return "transparent";
            return Appearance.colors.colLayer0Border;
        }
        border.width: isSelected && !isDragging ? 0 : (isDragging ? 2 : 1)

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        DashedBorder {
            anchors.fill: parent
            color: Appearance.colors.colPrimary
            borderWidth: 2
            dashLength: 6
            gapLength: 4
            radius: rectRoot.radius
            visible: rectRoot.isSelected && !rectRoot.isDragging
        }

        Column {
            anchors.centerIn: parent
            spacing: rectRoot.height < 64 ? 1 : 3

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (rectRoot.monitorIndex + 1).toString()
                font.pixelSize: Math.max(12, Math.min(34, Math.min(rectRoot.width * 0.24, rectRoot.height * 0.38)))
                font.weight: Font.Bold
                font.family: Appearance.font.family.numbers
                color: (monitor && monitor.disabled) ? Appearance.colors.colSubtext : isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: rectRoot.height >= 42 && rectRoot.width >= 44
                text: monitor && monitor.name ? monitor.name : "Display"
                font.pixelSize: Math.max(9, Math.min(13, Math.min(rectRoot.width * 0.1, rectRoot.height * 0.16)))
                font.weight: Font.Medium
                color: (monitor && monitor.disabled) ? Appearance.colors.colSubtext : isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, Math.max(0, rectRoot.width - 8))
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: rectRoot.height >= 76 && rectRoot.width >= 88
                text: rectRoot.logW + "×" + rectRoot.logH
                font.pixelSize: 10
                opacity: 0.72
                color: (monitor && monitor.disabled) ? Appearance.colors.colSubtext : isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            }
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: (monitor && monitor.disabled) ? Qt.ArrowCursor : (rectRoot.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
            preventStealing: true

            onPressed: event => {
                const startPos = hoverArea.mapToItem(rectRoot.canvasItem, event.x, event.y);
                rectRoot.pressPending = true;
                rectRoot.pressCanvasX = startPos.x;
                rectRoot.pressCanvasY = startPos.y;
                rectRoot.curCanvasX = startPos.x;
                rectRoot.curCanvasY = startPos.y;
                if (monitor && !monitor.disabled) {
                    rectRoot.grabFracX = rectRoot.width > 0 ? Math.max(0, Math.min(1, (startPos.x - rectRoot.x) / rectRoot.width)) : 0.5;
                    rectRoot.grabFracY = rectRoot.height > 0 ? Math.max(0, Math.min(1, (startPos.y - rectRoot.y) / rectRoot.height)) : 0.5;
                }
            }

            onPositionChanged: event => {
                if (!rectRoot.pressPending && !rectRoot.isDragging)
                    return;
                if (!monitor || monitor.disabled)
                    return;
                const currentPos = hoverArea.mapToItem(rectRoot.canvasItem, event.x, event.y);
                rectRoot.curCanvasX = currentPos.x;
                rectRoot.curCanvasY = currentPos.y;
                if (!rectRoot.isDragging) {
                    if (Math.hypot(currentPos.x - rectRoot.pressCanvasX, currentPos.y - rectRoot.pressCanvasY) < rectRoot.dragThresholdPx)
                        return;
                    rectRoot.dragStarted(rectRoot.monitorIndex);
                    rectRoot.isDragging = true;
                }
            }

            onReleased: event => {
                rectRoot.pressPending = false;
                if (!rectRoot.isDragging) {
                    rectRoot.monitorClicked(rectRoot.monitorIndex);
                    return;
                }
                const snap = rectRoot.snapResult;
                rectRoot.isDragging = false;
                if (snap && snap.valid) {
                    rectRoot.positionCommitted(rectRoot.monitorIndex, snap.x, snap.y);
                } else {
                    rectRoot.dragCanceled();
                }
            }

            onCanceled: {
                rectRoot.pressPending = false;
                if (rectRoot.isDragging) {
                    rectRoot.isDragging = false;
                    rectRoot.dragCanceled();
                }
            }
        }
    }

    component MonitorCanvas: Item {
        id: canvasRoot
        objectName: "monitorCanvas"
        property var monitorConfig
        property real padding: 24
        property int selectedIndex: 0
        property var previewPositions: ({})
        property bool dragHasOverlap: false
        property bool draggingActive: false
        property int dragMonitorIndex: -1
        property var dragBoundsSnapshot: null
        property var activeSnap: null
        property bool ghostArmed: false
        property real userZoom: 1.0
        property bool cameraReady: false

        readonly property var monitors: monitorConfig ? (monitorConfig.monitors || []) : []
        readonly property var idleBounds: MonitorLayoutUtils.computeBounds(monitors, null)
        readonly property var viewBounds: (draggingActive && dragBoundsSnapshot) ? dragBoundsSnapshot : idleBounds
        readonly property real effectiveZoom: draggingActive ? Math.min(1.0, userZoom) : userZoom
        readonly property var targetCamera: MonitorLayoutUtils.computeFitCamera(viewBounds, width, height, padding, effectiveZoom)

        property real scaleFactor: targetCamera.scale
        property real offsetX: targetCamera.offsetX
        property real offsetY: targetCamera.offsetY
        readonly property point offset: Qt.point(offsetX, offsetY)

        readonly property real targetCanvasHeight: {
            if (!idleBounds || idleBounds.width <= 0)
                return 260;
            const ratio = idleBounds.height / idleBounds.width;
            if (ratio >= 1.25)
                return 340;
            if (ratio >= 0.72)
                return 300;
            return 250;
        }
        property real latchedHeight: 260

        onTargetCanvasHeightChanged: {
            if (!draggingActive)
                latchedHeight = targetCanvasHeight;
        }
        onDraggingActiveChanged: {
            if (!draggingActive)
                latchedHeight = targetCanvasHeight;
        }
        Component.onCompleted: {
            latchedHeight = targetCanvasHeight;
            maybeArmCamera();
        }

        Behavior on latchedHeight {
            enabled: canvasRoot.cameraReady && !canvasRoot.draggingActive && !Appearance.reducedMotion
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scaleFactor {
            enabled: canvasRoot.cameraReady && !Appearance.reducedMotion
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }
        Behavior on offsetX {
            enabled: canvasRoot.cameraReady && !Appearance.reducedMotion
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }
        Behavior on offsetY {
            enabled: canvasRoot.cameraReady && !Appearance.reducedMotion
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        implicitHeight: latchedHeight

        function maybeArmCamera() {
            if (!cameraReady && width > 40 && height > 40 && monitors.length > 0) {
                Qt.callLater(() => {
                    if (canvasRoot)
                        canvasRoot.cameraReady = true;
                });
            }
        }

        onWidthChanged: maybeArmCamera()
        onHeightChanged: maybeArmCamera()
        onMonitorsChanged: {
            maybeArmCamera();
            if (selectedIndex >= monitors.length)
                selectedIndex = Math.max(0, monitors.length - 1);
        }

        readonly property var snapPoints: MonitorLayoutUtils.computeSnapPoints(monitors, previewPositions)

        function checkOverlap(monitorsList, idx) {
            return MonitorLayoutUtils.checkOverlap(monitorsList, idx);
        }

        function computeNormalized(monitorsList, changedIdx, newX, newY) {
            return MonitorLayoutUtils.computeNormalized(monitorsList, changedIdx, newX, newY);
        }

        function beginDrag(idx) {
            canvasRoot.selectedIndex = idx;
            canvasRoot.dragBoundsSnapshot = MonitorLayoutUtils.computeDragBounds(monitors, idx, 1.15);
            canvasRoot.dragMonitorIndex = idx;
            canvasRoot.draggingActive = true;
            canvasRoot.ghostArmed = false;
        }

        function updateDragSnap(idx, snap) {
            if (!canvasRoot.draggingActive || idx !== canvasRoot.dragMonitorIndex)
                return;
            const hadSnap = canvasRoot.activeSnap !== null;
            canvasRoot.activeSnap = snap;
            canvasRoot.dragHasOverlap = snap ? !snap.valid : false;
            if (!hadSnap && snap && snap.valid) {
                Qt.callLater(() => {
                    if (canvasRoot && canvasRoot.draggingActive)
                        canvasRoot.ghostArmed = true;
                });
            }
            const mon = monitors[idx];
            if (mon && mon.name && snap && snap.valid) {
                const preview = {};
                preview[mon.name] = { x: snap.x, y: snap.y };
                canvasRoot.previewPositions = preview;
            } else {
                canvasRoot.previewPositions = {};
            }
        }

        function finishDrag(idx, newX, newY, commit) {
            canvasRoot.draggingActive = false;
            canvasRoot.dragMonitorIndex = -1;
            canvasRoot.dragBoundsSnapshot = null;
            canvasRoot.activeSnap = null;
            canvasRoot.ghostArmed = false;
            canvasRoot.previewPositions = {};
            canvasRoot.dragHasOverlap = false;
            if (commit && idx >= 0)
                commitPosition(idx, newX, newY);
        }

        function commitPosition(idx, newX, newY) {
            const normalized = computeNormalized(monitorConfig.monitors || [], idx, newX, newY);
            monitorConfig.monitors = normalized;
            canvasRoot.previewPositions = {};
            monitorConfig.save();
        }

        function adjustZoom(delta) {
            const next = Math.round((canvasRoot.userZoom + delta) * 10) / 10;
            canvasRoot.userZoom = Math.max(0.4, Math.min(1.6, next));
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            Item {
                id: canvasInner
                anchors.fill: parent

                Rectangle {
                    id: snapGhost
                    objectName: "snapGhost"
                    visible: canvasRoot.activeSnap !== null && canvasRoot.activeSnap.valid
                    x: canvasRoot.activeSnap ? canvasRoot.activeSnap.x * canvasRoot.scaleFactor + canvasRoot.offsetX : 0
                    y: canvasRoot.activeSnap ? canvasRoot.activeSnap.y * canvasRoot.scaleFactor + canvasRoot.offsetY : 0
                    width: canvasRoot.activeSnap ? canvasRoot.activeSnap.w * canvasRoot.scaleFactor : 0
                    height: canvasRoot.activeSnap ? canvasRoot.activeSnap.h * canvasRoot.scaleFactor : 0
                    radius: Appearance.rounding.small
                    color: Qt.alpha(Appearance.colors.colPrimary, 0.16)
                    border.color: Appearance.colors.colPrimary
                    border.width: 2
                    z: 90

                    Behavior on x {
                        enabled: canvasRoot.ghostArmed && !Appearance.reducedMotion
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on y {
                        enabled: canvasRoot.ghostArmed && !Appearance.reducedMotion
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Repeater {
                    model: (canvasRoot.monitorConfig.monitors || []).length
                    delegate: MonitorRect {
                        required property int index
                        monitor: canvasRoot.monitorConfig.monitors ? canvasRoot.monitorConfig.monitors[index] : null
                        monitorIndex: index
                        scaleFactor: canvasRoot.scaleFactor
                        canvasOffset: canvasRoot.offset
                        allMonitors: canvasRoot.monitorConfig.monitors || []
                        canvasItem: canvasInner
                        isSelected: index === canvasRoot.selectedIndex

                        onMonitorClicked: idx => canvasRoot.selectedIndex = idx
                        onDragStarted: idx => canvasRoot.beginDrag(idx)
                        onDragMoved: (idx, snap) => canvasRoot.updateDragSnap(idx, snap)
                        onPositionCommitted: (idx, x, y) => canvasRoot.finishDrag(idx, x, y, true)
                        onDragCanceled: () => canvasRoot.finishDrag(-1, 0, 0, false)
                    }
                }

                Repeater {
                    model: canvasRoot.snapPoints
                    delegate: Rectangle {
                        required property var modelData
                        x: modelData.x * canvasRoot.scaleFactor + canvasRoot.offsetX - width / 2
                        y: modelData.y * canvasRoot.scaleFactor + canvasRoot.offsetY - height / 2
                        width: 14
                        height: 14
                        radius: 7
                        color: Appearance.colors.colPrimary
                        border.width: 1.5
                        border.color: Appearance.colors.colOnPrimary
                        z: 110

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "link"
                            iconSize: 9
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            Rectangle {
                id: zoomToolbar
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                z: 200
                implicitWidth: zoomRow.implicitWidth + 6
                implicitHeight: 30
                radius: Appearance.rounding.full
                color: Qt.alpha(Appearance.colors.colLayer1, 0.92)
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                opacity: canvasRoot.draggingActive ? 0.35 : 1.0
                enabled: !canvasRoot.draggingActive

                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }

                RowLayout {
                    id: zoomRow
                    anchors.centerIn: parent
                    spacing: 2

                    RippleButton {
                        objectName: "zoomOutBtn"
                        implicitWidth: 24
                        implicitHeight: 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        enabled: canvasRoot.userZoom > 0.45
                        opacity: enabled ? 1.0 : 0.4
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "zoom_out"
                            iconSize: 15
                            color: Appearance.colors.colOnLayer1
                        }
                        onClicked: canvasRoot.adjustZoom(-0.2)
                        StyledToolTip {
                            text: Translation.tr("Zoom out")
                        }
                    }

                    RippleButton {
                        objectName: "zoomResetBtn"
                        implicitWidth: fitLabel.visible ? Math.max(36, fitLabel.implicitWidth + 10) : 24
                        implicitHeight: 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: Math.abs(canvasRoot.userZoom - 1.0) > 0.05 ? Appearance.colors.colSecondaryContainer : "transparent"
                        contentItem: Item {
                            StyledText {
                                id: fitLabel
                                anchors.centerIn: parent
                                visible: Math.abs(canvasRoot.userZoom - 1.0) > 0.05
                                text: Math.round(canvasRoot.userZoom * 100) + "%"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !fitLabel.visible
                                text: "fit_screen"
                                iconSize: 15
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        onClicked: canvasRoot.userZoom = 1.0
                        StyledToolTip {
                            text: Translation.tr("Fit monitors to canvas")
                        }
                    }

                    RippleButton {
                        objectName: "zoomInBtn"
                        implicitWidth: 24
                        implicitHeight: 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        enabled: canvasRoot.userZoom < 1.55
                        opacity: enabled ? 1.0 : 0.4
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "zoom_in"
                            iconSize: 15
                            color: Appearance.colors.colOnLayer1
                        }
                        onClicked: canvasRoot.adjustZoom(0.2)
                        StyledToolTip {
                            text: Translation.tr("Zoom in")
                        }
                    }
                }
            }
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        text: Translation.tr("Monitor Settings uses hyprmon to configure your monitors. It is required to have hyprmon installed for this page to work properly.")

        RippleButtonWithIcon {
            buttonRadius: Appearance.rounding.small
            materialIcon: "terminal"
            mainText: Translation.tr("Open Hyprmon")
            Layout.fillWidth: false
            onClicked: {
                Quickshell.execDetached(["bash", "-c", "${TERMINAL:-kitty} -e hyprmon"]);
            }
        }
        RippleButtonWithIcon {
            buttonRadius: Appearance.rounding.small
            materialIcon: "open_in_new"
            mainText: Translation.tr("How to install")
            Layout.fillWidth: false
            onClicked: {
                Quickshell.execDetached(["xdg-open", "https://github.com/erans/hyprmon"]);
            }
        }
    }

    function moveSelectedMonitor(dx, dy) {
        const idx = monitorCanvas.selectedIndex;
        if (idx >= 0 && idx < monitorConfig.monitors.length) {
            const m = monitorConfig.monitors[idx];
            if (m && !m.disabled) {
                let newX = (m.x || 0) + dx;
                let newY = (m.y || 0) + dy;
                const normalized = monitorCanvas.computeNormalized(monitorConfig.monitors || [], idx, newX, newY);
                const hasOverlap = monitorCanvas.checkOverlap(normalized, idx);
                if (!hasOverlap) {
                    monitorCanvas.commitPosition(idx, newX, newY);
                }
            }
        }
    }

    // ── 1. Monitor Overview ──────────────────────────────────────────────────
    ContentSection {
        id: overviewSection
        icon: "monitor"
        title: Translation.tr("Monitor Overview")
        visible: monitorConfig.monitors && monitorConfig.monitors.length > 0

        RowLayout {
            id: overviewRowLayout
            Layout.fillWidth: true
            spacing: 20

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 280
                spacing: 8

                MonitorCanvas {
                    id: monitorCanvas
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    monitorConfig: monitorConfig
                }
            }

            // Right panel
            ColumnLayout {
                id: rightPanelLayout
                Layout.fillWidth: false
                Layout.preferredWidth: 230
                Layout.minimumWidth: 200
                Layout.maximumWidth: 260
                Layout.alignment: Qt.AlignTop
                spacing: 4

                Rectangle {
                    id: selectedMonitorCard
                    Layout.fillWidth: true
                    implicitHeight: selectedMonitorCol.implicitHeight + 24
                    color: Appearance.colors.colLayer2Base

                    readonly property int itemIndex: {
                        var p = parent;
                        if (!p)
                            return 0;
                        var idx = 0;
                        for (var i = 0; i < p.children.length; ++i) {
                            if (p.children[i] === selectedMonitorCard)
                                return idx;
                            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                                idx++;
                        }
                        return 0;
                    }
                    readonly property int totalItems: {
                        var p = parent;
                        if (!p)
                            return 1;
                        var count = 0;
                        for (var i = 0; i < p.children.length; ++i) {
                            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                                count++;
                        }
                        return count;
                    }
                    property bool isFirst: itemIndex === 0
                    property bool isLast: itemIndex === totalItems - 1

                    topLeftRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                    topRightRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomLeftRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomRightRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall

                    ColumnLayout {
                        id: selectedMonitorCol
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        spacing: 4

                        StyledText {
                            text: Translation.tr("Selected Monitor")
                            font.pixelSize: 11
                            color: Appearance.colors.colSubtext
                            Layout.fillWidth: true
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: (monitorConfig.monitors && monitorConfig.monitors.length > 0 && monitorCanvas.selectedIndex >= 0 && monitorCanvas.selectedIndex < monitorConfig.monitors.length) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].description || monitorConfig.monitors[monitorCanvas.selectedIndex].name) : Translation.tr("None")
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer1
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Rectangle {
                    id: positionControlsCard
                    Layout.fillWidth: true
                    implicitHeight: positionControlsRow.implicitHeight + 24
                    color: Appearance.colors.colLayer2Base

                    readonly property int itemIndex: {
                        var p = parent;
                        if (!p)
                            return 0;
                        var idx = 0;
                        for (var i = 0; i < p.children.length; ++i) {
                            if (p.children[i] === positionControlsCard)
                                return idx;
                            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                                idx++;
                        }
                        return 0;
                    }
                    readonly property int totalItems: {
                        var p = parent;
                        if (!p)
                            return 1;
                        var count = 0;
                        for (var i = 0; i < p.children.length; ++i) {
                            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                                count++;
                        }
                        return count;
                    }
                    property bool isFirst: itemIndex === 0
                    property bool isLast: itemIndex === totalItems - 1

                    topLeftRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                    topRightRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomLeftRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomRightRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall

                    RowLayout {
                        id: positionControlsRow
                        anchors.centerIn: parent
                        spacing: 8

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                text: "arrow_back"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                                anchors.centerIn: parent
                            }
                            onClicked: {
                                page.moveSelectedMonitor(-100, 0);
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                text: "arrow_forward"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                                anchors.centerIn: parent
                            }
                            onClicked: {
                                page.moveSelectedMonitor(100, 0);
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                text: "arrow_upward"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                                anchors.centerIn: parent
                            }
                            onClicked: {
                                page.moveSelectedMonitor(0, -100);
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                text: "arrow_downward"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                                anchors.centerIn: parent
                            }
                            onClicked: {
                                page.moveSelectedMonitor(0, 100);
                            }
                        }
                    }
                }

                ConfigSwitch {
                    id: monitorEnabledSwitch
                    Layout.fillWidth: true
                    buttonIcon: checked ? "tv" : "tv_off"
                    text: Translation.tr("Enabled")

                    readonly property bool isCurrentMonitorActive: Boolean(monitorConfig.monitors
                        && monitorConfig.monitors[monitorCanvas.selectedIndex]
                        && !monitorConfig.monitors[monitorCanvas.selectedIndex].disabled)
                    readonly property bool isLastActiveMonitor: isCurrentMonitorActive && page.activeMonitorCount <= 1

                    enabled: !isLastActiveMonitor
                    checked: isCurrentMonitorActive
                    description: isLastActiveMonitor ? Translation.tr("Cannot disable the only active display") : ""

                    Binding {
                        target: monitorEnabledSwitch
                        property: "checked"
                        value: monitorEnabledSwitch.isCurrentMonitorActive
                    }

                    onCheckedChanged: {
                        if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                            let currentVal = !monitorConfig.monitors[monitorCanvas.selectedIndex].disabled;
                            if (checked !== currentVal) {
                                if (!checked && page.activeMonitorCount <= 1) {
                                    checked = true;
                                    return;
                                }
                                monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                                    disabled: !checked
                                });
                                monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                            }
                        }
                    }
                }
            }
        }
    }

    // ── 2. Monitor Settings ──────────────────────────────────────────────────
    ContentSection {
        icon: "settings"
        title: Translation.tr("Monitor Settings")
        visible: monitorConfig.monitors && monitorConfig.monitors.length > 0 && monitorCanvas.selectedIndex >= 0 && monitorCanvas.selectedIndex < monitorConfig.monitors.length

        ContentSubsection {
            title: Translation.tr("Resolution & Refresh Rate")
            icon: "aspect_ratio"
            StyledComboBox {
                buttonIcon: "aspect_ratio"
                Layout.fillWidth: true
                model: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex] ? (monitorConfig.monitors[monitorCanvas.selectedIndex].availableModes || []) : []).map(mode => ({
                            display: mode,
                            value: mode
                        }))
                textRole: "display"
                currentIndex: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex] ? (monitorConfig.monitors[monitorCanvas.selectedIndex].availableModes || []) : []).indexOf(monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex] ? (monitorConfig.monitors[monitorCanvas.selectedIndex].currentMode || "") : "")
                onActivated: index => {
                    const mon = monitorConfig.monitors[monitorCanvas.selectedIndex];
                    const mode = mon.availableModes[index];
                    const parts = mode.match(/(\d+)x(\d+)@([\d.]+)Hz/);
                    if (parts) {
                        monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                            currentMode: mode,
                            width: parseInt(parts[1]),
                            height: parseInt(parts[2]),
                            refreshRate: parseFloat(parts[3])
                        });
                        monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                    }
                }
            }
        }

        ConfigSlider {
            buttonIcon: "zoom_in"
            text: Translation.tr("Scale") + ` (${(value || 1.0).toFixed(2)}x)`
            value: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].scale || 1.0) : 1.0
            from: 0.5
            to: 3.0
            stepSize: 0.25
            snapMode: Slider.SnapAlways
            stopIndicatorValues: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0]
            usePercentTooltip: false
            tooltipContent: (value || 1.0).toFixed(2) + "x"
            onValueChanged: {
                if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                    let currentVal = monitorConfig.monitors[monitorCanvas.selectedIndex].scale || 1.0;
                    if (Math.abs(value - currentVal) > 0.01) {
                        monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                            scale: value
                        });
                        monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Orientation")
            icon: "screen_rotation_alt"
            ConfigSelectionArray {
                currentValue: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].transform || 0) : 0
                onSelected: newValue => {
                    if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                        let currentVal = monitorConfig.monitors[monitorCanvas.selectedIndex].transform || 0;
                        if (newValue !== currentVal) {
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                                transform: newValue
                            });
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                        }
                    }
                }
                options: [
                    {
                        displayName: Translation.tr("Normal"),
                        icon: "screen_rotation_alt",
                        value: 0
                    },
                    {
                        displayName: "90°",
                        icon: "rotate_90_degrees_cw",
                        value: 1
                    },
                    {
                        displayName: "180°",
                        icon: "screen_rotation",
                        value: 2
                    },
                    {
                        displayName: "270°",
                        icon: "rotate_90_degrees_ccw",
                        value: 3
                    },
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Mirror Screen")
            icon: "screen_share"
            StyledComboBox {
                buttonIcon: "screen_share"
                Layout.fillWidth: true
                property var otherMonitors: (monitorConfig.monitors || []).filter((_, idx) => idx !== monitorCanvas.selectedIndex)
                model: [
                    {
                        display: Translation.tr("None"),
                        value: "none"
                    }
                ].concat(otherMonitors.map(m => ({
                            display: m.name + " (" + (m.description || "") + ")",
                            value: m.name
                        })))
                textRole: "display"
                currentIndex: {
                    const mon = monitorConfig.monitors[monitorCanvas.selectedIndex];
                    if (!mon || !mon.mirrorOf || mon.mirrorOf === "none")
                        return 0;
                    for (let i = 0; i < otherMonitors.length; i++) {
                        if (otherMonitors[i].name === mon.mirrorOf)
                            return i + 1;
                    }
                    return 0;
                }
                onActivated: index => {
                    const mirrorValue = index === 0 ? "none" : otherMonitors[index - 1].name;
                    monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                        mirrorOf: mirrorValue
                    });
                    monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                }
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("Position")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "swap_horiz"
                text: Translation.tr("Position X")
                value: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].x || 0) : 0
                from: 0
                to: 15360
                stepSize: 1
                onValueChanged: {
                    if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                        let currentVal = monitorConfig.monitors[monitorCanvas.selectedIndex].x || 0;
                        if (value !== currentVal) {
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                                x: value
                            });
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                        }
                    }
                }
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "swap_vert"
                text: Translation.tr("Position Y")
                value: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].y || 0) : 0
                from: 0
                to: 8640
                stepSize: 1
                onValueChanged: {
                    if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                        let currentVal = monitorConfig.monitors[monitorCanvas.selectedIndex].y || 0;
                        if (value !== currentVal) {
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                                y: value
                            });
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                        }
                    }
                }
            }
        }
    }

    // ── 3. Advanced Settings ─────────────────────────────────────────────────
    ContentSection {
        id: advancedSection
        icon: "tune"
        title: Translation.tr("Advanced Settings")
        visible: monitorConfig.monitors && monitorConfig.monitors.length > 0 && monitorCanvas.selectedIndex >= 0 && monitorCanvas.selectedIndex < monitorConfig.monitors.length

        readonly property bool isHdrEnabled: {
            const mon = (monitorConfig.monitors && monitorCanvas.selectedIndex >= 0 && monitorCanvas.selectedIndex < monitorConfig.monitors.length) ? monitorConfig.monitors[monitorCanvas.selectedIndex] : null;
            return mon ? (mon.colorManagementPreset === "hdr" || mon.colorManagementPreset === "hdr-edid") : false;
        }

        ContentSubsection {
            title: Translation.tr("Bit Depth")
            icon: "settings_brightness"
            ConfigSelectionArray {
                currentValue: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].bitDepth || 8) : 8
                onSelected: newValue => {
                    if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                        let currentVal = monitorConfig.monitors[monitorCanvas.selectedIndex].bitDepth || 8;
                        if (newValue !== currentVal) {
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                                bitDepth: newValue
                            });
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                        }
                    }
                }
                options: [
                    {
                        displayName: "8-bit",
                        icon: "settings_brightness",
                        value: 8
                    },
                    {
                        displayName: "10-bit",
                        icon: "hdr_on",
                        value: 10
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Color Management")
            icon: "palette"
            StyledComboBox {
                buttonIcon: "palette"
                Layout.fillWidth: true
                model: [
                    {
                        display: Translation.tr("sRGB (Standard)"),
                        value: "srgb"
                    },
                    {
                        display: Translation.tr("HDR"),
                        value: "hdr"
                    },
                    {
                        display: Translation.tr("HDR (EDID)"),
                        value: "hdr-edid"
                    },
                    {
                        display: Translation.tr("Wide Color Gamut"),
                        value: "wide"
                    },
                    {
                        display: Translation.tr("Auto"),
                        value: "auto"
                    }
                ]
                textRole: "display"
                currentIndex: {
                    const mon = monitorConfig.monitors[monitorCanvas.selectedIndex];
                    if (!mon || !mon.colorManagementPreset)
                        return 0;
                    const val = mon.colorManagementPreset;
                    if (val === "srgb")
                        return 0;
                    if (val === "hdr")
                        return 1;
                    if (val === "hdr-edid")
                        return 2;
                    if (val === "wide")
                        return 3;
                    if (val === "auto")
                        return 4;
                    return 0;
                }
                onActivated: index => {
                    const vals = ["srgb", "hdr", "hdr-edid", "wide", "auto"];
                    const cmValue = vals[index];
                    monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                        colorManagementPreset: cmValue
                    });
                    monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                }
            }
        }

        ConfigSlider {
            enabled: advancedSection.isHdrEnabled
            opacity: enabled ? 1.0 : 0.5
            buttonIcon: "brightness_6"
            text: Translation.tr("SDR Brightness") + ` (${(value || 1.0).toFixed(2)})`
            value: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].sdrBrightness || 1.0) : 1.0
            from: 0.5
            to: 2.0
            stepSize: 0.1
            usePercentTooltip: false
            tooltipContent: (value || 1.0).toFixed(2)
            onValueChanged: {
                if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                    let currentVal = monitorConfig.monitors[monitorCanvas.selectedIndex].sdrBrightness || 1.0;
                    if (Math.abs(value - currentVal) > 0.01) {
                        monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                            sdrBrightness: value
                        });
                        monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                    }
                }
            }
        }

        ConfigSlider {
            enabled: advancedSection.isHdrEnabled
            opacity: enabled ? 1.0 : 0.5
            buttonIcon: "palette"
            text: Translation.tr("SDR-in-HDR Saturation") + ` (${(value || 1.0).toFixed(2)})`
            value: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].sdrSaturation || 1.0) : 1.0
            from: 0.5
            to: 1.5
            stepSize: 0.05
            usePercentTooltip: false
            tooltipContent: (value || 1.0).toFixed(2)
            onValueChanged: {
                if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                    let currentVal = monitorConfig.monitors[monitorCanvas.selectedIndex].sdrSaturation || 1.0;
                    if (Math.abs(value - currentVal) > 0.01) {
                        monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                            sdrSaturation: value
                        });
                        monitorConfig.applyAndSave(monitorCanvas.selectedIndex);
                    }
                }
            }
        }
    }

    // ── 4. Color & Contrast ──────────────────────────────────────────────────
    ContentSection {
        id: colorCalibrationSection
        icon: "contrast"
        title: Translation.tr("Color & Contrast")
        visible: page.selectedMonitor !== null

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            text: Translation.tr("Adjusting %1. GPU fallback works on any output; supported hardware controls appear below.").arg(page.selectedMonitor ? (page.selectedMonitor.description || page.selectedMonitorName) : "")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        ContentSubsectionLabel {
            text: Translation.tr("GPU color filter")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: DisplayColorFilter.applied
            materialIcon: "science"
            text: Translation.tr("Experimental feature: the GPU fallback uses Hyprland's screen shader slot, so other screen shaders are disabled while it is active. Activating another shader temporarily pauses these color adjustments.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: page.selectedMonitorName.length > 0
                && !DisplayColorFilter.isMonitorNeutral(page.selectedMonitorName)
                && ScreenShader.active
            materialIcon: "pause_circle"
            text: Translation.tr("GPU calibration is temporarily paused while the %1 screen filter is active.").arg(ScreenShader.statusText)
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: DisplayColorFilter.errorMessage.length > 0
            materialIcon: "error"
            text: Translation.tr("The GPU color filter could not be generated. Your saved calibration was preserved.")
        }

        ConfigSlider {
            buttonIcon: "palette"
            text: Translation.tr("GPU saturation") + ` (${Math.round(value)}%)`
            value: page.selectedGpuCalibration ? page.selectedGpuCalibration.saturation * 100 : 100
            from: 0
            to: 200
            stepSize: 1
            stopIndicatorValues: [100]
            onValueChanged: {
                if (page.selectedGpuCalibration
                        && Math.abs(value / 100 - page.selectedGpuCalibration.saturation) > 0.001)
                    DisplayColorFilter.setSaturation(page.selectedMonitorName, value / 100);
            }
        }

        ConfigSlider {
            buttonIcon: "contrast"
            text: Translation.tr("GPU contrast") + ` (${Math.round(value)}%)`
            value: page.selectedGpuCalibration ? page.selectedGpuCalibration.contrast * 100 : 100
            from: 50
            to: 150
            stepSize: 1
            stopIndicatorValues: [100]
            onValueChanged: {
                if (page.selectedGpuCalibration
                        && Math.abs(value / 100 - page.selectedGpuCalibration.contrast) > 0.001)
                    DisplayColorFilter.setContrast(page.selectedMonitorName, value / 100);
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("GPU color balance")
        }

        ConfigSlider {
            buttonIcon: "format_color_fill"
            text: Translation.tr("GPU red channel") + ` (${Math.round(value)}%)`
            value: page.selectedGpuCalibration ? page.selectedGpuCalibration.red * 100 : 100
            from: 50
            to: 150
            stepSize: 1
            stopIndicatorValues: [100]
            onValueChanged: {
                if (page.selectedGpuCalibration
                        && Math.abs(value / 100 - page.selectedGpuCalibration.red) > 0.001)
                    DisplayColorFilter.setRed(page.selectedMonitorName, value / 100);
            }
        }

        ConfigSlider {
            buttonIcon: "grass"
            text: Translation.tr("GPU green channel") + ` (${Math.round(value)}%)`
            value: page.selectedGpuCalibration ? page.selectedGpuCalibration.green * 100 : 100
            from: 50
            to: 150
            stepSize: 1
            stopIndicatorValues: [100]
            onValueChanged: {
                if (page.selectedGpuCalibration
                        && Math.abs(value / 100 - page.selectedGpuCalibration.green) > 0.001)
                    DisplayColorFilter.setGreen(page.selectedMonitorName, value / 100);
            }
        }

        ConfigSlider {
            buttonIcon: "water_drop"
            text: Translation.tr("GPU blue channel") + ` (${Math.round(value)}%)`
            value: page.selectedGpuCalibration ? page.selectedGpuCalibration.blue * 100 : 100
            from: 50
            to: 150
            stepSize: 1
            stopIndicatorValues: [100]
            onValueChanged: {
                if (page.selectedGpuCalibration
                        && Math.abs(value / 100 - page.selectedGpuCalibration.blue) > 0.001)
                    DisplayColorFilter.setBlue(page.selectedMonitorName, value / 100);
            }
        }

        RippleButtonWithIcon {
            visible: page.selectedMonitorName.length > 0
                && !DisplayColorFilter.isMonitorNeutral(page.selectedMonitorName)
            Layout.fillWidth: false
            materialIcon: "restart_alt"
            mainText: Translation.tr("Reset GPU calibration")
            onClicked: DisplayColorFilter.resetMonitor(page.selectedMonitorName)
        }

        ContentSubsectionLabel {
            text: Translation.tr("Hardware controls (DDC/CI)")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: !DisplayCalibration.ddcutilAvailable
            materialIcon: "error"
            text: Translation.tr("ddcutil is required for hardware color and contrast controls.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: DisplayCalibration.ddcutilAvailable
                && !DisplayCalibration.detectionFailed
                && (!DisplayCalibration.detectionComplete
                    || (page.selectedCalibration && page.selectedCalibration.probing))
            materialIcon: "hourglass_top"
            text: Translation.tr("Reading the selected monitor's color controls…")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: DisplayCalibration.ddcutilAvailable
                && DisplayCalibration.detectionFailed
            materialIcon: "error"
            text: Translation.tr("The display color service could not enumerate DDC/CI monitors. Check I²C permissions and try again.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: DisplayCalibration.ddcutilAvailable
                && !DisplayCalibration.detectionFailed
                && DisplayCalibration.detectionComplete
                && (!page.selectedCalibration || !page.selectedCalibration.isDdc)
            materialIcon: "info"
            text: Translation.tr("This display does not expose DDC/CI controls. Internal panels and some adapters may not support hardware color adjustment.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: page.selectedCalibration
                && page.selectedCalibration.ready
                && page.selectedCalibration.isDdc
                && page.selectedCalibration.error !== "readFailed"
                && !page.selectedCalibration.hasAnyControl
            materialIcon: "info"
            text: Translation.tr("DDC/CI is available, but this monitor does not report contrast or RGB gain controls.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: page.selectedCalibration
                && (page.selectedCalibration.error === "readFailed"
                    || page.selectedCalibration.error === "writeFailed")
            materialIcon: "error"
            text: page.selectedCalibration && page.selectedCalibration.error === "writeFailed"
                ? Translation.tr("The monitor rejected the last color adjustment. Reload its values and try again.")
                : Translation.tr("The monitor was detected, but its color controls could not be read.")
        }

        ConfigSlider {
            visible: page.selectedCalibration
                && page.selectedCalibration.ready
                && page.selectedCalibration.contrastSupported
            buttonIcon: "contrast"
            text: Translation.tr("Hardware contrast") + ` (${Math.round(value)}%)`
            value: page.selectedCalibration ? page.selectedCalibration.contrast : 50
            from: 0
            to: 100
            stepSize: 1
            stopIndicatorValues: [50]
            onValueChanged: {
                if (page.selectedCalibration
                        && page.selectedCalibration.contrastSupported
                        && Math.round(value) !== page.selectedCalibration.contrast)
                    page.selectedCalibration.setContrast(value);
            }
        }

        ContentSubsectionLabel {
            visible: page.selectedCalibration
                && page.selectedCalibration.ready
                && page.selectedCalibration.hasColorControls
            text: Translation.tr("Hardware color balance")
        }

        ConfigSlider {
            visible: page.selectedCalibration
                && page.selectedCalibration.ready
                && page.selectedCalibration.redSupported
            buttonIcon: "format_color_fill"
            text: Translation.tr("Red gain") + ` (${Math.round(value)}%)`
            value: page.selectedCalibration ? page.selectedCalibration.red : 50
            from: 0
            to: 100
            stepSize: 1
            stopIndicatorValues: [50]
            onValueChanged: {
                if (page.selectedCalibration
                        && page.selectedCalibration.redSupported
                        && Math.round(value) !== page.selectedCalibration.red)
                    page.selectedCalibration.setRed(value);
            }
        }

        ConfigSlider {
            visible: page.selectedCalibration
                && page.selectedCalibration.ready
                && page.selectedCalibration.greenSupported
            buttonIcon: "grass"
            text: Translation.tr("Green gain") + ` (${Math.round(value)}%)`
            value: page.selectedCalibration ? page.selectedCalibration.green : 50
            from: 0
            to: 100
            stepSize: 1
            stopIndicatorValues: [50]
            onValueChanged: {
                if (page.selectedCalibration
                        && page.selectedCalibration.greenSupported
                        && Math.round(value) !== page.selectedCalibration.green)
                    page.selectedCalibration.setGreen(value);
            }
        }

        ConfigSlider {
            visible: page.selectedCalibration
                && page.selectedCalibration.ready
                && page.selectedCalibration.blueSupported
            buttonIcon: "water_drop"
            text: Translation.tr("Blue gain") + ` (${Math.round(value)}%)`
            value: page.selectedCalibration ? page.selectedCalibration.blue : 50
            from: 0
            to: 100
            stepSize: 1
            stopIndicatorValues: [50]
            onValueChanged: {
                if (page.selectedCalibration
                        && page.selectedCalibration.blueSupported
                        && Math.round(value) !== page.selectedCalibration.blue)
                    page.selectedCalibration.setBlue(value);
            }
        }

        RippleButtonWithIcon {
            visible: page.selectedCalibration && page.selectedCalibration.isDdc
            enabled: page.selectedCalibration
                && !page.selectedCalibration.probing
                && !DisplayCalibration.detecting
            Layout.fillWidth: false
            materialIcon: "refresh"
            mainText: Translation.tr("Reload hardware values")
            onClicked: DisplayCalibration.refreshMonitor(page.selectedMonitorName)
        }
    }

    // ── 5. Profiles ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "display_settings"
        title: Translation.tr("Profiles")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            Repeater {
                model: monitorConfig.profiles
                delegate: Loader {
                    id: profileCardLoader
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 65
                    source: Qt.resolvedUrl("MonitorProfileCard.qml")

                    Binding {
                        target: profileCardLoader.item
                        property: "profileName"
                        value: profileCardLoader.modelData.name
                        when: profileCardLoader.item !== null
                    }

                    Binding {
                        target: profileCardLoader.item
                        property: "isActive"
                        value: profileCardLoader.modelData.isActive
                        when: profileCardLoader.item !== null
                    }

                    Connections {
                        target: profileCardLoader.item
                        function onApplyClicked() {
                            monitorConfig.applyProfile(profileCardLoader.modelData.name);
                            Quickshell.execDetached(["notify-send", "Monitors", Translation.tr(`Profile '${profileCardLoader.modelData.name}' applied!`)]);
                        }
                        function onDeleteClicked() {
                            monitorConfig.deleteProfile(profileCardLoader.modelData.name);
                            Quickshell.execDetached(["notify-send", "Monitors", Translation.tr(`Profile '${profileCardLoader.modelData.name}' deleted!`)]);
                        }
                    }
                }
            }

            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.small
                materialIcon: "add"
                mainText: Translation.tr("New Profile")
                onClicked: {
                    createProfileDialog.show = true;
                }
            }
        }
    }

    // ── Floating Action Buttons (Fixed Bottom-Right) ─────────────────────────
    RowLayout {
        parent: page.parent ? page.parent : page
        anchors.bottom: parent ? parent.bottom : undefined
        anchors.right: parent ? parent.right : undefined
        anchors.margins: 25
        spacing: 12
        z: 9999

        FloatingActionButton {
            iconText: "history"
            buttonText: Translation.tr("Rollback")
            expanded: hovered
            onClicked: {
                monitorConfig.reloadFromHyprland();
            }
        }

        FloatingActionButton {
            iconText: "save"
            buttonText: Translation.tr("Save to Hyprland")
            expanded: hovered
            onClicked: {
                monitorConfig.saveToHyprland();
            }
        }
    }

    // Create Profile Dialog
    WindowDialog {
        id: createProfileDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        backgroundWidth: 320
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            text: Translation.tr("New Profile")
        }

        WindowDialogParagraph {
            text: Translation.tr("Enter a name for the new profile:")
        }

        MaterialTextField {
            id: profileNameInput
            Layout.fillWidth: true
            placeholderText: Translation.tr("Profile name")
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: createProfileDialog.show = false
            }
            DialogButton {
                buttonText: Translation.tr("Create")
                onClicked: {
                    if (profileNameInput.text.trim().length > 0) {
                        monitorConfig.saveProfile(profileNameInput.text.trim());
                        profileNameInput.text = "";
                        createProfileDialog.show = false;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "brightness_1"
        title: Translation.tr("Always On Display")

        StyledText {
            text: Translation.tr("Super + R turns all monitors into an Always On Display: pure black, with the lock screen's widgets in grey, where the lock screen places them. A click, a key or the same shortcut wakes them. On the lock screen it also comes on by itself after the timeout below.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            Layout.bottomMargin: 8
        }

        ConfigSwitch {
            id: aodEnabledSwitch
            buttonIcon: checked ? "brightness_1" : "brightness_empty"
            text: Translation.tr("Enable Always On Display")
            checked: Config.options.oledSaver.enable ?? true

            Binding {
                target: aodEnabledSwitch
                property: "checked"
                value: Config.options.oledSaver.enable ?? true
            }

            onCheckedChanged: {
                if (Config.ready && Config.options.oledSaver) {
                    Config.options.oledSaver.enable = checked;
                    if (!checked)
                        GlobalStates.oledSaverMonitors = [];
                }
            }
        }

        ConfigSwitch {
            id: aodAntiBurnInSwitch
            enabled: aodEnabledSwitch.checked
            opacity: enabled ? 1.0 : 0.5
            buttonIcon: "motion_photos_on"
            text: Translation.tr("Anti burn-in pixel shift")
            checked: Config.options.oledSaver.antiBurnIn ?? true

            Binding {
                target: aodAntiBurnInSwitch
                property: "checked"
                value: Config.options.oledSaver.antiBurnIn ?? true
            }

            onCheckedChanged: {
                if (Config.ready && Config.options.oledSaver) {
                    Config.options.oledSaver.antiBurnIn = checked;
                }
            }

            StyledToolTip {
                text: Translation.tr("Periodically shifts widgets every minute to prevent OLED screen burn-in")
            }
        }

        ConfigSpinBox {
            enabled: aodEnabledSwitch.checked
            opacity: enabled ? 1.0 : 0.5
            icon: "mouse"
            text: Translation.tr("Cursor hide delay (seconds)")
            value: Config.options.oledSaver.cursorHideDelay
            from: 1
            to: 60
            stepSize: 1
            onValueChanged: {
                Config.options.oledSaver.cursorHideDelay = value;
            }
            StyledToolTip {
                text: Translation.tr("How long after you stop moving the mouse before the cursor hides again")
            }
        }

        ConfigSpinBox {
            enabled: aodEnabledSwitch.checked
            opacity: enabled ? 1.0 : 0.5
            icon: "lock_clock"
            text: Translation.tr("Lock screen timeout (minutes)")
            value: Config.options.oledSaver.lockTimeout
            from: 0
            to: 60
            stepSize: 1
            onValueChanged: {
                Config.options.oledSaver.lockTimeout = value;
            }
            StyledToolTip {
                text: Translation.tr("Minutes without input on the lock screen before it turns into the Always On Display. 0 turns the timer off; the shortcut still works")
            }
        }
    }

    ContentSection {
        icon: "crop"
        title: Translation.tr("Edge & Interaction Tweaks")

        ConfigSwitch {
            buttonIcon: "crop"
            text: Translation.tr("Enable 1-pixel screen edge workaround")
            checked: Config.options.interactions.deadPixelWorkaround.enable ?? false
            onCheckedChanged: {
                Config.options.interactions.deadPixelWorkaround.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Compensates for 1-pixel margin discrepancies on the right and bottom screen edges in Hyprland.")
            }
        }
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "colors"
                label: Translation.tr("Night Light")
                sectionHighlight: Translation.tr("Night Light")
            }

            RelatedChip {
                pageId: "lockScreen"
                label: Translation.tr("Always On Display")
                sectionHighlight: Translation.tr("Always On Display")
            }
        }
    }
}
