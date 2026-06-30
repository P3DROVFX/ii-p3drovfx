pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property string searchQuery: ""

    readonly property int panelWidth: 560
    readonly property int gridColumns: 4
    readonly property int cellSize: 123
    readonly property int maxItems: 100

    implicitWidth: panelWidth
    implicitHeight: 520

    property int focusedControlIndex: -1
    property var allIcons: []
    property var filteredIcons: []
    property bool dataLoaded: false

    property color colItemBg: Appearance.colors.colSurfaceContainerHigh
    property color colItemBgHover: Appearance.colors.colSurfaceContainerHighest
    property color colItemSelected: Appearance.colors.colPrimaryContainer
    property color colText: Appearance.colors.colOnSurface
    property color colSubtext: Appearance.colors.colSubtext
    property color colTagText: Appearance.colors.colOnSurfaceVariant

    readonly property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    readonly property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    readonly property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

    readonly property int cellWidth: Math.floor(gridFlickable.width / root.gridColumns)
    readonly property int cellHeight: root.cellSize + 8
    readonly property int gridSpacing: 0

    function loadData() {
        symbolsFileView.reload();
    }

    function filterIcons() {
        if (!dataLoaded || allIcons.length === 0) {
            filteredIcons = [];
            return;
        }

        const query = root.searchQuery.trim().toLowerCase();
        if (query.length === 0) {
            filteredIcons = allIcons.slice(0, maxItems);
            return;
        }

        const queryTerms = query.split(/\s+/).filter(t => t.length > 0);
        const scored = [];

        for (let i = 0; i < allIcons.length; i++) {
            const icon = allIcons[i];
            const name = icon.n.toLowerCase();
            const tags = icon.t;
            const categories = icon.c;

            let score = 0;
            let allTermsMatch = true;

            for (let t = 0; t < queryTerms.length; t++) {
                const term = queryTerms[t];
                let termMatched = false;

                if (name === term) {
                    score += 100;
                    termMatched = true;
                } else if (name.startsWith(term)) {
                    score += 50;
                    termMatched = true;
                } else if (name.includes(term)) {
                    score += 25;
                    termMatched = true;
                }

                if (!termMatched) {
                    for (let j = 0; j < tags.length; j++) {
                        const tag = tags[j].toLowerCase();
                        if (tag === term) {
                            score += 30;
                            termMatched = true;
                            break;
                        } else if (tag.startsWith(term)) {
                            score += 15;
                            termMatched = true;
                            break;
                        } else if (tag.includes(term)) {
                            score += 8;
                            termMatched = true;
                            break;
                        }
                    }
                }

                if (!termMatched) {
                    for (let j = 0; j < categories.length; j++) {
                        const cat = categories[j].toLowerCase();
                        if (cat.includes(term)) {
                            score += 5;
                            termMatched = true;
                            break;
                        }
                    }
                }

                if (!termMatched) {
                    allTermsMatch = false;
                    break;
                }
            }

            if (allTermsMatch && score > 0) {
                score += (icon.p || 0) / 10000;
                scored.push({ icon: icon, score: score });
            }
        }

        scored.sort((a, b) => b.score - a.score);
        filteredIcons = scored.slice(0, maxItems).map(s => s.icon);
    }

    function navigateUp() {
        if (filteredIcons.length === 0) return;
        const cols = root.gridColumns;
        if (focusedControlIndex < 0) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex >= cols) {
            focusedControlIndex -= cols;
        } else {
            focusedControlIndex = -1;
            root.requestFocusSearchInput();
        }
        ensureVisible();
    }

    function navigateDown() {
        if (filteredIcons.length === 0) return;
        const cols = root.gridColumns;
        if (focusedControlIndex < 0) {
            focusedControlIndex = 0;
        } else {
            const next = focusedControlIndex + cols;
            if (next < filteredIcons.length) {
                focusedControlIndex = next;
            }
        }
        ensureVisible();
    }

    function navigateLeft() {
        if (filteredIcons.length === 0) return;
        if (focusedControlIndex < 0) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex > 0) {
            focusedControlIndex--;
        }
        ensureVisible();
    }

    function navigateRight() {
        if (filteredIcons.length === 0) return;
        if (focusedControlIndex < 0) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex < filteredIcons.length - 1) {
            focusedControlIndex++;
        }
        ensureVisible();
    }

    function activateSelected() {
        if (focusedControlIndex >= 0 && focusedControlIndex < filteredIcons.length) {
            copyIconName(filteredIcons[focusedControlIndex].n);
        } else if (filteredIcons.length > 0) {
            copyIconName(filteredIcons[0].n);
        }
        GlobalStates.overviewOpen = false;
    }

    function focusInput() {
        focusedControlIndex = -1;
        root.requestFocusSearchInput();
    }

    function ensureVisible() {
        if (focusedControlIndex < 0) return;
        const cols = root.gridColumns;
        const row = Math.floor(focusedControlIndex / cols);
        const itemTop = row * root.cellHeight;
        const itemBottom = itemTop + root.cellSize;
        const viewTop = gridFlickable.contentY;
        const viewBottom = viewTop + gridFlickable.height;

        if (itemTop < viewTop) {
            gridFlickable.contentY = itemTop - 8;
        } else if (itemBottom > viewBottom) {
            gridFlickable.contentY = itemBottom - gridFlickable.height + 8;
        }
    }

    function copyIconName(name) {
        Quickshell.clipboardText = name;
        copyFeedbackIcon = name;
        copyFeedbackTimer.restart();
    }

    function copyIconSvg(iconData) {
        if (!iconData) return;
        const cp = iconData.cp;
        const hex = cp.toString(16).toUpperCase();
        const name = iconData.n;
        const svg = `<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><text x="480" y="0" font-family="Material Symbols Rounded" font-size="960" text-anchor="middle" dominant-baseline="central" fill="black">&#x${hex};</text></svg>`;
        Quickshell.clipboardText = svg;
        copyFeedbackIcon = name;
        copyFeedbackTimer.restart();
    }

    function copyFocusedIconSvg() {
        if (focusedControlIndex >= 0 && focusedControlIndex < filteredIcons.length) {
            copyIconSvg(filteredIcons[focusedControlIndex]);
        } else if (filteredIcons.length > 0) {
            copyIconSvg(filteredIcons[0]);
        }
        GlobalStates.overviewOpen = false;
    }

    function recalculateLayout() {
        const cols = root.gridColumns;
        const cw = root.cellWidth;
        const ch = root.cellHeight;
        var visibleIndex = 0;
        for (var i = 0; i < iconRepeater.count; i++) {
            var item = iconRepeater.itemAt(i);
            if (!item) continue;
            if (item.hasData) {
                var col = visibleIndex % cols;
                var row = Math.floor(visibleIndex / cols);
                item.x = col * cw;
                item.y = row * ch;
                visibleIndex++;
            }
        }
        var totalRows = Math.ceil(visibleIndex / cols);
        contentContainer.height = Math.max(0, totalRows * ch);
    }

    function recountVisible() {
        var count = 0;
        for (var i = 0; i < iconRepeater.count; i++) {
            var item = iconRepeater.itemAt(i);
            if (item && item.hasData) count++;
        }
        return count;
    }

    property string copyFeedbackIcon: ""

    signal requestFocusSearchInput()

    onSearchQueryChanged: {
        root.filterIcons();
        focusedControlIndex = -1;
    }

    onFilteredIconsChanged: {
        gridArea.triggerLayout();
    }

    Timer {
        id: copyFeedbackTimer
        interval: 1500
        repeat: false
    }

    FileView {
        id: symbolsFileView
        path: Directories.assetsPath + "/data/material_symbols.json"
        onLoadedChanged: {
            if (loaded) {
                try {
                    const content = text();
                    allIcons = JSON.parse(content);
                    dataLoaded = true;
                    root.filterIcons();
                } catch (e) {
                    console.warn("[MaterialSymbolsPanel] Failed to parse data:", e);
                }
            }
        }
    }

    Component.onCompleted: {
        root.loadData();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.colSurfaceContainer

            Flickable {
                id: gridFlickable
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                contentHeight: contentContainer.height
                contentWidth: width

                maximumFlickVelocity: 3500
                boundsBehavior: Flickable.DragOverBounds
                pixelAligned: true
                property real scrollTargetY: 0

                Behavior on contentY {
                    NumberAnimation {
                        id: scrollAnim
                        alwaysRunToEnd: true
                        duration: Appearance.animation.scroll.duration
                        easing.type: Appearance.animation.scroll.type
                        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                    }
                }

                onContentYChanged: {
                    if (!scrollAnim.running) {
                        gridFlickable.scrollTargetY = gridFlickable.contentY;
                    }
                }

                MouseArea {
                    z: 99
                    visible: Config?.options.interactions.scrolling.fasterTouchpadScroll
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: function(wheelEvent) {
                        const delta = wheelEvent.angleDelta.y / root.mouseScrollDeltaThreshold;
                        var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;
                        const maxY = Math.max(0, gridFlickable.contentHeight - gridFlickable.height);
                        const base = scrollAnim.running ? gridFlickable.scrollTargetY : gridFlickable.contentY;
                        var targetY = Math.max(0, Math.min(base - delta * scrollFactor, maxY));
                        gridFlickable.scrollTargetY = targetY;
                        gridFlickable.contentY = targetY;
                        wheelEvent.accepted = true;
                    }
                }

                layer.enabled: root.filteredIcons.length > 0
                layer.effect: OpacityMask {
                    maskSource: Item {
                        id: maskRoot
                        width: gridFlickable.width
                        height: gridFlickable.height

                        property color topFadeColor: gridFlickable.atYBeginning ? "white" : "transparent"
                        property color bottomFadeColor: gridFlickable.atYEnd ? "white" : "transparent"

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

                Item {
                    id: gridArea
                    width: gridFlickable.width
                    implicitHeight: contentContainer.height

                    function triggerLayout() {
                        layoutTimer.restart();
                    }

                    Timer {
                        id: layoutTimer
                        interval: 20
                        repeat: false
                        onTriggered: gridArea.recalculateLayout()
                    }

                    function recalculateLayout() {
                        const cols = root.gridColumns;
                        const cw = root.cellWidth;
                        const ch = root.cellHeight;
                        var visibleIndex = 0;
                        for (var i = 0; i < iconRepeater.count; i++) {
                            var item = iconRepeater.itemAt(i);
                            if (!item) continue;
                            if (item.hasData) {
                                var col = visibleIndex % cols;
                                var row = Math.floor(visibleIndex / cols);
                                item.x = col * cw;
                                item.y = row * ch;
                                visibleIndex++;
                            }
                        }
                        var totalRows = Math.ceil(visibleIndex / cols);
                        contentContainer.height = Math.max(0, totalRows * ch);
                    }

                    Item {
                        id: contentContainer
                        width: gridArea.width
                        height: 0

                        Repeater {
                            id: iconRepeater
                            model: root.maxItems

                            delegate: Item {
                                id: delegateItem
                                required property int index

                                property var iconData: index < root.filteredIcons.length ? root.filteredIcons[index] : null
                                property bool hasData: iconData !== null

                                readonly property bool isFocused: root.focusedControlIndex === index && hasData
                                readonly property bool isHovered: iconMouseArea.containsMouse

                                width: root.cellWidth
                                height: hasData ? root.cellHeight : 0
                                opacity: hasData ? 1.0 : 0.0
                                visible: hasData || opacity > 0.01
                                clip: true

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 220
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Appearance.animationCurves.emphasized
                                    }
                                }
                                Behavior on y {
                                    NumberAnimation {
                                        duration: 220
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Appearance.animationCurves.emphasized
                                    }
                                }
                                Behavior on height {
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

                                onImplicitHeightChanged: gridArea.triggerLayout()
                                onVisibleChanged: gridArea.triggerLayout()
                                onHasDataChanged: gridArea.triggerLayout()

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: root.cellSize
                                    height: root.cellSize
                                    radius: Appearance.rounding.normal
                                    color: delegateItem.isFocused ? root.colItemSelected :
                                           (delegateItem.isHovered ? root.colItemBgHover : root.colItemBg)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.animation.elementMoveFast.duration
                                            easing.type: Easing.OutQuad
                                        }
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 2

                                        MaterialSymbol {
                                            text: delegateItem.iconData ? delegateItem.iconData.n : ""
                                            iconSize: 28
                                            color: root.colText
                                            fill: delegateItem.isFocused ? 1.0 : 0.0
                                            Layout.alignment: Qt.AlignHCenter
                                            horizontalAlignment: Text.AlignHCenter
                                        }

                                        StyledText {
                                            text: delegateItem.iconData ? delegateItem.iconData.n : ""
                                            color: root.colText
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            Layout.fillWidth: true
                                            maximumLineCount: 1
                                        }

                                        StyledText {
                                            text: {
                                                if (!delegateItem.iconData) return "";
                                                const tags = delegateItem.iconData.t;
                                                if (!tags || tags.length === 0) return "";
                                                const display = tags.slice(0, 3).join(", ");
                                                return tags.length > 3 ? display + "..." : display;
                                            }
                                            color: root.colTagText
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            Layout.fillWidth: true
                                            maximumLineCount: 1
                                            opacity: 0.7
                                        }
                                    }

                                    RippleButton {
                                        anchors.fill: parent
                                        buttonRadius: Appearance.rounding.normal
                                        colBackground: "transparent"
                                        enabled: delegateItem.hasData
                                        id: iconMouseArea

                                        onClicked: {
                                            root.focusedControlIndex = delegateItem.index;
                                            root.copyIconName(delegateItem.iconData.n);
                                            GlobalStates.overviewOpen = false;
                                        }

                                        Keys.onPressed: event => {
                                            if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                                                root.copyIconSvg(delegateItem.iconData);
                                                event.accepted = true;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.centerIn: parent
                visible: root.filteredIcons.length === 0 && root.dataLoaded && root.searchQuery.trim().length > 0
                implicitWidth: noResultsColumn.implicitWidth
                implicitHeight: noResultsColumn.implicitHeight

                ColumnLayout {
                    id: noResultsColumn
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: "search_off"
                        iconSize: 48
                        color: Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignHCenter
                        opacity: 0.5
                    }

                    StyledText {
                        text: Translation.tr("No symbols found")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }

        StyledText {
            text: Translation.tr("Enter to copy name • Ctrl+S to copy SVG • Search by tag, name or category")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
            opacity: 0.6
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
