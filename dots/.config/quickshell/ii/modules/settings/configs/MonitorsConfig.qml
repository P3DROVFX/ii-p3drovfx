import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models.hyprland

ContentPage {
    id: page
    forceWidth: false

    MonitorConfigOption {
        id: monitorConfig
    }

    component MonitorRect: Rectangle {
        id: rectRoot
        required property var monitor
        required property int monitorIndex
        required property var monitorConfig
        required property real scaleFactor
        required property point canvasOffset
        required property var allMonitors
        property bool isSelected: false
        property var previewPositions: ({})
        property bool hasOverlap: false

        signal positionCommitted(int index, int x, int y)
        signal monitorClicked(int index)
        signal positionDragging(int index, int x, int y)

        property bool isDragging: false
        property real dragX: 0
        property real dragY: 0
        property int snappedX: 0
        property int snappedY: 0
        property real snapThreshold: 12

        property real startMouseX: 0
        property real startMouseY: 0
        property real startX: 0
        property real startY: 0

        property int logW: (monitor && typeof monitor.width === "number" && typeof monitor.height === "number") ? monitorConfig.logicalWidth(monitor) : 1920
        property int logH: (monitor && typeof monitor.width === "number" && typeof monitor.height === "number") ? monitorConfig.logicalHeight(monitor) : 1080

        x: isDragging ? dragX : (monitor ? ((previewPositions[monitor.name] !== undefined && previewPositions[monitor.name].x !== undefined) ? previewPositions[monitor.name].x : monitor.x) * scaleFactor + canvasOffset.x : 0)
        y: isDragging ? dragY : (monitor ? ((previewPositions[monitor.name] !== undefined && previewPositions[monitor.name].y !== undefined) ? previewPositions[monitor.name].y : monitor.y) * scaleFactor + canvasOffset.y : 0)
        width: logW * scaleFactor
        height: logH * scaleFactor

        radius: Appearance.rounding.small
        z: isDragging ? 100 : isSelected ? 2 : 1

        color: {
            if (monitor && monitor.disabled)
                return Appearance.colors.colLayer2;
            if (isDragging && hasOverlap)
                return Qt.alpha(Appearance.m3colors.m3error, 0.5);
            if (isDragging)
                return Qt.alpha(Appearance.colors.colPrimaryContainer, 0.7);
            if (isSelected)
                return Appearance.colors.colPrimaryContainer;
            if (hoverArea.containsMouse)
                return Appearance.colors.colSecondaryContainerHover;
            return Appearance.colors.colSecondaryContainer;
        }

        border.color: {
            if (isDragging && hasOverlap)
                return Appearance.m3colors.m3error;
            if (isDragging)
                return Appearance.colors.colPrimary;
            if (isSelected)
                return "transparent";
            return Appearance.colors.colLayer0Border;
        }
        border.width: isSelected ? 0 : (isDragging ? 2 : 1)

        Behavior on x {
            enabled: !isDragging && monitorCanvas.width > 40
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            enabled: !isDragging && monitorCanvas.width > 40
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
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

        Rectangle {
            parent: rectRoot.parent
            visible: rectRoot.isDragging && !rectRoot.hasOverlap
            x: rectRoot.snappedX * rectRoot.scaleFactor + rectRoot.canvasOffset.x
            y: rectRoot.snappedY * rectRoot.scaleFactor + rectRoot.canvasOffset.y
            width: rectRoot.width
            height: rectRoot.height
            radius: rectRoot.radius
            color: "transparent"
            border.color: Appearance.colors.colPrimary
            border.width: 2
            opacity: 0.6
            z: 99
        }

        Column {
            anchors.centerIn: parent
            spacing: 4

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (rectRoot.monitorIndex + 1).toString()
                font.pixelSize: Math.max(20, Math.min(36, rectRoot.width * 0.25))
                font.weight: Font.Bold
                font.family: Appearance.font.family.numbers
                color: (monitor && monitor.disabled) ? Appearance.colors.colSubtext : isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: monitor && monitor.name ? monitor.name : "Display"
                font.pixelSize: Math.max(9, Math.min(13, rectRoot.width * 0.1))
                font.weight: Font.Medium
                color: (monitor && monitor.disabled) ? Appearance.colors.colSubtext : isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, rectRoot.width - 8)
                horizontalAlignment: Text.AlignHCenter
            }
        }

        function snapPosition(px, py) {
            let sx = px, sy = py;
            const thresh = snapThreshold / scaleFactor;
            for (let i = 0; i < allMonitors.length; i++) {
                if (i === monitorIndex)
                    continue;
                const other = allMonitors[i];
                if (!other || other.disabled || typeof other.x !== "number" || typeof other.y !== "number")
                    continue;
                const ow = monitorConfig.logicalWidth(other);
                const oh = monitorConfig.logicalHeight(other);
                if (Math.abs(px - other.x) < thresh)
                    sx = other.x;
                if (Math.abs(px - (other.x + ow)) < thresh)
                    sx = other.x + ow;
                if (Math.abs((px + logW) - other.x) < thresh)
                    sx = other.x - logW;
                if (Math.abs((px + logW) - (other.x + ow)) < thresh)
                    sx = other.x + ow - logW;
                if (Math.abs(py - other.y) < thresh)
                    sy = other.y;
                if (Math.abs(py - (other.y + oh)) < thresh)
                    sy = other.y + oh;
                if (Math.abs((py + logH) - other.y) < thresh)
                    sy = other.y - logH;
                if (Math.abs((py + logH) - (other.y + oh)) < thresh)
                    sy = other.y + oh - logH;
            }
            return Qt.point(sx, sy);
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: (monitor && monitor.disabled) ? Qt.ArrowCursor : (rectRoot.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
            drag.threshold: 4
            preventStealing: true

            onPressed: event => {
                let startPos = hoverArea.mapToItem(rectRoot.parent, event.x, event.y);
                rectRoot.startMouseX = startPos.x;
                rectRoot.startMouseY = startPos.y;
                rectRoot.startX = rectRoot.x;
                rectRoot.startY = rectRoot.y;
                rectRoot.dragX = rectRoot.x;
                rectRoot.dragY = rectRoot.y;
                rectRoot.snappedX = monitor.x;
                rectRoot.snappedY = monitor.y;
                if (monitor && !monitor.disabled) {
                    rectRoot.isDragging = true;
                }
            }

            onPositionChanged: event => {
                if (!rectRoot.isDragging)
                    return;
                let currentPos = hoverArea.mapToItem(rectRoot.parent, event.x, event.y);
                let dx = currentPos.x - rectRoot.startMouseX;
                let dy = currentPos.y - rectRoot.startMouseY;
                rectRoot.dragX = rectRoot.startX + dx;
                rectRoot.dragY = rectRoot.startY + dy;
                const realX = Math.round((rectRoot.dragX - rectRoot.canvasOffset.x) / rectRoot.scaleFactor);
                const realY = Math.round((rectRoot.dragY - rectRoot.canvasOffset.y) / rectRoot.scaleFactor);
                const snapped = rectRoot.snapPosition(realX, realY);
                rectRoot.snappedX = snapped.x;
                rectRoot.snappedY = snapped.y;
                rectRoot.positionDragging(rectRoot.monitorIndex, rectRoot.snappedX, rectRoot.snappedY);
            }

            onReleased: event => {
                rectRoot.isDragging = false;
                if (rectRoot.snappedX === monitor.x && rectRoot.snappedY === monitor.y) {
                    rectRoot.monitorClicked(rectRoot.monitorIndex);
                    return;
                }
                rectRoot.positionCommitted(rectRoot.monitorIndex, rectRoot.snappedX, rectRoot.snappedY);
            }
        }
    }

    component MonitorCanvas: Item {
        id: canvasRoot
        property var monitorConfig
        property real padding: 20
        property int selectedIndex: 0
        property var previewPositions: ({})
        property bool dragHasOverlap: false

        implicitHeight: 220

        property var bounds: {
            let minX = Infinity, minY = Infinity;
            let maxX = -Infinity, maxY = -Infinity;
            const mons = monitorConfig.monitors || [];
            for (let i = 0; i < mons.length; i++) {
                const m = mons[i];
                if (!m || typeof m.width !== "number" || typeof m.height !== "number")
                    continue;
                const w = monitorConfig.logicalWidth(m) || 1920;
                const h = monitorConfig.logicalHeight(m) || 1080;
                const px = (m.name && previewPositions[m.name] !== undefined && previewPositions[m.name].x !== undefined) ? previewPositions[m.name].x : (m.x || 0);
                const py = (m.name && previewPositions[m.name] !== undefined && previewPositions[m.name].y !== undefined) ? previewPositions[m.name].y : (m.y || 0);
                minX = Math.min(minX, px);
                minY = Math.min(minY, py);
                maxX = Math.max(maxX, px + w);
                maxY = Math.max(maxY, py + h);
            }
            if (minX === Infinity)
                return {
                    minX: 0,
                    minY: 0,
                    width: 1920,
                    height: 1080
                };
            return {
                minX,
                minY,
                width: maxX - minX,
                height: maxY - minY
            };
        }

        property real scaleFactor: {
            if (bounds.width === 0 || bounds.height === 0 || isNaN(bounds.width) || isNaN(bounds.height))
                return 0.1;
            if (canvasRoot.width <= padding * 2 || canvasRoot.height <= padding * 2)
                return 0.1;
            const scaleX = (canvasRoot.width - padding * 2) / bounds.width;
            const scaleY = (canvasRoot.height - padding * 2) / bounds.height;
            return Math.max(0.01, Math.min(scaleX, scaleY));
        }

        property point offset: Qt.point((canvasRoot.width - bounds.width * scaleFactor) / 2 - bounds.minX * scaleFactor, (canvasRoot.height - bounds.height * scaleFactor) / 2 - bounds.minY * scaleFactor)

        property var snapPoints: {
            let list = [];
            const mons = monitorConfig.monitors || [];
            for (let i = 0; i < mons.length; i++) {
                const a = mons[i];
                if (!a || a.disabled)
                    continue;
                const aw = monitorConfig.logicalWidth(a);
                const ah = monitorConfig.logicalHeight(a);
                const ax = (a.name && previewPositions[a.name] !== undefined && previewPositions[a.name].x !== undefined) ? previewPositions[a.name].x : (a.x || 0);
                const ay = (a.name && previewPositions[a.name] !== undefined && previewPositions[a.name].y !== undefined) ? previewPositions[a.name].y : (a.y || 0);

                for (let j = i + 1; j < mons.length; j++) {
                    const b = mons[j];
                    if (!b || b.disabled)
                        continue;
                    const bw = monitorConfig.logicalWidth(b);
                    const bh = monitorConfig.logicalHeight(b);
                    const bx = (b.name && previewPositions[b.name] !== undefined && previewPositions[b.name].x !== undefined) ? previewPositions[b.name].x : (b.x || 0);
                    const by = (b.name && previewPositions[b.name] !== undefined && previewPositions[b.name].y !== undefined) ? previewPositions[b.name].y : (b.y || 0);

                    const aR = ax + aw;
                    const bR = bx + bw;
                    const aB = ay + ah;
                    const bB = by + bh;
                    const THRESH = 6; // px tolerance in logical units

                    const hAdjLeft = Math.abs(aR - bx) < THRESH;
                    const hAdjRight = Math.abs(bR - ax) < THRESH;
                    const vAdjTop = Math.abs(aB - by) < THRESH;
                    const vAdjBottom = Math.abs(bB - ay) < THRESH;

                    const hOverlap = Math.min(aR, bR) > Math.max(ax, bx);
                    const vOverlap = Math.min(aB, bB) > Math.max(ay, by);

                    if (hAdjLeft && vOverlap) {
                        let cx = aR;
                        let cy = (Math.max(ay, by) + Math.min(aB, bB)) / 2;
                        list.push({
                            x: cx,
                            y: cy
                        });
                    } else if (hAdjRight && vOverlap) {
                        let cx = bR;
                        let cy = (Math.max(ay, by) + Math.min(aB, bB)) / 2;
                        list.push({
                            x: cx,
                            y: cy
                        });
                    } else if (vAdjTop && hOverlap) {
                        let cx = (Math.max(ax, bx) + Math.min(aR, bR)) / 2;
                        let cy = aB;
                        list.push({
                            x: cx,
                            y: cy
                        });
                    } else if (vAdjBottom && hOverlap) {
                        let cx = (Math.max(ax, bx) + Math.min(aR, bR)) / 2;
                        let cy = bB;
                        list.push({
                            x: cx,
                            y: cy
                        });
                    }
                }
            }
            return list;
        }

        function checkOverlap(monitors, idx) {
            const a = monitors[idx];
            if (!a || a.disabled)
                return false;
            const aw = monitorConfig.logicalWidth(a) || 1920;
            const ah = monitorConfig.logicalHeight(a) || 1080;
            for (let i = 0; i < monitors.length; i++) {
                if (i === idx)
                    continue;
                const b = monitors[i];
                if (!b || b.disabled)
                    continue;
                const bw = monitorConfig.logicalWidth(b) || 1920;
                const bh = monitorConfig.logicalHeight(b) || 1080;
                if (a.x < b.x + bw && a.x + aw > b.x && a.y < b.y + bh && a.y + ah > b.y) {
                    return true;
                }
            }
            return false;
        }

        function computeNormalized(monitors, changedIdx, newX, newY) {
            let m = monitors.slice().map(mon => Object.assign({}, mon));
            if (m[changedIdx]) {
                m[changedIdx].x = newX;
                m[changedIdx].y = newY;
            }
            let minX = Infinity, minY = Infinity;
            for (let i = 0; i < m.length; i++) {
                if (!m[i] || m[i].disabled)
                    continue;
                minX = Math.min(minX, m[i].x);
                minY = Math.min(minY, m[i].y);
            }
            const offX = minX < 0 ? -minX : 0;
            const offY = minY < 0 ? -minY : 0;
            if (offX > 0 || offY > 0) {
                for (let i = 0; i < m.length; i++) {
                    if (m[i]) {
                        m[i].x += offX;
                        m[i].y += offY;
                    }
                }
            }
            return m;
        }

        function updatePreview(idx, newX, newY) {
            const normalized = computeNormalized(monitorConfig.monitors || [], idx, newX, newY);
            canvasRoot.dragHasOverlap = checkOverlap(normalized, idx);
            let preview = {};
            for (let i = 0; i < normalized.length; i++) {
                if (normalized[i] && normalized[i].name) {
                    preview[normalized[i].name] = {
                        x: normalized[i].x,
                        y: normalized[i].y
                    };
                }
            }
            canvasRoot.previewPositions = preview;
        }

        function commitPosition(idx, newX, newY) {
            const normalized = computeNormalized(monitorConfig.monitors || [], idx, newX, newY);
            monitorConfig.monitors = normalized;
            canvasRoot.previewPositions = {};
            monitorConfig.save();
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Item {
                id: canvasInner
                anchors.fill: parent

                Repeater {
                    model: (canvasRoot.monitorConfig.monitors || []).length
                    delegate: MonitorRect {
                        required property int index
                        monitor: canvasRoot.monitorConfig.monitors ? canvasRoot.monitorConfig.monitors[index] : null
                        monitorIndex: index
                        monitorConfig: canvasRoot.monitorConfig
                        scaleFactor: canvasRoot.scaleFactor
                        canvasOffset: canvasRoot.offset
                        allMonitors: canvasRoot.monitorConfig.monitors || []
                        isSelected: index === canvasRoot.selectedIndex
                        previewPositions: canvasRoot.previewPositions
                        hasOverlap: canvasRoot.dragHasOverlap && isDragging

                        onMonitorClicked: idx => canvasRoot.selectedIndex = idx
                        onPositionDragging: (idx, x, y) => canvasRoot.updatePreview(idx, x, y)
                        onPositionCommitted: (idx, x, y) => {
                            const hadOverlap = canvasRoot.dragHasOverlap;
                            canvasRoot.previewPositions = {};
                            canvasRoot.dragHasOverlap = false;
                            if (!hadOverlap)
                                canvasRoot.commitPosition(idx, x, y);
                        }
                    }
                }

                Repeater {
                    model: canvasRoot.snapPoints
                    delegate: Rectangle {
                        required property var modelData
                        x: modelData.x * canvasRoot.scaleFactor + canvasRoot.offset.x - width / 2
                        y: modelData.y * canvasRoot.scaleFactor + canvasRoot.offset.y - height / 2
                        width: 14
                        height: 14
                        radius: 7
                        color: Appearance.colors.colPrimary
                        border.width: 1.5
                        border.color: Appearance.colors.colOnPrimary
                        z: 10

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "link"
                            iconSize: 9
                            color: Appearance.colors.colOnPrimary
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
                Layout.preferredWidth: 7
                spacing: 8

                MonitorCanvas {
                    id: monitorCanvas
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    monitorConfig: monitorConfig
                }
            }

            // Right panel
            ColumnLayout {
                id: rightPanelLayout
                Layout.fillWidth: true
                Layout.preferredWidth: 3
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
                    Layout.fillWidth: true
                    buttonIcon: "tv_off"
                    text: Translation.tr("Enabled")
                    checked: !(monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex] && monitorConfig.monitors[monitorCanvas.selectedIndex].disabled)
                    onCheckedChanged: {
                        if (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) {
                            let currentVal = !monitorConfig.monitors[monitorCanvas.selectedIndex].disabled;
                            if (checked !== currentVal) {
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
            spacing: 12

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "swap_horiz"
                text: Translation.tr("Position X")
                value: (monitorConfig.monitors && monitorConfig.monitors[monitorCanvas.selectedIndex]) ? (monitorConfig.monitors[monitorCanvas.selectedIndex].x || 0) : 0
                from: 0
                to: 7680
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
                to: 4320
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
            text: Translation.tr("SDR Saturation") + ` (${(value || 1.0).toFixed(2)})`
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

    // ── 4. Profiles ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "display_settings"
        title: Translation.tr("Profiles")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            Repeater {
                model: monitorConfig.profiles
                delegate: MonitorProfileCard {
                    profileName: modelData.name
                    isActive: modelData.isActive
                    onApplyClicked: {
                        monitorConfig.applyProfile(modelData.name);
                        Quickshell.execDetached(["notify-send", "Monitors", Translation.tr(`Profile '${modelData.name}' applied!`)]);
                    }
                    onDeleteClicked: {
                        monitorConfig.deleteProfile(modelData.name);
                        Quickshell.execDetached(["notify-send", "Monitors", Translation.tr(`Profile '${modelData.name}' deleted!`)]);
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
}
