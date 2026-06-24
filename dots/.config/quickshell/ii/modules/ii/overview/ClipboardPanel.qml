pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
    property string clipboardPrefix: Config.options.search.prefix.clipboard

    readonly property int panelWidth: Config.options.search.clipboard.panelWidth
    readonly property real listColumnRatio: Config.options.search.clipboard.listColumnRatio
    readonly property int listColumnWidth: Math.round(panelWidth * listColumnRatio)
    readonly property int detailColumnWidth: panelWidth - listColumnWidth

    implicitWidth: panelWidth
    implicitHeight: Math.min(560, Math.max(320, entryListView.contentHeight + 40))
    property var filteredEntries: {
        const q = root.searchQuery;
        const allEntries = Cliphist.entries;
        const pinned = Cliphist.pinnedEntries;

        let pinnedFiltered = [];
        for (let i = 0; i < pinned.length; i++) {
            const e = pinned[i];
            if (q === "" || e.toLowerCase().includes(q.toLowerCase()))
                pinnedFiltered.push(e);
        }

        let regularFiltered = [];
        if (q === "") {
            for (let i = 0; i < allEntries.length; i++) {
                if (!Cliphist.isPinned(allEntries[i]))
                    regularFiltered.push(allEntries[i]);
            }
        } else {
            const fuzzy = Cliphist.fuzzyQuery(q);
            for (let i = 0; i < fuzzy.length; i++) {
                if (!Cliphist.isPinned(fuzzy[i]))
                    regularFiltered.push(fuzzy[i]);
            }
        }

        return pinnedFiltered.concat(regularFiltered);
    }

    property int selectedIndex: 0
    property int selectedActionIndex: -1
    property string selectedEntry: filteredEntries.length > 0 ? filteredEntries[Math.min(selectedIndex, filteredEntries.length - 1)] : ""

    readonly property bool hasSmartAction: {
        if (selectedIsImage)
            return true;
        if (!selectedContentType)
            return false;
        return selectedContentType === "filepath" || selectedContentType === "url" || selectedContentType === "email" || selectedContentType === "phone" || selectedContentType === "json" || selectedContentType === "markdown" || selectedContentType === "number";
    }

    readonly property int copyIndex: 0
    readonly property int pasteIndex: 1
    readonly property int smartIndex: hasSmartAction ? 2 : -2
    readonly property int pinIndex: hasSmartAction ? 3 : 2
    readonly property int deleteIndex: hasSmartAction ? 4 : 3

    function selectFirstRegular() {
        let firstRegularIndex = 0;
        for (let i = 0; i < filteredEntries.length; i++) {
            if (!Cliphist.isPinned(filteredEntries[i])) {
                firstRegularIndex = i;
                break;
            }
        }
        let targetIndex = Math.min(firstRegularIndex, filteredEntries.length > 0 ? filteredEntries.length - 1 : 0);
        if (selectedIndex === targetIndex) {
            // Index didn't change, trigger startDecoding manually since onSelectedEntryChanged won't fire
            startDecoding(selectedEntry);
        } else {
            selectedIndex = targetIndex;
        }
        if (entryListView) {
            entryListView.currentIndex = selectedIndex;
            entryListView.positionViewAtIndex(selectedIndex, ListView.Contain);
        }
    }

    Timer {
        id: selectTimer
        interval: 50
        repeat: false
        onTriggered: selectFirstRegular()
    }

    onFilteredEntriesChanged: {
        selectTimer.restart();
    }

    Component.onCompleted: {
        selectTimer.restart();
    }

    property string selectedDecodedContent: ""

    Process {
        id: decodeProc
        property var buffer: []
        property string targetEntry: ""

        command: ["bash", "-c", ""]

        stdout: SplitParser {
            onRead: line => {
                decodeProc.buffer.push(line);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && targetEntry === root.selectedEntry) {
                root.selectedDecodedContent = decodeProc.buffer.join("\n");
            }
        }
    }

    function startDecoding(entry) {
        decodeProc.running = false;
        decodeProc.buffer = [];
        decodeProc.targetEntry = entry;

        if (!entry) {
            root.selectedDecodedContent = "";
            return;
        }

        const isImg = Cliphist.entryIsImage(entry);
        if (isImg) {
            root.selectedDecodedContent = "";
            return;
        }

        // Set fallback first line immediately to avoid blank flashes
        root.selectedDecodedContent = StringUtils.cleanCliphistEntry(entry);

        let cmd = "";
        if (Cliphist.cliphistBinary.includes("cliphist")) {
            cmd = "printf '" + StringUtils.shellSingleQuoteEscape(entry) + "' | " + Cliphist.cliphistBinary + " decode";
        } else {
            const entryNumber = entry.split("\t")[0];
            cmd = Cliphist.cliphistBinary + " decode " + entryNumber;
        }

        decodeProc.command = ["bash", "-c", cmd];
        decodeProc.running = true;
    }

    onSelectedEntryChanged: {
        startDecoding(selectedEntry);
    }

    readonly property string selectedContent: {
        if (!selectedEntry)
            return "";
        return StringUtils.cleanCliphistEntry(selectedEntry);
    }

    readonly property bool selectedIsImage: selectedEntry ? Cliphist.entryIsImage(selectedEntry) : false
    readonly property bool selectedIsPinned: selectedEntry ? Cliphist.isPinned(selectedEntry) : false
    readonly property string selectedContentType: {
        if (!selectedEntry)
            return "";
        const content = selectedContent.trim();
        if (/^#?([0-9A-Fa-f]{3,4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(content))
            return "hex-color";
        return Cliphist.classifyEntry(selectedEntry);
    }

    readonly property string selectedMime: {
        if (selectedIsImage) {
            const match = selectedEntry.match(/\[\[(.+?)\s/);
            return match ? match[1] : "image/*";
        }
        return "text/plain;charset=utf-8";
    }

    readonly property int selectedSize: {
        if (!selectedDecodedContent)
            return 0;
        return selectedDecodedContent.length;
    }

    readonly property string selectedCopiedAt: {
        if (!selectedEntry)
            return "";
        const id = selectedEntry.match(/^(\d+)\t/);
        if (!id)
            return "";
        return "#" + id[1];
    }

    readonly property string selectedMd5: {
        if (!selectedDecodedContent)
            return "";
        return Qt.md5(selectedDecodedContent);
    }

    function formatBytes(bytes) {
        if (bytes < 1024)
            return bytes + " bytes";
        if (bytes < 1048576)
            return (bytes / 1024).toFixed(1) + " KB";
        return (bytes / 1048576).toFixed(1) + " MB";
    }

    function getContrastColor(hexColor) {
        let color = hexColor.trim().replace('#', '');
        if (color.length === 3) {
            color = color[0] + color[0] + color[1] + color[1] + color[2] + color[2];
        }
        if (color.length === 4) {
            color = color[0] + color[0] + color[1] + color[1] + color[2] + color[2];
        }
        if (color.length === 8) {
            color = color.substring(0, 6);
        }
        const r = parseInt(color.substring(0, 2), 16);
        const g = parseInt(color.substring(2, 4), 16);
        const b = parseInt(color.substring(4, 6), 16);
        if (isNaN(r) || isNaN(g) || isNaN(b))
            return Appearance.colors.colOnSurface;
        const yiq = ((r * 299) + (g * 587) + (b * 114)) / 1000;
        return (yiq >= 128) ? "#000000" : "#ffffff";
    }

    function formatColor(colorStr) {
        let c = colorStr.trim();
        if (/^[0-9A-Fa-f]{3,4}$|^[0-9A-Fa-f]{6}$|^[0-9A-Fa-f]{8}$/.test(c)) {
            return "#" + c;
        }
        return c;
    }

    function navigateUp() {
        selectedActionIndex = -1;
        if (selectedIndex > 0) {
            selectedIndex--;
            entryListView.positionViewAtIndex(selectedIndex, ListView.Contain);
        }
    }

    function navigateDown() {
        selectedActionIndex = -1;
        if (selectedIndex < filteredEntries.length - 1) {
            selectedIndex++;
            entryListView.positionViewAtIndex(selectedIndex, ListView.Contain);
        }
    }

    function navigateLeft() {
        if (selectedActionIndex > -1) {
            selectedActionIndex--;
        }
    }

    function navigateRight() {
        const maxIndex = hasSmartAction ? 4 : 3;
        if (selectedActionIndex < maxIndex) {
            selectedActionIndex++;
        }
    }

    function triggerSmartAction() {
        if (!selectedEntry)
            return;
        if (selectedIsImage) {
            const match = selectedEntry.match(/^(\d+)\t/);
            const entryNumber = match ? parseInt(match[1]) : 0;
            const path = Directories.cliphistDecode + "/" + entryNumber;
            Quickshell.execDetached(["bash", "-c", "[ -f '" + path + "' ] || echo '" + StringUtils.shellSingleQuoteEscape(selectedEntry) + "' | " + Cliphist.cliphistBinary + " decode > '" + path + "'; xdg-open '" + path + "'"]);
            GlobalStates.overviewOpen = false;
            return;
        }
        const content = selectedDecodedContent.trim();
        if (selectedContentType === "filepath") {
            Quickshell.execDetached(["xdg-open", content]);
            GlobalStates.overviewOpen = false;
        } else if (selectedContentType === "url") {
            Quickshell.execDetached(["xdg-open", content]);
            GlobalStates.overviewOpen = false;
        } else if (selectedContentType === "email") {
            Quickshell.execDetached(["xdg-open", "mailto:" + content]);
            GlobalStates.overviewOpen = false;
        } else if (selectedContentType === "phone") {
            Quickshell.execDetached(["xdg-open", "tel:" + content]);
            GlobalStates.overviewOpen = false;
        } else if (selectedContentType === "json") {
            try {
                const parsed = JSON.parse(content);
                const formatted = JSON.stringify(parsed, null, 4);
                Quickshell.execDetached(["bash", "-c", "printf '" + StringUtils.shellSingleQuoteEscape(formatted) + "' | wl-copy"]);
                GlobalStates.overviewOpen = false;
            } catch (e) {}
        } else if (selectedContentType === "markdown") {
            // Strip common markdown markup and copy plain text
            let plain = content.replace(/^#{1,6}\s+/gm, "")        // headings
            .replace(/\*\*(.+?)\*\*/g, "$1")    // bold
            .replace(/\*(.+?)\*/g, "$1")         // italic
            .replace(/`{1,3}([^`]+)`{1,3}/g, "$1") // code
            .replace(/^\s*[-*+]\s+/gm, "• ")    // bullets
            .replace(/^\s*>\s*/gm, "")           // blockquotes
            .replace(/\[(.+?)\]\(.+?\)/g, "$1") // links
            .trim();
            Quickshell.clipboardText = plain;
            GlobalStates.overviewOpen = false;
        } else if (selectedContentType === "number") {
            // Copy number stripped of formatting separators (spaces, commas, underscores)
            const bare = content.replace(/[\s,_]/g, "");
            Quickshell.clipboardText = bare;
            GlobalStates.overviewOpen = false;
        }
    }

    function activateSelected() {
        if (selectedActionIndex === -1 || selectedActionIndex === copyIndex) {
            if (selectedEntry) {
                Cliphist.copy(selectedEntry);
                GlobalStates.overviewOpen = false;
            }
        } else if (selectedActionIndex === pasteIndex) {
            if (selectedEntry) {
                Cliphist.paste(selectedEntry);
                GlobalStates.overviewOpen = false;
            }
        } else if (selectedActionIndex === smartIndex) {
            triggerSmartAction();
        } else if (selectedActionIndex === pinIndex) {
            if (selectedEntry) {
                if (selectedIsPinned)
                    Cliphist.unpin(selectedEntry);
                else
                    Cliphist.pin(selectedEntry);
            }
        } else if (selectedActionIndex === deleteIndex) {
            if (selectedEntry) {
                Cliphist.deleteEntry(selectedEntry);
                selectedActionIndex = -1;
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            navigateUp();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            navigateDown();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
            navigateLeft();
            event.accepted = true;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
            navigateRight();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activateSelected();
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
            if (selectedEntry) {
                Cliphist.deleteEntry(selectedEntry);
                selectedActionIndex = -1;
            }
            event.accepted = true;
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: listColumn
            Layout.preferredWidth: root.listColumnWidth
            Layout.fillHeight: true
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 6
                    color: "transparent"

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filteredEntries.length + " " + (root.filteredEntries.length === 1 ? Translation.tr("item") : Translation.tr("items"))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                ListView {
                    id: entryListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    topMargin: 4
                    bottomMargin: 4
                    spacing: 2

                    model: root.filteredEntries

                    currentIndex: root.selectedIndex
                    highlightMoveDuration: 80

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Item {
                            id: maskRoot
                            width: entryListView.width
                            height: entryListView.height

                            property color topFadeColor: !entryListView.atYBeginning ? "transparent" : "white"
                            property color bottomFadeColor: !entryListView.atYEnd ? "transparent" : "white"

                            Behavior on topFadeColor {
                                ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
                            }
                            Behavior on bottomFadeColor {
                                ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
                            }

                            Column {
                                anchors.fill: parent
                                spacing: 0

                                Rectangle {
                                    width: parent.width
                                    height: Math.min(36, parent.height / 2)
                                    color: "transparent"
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: maskRoot.topFadeColor }
                                        GradientStop { position: 1.0; color: "white" }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: Math.max(0, parent.height - Math.min(36, parent.height / 2) * 2)
                                    color: "white"
                                }

                                Rectangle {
                                    width: parent.width
                                    height: Math.min(36, parent.height / 2)
                                    color: "transparent"
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "white" }
                                        GradientStop { position: 1.0; color: maskRoot.bottomFadeColor }
                                    }
                                }
                            }
                        }
                    }

                    ScrollBar.vertical: StyledScrollBar {}

                    // Touchpad and mouse scroll physics adjustments
                    property real scrollTargetY: 0
                    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
                    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
                    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

                    maximumFlickVelocity: 3500

                    MouseArea {
                        z: 99
                        visible: Config?.options.interactions.scrolling.fasterTouchpadScroll
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: function (wheelEvent) {
                            const delta = wheelEvent.angleDelta.y / entryListView.mouseScrollDeltaThreshold;
                            var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= entryListView.mouseScrollDeltaThreshold ? entryListView.mouseScrollFactor : entryListView.touchpadScrollFactor;

                            const maxY = Math.max(0, entryListView.contentHeight - entryListView.height);
                            const base = scrollAnim.running ? entryListView.scrollTargetY : entryListView.contentY;
                            var targetY = Math.max(0, Math.min(base - delta * scrollFactor, maxY));

                            entryListView.scrollTargetY = targetY;
                            entryListView.contentY = targetY;
                            wheelEvent.accepted = true;
                        }
                    }

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
                            entryListView.scrollTargetY = entryListView.contentY;
                        }
                    }

                    delegate: RippleButton {
                        id: entryDelegate
                        required property var modelData
                        required property int index

                        readonly property string rawEntry: modelData
                        readonly property string cleanContent: StringUtils.cleanCliphistEntry(rawEntry)
                        readonly property bool isImage: Cliphist.entryIsImage(rawEntry)
                        readonly property bool isPinned: Cliphist.isPinned(rawEntry)
                        readonly property bool isFirst: index === 0
                        readonly property bool isLast: index === entryListView.count - 1
                        readonly property bool isSelected: index === root.selectedIndex
                        readonly property bool isCurrentClipboard: cleanContent === Quickshell.clipboardText
                        readonly property bool isAboveSelected: root.selectedIndex === index + 1 && root.selectedIndex !== -1
                        readonly property bool isBelowSelected: root.selectedIndex === index - 1 && root.selectedIndex !== -1
                        readonly property real pillRadius: Math.min(implicitHeight / 2, Appearance.rounding.large)
                        readonly property string contentType: Cliphist.classifyEntry(rawEntry)

                        width: entryListView.width
                        implicitHeight: 52
                        buttonRadius: 0

                        opacity: 0
                        transform: Translate {
                            id: entrySlide
                            y: -12
                        }

                        Component.onCompleted: {
                            entryRevealOpacity.start();
                            entryRevealSlide.start();
                        }

                        NumberAnimation {
                            id: entryRevealOpacity
                            target: entryDelegate
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            id: entryRevealSlide
                            target: entrySlide
                            property: "y"
                            from: -16
                            to: 0
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }

                        colBackground: isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: isSelected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighest
                        colRipple: Appearance.colors.colPrimaryContainerActive

                        background: Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            color: entryDelegate.colBackground
                            antialiasing: true

                            topLeftRadius: entryDelegate.isFirst ? Appearance.rounding.large : (entryDelegate.isSelected || entryDelegate.isBelowSelected ? entryDelegate.pillRadius : Appearance.rounding.small)
                            topRightRadius: topLeftRadius
                            bottomLeftRadius: entryDelegate.isLast ? Appearance.rounding.large : (entryDelegate.isSelected || entryDelegate.isAboveSelected ? entryDelegate.pillRadius : Appearance.rounding.small)
                            bottomRightRadius: bottomLeftRadius

                            Behavior on topLeftRadius {
                                NumberAnimation {
                                    duration: 350
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on topRightRadius {
                                NumberAnimation {
                                    duration: 350
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on bottomLeftRadius {
                                NumberAnimation {
                                    duration: 350
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on bottomRightRadius {
                                NumberAnimation {
                                    duration: 350
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }

                        onClicked: {
                            root.selectedIndex = index;
                        }
                        onDoubleClicked: {
                            root.selectedIndex = index;
                            root.activateSelected();
                        }

                        PointingHandInteraction {}

                        Component {
                            id: listImageComponent
                            Rectangle {
                                implicitWidth: 32
                                implicitHeight: 32
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colSurfaceContainerHighest
                                clip: true
                                CliphistImage {
                                    entry: entryDelegate.rawEntry
                                    maxWidth: 32
                                    maxHeight: 32
                                    anchors.centerIn: parent
                                }
                            }
                        }

                        Component {
                            id: listColorComponent
                            Rectangle {
                                implicitWidth: 32
                                implicitHeight: 32
                                radius: Appearance.rounding.full
                                color: root.formatColor(entryDelegate.cleanContent)
                                border.width: 1
                                border.color: Appearance.colors.colOutlineVariant
                            }
                        }

                        Component {
                            id: listIconComponent
                            Item {
                                implicitWidth: 32
                                implicitHeight: 32
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: {
                                        if (entryDelegate.isCurrentClipboard)
                                            return "check_circle";
                                        switch (entryDelegate.contentType) {
                                        case "url":
                                            return "link";
                                        case "email":
                                            return "alternate_email";
                                        case "phone":
                                            return "phone";
                                        case "json":
                                            return "data_object";
                                        case "filepath":
                                            return "folder_open";
                                        case "markdown":
                                            return "markdown";
                                        case "number":
                                            return "tag";
                                        case "multiline":
                                            return "notes";
                                        default:
                                            return "content_paste";
                                        }
                                    }
                                    iconSize: 18
                                    color: entryDelegate.isCurrentClipboard ? Appearance.colors.colPrimary : (entryDelegate.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant)
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Loader {
                                active: entryDelegate.isPinned
                                visible: active
                                Layout.preferredWidth: active ? 14 : 0
                                Layout.preferredHeight: active ? 14 : 0
                                sourceComponent: MaterialSymbol {
                                    text: "keep"
                                    iconSize: 14
                                    color: Appearance.colors.colPrimary
                                }
                            }

                            Loader {
                                id: visualLoader
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                sourceComponent: {
                                    if (entryDelegate.isImage)
                                        return listImageComponent;
                                    if (entryDelegate.contentType === "hex-color")
                                        return listColorComponent;
                                    return listIconComponent;
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: entryDelegate.isImage ? entryDelegate.cleanContent.replace(/\[\[|\]\]/g, "") : entryDelegate.cleanContent.replace(/\n/g, " ").substring(0, 80)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: entryDelegate.contentType === "json" ? Appearance.font.family.monospace : Appearance.font.family.main
                                    color: entryDelegate.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: {
                                        if (entryDelegate.isImage)
                                            return true;
                                        if (entryDelegate.contentType && entryDelegate.contentType !== "clipboard")
                                            return true;
                                        const lines = (entryDelegate.cleanContent.match(/\n/g) || []).length;
                                        return lines >= 1;
                                    }
                                    text: {
                                        if (entryDelegate.isImage)
                                            return "Image";
                                        if (entryDelegate.contentType === "url")
                                            return StringUtils.getDomain(entryDelegate.cleanContent) || "URL";
                                        if (entryDelegate.contentType === "json")
                                            return "JSON";
                                        if (entryDelegate.contentType === "email")
                                            return "Email";
                                        if (entryDelegate.contentType === "phone")
                                            return "Phone";
                                        if (entryDelegate.contentType === "filepath")
                                            return "File path";
                                        if (entryDelegate.contentType === "hex-color")
                                            return "Color";
                                        if (entryDelegate.contentType === "markdown")
                                            return "Markdown";
                                        if (entryDelegate.contentType === "number")
                                            return "Number";
                                        const lines = (entryDelegate.cleanContent.match(/\n/g) || []).length + 1;
                                        return lines + " lines";
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: entryDelegate.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    opacity: 0.8
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: detailColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Loader {
                    id: imagePreviewLoader
                    active: root.selectedIsImage && root.selectedEntry !== ""
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: active ? 12 : 0

                    Connections {
                        target: root
                        function onSelectedEntryChanged() {
                            imagePreviewLoader.active = false;
                            imageReloadTimer.restart();
                        }
                    }
                    Timer {
                        id: imageReloadTimer
                        interval: 25
                        onTriggered: imagePreviewLoader.active = root.selectedIsImage && root.selectedEntry !== ""
                    }

                    sourceComponent: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainerHighest
                        clip: true

                        opacity: 0
                        transform: Translate {
                            id: imgSlide
                            y: -10
                        }
                        NumberAnimation on opacity {
                            from: 0
                            to: 1
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: imgSlide
                            property: "y"
                            running: true
                            from: -10
                            to: 0
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }

                        CliphistImage {
                            id: clipImg
                            entry: root.selectedEntry
                            maxWidth: parent.width - 24
                            maxHeight: parent.height - 24
                            anchors.centerIn: parent
                        }
                    }
                }

                Loader {
                    id: textPreviewLoader
                    active: !root.selectedIsImage && root.selectedContentType !== "hex-color" && root.selectedContent !== ""
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: active ? 12 : 0

                    Connections {
                        target: root
                        function onSelectedEntryChanged() {
                            textPreviewLoader.active = false;
                            textReloadTimer.restart();
                        }
                    }
                    Timer {
                        id: textReloadTimer
                        interval: 25
                        onTriggered: textPreviewLoader.active = !root.selectedIsImage && root.selectedContentType !== "hex-color" && root.selectedContent !== ""
                    }

                    sourceComponent: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainerHigh
                        clip: true

                        opacity: 0
                        transform: Translate {
                            id: txtSlide
                            y: -10
                        }
                        NumberAnimation on opacity {
                            from: 0
                            to: 1
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: txtSlide
                            property: "y"
                            running: true
                            from: -10
                            to: 0
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }

                        StyledFlickable {
                            anchors.fill: parent
                            anchors.margins: 10
                            contentHeight: contentText.implicitHeight
                            clip: true

                            StyledText {
                                id: contentText
                                width: parent.width
                                text: root.selectedDecodedContent
                                font.pixelSize: Config.options.search.clipboard.previewFontSize
                                font.family: (root.selectedContentType === "json" || root.selectedContentType === "number") ? Appearance.font.family.monospace : Appearance.font.family.main
                                color: Appearance.m3colors.m3onSurface
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }

                Loader {
                    id: hexColorLoader
                    active: root.selectedContentType === "hex-color" && root.selectedContent !== ""
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: active ? 12 : 0

                    sourceComponent: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: root.formatColor(root.selectedContent)
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant

                        opacity: 0
                        transform: Translate {
                            id: colorSlide
                            y: -10
                        }
                        NumberAnimation on opacity {
                            from: 0
                            to: 1
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: colorSlide
                            property: "y"
                            running: true
                            from: -10
                            to: 0
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.formatColor(root.selectedContent).toUpperCase()
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.family: Appearance.font.family.monospace
                                font.weight: Font.Bold
                                color: root.getContrastColor(root.selectedContent)
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "HEX COLOR"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.getContrastColor(root.selectedContent)
                                opacity: 0.7
                                font.letterSpacing: 1.5
                            }
                        }
                    }
                }

                Loader {
                    id: emptyLoader
                    active: root.selectedContent === "" && root.filteredEntries.length === 0
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 24

                    sourceComponent: Item {
                        anchors.fill: parent
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "content_paste_off"
                                iconSize: 48
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: 0.5
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Clipboard is empty"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.preferredHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.5
                    visible: root.selectedEntry !== "" && Config.options.search.clipboard.showMetadata
                }

                GridLayout {
                    id: metadataGrid
                    visible: root.selectedEntry !== "" && Config.options.search.clipboard.showMetadata
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 8
                    Layout.bottomMargin: 4
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 4
                    opacity: 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 100
                            easing.type: Easing.OutQuad
                        }
                    }
                    Connections {
                        target: root
                        function onSelectedEntryChanged() {
                            metadataGrid.opacity = 0;
                            metadataReveal.restart();
                        }
                    }
                    Timer {
                        id: metadataReveal
                        interval: 60
                        onTriggered: metadataGrid.opacity = 1.0
                    }
                    Component.onCompleted: {
                        metadataReveal.start();
                    }

                    StyledText {
                        text: "Mime"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: root.selectedMime
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.m3colors.m3onSurface
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: "Size"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: root.formatBytes(root.selectedSize)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.m3colors.m3onSurface
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                    }

                    StyledText {
                        text: "Entry"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: root.selectedCopiedAt
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.m3colors.m3onSurface
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                    }

                    StyledText {
                        text: "MD5"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: root.selectedMd5
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.m3colors.m3onSurface
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideMiddle
                    }

                    Loader {
                        active: root.selectedContentType !== ""
                        visible: active
                        Layout.columnSpan: 1
                        sourceComponent: StyledText {
                            text: "Type"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Loader {
                        active: root.selectedContentType !== ""
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: StyledText {
                            text: root.selectedContentType || ""
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.m3colors.m3onSurface
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.5
                    visible: root.selectedEntry !== "" && Config.options.search.clipboard.showMetadata
                }

                RowLayout {
                    id: actionBar
                    visible: root.selectedEntry !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.bottomMargin: 8
                    spacing: 8

                    RippleButton {
                        id: copyButton
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: root.selectedActionIndex === 0 ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: {
                            root.selectedActionIndex = 0;
                            root.activateSelected();
                        }
                        PointingHandInteraction {}

                        RowLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 12, implicitWidth)
                            spacing: 6
                            MaterialSymbol {
                                id: copyIcon
                                Layout.alignment: Qt.AlignVCenter
                                text: "content_copy"
                                iconSize: 18
                                fill: (copyButton.hovered || root.selectedActionIndex === 0) ? 1.0 : 0.0
                                color: root.selectedActionIndex === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                scale: (copyButton.hovered || root.selectedActionIndex === 0) ? 1.08 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 120
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Copy"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                color: root.selectedActionIndex === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    RippleButton {
                        id: pasteButton
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: root.selectedActionIndex === 1 ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: {
                            root.selectedActionIndex = 1;
                            root.activateSelected();
                        }
                        PointingHandInteraction {}

                        RowLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 12, implicitWidth)
                            spacing: 6
                            MaterialSymbol {
                                id: pasteIcon
                                Layout.alignment: Qt.AlignVCenter
                                text: "content_paste"
                                iconSize: 18
                                fill: (pasteButton.hovered || root.selectedActionIndex === 1) ? 1.0 : 0.0
                                color: root.selectedActionIndex === 1 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                                scale: (pasteButton.hovered || root.selectedActionIndex === 1) ? 1.08 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 120
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Paste in active window"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                color: root.selectedActionIndex === 1 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    RippleButton {
                        id: smartButton
                        visible: root.hasSmartAction
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: root.selectedActionIndex === root.smartIndex ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: {
                            root.selectedActionIndex = root.smartIndex;
                            root.triggerSmartAction();
                        }
                        PointingHandInteraction {}

                        RowLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 12, implicitWidth)
                            spacing: 6
                            MaterialSymbol {
                                id: smartIcon
                                Layout.alignment: Qt.AlignVCenter
                                text: {
                                    if (root.selectedIsImage)
                                        return "image";
                                    if (root.selectedContentType === "filepath")
                                        return "folder_open";
                                    if (root.selectedContentType === "url")
                                        return "open_in_new";
                                    if (root.selectedContentType === "email")
                                        return "mail";
                                    if (root.selectedContentType === "phone")
                                        return "call";
                                    if (root.selectedContentType === "json")
                                        return "data_object";
                                    if (root.selectedContentType === "markdown")
                                        return "text_fields";
                                    if (root.selectedContentType === "number")
                                        return "pin";
                                    return "star";
                                }
                                iconSize: 18
                                fill: (smartButton.hovered || root.selectedActionIndex === root.smartIndex) ? 1.0 : 0.0
                                color: root.selectedActionIndex === root.smartIndex ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                                scale: (smartButton.hovered || root.selectedActionIndex === root.smartIndex) ? 1.08 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 120
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (root.selectedIsImage)
                                        return Translation.tr("Open Image");
                                    if (root.selectedContentType === "filepath")
                                        return Translation.tr("Open File");
                                    if (root.selectedContentType === "url")
                                        return Translation.tr("Open Link");
                                    if (root.selectedContentType === "email")
                                        return Translation.tr("Send Email");
                                    if (root.selectedContentType === "phone")
                                        return Translation.tr("Call Number");
                                    if (root.selectedContentType === "json")
                                        return Translation.tr("Format JSON");
                                    if (root.selectedContentType === "markdown")
                                        return Translation.tr("Copy Plain");
                                    if (root.selectedContentType === "number")
                                        return Translation.tr("Copy Clean");
                                    return Translation.tr("Smart Action");
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                color: root.selectedActionIndex === root.smartIndex ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    RippleButton {
                        id: pinButton
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: root.selectedActionIndex === root.pinIndex ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: {
                            root.selectedActionIndex = root.pinIndex;
                            root.activateSelected();
                        }
                        PointingHandInteraction {}
                        MaterialSymbol {
                            id: pinIcon
                            anchors.centerIn: parent
                            text: root.selectedIsPinned ? "keep_off" : "keep"
                            iconSize: 18
                            fill: (pinButton.hovered || root.selectedActionIndex === root.pinIndex) ? 1.0 : 0.0
                            color: root.selectedIsPinned ? Appearance.colors.colPrimary : (root.selectedActionIndex === root.pinIndex ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant)
                            scale: (pinButton.hovered || root.selectedActionIndex === root.pinIndex) ? 1.08 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                        StyledToolTip {
                            text: root.selectedIsPinned ? "Unpin" : "Pin"
                            y: -parent.height
                        }
                    }

                    RippleButton {
                        id: deleteButton
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: root.selectedActionIndex === root.deleteIndex ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colErrorContainerHover
                        colRipple: Appearance.colors.colErrorContainerActive
                        onClicked: {
                            root.selectedActionIndex = root.deleteIndex;
                            root.activateSelected();
                        }
                        PointingHandInteraction {}
                        MaterialSymbol {
                            id: deleteIcon
                            anchors.centerIn: parent
                            text: "delete"
                            iconSize: 18
                            fill: (deleteButton.hovered || root.selectedActionIndex === root.deleteIndex) ? 1.0 : 0.0
                            color: root.selectedActionIndex === root.deleteIndex ? Appearance.colors.colOnErrorContainer : Appearance.colors.colError
                            scale: (deleteButton.hovered || root.selectedActionIndex === root.deleteIndex) ? 1.08 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                        StyledToolTip {
                            text: "Delete"
                            y: -parent.height
                        }
                    }
                }
            }
        }
    }
}
