pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    readonly property var rawKeybinds: {
        const defaultKeybinds = HyprlandKeybinds.defaultKeybinds.children ?? [];
        const userKeybinds = HyprlandKeybinds.userKeybinds.children ?? [];
        const unbinds = Config.options.cheatsheet.filterUnbinds ? parseUnbinds(userKeybinds) : [];
        return [...(processKeymaps(defaultKeybinds, unbinds) ?? []), ...(processKeymaps(userKeybinds) ?? [])];
    }

    property var flatSections: flattenSections(rawKeybinds)

    function flattenSections(tree) {
        const sections = [];
        if (!tree) return sections;
        for (let i = 0; i < tree.length; i++) {
            const node = tree[i];
            if (node.keybinds && node.keybinds.length > 0) {
                sections.push({
                    name: node.name || "",
                    keybinds: node.keybinds
                });
            }
            if (node.children && node.children.length > 0) {
                const childSections = flattenSections(node.children);
                for (let j = 0; j < childSections.length; j++) {
                    sections.push(childSections[j]);
                }
            }
        }
        return sections;
    }

    property string filter: ''

    function bindMatches(keybind, sectionName) {
        if (root.filter === "") return true;
        let blob = keybind.__searchBlob;
        if (blob === undefined) {
            const modsStr = keybind.mods ? keybind.mods.join(" ") : "";
            blob = `${sectionName} ${modsStr} ${keybind.key} ${keybind.comment}`.toLowerCase();
            keybind.__searchBlob = blob;
        }
        return blob.includes(root.filter.toLowerCase());
    }

    readonly property bool hasMatches: {
        if (root.filter === "") return true;
        for (let i = 0; i < root.flatSections.length; i++) {
            const sec = root.flatSections[i];
            for (let j = 0; j < sec.keybinds.length; j++) {
                if (root.bindMatches(sec.keybinds[j], sec.name)) return true;
            }
        }
        return false;
    }

    readonly property var categoryIcons: ({
            "Window": "select_window",
            "Launcher": "search",
            "Apps": "grid_view",
            "App": "apps",
            "Application": "smart_display",
            "Utilities": "build",
            "Utility": "construction",
            "Shell": "terminal",
            "Screenshot": "screenshot_monitor",
            "Workspace": "view_carousel",
            "Workspaces": "flip_to_front",
            "Monitor": "tv",
            "Media": "music_note",
            "Volume": "volume_up",
            "Audio": "headphones",
            "Backlight": "light_mode",
            "Brightness": "brightness_6",
            "Power": "power_settings_new",
            "Session": "logout",
            "System": "settings",
            "Lock": "lock",
            "Default Keybinds": "keyboard",
            "User Keybinds": "person"
        })

    readonly property var sectionShapes: [
        "Circle",
        "Cookie9Sided",
        "Flower"
    ]

    property var macSymbolMap: ({
            "Ctrl": "",
            "Alt": "",
            "Shift": "",
            "Space": "",
            "Tab": "↹",
            "Equal": "󰇼",
            "Minus": "",
            "Print": "",
            "BackSpace": "󰭜",
            "Delete": "",
            "Return": "",
            "Period": ".",
            "Escape": "⎋"
        })
    property var functionSymbolMap: ({
            "F1": "",
            "F2": "",
            "F3": "",
            "F4": "",
            "F5": "",
            "F6": "",
            "F7": "",
            "F8": "",
            "F9": "",
            "F10": "󱊴",
            "F11": "󱊵",
            "F12": "󱊶"
        })
    property var mouseSymbolMap: ({
            "mouse_up": "󱕐",
            "mouse_down": "󱕑",
            "mouse:272": "L󰍽",
            "mouse:273": "R",
            "Scroll ↑/↓": "󱕒",
            "Page_↑/↓": "⇞/⇟"
        })
    property var keyBlacklist: ["Super_L"]
    property var keySubstitutions: {
        const _super = Config.options.cheatsheet.superKey;
        const _mac = Config.options.cheatsheet.useMacSymbol;
        const _fn = Config.options.cheatsheet.useFnSymbol;
        const _mouse = Config.options.cheatsheet.useMouseSymbol;
        return Object.assign({
            "SUPER": "",
            "Super": "",
            "mouse_up": "Scroll ↓",
            "mouse_down": "Scroll ↑",
            "mouse:272": "LMB",
            "mouse:273": "RMB",
            "mouse:275": "MouseBack",
            "Slash": "/",
            "Hash": "#",
            "Return": "Enter"
        }, !!_super ? {
            "SUPER": _super,
            "Super": _super
        } : {}, _mac ? macSymbolMap : {}, _fn ? functionSymbolMap : {}, _mouse ? mouseSymbolMap : {});
    }

    function processKeymaps(categories, unbinds) {
        if (!categories) return [];
        if (!unbinds) unbinds = [];
        return categories.map(cat => {
            const newChildren = (cat.children ?? []).map(section => {
                const keybinds = (section.keybinds ?? []).map(kb => {
                    let mods = [];
                    for (let j = 0; j < kb.mods.length; j++) {
                        mods[j] = keySubstitutions[kb.mods[j]] || kb.mods[j];
                    }
                    for (let i = 0; i < unbinds.length; i++) {
                        let unbindMatch = unbinds[i].mods.length === kb.mods.length;
                        for (let j = 0; j < kb.mods.length; j++) {
                            if (unbinds[i].mods[j] && kb.mods[j] !== unbinds[i].mods[j]) {
                                unbindMatch = false;
                            }
                        }
                        if (unbindMatch && kb.key === unbinds[i].key) {
                            return Config.options.cheatsheet.filterUnbinds ? null : kb;
                        }
                    }
                    if (!Config.options.cheatsheet.splitButtons) {
                        mods = [mods.join(' ')];
                        mods[0] += !keyBlacklist.includes(kb.key) && kb.mods.length ? ' ' : '';
                        mods[0] += !keyBlacklist.includes(kb.key) ? (keySubstitutions[kb.key] || kb.key) : '';
                    }
                    return Object.assign({}, kb, { mods });
                }).filter(kb => kb !== null);

                return Object.assign({}, section, { keybinds });
            });

            const directKeybinds = cat.keybinds ?? [];
            if (directKeybinds.length > 0) {
                const autoSection = {
                    name: cat.name || "Keybinds",
                    keybinds: directKeybinds.map(kb => {
                        let mods = kb.mods ? kb.mods.map(m => keySubstitutions[m] || m) : [];
                        return Object.assign({}, kb, { mods });
                    }),
                    children: [],
                    unbinds: []
                };
                newChildren.unshift(autoSection);
            }

            return Object.assign({}, cat, { children: newChildren });
        });
    }

    function parseUnbinds(cheatsheet) {
        const unbinds = [];
        if (!cheatsheet || !cheatsheet.length) return [];
        function walk(nodes) {
            if (!nodes) return;
            for (let i = 0; i < nodes.length; i++) {
                const node = nodes[i];
                if (node.unbinds) {
                    for (let j = 0; j < node.unbinds.length; j++) {
                        unbinds.push(node.unbinds[j]);
                    }
                }
                if (node.children) walk(node.children);
            }
        }
        walk(cheatsheet);
        return unbinds;
    }

    onFocusChanged: focus => {
        if (focus) filterField.forceActiveFocus();
    }

    property real cardSpacing: 12
    property real cardPadding: 12
    property real cardInnerSpacing: 6
    property real cardBindSpacing: 2

    readonly property int numColumns: 4
    readonly property real cardWidth: (contentArea.width - cardSpacing * (numColumns - 1)) / numColumns

    // --- ListModel for live reordering without delegate recreation ---
    ListModel {
        id: sectionOrderModel
    }

    function getSectionData(flatIndex) {
        if (flatIndex >= 0 && flatIndex < root.flatSections.length) {
            return root.flatSections[flatIndex];
        }
        return { name: "", keybinds: [] };
    }

    function rebuildModel() {
        sectionOrderModel.clear();
        if (!root.flatSections || root.flatSections.length === 0) return;

        const savedOrder = Persistent.states.cheatsheet.sectionOrder;
        const used = new Set(); // tracks flatIndices already added

        // First pass: add sections in saved order
        for (let s = 0; s < savedOrder.length; s++) {
            const savedName = savedOrder[s];
            for (let i = 0; i < root.flatSections.length; i++) {
                if (!used.has(i) && root.flatSections[i].name === savedName) {
                    var uid = i + "|" + root.flatSections[i].name;
                    sectionOrderModel.append({
                        name: root.flatSections[i].name,
                        originalIndex: i,
                        uniqueId: uid
                    });
                    used.add(i);
                    break;
                }
            }
        }

        // Second pass: append remaining sections in flatSections order
        for (let i = 0; i < root.flatSections.length; i++) {
            if (!used.has(i)) {
                var uid = i + "|" + root.flatSections[i].name;
                sectionOrderModel.append({
                    name: root.flatSections[i].name,
                    originalIndex: i,
                    uniqueId: uid
                });
            }
        }
    }

    onFlatSectionsChanged: Qt.callLater(rebuildModel)
    Component.onCompleted: rebuildModel()

    // --- Drag State ---
    property bool dragging: false
    property string dragUniqueId: ""
    property real dragStartX: 0
    property real dragStartY: 0

    // Animated drag offset (used by transform)
    property real dragOffsetX: 0
    property real dragOffsetY: 0

    // Snap-back animations for "no valid target" (elastic bounce)
    NumberAnimation {
        id: snapBackX
        target: root
        property: "dragOffsetX"
        to: 0
        duration: 350
        easing.type: Easing.OutBack
        easing.overshoot: 1.5
        onStopped: root.finishDrag()
    }
    NumberAnimation {
        id: snapBackY
        target: root
        property: "dragOffsetY"
        to: 0
        duration: 350
        easing.type: Easing.OutBack
        easing.overshoot: 1.5
    }

    // Success snap animations for "reordered" (smooth emphasized)
    NumberAnimation {
        id: successSnapX
        target: root
        property: "dragOffsetX"
        to: 0
        duration: 250
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasized
        onStopped: root.finishDrag()
    }
    NumberAnimation {
        id: successSnapY
        target: root
        property: "dragOffsetY"
        to: 0
        duration: 250
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasized
    }

    // Drag target lock to prevent flicker
    property string dragTargetId: ""
    property bool dragReorderCooldown: false
    property bool dragHadReorder: false

    function findModelIndexByUniqueId(uid) {
        for (var i = 0; i < sectionOrderModel.count; i++) {
            if (sectionOrderModel.get(i).uniqueId === uid) return i;
        }
        return -1;
    }

    function reorderSectionsInModel(fromIndex, toIndex) {
        if (fromIndex < 0 || toIndex < 0 || fromIndex === toIndex) return;
        if (fromIndex >= sectionOrderModel.count || toIndex >= sectionOrderModel.count) return;
        sectionOrderModel.move(fromIndex, toIndex, 1);
        contentArea.layoutRevision = contentArea.layoutRevision + 1;
    }

    function finishDrag() {
        root.dragging = false;
        root.dragUniqueId = "";
        root.dragTargetId = "";
        root.dragReorderCooldown = false;
        root.dragHadReorder = false;
        root.dragOffsetX = 0;
        root.dragOffsetY = 0;
        // Save order to Persistent
        var order = [];
        for (var i = 0; i < sectionOrderModel.count; i++) {
            order.push(sectionOrderModel.get(i).name);
        }
        Persistent.states.cheatsheet.sectionOrder = order;
    }

    Timer {
        id: reorderCooldownTimer
        interval: 500
        repeat: false
        onTriggered: root.dragReorderCooldown = false
    }

    Item {
        id: contentArea
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true

        property int layoutRevision: 0

        function getColumnIndex(targetIndex) {
            var h = [0, 0, 0, 0];
            var count = 0;
            var maxH = contentArea.height > 0 ? contentArea.height : 99999;
            for (var i = 0; i < sectionOrderModel.count; i++) {
                var child = cardRepeater.itemAt(i);
                if (!child) continue;
                var childH = child.implicitHeight || 100;
                if (!child.hasMatches) childH = 0;
                if (childH <= 0) continue;

                var minIdx = 0;
                for (var j = 1; j < 4; j++) {
                    if (h[j] < h[minIdx]) minIdx = j;
                }

                if (h[minIdx] + childH + root.cardSpacing > maxH) {
                    var bestIdx = minIdx;
                    var bestH = h[minIdx];
                    var found = false;
                    for (var j = 0; j < 4; j++) {
                        if (h[j] + childH + root.cardSpacing <= maxH && h[j] < bestH) {
                            bestH = h[j];
                            bestIdx = j;
                            found = true;
                        }
                    }
                    if (found) minIdx = bestIdx;
                }

                if (count === targetIndex) return minIdx;
                h[minIdx] += childH + root.cardSpacing;
                count++;
            }
            return 0;
        }

        function getY(targetIndex) {
            var h = [0, 0, 0, 0];
            var count = 0;
            var maxH = contentArea.height > 0 ? contentArea.height : 99999;
            for (var i = 0; i < sectionOrderModel.count; i++) {
                var child = cardRepeater.itemAt(i);
                if (!child) continue;
                var childH = child.implicitHeight || 100;
                if (!child.hasMatches) childH = 0;
                if (childH <= 0) continue;

                var minIdx = 0;
                for (var j = 1; j < 4; j++) {
                    if (h[j] < h[minIdx]) minIdx = j;
                }

                if (h[minIdx] + childH + root.cardSpacing > maxH) {
                    var bestIdx = minIdx;
                    var bestH = h[minIdx];
                    var found = false;
                    for (var j = 0; j < 4; j++) {
                        if (h[j] + childH + root.cardSpacing <= maxH && h[j] < bestH) {
                            bestH = h[j];
                            bestIdx = j;
                            found = true;
                        }
                    }
                    if (found) minIdx = bestIdx;
                }

                if (count === targetIndex) return h[minIdx];
                h[minIdx] += childH + root.cardSpacing;
                count++;
            }
            return 0;
        }

        Repeater {
            id: cardRepeater
            model: sectionOrderModel

            delegate: CheatsheetKeybindsCategory {
                id: cardDelegate
                required property string name
                required property int originalIndex
                required property int index
                required property string uniqueId

                sectionData: root.getSectionData(originalIndex)
                sectionIndex: originalIndex
                cheatsheetRoot: root
                cardWidth: root.cardWidth

                readonly property bool isDragged: root.dragging && uniqueId === root.dragUniqueId

                readonly property int _col: {
                    var _rev = contentArea.layoutRevision;
                    return contentArea.getColumnIndex(index);
                }
                readonly property real _yPos: {
                    var _rev = contentArea.layoutRevision;
                    return contentArea.getY(index);
                }

                x: _col * (root.cardWidth + root.cardSpacing)
                y: _yPos

                transform: Translate {
                    x: cardDelegate.isDragged ? root.dragOffsetX : 0
                    y: cardDelegate.isDragged ? root.dragOffsetY : 0
                }

                Behavior on x {
                    enabled: !cardDelegate.isDragged
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }
                Behavior on y {
                    enabled: !cardDelegate.isDragged
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                scale: isDragged ? 1.04 : 1.0
                opacity: isDragged ? 0.85 : 1.0
                z: isDragged ? 100 : 0

                Behavior on scale {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                onImplicitHeightChanged: layoutTimer.restart()
                onHasMatchesChanged: layoutTimer.restart()

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: root.dragging && cardDelegate.uniqueId === root.dragUniqueId ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                    onPressed: event => {
                        if (root.filter !== "") return;
                        var absPos = contentArea.mapFromItem(dragArea, event.x, event.y);
                        root.dragStartX = absPos.x;
                        root.dragStartY = absPos.y;
                        root.dragOffsetX = 0;
                        root.dragOffsetY = 0;
                        root.dragUniqueId = cardDelegate.uniqueId;
                        root.dragTargetId = "";
                        root.dragReorderCooldown = false;
                        root.dragHadReorder = false;
                    }

                    onPositionChanged: event => {
                        if (!pressed) return;
                        var absPos = contentArea.mapFromItem(dragArea, event.x, event.y);
                        var dx = absPos.x - root.dragStartX;
                        var dy = absPos.y - root.dragStartY;

                        if (!root.dragging && (Math.abs(dx) > 5 || Math.abs(dy) > 5)) {
                            root.dragging = true;
                        }

                        if (root.dragging) {
                            root.dragOffsetX = dx;
                            root.dragOffsetY = dy;

                            var myModelIndex = root.findModelIndexByUniqueId(root.dragUniqueId);
                            if (myModelIndex < 0) return;

                            // Check if we left the current locked target
                            if (root.dragTargetId !== "") {
                                var stillInside = false;
                                for (var k = 0; k < cardRepeater.count; k++) {
                                    var t = cardRepeater.itemAt(k);
                                    if (t && t.uniqueId === root.dragTargetId && t.visible) {
                                        var tGlobal = t.mapToItem(contentArea, 0, 0);
                                        var margin = 60;
                                        if (absPos.x >= tGlobal.x - margin && absPos.x < tGlobal.x + t.width + margin &&
                                            absPos.y >= tGlobal.y - margin && absPos.y < tGlobal.y + t.height + margin) {
                                            stillInside = true;
                                        }
                                        break;
                                    }
                                }
                                if (stillInside) {
                                    return;
                                } else {
                                    root.dragTargetId = "";
                                }
                            }

                            if (root.dragReorderCooldown) return;

                            var myOldGlobalPos = cardDelegate.mapToItem(contentArea, 0, 0);

                            // Find closest card by center distance
                            var bestDist = Infinity;
                            var bestIndex = -1;
                            for (var i = 0; i < cardRepeater.count; i++) {
                                var sibling = cardRepeater.itemAt(i);
                                if (!sibling || sibling.uniqueId === root.dragUniqueId || !sibling.visible) continue;
                                var sGlobal = sibling.mapToItem(contentArea, 0, 0);
                                var cx = sGlobal.x + sibling.width / 2;
                                var cy = sGlobal.y + sibling.height / 2;
                                var dist = Math.sqrt((absPos.x - cx) * (absPos.x - cx) + (absPos.y - cy) * (absPos.y - cy));
                                if (dist < bestDist) {
                                    bestDist = dist;
                                    bestIndex = i;
                                }
                            }

                            // Only reorder if very close (180px threshold)
                            if (bestIndex >= 0 && bestDist < 180) {
                                var sibling = cardRepeater.itemAt(bestIndex);
                                if (sibling) {
                                    root.dragTargetId = sibling.uniqueId;
                                    root.dragReorderCooldown = true;
                                    root.dragHadReorder = true;
                                    reorderCooldownTimer.start();

                                    root.reorderSectionsInModel(myModelIndex, bestIndex);

                                    var myNewGlobalPos = cardDelegate.mapToItem(contentArea, 0, 0);
                                    root.dragStartX += myNewGlobalPos.x - myOldGlobalPos.x;
                                    root.dragStartY += myNewGlobalPos.y - myOldGlobalPos.y;
                                }
                            }
                        }
                    }

                    onReleased: event => {
                        if (root.dragging) {
                            if (!root.dragHadReorder) {
                                // Snap back animation (no valid target) — elastic bounce
                                snapBackX.from = root.dragOffsetX;
                                snapBackY.from = root.dragOffsetY;
                                snapBackX.start();
                                snapBackY.start();
                            } else {
                                // Had reorder — smooth snap to new base position
                                successSnapX.from = root.dragOffsetX;
                                successSnapY.from = root.dragOffsetY;
                                successSnapX.start();
                                successSnapY.start();
                            }
                        }
                    }
                }
            }
        }

        Timer {
            id: layoutTimer
            interval: 100
            repeat: false
            onTriggered: contentArea.layoutRevision = contentArea.layoutRevision + 1
        }

        Component.onCompleted: {
            settlingTimer.start();
        }

        Timer {
            id: settlingTimer
            interval: 500
            repeat: false
            onTriggered: contentArea.layoutRevision = contentArea.layoutRevision + 1
        }
    }

    Toolbar {
        id: extraOptions
        z: 2
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 8
        }

        IconToolbarButton {
            implicitWidth: height
            text: Config.options.cheatsheet.filterUnbinds ? "filter_alt" : "filter_alt_off"
            onClicked: Config.options.cheatsheet.filterUnbinds = !Config.options.cheatsheet.filterUnbinds
            StyledToolTip {
                text: Translation.tr("Toggle filter on system shortcuts unbind by the user")
            }
        }

        ToolbarTextField {
            id: filterField
            placeholderText: focus ? Translation.tr("Filter shortcuts") : Translation.tr("Hit \"/\" to filter")
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            onTextChanged: root.filter = text;
        }

        IconToolbarButton {
            implicitWidth: height
            onClicked: root.filter = filterField.text = '';
            text: "close"
            StyledToolTip {
                text: Translation.tr("Clear filter")
            }
        }
    }

    PagePlaceholder {
        shown: !root.hasMatches && root.filter !== ''
        icon: "search_off"
        description: Translation.tr("No results")
        shape: MaterialShape.Shape.Ghostish
        descriptionHorizontalAlignment: Text.AlignHCenter
        anchors.centerIn: parent
    }
}
