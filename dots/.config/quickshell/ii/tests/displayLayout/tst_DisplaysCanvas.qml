import QtQuick
import QtTest
import qs.modules.common.models.hyprland

Item {
    id: root
    width: 900
    height: 900

    Loader {
        id: pageLoader
        anchors.fill: parent
    }

    TestCase {
        name: "DisplaysCanvasInteraction"
        when: windowShown

        function findByObjectName(item, name) {
            if (!item)
                return null;
            if (item.objectName === name)
                return item;
            const children = item.children || [];
            for (let i = 0; i < children.length; ++i) {
                const hit = findByObjectName(children[i], name);
                if (hit)
                    return hit;
            }
            if (item.contentItem) {
                const hit = findByObjectName(item.contentItem, name);
                if (hit)
                    return hit;
            }
            return null;
        }

        function sampleMonitors() {
            return [
                {
                    name: "eDP-1",
                    description: "Built-in Display",
                    width: 1920,
                    height: 1080,
                    refreshRate: 144,
                    x: 0,
                    y: 0,
                    scale: 1,
                    transform: 0,
                    disabled: false,
                    availableModes: ["1920x1080@144.00Hz"],
                    currentMode: "1920x1080@144.00Hz",
                    mirrorOf: "none",
                    bitDepth: 8,
                    colorManagementPreset: "srgb",
                    sdrBrightness: 1.0,
                    sdrSaturation: 1.0,
                    vrr: 0
                },
                {
                    name: "HDMI-A-1",
                    description: "External Monitor",
                    width: 1920,
                    height: 1080,
                    refreshRate: 60,
                    x: 1920,
                    y: 0,
                    scale: 1,
                    transform: 0,
                    disabled: false,
                    availableModes: ["1920x1080@60.00Hz"],
                    currentMode: "1920x1080@60.00Hz",
                    mirrorOf: "none",
                    bitDepth: 8,
                    colorManagementPreset: "srgb",
                    sdrBrightness: 1.0,
                    sdrSaturation: 1.0,
                    vrr: 0
                }
            ];
        }

        function init() {
            pageLoader.source = "";
            wait(20);
            pageLoader.source = "DisplaysConfig.qml";
            tryVerify(() => pageLoader.item !== null, 2000);
            const cfg = pageLoader.item.children[0];
            // Locate MonitorConfigOption on the page
            const canvas = findByObjectName(pageLoader.item, "monitorCanvas");
            verify(canvas !== null);
            canvas.monitorConfig.monitors = sampleMonitors();
            wait(60);
        }

        function test_01_drag_side_by_side_monitor_above_and_below() {
            const canvas = findByObjectName(pageLoader.item, "monitorCanvas");
            verify(canvas !== null);
            verify(canvas.width > 300);

            const rect0 = findByObjectName(canvas, "monitorRect_0");
            const rect1 = findByObjectName(canvas, "monitorRect_1");
            const ghost = findByObjectName(canvas, "snapGhost");
            verify(rect0 !== null);
            verify(rect1 !== null);
            verify(ghost !== null);

            const idleScale = canvas.scaleFactor;
            compare(canvas.latchedHeight, 250);

            // Start drag from center of rect1 (monitor 1 at right)
            const startX = rect1.x + rect1.width / 2;
            const startY = rect1.y + rect1.height / 2;
            mousePress(canvas, startX, startY, Qt.LeftButton);
            mouseMove(canvas, startX - 15, startY - 15);
            tryVerify(() => canvas.draggingActive, 500);

            // Wait for zoom-out animation to settle
            wait(240);
            verify(canvas.scaleFactor < idleScale);

            // Now move straight above monitor 0 (centered over stationary monitor 0, upper region of canvas)
            const targetAboveX = rect0.x + rect0.width / 2;
            const targetAboveY = Math.max(24, rect0.y - rect0.height * 0.65);
            mouseMove(canvas, targetAboveX, targetAboveY);
            wait(50);

            verify(ghost.visible);
            verify(ghost.y < rect0.y);

            mouseRelease(canvas, targetAboveX, targetAboveY, Qt.LeftButton);
            wait(260);

            verify(!canvas.draggingActive);
            const monsAfterAbove = canvas.monitorConfig.monitors;
            compare(monsAfterAbove[1].x, 0);
            compare(monsAfterAbove[1].y, 0);
            compare(monsAfterAbove[0].x, 0);
            compare(monsAfterAbove[0].y, 1080);

            // Canvas adapts taller for vertical arrangement
            verify(canvas.latchedHeight >= 300);

            // Now drag top monitor (rect1, now at y=0) below rect0 (at y=1080)
            const topStartX = rect1.x + rect1.width / 2;
            const topStartY = rect1.y + rect1.height / 2;
            mousePress(canvas, topStartX, topStartY, Qt.LeftButton);
            mouseMove(canvas, topStartX, topStartY + 15);
            tryVerify(() => canvas.draggingActive, 500);
            wait(240);

            const targetBelowX = rect0.x + rect0.width / 2;
            const targetBelowY = Math.min(canvas.height - 24, rect0.y + rect0.height * 1.65);
            mouseMove(canvas, targetBelowX, targetBelowY);
            wait(50);

            verify(ghost.visible);
            verify(ghost.y > rect0.y);

            mouseRelease(canvas, targetBelowX, targetBelowY, Qt.LeftButton);
            wait(260);

            const monsAfterBelow = canvas.monitorConfig.monitors;
            compare(monsAfterBelow[1].x, monsAfterBelow[0].x);
            compare(monsAfterBelow[1].y, monsAfterBelow[0].y + 1080);
        }

        function test_02_zoom_toolbar_controls() {
            const canvas = findByObjectName(pageLoader.item, "monitorCanvas");
            const zoomOut = findByObjectName(canvas, "zoomOutBtn");
            const zoomReset = findByObjectName(canvas, "zoomResetBtn");
            const zoomIn = findByObjectName(canvas, "zoomInBtn");
            verify(zoomOut !== null);
            verify(zoomReset !== null);
            verify(zoomIn !== null);

            const baseScale = canvas.scaleFactor;
            mouseClick(zoomOut);
            wait(220);
            verify(canvas.userZoom < 0.9);
            verify(canvas.scaleFactor < baseScale);

            mouseClick(zoomReset);
            wait(220);
            compare(canvas.userZoom, 1.0);

            mouseClick(zoomIn);
            wait(220);
            verify(canvas.userZoom > 1.1);
            verify(canvas.scaleFactor > baseScale);
        }
    }
}
