pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "clipboard"

/**
 * Clipboard history, Material 3 Expressive.
 *
 * Two slabs on the pane colour, no dividers: the list carries a rail of dashed type
 * filters (images, colours, links, numbers, …) above pill rows whose leading shape
 * says what each entry is; the detail pane answers with a hero — the image itself,
 * the colour filling the whole card in expressive digits, or the text — metadata as
 * small pills, and the actions as filled pills (paste primary, copy secondary,
 * the smart action tertiary, pin and delete tinted in the header).
 * Below the wide breakpoint the panes stack instead of squeezing.
 */
Item {
    id: root
    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    property string searchQuery: ""

    readonly property int panelWidth: Config.options.search.clipboard.panelWidth
    readonly property real listColumnRatio: Config.options.search.clipboard.listColumnRatio

    implicitWidth: panelWidth
    implicitHeight: 520

    /// Side-by-side panes need room for a list and a hero; below this they stack.
    readonly property bool wideLayout: root.width >= 640
    readonly property int listPaneWidth: Math.max(260, Math.min(Math.round(root.width * root.listColumnRatio), root.width - 320))

    // ── Filtering ────────────────────────────────────────────────────────
    /// "" = everything; otherwise one of the typeOf() keys.
    property string activeFilter: "all"

    readonly property var filterDefs: [
        { key: "image", label: Translation.tr("Images"), symbol: "image" },
        { key: "hex-color", label: Translation.tr("Colors"), symbol: "palette" },
        { key: "url", label: Translation.tr("Links"), symbol: "link" },
        { key: "number", label: Translation.tr("Numbers"), symbol: "tag" },
        { key: "json", label: "JSON", symbol: "data_object" },
        { key: "email", label: Translation.tr("Emails"), symbol: "alternate_email" },
        { key: "phone", label: Translation.tr("Phones"), symbol: "phone" },
        { key: "filepath", label: Translation.tr("Files"), symbol: "folder_open" },
        { key: "markdown", label: Translation.tr("Markdown"), symbol: "markdown" },
        { key: "text", label: Translation.tr("Text"), symbol: "notes" }
    ]

    /// One type key per entry: images first, then the detector result folded so
    /// plain and multiline text share the "text" filter.
    function typeOf(entry) {
        if (!entry)
            return "text";
        if (Cliphist.entryIsImage(entry))
            return "image";
        const content = StringUtils.cleanCliphistEntry(entry).trim();
        if (/^#?([0-9A-Fa-f]{3,4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(content))
            return "hex-color";
        const t = Cliphist.classifyEntry(entry);
        return (t === "" || t === "multiline") ? "text" : t;
    }

    function typeLabel(type) {
        switch (type) {
        case "image": return Translation.tr("Image");
        case "hex-color": return Translation.tr("Color");
        case "url": return Translation.tr("Link");
        case "number": return Translation.tr("Number");
        case "json": return "JSON";
        case "email": return Translation.tr("Email");
        case "phone": return Translation.tr("Phone");
        case "filepath": return Translation.tr("File path");
        case "markdown": return Translation.tr("Markdown");
        default: return Translation.tr("Text");
        }
    }

    function typeShape(type) {
        switch (type) {
        case "image": return MaterialShape.Shape.Sunny;
        case "hex-color": return MaterialShape.Shape.Flower;
        case "url": return MaterialShape.Shape.Cookie6Sided;
        case "number": return MaterialShape.Shape.Cookie12Sided;
        case "json": return MaterialShape.Shape.Cookie9Sided;
        case "email": return MaterialShape.Shape.Clover4Leaf;
        case "phone": return MaterialShape.Shape.SoftBurst;
        case "filepath": return MaterialShape.Shape.Cookie4Sided;
        case "markdown": return MaterialShape.Shape.Burst;
        default: return MaterialShape.Shape.Cookie7Sided;
        }
    }

    function typeSymbol(type) {
        switch (type) {
        case "image": return "image";
        case "hex-color": return "palette";
        case "url": return "link";
        case "number": return "tag";
        case "json": return "data_object";
        case "email": return "alternate_email";
        case "phone": return "phone";
        case "filepath": return "folder_open";
        case "markdown": return "markdown";
        case "multiline": return "notes";
        default: return "content_paste";
        }
    }

    /// Query matches, pinned first — the pool the chips count and the list filters.
    readonly property var queryMatches: {
        const q = root.searchQuery;
        const pinned = Cliphist.pinnedEntries;
        const out = [];
        for (let i = 0; i < pinned.length; i++) {
            const e = pinned[i];
            if (q === "" || e.toLowerCase().includes(q.toLowerCase()))
                out.push(e);
        }
        const base = q === "" ? Cliphist.entries : Cliphist.fuzzyQuery(q);
        for (let i = 0; i < base.length && out.length < 200; i++) {
            if (!Cliphist.isPinned(base[i]))
                out.push(base[i]);
        }
        return out;
    }

    readonly property var typeCounts: {
        const counts = ({});
        const matches = root.queryMatches;
        for (let i = 0; i < matches.length; i++) {
            const t = root.typeOf(matches[i]);
            counts[t] = (counts[t] ?? 0) + 1;
        }
        return counts;
    }

    readonly property var filterChips: {
        const chips = [{ key: "all", label: Translation.tr("All"), symbol: "apps", count: root.queryMatches.length }];
        for (let i = 0; i < root.filterDefs.length; i++) {
            const def = root.filterDefs[i];
            const n = root.typeCounts[def.key] ?? 0;
            if (n > 0)
                chips.push({ key: def.key, label: def.label, symbol: def.symbol, count: n });
        }
        return chips;
    }

    // A filter whose type just vanished from the matches would strand the list
    // on an empty view with no chip to show it — fall back to All instead.
    onTypeCountsChanged: {
        if (root.activeFilter !== "all" && !(root.activeFilter in root.typeCounts))
            root.activeFilter = "all";
    }

    onActiveFilterChanged: {
        root.confirmWipe = false;
        confirmWipeTimer.stop();
    }

    readonly property var clearableEntries: {
        const f = root.activeFilter;
        const out = [];
        for (let i = 0; i < Cliphist.entries.length; i++) {
            const entry = Cliphist.entries[i];
            if (!Cliphist.isPinned(entry)) {
                if (f === "all" || root.typeOf(entry) === f)
                    out.push(entry);
            }
        }
        return out;
    }

    property var filteredEntries: {
        const f = root.activeFilter;
        const matches = root.queryMatches;
        const out = [];
        for (let i = 0; i < matches.length; i++) {
            if (f !== "all" && root.typeOf(matches[i]) !== f)
                continue;
            out.push(matches[i]);
            if (out.length >= 100)
                break;
        }
        return out;
    }

    // ── Selection and actions ────────────────────────────────────────────
    property int selectedIndex: -1
    property int selectedActionIndex: -1
    property string selectedEntry: (filteredEntries.length > 0 && selectedIndex >= 0) ? filteredEntries[Math.min(selectedIndex, filteredEntries.length - 1)] : ""
    property bool confirmWipe: false
    /// Selection re-anchored by typing/filtering lands without replaying the
    /// corner morph, exactly like SearchItem's snapSelection.
    property bool snapSelection: false

    // ── Sliding selection pill (the search list's system) ───────────────
    // One pill for the whole list; each row paints the slice of it that lies
    // over itself. On a move the pill is re-attached to the new row at the
    // position it was painted at, then the offset glides to zero.
    property real selectionSlideOffset: 0
    property real selectionSlideHeightDelta: 0
    readonly property Item selectionIndicatorItem: entryListView.itemAtIndex(root.selectedIndex)
    readonly property real selectionIndicatorY: selectionIndicatorItem
        ? selectionIndicatorItem.y + selectionSlideOffset
        : -100000
    readonly property real selectionIndicatorHeight: selectionIndicatorItem
        ? selectionIndicatorItem.height + selectionSlideHeightDelta
        : 0

    ParallelAnimation {
        id: selectionSlideAnim
        NumberAnimation {
            target: root
            property: "selectionSlideOffset"
            to: 0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        NumberAnimation {
            target: root
            property: "selectionSlideHeightDelta"
            to: 0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    function stopSelectionSlide() {
        selectionSlideAnim.stop();
        root.selectionSlideOffset = 0;
        root.selectionSlideHeightDelta = 0;
    }

    function startSelectionSlide(fromIndex: int, slide: bool) {
        const from = fromIndex >= 0 ? entryListView.itemAtIndex(fromIndex) : null;
        const to = entryListView.itemAtIndex(root.selectedIndex);
        selectionSlideAnim.stop();
        if (!slide || root.animationsDisabled || !from || !to || from === to) {
            root.selectionSlideOffset = 0;
            root.selectionSlideHeightDelta = 0;
            return;
        }
        const visibleY = from.y + root.selectionSlideOffset;
        const visibleHeight = from.height + root.selectionSlideHeightDelta;
        root.selectionSlideOffset = visibleY - to.y;
        root.selectionSlideHeightDelta = visibleHeight - to.height;
        selectionSlideAnim.start();
    }

    property int lastSelectedIndex: -1
    onSelectedIndexChanged: {
        startSelectionSlide(lastSelectedIndex, !snapSelection);
        lastSelectedIndex = selectedIndex;
    }

    Timer {
        id: confirmWipeTimer
        interval: 3000
        repeat: false
        onTriggered: root.confirmWipe = false
    }

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
        root.snapSelection = true;
        if (selectedIndex !== targetIndex) {
            selectedIndex = targetIndex;
        }
        Qt.callLater(() => root.snapSelection = false);
        if (entryListView) {
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
        stopSelectionSlide();
        selectTimer.restart();
    }

    Component.onCompleted: {
        selectTimer.restart();
    }

    // ── Decoded preview ──────────────────────────────────────────────────
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
        if (selectedIsImage)
            return "image";
        const t = root.typeOf(selectedEntry);
        return t === "text" ? "" : t;
    }

    readonly property string selectedMime: {
        if (selectedIsImage) {
            // Preview format is "[[ binary data <size> <format> <W>x<H> ]]";
            // the old regex grabbed the leading "binary" fragment instead of
            // the actual format token before the dimensions.
            const match = selectedEntry.match(/\s(\w+)\s\d+x\d+\s\]\]\s*$/);
            return match ? `image/${match[1]}` : "image/*";
        }
        return "text/plain;charset=utf-8";
    }

    readonly property string selectedSize: {
        if (selectedIsImage) {
            // Reuse cliphist's human-readable size; no image decoding or file I/O.
            const match = selectedEntry.match(/^\d+\t\[\[ binary data (\d+(?:\.\d+)?\s+(?:[KMGTPE]i)?B)\s/);
            return match ? match[1] : "—";
        }
        return formatBytes(selectedDecodedContent.length);
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
            Quickshell.execDetached(["bash", "-c", "[ -f '" + path + "' ] || echo '" + StringUtils.shellSingleQuoteEscape(selectedEntry) + "' | " + Cliphist.cliphistBinary + " decode > '" + path + "'; xdg-open '" + path + "'; "]);
            GlobalStates.closeSearchSurfaces();
            return;
        }
        const content = selectedDecodedContent.trim();
        if (selectedContentType === "filepath") {
            Quickshell.execDetached(["xdg-open", content]);
            GlobalStates.closeSearchSurfaces();
        } else if (selectedContentType === "url") {
            Quickshell.execDetached(["xdg-open", content]);
            GlobalStates.closeSearchSurfaces();
        } else if (selectedContentType === "email") {
            Quickshell.execDetached(["xdg-open", "mailto:" + content]);
            GlobalStates.closeSearchSurfaces();
        } else if (selectedContentType === "phone") {
            Quickshell.execDetached(["xdg-open", "tel:" + content]);
            GlobalStates.closeSearchSurfaces();
        } else if (selectedContentType === "json") {
            try {
                const parsed = JSON.parse(content);
                const formatted = JSON.stringify(parsed, null, 4);
                Quickshell.execDetached(["bash", "-c", "printf '" + StringUtils.shellSingleQuoteEscape(formatted) + "' | wl-copy"]);
                GlobalStates.closeSearchSurfaces();
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
            GlobalStates.closeSearchSurfaces();
        } else if (selectedContentType === "number") {
            // Copy number stripped of formatting separators (spaces, commas, underscores)
            const bare = content.replace(/[\s,_]/g, "");
            Quickshell.clipboardText = bare;
            GlobalStates.closeSearchSurfaces();
        }
    }

    function activateSelected() {
        if (selectedActionIndex === -1 || selectedActionIndex === copyIndex) {
            if (selectedEntry) {
                Cliphist.copy(selectedEntry);
                GlobalStates.closeSearchSurfaces();
            }
        } else if (selectedActionIndex === pasteIndex) {
            if (selectedEntry) {
                Cliphist.paste(selectedEntry);
                GlobalStates.closeSearchSurfaces();
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

    function togglePin(entry) {
        if (!entry)
            return;
        if (Cliphist.isPinned(entry))
            Cliphist.unpin(entry);
        else
            Cliphist.pin(entry);
    }

    // This is a flat panel — there is no sub-level to back out of. Without
    // this, Backspace on an empty query falls through to
    // SearchWidget.exitActivePanel() and kicks the user back to plain Search,
    // so clearing the query to retype something silently exits the panel.
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

    // ══ Panes ════════════════════════════════════════════════════════════
    GridLayout {
        id: panes
        anchors.fill: parent
        columns: root.wideLayout ? 2 : 1
        columnSpacing: 12
        rowSpacing: 12

        // ── List pane ────────────────────────────────────────────────────
        Rectangle {
            id: listPane
            Layout.fillWidth: !root.wideLayout
            Layout.fillHeight: root.wideLayout
            Layout.preferredWidth: root.wideLayout ? root.listPaneWidth : -1
            Layout.preferredHeight: root.wideLayout ? -1 : Math.round(root.height * 0.56) - 6
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                // ── Type filters ────────────────────────────────────────
                Flickable {
                    id: chipFlickable
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    visible: root.filterChips.length > 1
                    clip: true
                    contentWidth: chipRow.implicitWidth
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: wheel => {
                            const maxX = Math.max(0, chipFlickable.contentWidth - chipFlickable.width);
                            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                            chipFlickable.contentX = Math.max(0, Math.min(chipFlickable.contentX - delta / 8, maxX));
                            wheel.accepted = true;
                        }
                    }

                    Row {
                        id: chipRow
                        spacing: 6
                        height: parent.height

                        Repeater {
                            model: root.filterChips

                            delegate: ClipboardFilterChip {
                                required property var modelData
                                symbol: modelData.symbol
                                label: modelData.label
                                count: modelData.count
                                selected: modelData.key === root.activeFilter
                                onClicked: root.activeFilter = modelData.key
                                PointingHandInteraction {}
                            }
                        }
                    }
                }

                // ── Entries ─────────────────────────────────────────────
                ListView {
                    id: entryListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    topMargin: 2
                    bottomMargin: 2

                    model: root.filteredEntries

                    currentIndex: root.selectedIndex
                    highlightMoveDuration: root.animationsDisabled ? 0 : 80

                    // edge fade lives on the pane, anchored to this view

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
                        enabled: !root.animationsDisabled
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
                        id: entryRow
                        required property var modelData
                        required property int index

                        readonly property string rawEntry: modelData
                        readonly property string cleanContent: StringUtils.cleanCliphistEntry(rawEntry)
                        readonly property bool isImage: Cliphist.entryIsImage(rawEntry)
                        readonly property bool isPinned: Cliphist.isPinned(rawEntry)
                        readonly property bool isSelected: index === root.selectedIndex
                        readonly property bool isCurrentClipboard: cleanContent === Quickshell.clipboardText
                        readonly property string entryType: root.typeOf(rawEntry)
                        readonly property bool dragAvailable: Teleprompter.available && !entryRow.isImage
                        /** Full decoded text once this row is selected; the preview until then. */
                        readonly property string dragText: entryRow.isSelected && root.selectedDecodedContent.length > 0
                            ? root.selectedDecodedContent : entryRow.cleanContent
                        readonly property color colContent: ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colOnLayer2, entryRow.selectionProgress)
                        readonly property bool isFirst: index === 0
                        readonly property bool isLast: index === entryListView.count - 1
                        readonly property bool selectedAbove: root.selectedIndex === index - 1
                        readonly property bool selectedBelow: root.selectedIndex === index + 1

                        // The search list's sliding pill: one pill for the whole list,
                        // each row paints the slice lying over itself, so the selection
                        // glides between rows instead of teleporting.
                        readonly property real indicatorTop: root.selectionIndicatorY - y
                        readonly property real indicatorBottom: root.selectionIndicatorY + root.selectionIndicatorHeight - y
                        readonly property real indicatorClipTop: isSelected ? Math.max(0, Math.min(height, indicatorTop)) : 0
                        readonly property real indicatorClipBottom: isSelected ? Math.max(0, Math.min(height, indicatorBottom)) : 0
                        readonly property real selectionProgress: height > 0 ? Math.max(0, indicatorClipBottom - indicatorClipTop) / height : (isSelected ? 1 : 0)
                        readonly property real pillRadius: Math.min(height / 2, Appearance.rounding.large)
                        property real neighbourTopOpen: selectedAbove ? 1 : 0
                        property real neighbourBottomOpen: selectedBelow ? 1 : 0
                        Behavior on neighbourTopOpen {
                            enabled: !root.animationsDisabled && !root.snapSelection
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                        }
                        Behavior on neighbourBottomOpen {
                            enabled: !root.animationsDisabled && !root.snapSelection
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                        }
                        readonly property real topOpenProgress: Math.max(selectionProgress, neighbourTopOpen)
                        readonly property real bottomOpenProgress: Math.max(selectionProgress, neighbourBottomOpen)
                        readonly property real restTopRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.small + (pillRadius - Appearance.rounding.small) * topOpenProgress
                        readonly property real restBottomRadius: isLast ? Appearance.rounding.large : Appearance.rounding.small + (pillRadius - Appearance.rounding.small) * bottomOpenProgress

                        width: entryListView.width
                        implicitHeight: 52

                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundActive: Appearance.colors.colLayer2Active
                        colRipple: Appearance.colors.colPrimaryContainerActive

                        background: Rectangle {
                            id: rowBg
                            anchors.fill: parent
                            antialiasing: true
                            clip: true
                            color: entryRow.buttonColor

                            topLeftRadius: entryRow.restTopRadius
                            topRightRadius: topLeftRadius
                            bottomLeftRadius: entryRow.restBottomRadius
                            bottomRightRadius: bottomLeftRadius

                            Behavior on color {
                                enabled: !root.animationsDisabled
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            // The slice of the list's selection pill over this row: an
                            // edge inside the row is the pill's own rounded end, an edge
                            // cut by the row takes the row's corner instead.
                            Rectangle {
                                readonly property real span: Math.max(0, entryRow.indicatorClipBottom - entryRow.indicatorClipTop)
                                readonly property real endRadius: Math.min(entryRow.pillRadius, span / 2)
                                readonly property bool enteredFromTop: entryRow.indicatorTop <= 0.5
                                readonly property bool exitsAtBottom: entryRow.indicatorBottom >= rowBg.height - 0.5
                                visible: span > 0.5
                                x: 0
                                y: entryRow.indicatorClipTop
                                width: rowBg.width
                                height: span
                                topLeftRadius: Math.min(enteredFromTop ? rowBg.topLeftRadius : endRadius, span / 2)
                                topRightRadius: Math.min(enteredFromTop ? rowBg.topRightRadius : endRadius, span / 2)
                                bottomLeftRadius: Math.min(exitsAtBottom ? rowBg.bottomLeftRadius : endRadius, span / 2)
                                bottomRightRadius: Math.min(exitsAtBottom ? rowBg.bottomRightRadius : endRadius, span / 2)
                                color: entryRow.down ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimary
                                antialiasing: true
                            }
                        }

                        onClicked: root.selectedIndex = index
                        onDoubleClicked: {
                            root.selectedIndex = index;
                            root.activateSelected();
                        }

                        PointingHandInteraction {}

                        // The drag's own visual: a chip that follows the grip while
                        // it is held. `Drag.Automatic` turns the movement into a
                        // QDrag carrying the entry's text, which the island's drop
                        // area turns into a teleprompter session.
                        Item {
                            id: dragProxy
                            width: 220
                            height: 40
                            z: 10
                            visible: gripArea.drag.active
                            Drag.dragType: Drag.Automatic
                            Drag.supportedActions: Qt.CopyAction
                            Drag.proposedAction: Qt.CopyAction
                            Drag.mimeData: ({
                                "text/plain": entryRow.dragText
                            })
                            Drag.onActiveChanged: GlobalStates.islandTextDragActive = dragProxy.Drag.active
                            Drag.onDragFinished: {
                                // The island cannot see a drag coming (no hover
                                // fires mid-drag), so the panel announces it and
                                // takes the announcement back when it ends.
                                GlobalStates.islandTextDragActive = false;
                                dragProxy.x = 0;
                                dragProxy.y = 0;
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colPrimaryContainer

                                StyledText {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    text: entryRow.dragText.replace(/\n/g, " ").substring(0, 48)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnPrimaryContainer
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                        }

                        leftPadding: 10
                        rightPadding: 10
                        contentItem: RowLayout {
                            spacing: 10

                            Item {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                Layout.alignment: Qt.AlignVCenter

                                // Image entries carry their own thumbnail.
                                Rectangle {
                                    anchors.fill: parent
                                    visible: entryRow.isImage
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colSurfaceContainerHighest
                                    clip: true

                                    CliphistImage {
                                        entry: entryRow.rawEntry
                                        maxWidth: 36
                                        maxHeight: 36
                                        anchors.centerIn: parent
                                    }
                                }

                                // Hex colours are their own swatch.
                                Rectangle {
                                    anchors.fill: parent
                                    visible: !entryRow.isImage && entryRow.entryType === "hex-color"
                                    radius: Appearance.rounding.full
                                    color: root.formatColor(entryRow.cleanContent)

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 10
                                        height: 10
                                        radius: Appearance.rounding.full
                                        color: root.getContrastColor(entryRow.cleanContent)
                                        opacity: 0.85
                                    }
                                }

                                // Everything else gets its type shape.
                                MaterialShapeWrappedMaterialSymbol {
                                    anchors.fill: parent
                                    visible: !entryRow.isImage && entryRow.entryType !== "hex-color"
                                    text: root.typeSymbol(entryRow.entryType)
                                    iconSize: 18
                                    padding: 9
                                    shape: root.typeShape(entryRow.entryType)
                                    color: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimary, entryRow.selectionProgress)
                                    colSymbol: ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimary, entryRow.selectionProgress)
                                    fill: entryRow.selectionProgress
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: entryRow.isImage ? entryRow.cleanContent.replace(/\[\[|\]\]/g, "").trim() : entryRow.cleanContent.replace(/\n/g, " ").substring(0, 90)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    font.family: entryRow.entryType === "json" ? Appearance.font.family.monospace : Appearance.font.family.main
                                    color: entryRow.colContent
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const parts = [];
                                        if (entryRow.isImage) {
                                            const dims = entryRow.rawEntry.match(/(\d+x\d+)/);
                                            parts.push(Translation.tr("Image") + (dims ? " · " + dims[1] : ""));
                                        } else if (entryRow.entryType === "url") {
                                            parts.push(StringUtils.getDomain(entryRow.cleanContent) || Translation.tr("Link"));
                                        } else {
                                            parts.push(root.typeLabel(entryRow.entryType));
                                        }
                                        if (entryRow.isPinned)
                                            parts.push(Translation.tr("Pinned"));
                                        return parts.join(" · ");
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: entryRow.colContent
                                    opacity: 0.75
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            MaterialSymbol {
                                visible: entryRow.isCurrentClipboard
                                Layout.alignment: Qt.AlignVCenter
                                text: "check_circle"
                                iconSize: 16
                                fill: 1
                                color: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, entryRow.selectionProgress)
                            }

                            // The grip: press-and-move drags the entry's text out of
                            // the panel (to the island, or anywhere that takes text).
                            // A handle and not the row itself, so the row keeps its
                            // click and the list keeps its flick.
                            Item {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 36
                                Layout.alignment: Qt.AlignVCenter
                                visible: entryRow.dragAvailable && (entryRow.hovered || gripArea.pressed)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "drag_indicator"
                                    iconSize: 16
                                    color: entryRow.colContent
                                    opacity: 0.75
                                }

                                MouseArea {
                                    id: gripArea
                                    anchors.fill: parent
                                    cursorShape: Qt.SizeAllCursor
                                    // Selecting starts the decode, so the drag carries
                                    // the full text rather than the list's one-liner.
                                    onPressed: root.selectedIndex = index
                                    drag.target: dragProxy
                                }
                            }
                        }
                    }

                    displaced: root.animationsDisabled ? null : clipDisplacedTransition
                    add: root.animationsDisabled ? null : clipAddTransition
                    remove: root.animationsDisabled ? null : clipRemoveTransition

                    Transition {
                        id: clipDisplacedTransition
                        NumberAnimation {
                            properties: "y"
                            duration: 220
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                    }

                    Transition {
                        id: clipAddTransition
                        ParallelAnimation {
                            NumberAnimation {
                                property: "opacity"
                                from: 0.0; to: 1.0
                                duration: 180
                                easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                property: "y"
                                duration: 220
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                        }
                    }

                    Transition {
                        id: clipRemoveTransition
                        NumberAnimation {
                            property: "opacity"
                            to: 0.0
                            duration: 120
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                // ── Footer: count and clear ─────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 8

                    StyledText {
                        text: root.filteredEntries.length + " " + (root.filteredEntries.length === 1 ? Translation.tr("item") : Translation.tr("items"))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colSubtext
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    RippleButton {
                        visible: root.clearableEntries.length > 0
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: clearWipeRow.implicitWidth + 20
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.confirmWipe ? Appearance.colors.colErrorContainer : "transparent"
                        colBackgroundHover: root.confirmWipe ? Appearance.colors.colErrorContainerHover : Appearance.colors.colLayer2Hover
                        colBackgroundActive: root.confirmWipe ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer2Active
                        colRipple: root.confirmWipe ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer2Active
                        onClicked: {
                            if (!root.confirmWipe) {
                                root.confirmWipe = true;
                                confirmWipeTimer.restart();
                                return;
                            }
                            root.confirmWipe = false;
                            confirmWipeTimer.stop();
                            const toDelete = root.clearableEntries;
                            if (toDelete.length > 0) {
                                const deletedMap = ({});
                                for (let i = 0; i < toDelete.length; i++) {
                                    const k = Cliphist.entryKey(toDelete[i]);
                                    if (k) deletedMap[k] = true;
                                }
                                if (Persistent.states.clipboard.historySeen) {
                                    Persistent.states.clipboard.historySeen = Persistent.states.clipboard.historySeen.filter(item => !deletedMap[String(item.id)]);
                                }
                                Cliphist.wipeEntries(toDelete);
                            }
                        }

                        PointingHandInteraction {}

                        Row {
                            id: clearWipeRow
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.confirmWipe ? "warning" : "delete_sweep"
                                iconSize: 15
                                fill: root.confirmWipe ? 1 : 0
                                color: root.confirmWipe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.confirmWipe ? Translation.tr("Confirm?") : Translation.tr("Clear")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: root.confirmWipe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        // ── Detail pane ──────────────────────────────────────────────────
        Rectangle {
            id: detailPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            clip: true

            ColumnLayout {
                id: detailColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                opacity: 0
                transform: Translate {
                    id: detailTranslate
                    x: 15
                }

                ParallelAnimation {
                    id: detailEntryAnim
                    NumberAnimation {
                        target: detailColumn
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: root.animationsDisabled ? 0 : 300
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: detailTranslate
                        property: "x"
                        from: 20
                        to: 0
                        duration: root.animationsDisabled ? 0 : 300
                        easing.type: Easing.OutCubic
                    }
                }

                Connections {
                    target: root
                    function onSelectedEntryChanged() {
                        detailEntryAnim.restart();
                    }
                }

                Component.onCompleted: detailEntryAnim.start()

                // ── Header: what this entry is, pin and delete ──────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    visible: root.selectedEntry !== ""
                    spacing: 10

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.typeSymbol(root.selectedIsImage ? "image" : root.typeOf(root.selectedEntry))
                        iconSize: 18
                        padding: 10
                        shape: root.typeShape(root.selectedIsImage ? "image" : root.typeOf(root.selectedEntry))
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                        fill: 1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.typeLabel(root.selectedIsImage ? "image" : root.typeOf(root.selectedEntry))
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: [root.selectedCopiedAt, root.selectedSize].filter(part => part.length > 0).join(" · ")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    ClockCardAction {
                        Layout.alignment: Qt.AlignVCenter
                        symbol: root.selectedIsPinned ? "keep" : "keep_off"
                        tip: root.selectedIsPinned ? Translation.tr("Unpin") : Translation.tr("Pin")
                        colContent: root.selectedIsPinned ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        onClicked: {
                            root.selectedActionIndex = root.pinIndex;
                            root.togglePin(root.selectedEntry);
                        }
                    }

                    ClockCardAction {
                        Layout.alignment: Qt.AlignVCenter
                        symbol: "delete"
                        tip: Translation.tr("Delete")
                        danger: true
                        onClicked: {
                            root.selectedActionIndex = root.deleteIndex;
                            if (root.selectedEntry) {
                                Cliphist.deleteEntry(root.selectedEntry);
                                root.selectedActionIndex = -1;
                            }
                        }
                    }
                }

                // ── Hero: image, colour or text ─────────────────────────
                Item {
                    id: heroArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 96

                    Loader {
                        id: imagePreviewLoader
                        anchors.fill: parent
                        active: root.selectedIsImage && root.selectedEntry !== ""
                        visible: active

                        sourceComponent: Rectangle {
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSurfaceContainerHighest
                            clip: true

                            CliphistImage {
                                entry: root.selectedEntry
                                maxWidth: parent.width - 24
                                maxHeight: parent.height - 24
                                anchors.centerIn: parent
                            }
                        }
                    }

                    Loader {
                        id: hexColorLoader
                        anchors.fill: parent
                        active: !root.selectedIsImage && root.typeOf(root.selectedEntry) === "hex-color" && root.selectedContent !== ""
                        visible: active

                        sourceComponent: Rectangle {
                            id: hexCard
                            radius: Appearance.rounding.normal
                            color: root.formatColor(root.selectedContent)
                            clip: true

                            // Ornament: a big scalloped flower parked off the right
                            // edge, cut by the card, tinted with the contrast ink.
                            MaterialShape {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: -parent.height * 1.2
                                width: parent.height * 1.9
                                height: parent.height * 1.9
                                shape: MaterialShape.Shape.Flower
                                color: root.getContrastColor(root.selectedContent)
                                opacity: 0.10
                                rotation: 18
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                width: hexCard.width - 40
                                spacing: 6

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.formatColor(root.selectedContent).toUpperCase()
                                    font.pixelSize: Math.round(Math.min(Appearance.font.pixelSize.huge + 8, hexCard.width / 5.5))
                                    font.family: Appearance.font.family.monospace
                                    font.weight: Font.Bold
                                    color: root.getContrastColor(root.selectedContent)
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Translation.tr("Hex color")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: root.getContrastColor(root.selectedContent)
                                    opacity: 0.7
                                    font.letterSpacing: 1.5
                                }
                            }
                        }
                    }

                    Loader {
                        id: textPreviewLoader
                        anchors.fill: parent
                        active: !root.selectedIsImage && root.typeOf(root.selectedEntry) !== "hex-color" && root.selectedEntry !== "" && root.filteredEntries.length > 0
                        visible: active

                        sourceComponent: Rectangle {
                            radius: Appearance.rounding.normal
                            color: Appearance.m3colors.m3surfaceContainerHighest
                            clip: true

                            StyledFlickable {
                                anchors.fill: parent
                                anchors.margins: 14
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

                    // Empty: nothing copied at all, or nothing left after a filter.
                    Loader {
                        anchors.fill: parent
                        active: root.selectedEntry === ""
                        visible: active

                        sourceComponent: Item {
                            // The Loader owns this item's size, so the centred box
                            // inside is what actually places the empty state.
                            Item {
                                id: emptyBox
                                anchors.centerIn: parent
                                width: 300
                                height: 236

                                readonly property bool noMatches: root.filteredEntries.length === 0 && (root.activeFilter !== "all" || root.searchQuery !== "")

                                Item {
                                    id: emptyBadge
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 96
                                    height: 96

                                    MaterialShape {
                                        anchors.fill: parent
                                        shapeString: "SoftBurst"
                                        color: Appearance.colors.colSecondaryContainer
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: emptyBox.noMatches ? "filter_alt_off" : "content_paste_off"
                                        iconSize: 36
                                        fill: 1
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }

                                StyledText {
                                    id: emptyTitle
                                    anchors.top: emptyBadge.bottom
                                    anchors.topMargin: 14
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: emptyBox.noMatches ? Translation.tr("No matching items") : Translation.tr("Clipboard is empty")
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colOnSurface
                                }

                                StyledText {
                                    anchors.top: emptyTitle.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 260
                                    text: emptyBox.noMatches ? Translation.tr("Try another filter or clear the search") : Translation.tr("Copy something and it shows up here")
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }

                // ── Metadata pills ──────────────────────────────────────
                Flow {
                    id: metadataFlow
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    visible: root.selectedEntry !== "" && Config.options.search.clipboard.showMetadata && root.wideLayout
                    spacing: 6

                    property var chips: {
                        if (root.selectedEntry === "" || !Config.options.search.clipboard.showMetadata)
                            return [];
                        const out = [{ k: Translation.tr("Type"), v: root.typeLabel(root.typeOf(root.selectedEntry)) }];
                        out.push({ k: Translation.tr("Mime"), v: root.selectedMime });
                        out.push({ k: Translation.tr("Size"), v: root.selectedSize });
                        if (root.selectedCopiedAt.length > 0)
                            out.push({ k: Translation.tr("Entry"), v: root.selectedCopiedAt });
                        if (root.selectedMd5.length > 0)
                            out.push({ k: "MD5", v: root.selectedMd5 });
                        return out;
                    }

                    Repeater {
                        model: metadataFlow.chips

                        delegate: Rectangle {
                            id: pill
                            required property var modelData
                            readonly property bool isHash: modelData.k === "MD5" || modelData.k === Translation.tr("Mime")
                            implicitHeight: 26
                            implicitWidth: Math.min(pillRow.implicitWidth + 16, metadataFlow.width)
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2

                            Row {
                                id: pillRow
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, pill.width - 16)
                                spacing: 5

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pill.modelData.k
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, 200)
                                    text: pill.modelData.v
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colOnSurface
                                    elide: pill.isHash ? Text.ElideMiddle : Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                        }
                    }
                }

                // ── Actions: copy, paste, smart ─────────────────────────
                RowLayout {
                    id: actionBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    visible: root.selectedEntry !== ""
                    spacing: 8

                    RippleButton {
                        id: copyButton
                        readonly property bool focusedAction: root.selectedActionIndex === root.copyIndex
                        Layout.fillWidth: true
                        implicitHeight: 42
                        Layout.preferredWidth: 3
                        buttonRadius: Appearance.rounding.full
                        colBackground: focusedAction ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                        colBackgroundHover: focusedAction ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                        colBackgroundActive: focusedAction ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: {
                            root.selectedActionIndex = root.copyIndex;
                            root.activateSelected();
                        }
                        PointingHandInteraction {}

                        contentItem: Item {
                            RowLayout {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 16, implicitWidth)
                                spacing: 6

                                MaterialSymbol {
                                    text: "content_copy"
                                    iconSize: 18
                                    fill: (copyButton.hovered || copyButton.focusedAction) ? 1 : 0
                                    color: copyButton.focusedAction ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Copy")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    color: copyButton.focusedAction ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                    }

                    RippleButton {
                        id: pasteButton
                        readonly property bool focusedAction: root.selectedActionIndex === root.pasteIndex
                        Layout.fillWidth: true
                        implicitHeight: 42
                        Layout.preferredWidth: 4
                        buttonRadius: Appearance.rounding.full
                        colBackground: focusedAction ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colBackgroundActive: Appearance.colors.colPrimaryActive
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: {
                            root.selectedActionIndex = root.pasteIndex;
                            root.activateSelected();
                        }
                        PointingHandInteraction {}

                        contentItem: Item {
                            RowLayout {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 16, implicitWidth)
                                spacing: 6

                                MaterialSymbol {
                                    text: "content_paste"
                                    iconSize: 18
                                    fill: pasteButton.hovered || pasteButton.focusedAction ? 1 : 0
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Paste")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }

                    RippleButton {
                        id: smartButton
                        readonly property bool focusedAction: root.selectedActionIndex === root.smartIndex
                        visible: root.hasSmartAction
                        Layout.fillWidth: true
                        implicitHeight: 42
                        Layout.preferredWidth: 3
                        buttonRadius: Appearance.rounding.full
                        colBackground: focusedAction ? Appearance.colors.colPrimary : Appearance.colors.colTertiaryContainer
                        colBackgroundHover: focusedAction ? Appearance.colors.colPrimaryHover : Appearance.colors.colTertiaryContainerHover
                        colBackgroundActive: focusedAction ? Appearance.colors.colPrimaryActive : Appearance.colors.colTertiaryContainerActive
                        colRipple: Appearance.colors.colTertiaryContainerActive
                        onClicked: {
                            root.selectedActionIndex = root.smartIndex;
                            root.triggerSmartAction();
                        }
                        PointingHandInteraction {}

                        contentItem: Item {
                            RowLayout {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 16, implicitWidth)
                                spacing: 6

                                MaterialSymbol {
                                    text: {
                                        if (root.selectedIsImage)
                                            return "image";
                                        switch (root.selectedContentType) {
                                        case "filepath": return "folder_open";
                                        case "url": return "open_in_new";
                                        case "email": return "mail";
                                        case "phone": return "call";
                                        case "json": return "data_object";
                                        case "markdown": return "text_fields";
                                        case "number": return "calculate";
                                        default: return "auto_awesome";
                                        }
                                    }
                                    iconSize: 18
                                    fill: (smartButton.hovered || smartButton.focusedAction) ? 1 : 0
                                    color: smartButton.focusedAction ? Appearance.colors.colOnPrimary : Appearance.colors.colOnTertiaryContainer
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        if (root.selectedIsImage)
                                            return Translation.tr("Open Image");
                                        switch (root.selectedContentType) {
                                        case "filepath": return Translation.tr("Open File");
                                        case "url": return Translation.tr("Open Link");
                                        case "email": return Translation.tr("Send Email");
                                        case "phone": return Translation.tr("Call Number");
                                        case "json": return Translation.tr("Format JSON");
                                        case "markdown": return Translation.tr("Copy Plain");
                                        case "number": return Translation.tr("Copy Clean");
                                        default: return Translation.tr("Smart Action");
                                        }
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    color: smartButton.focusedAction ? Appearance.colors.colOnPrimary : Appearance.colors.colOnTertiaryContainer
                                }
                            }
                        }
                    }

                    // Send the entry to the island's teleprompter: the whole
                    // decoded text, not the list's one-line preview. Icon only,
                    // named by its tooltip, beside the other actions. Only while
                    // the island exists to read it, and never for images.
                    RippleButton {
                        id: prompterButton
                        visible: Teleprompter.available && !root.selectedIsImage
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 42
                        implicitHeight: 42
                        buttonRadius: Appearance.rounding.full
                        colBackground: prompterHovered.hovered ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colTertiaryContainer
                        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                        colBackgroundActive: Appearance.colors.colTertiaryContainerActive
                        colRipple: Appearance.colors.colTertiaryContainerActive
                        onClicked: Teleprompter.start(root.selectedDecodedContent.length > 0
                            ? root.selectedDecodedContent : root.selectedContent)

                        HoverHandler {
                            id: prompterHovered
                        }
                        PointingHandInteraction {}

                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "subtitles"
                            iconSize: 18
                            fill: prompterHovered.hovered ? 1 : 0
                            color: Appearance.colors.colOnTertiaryContainer
                        }

                        StyledToolTip {
                            text: Translation.tr("Read with Teleprompter")
                            requireOverlay: false
                        }
                    }
                }
            }
        }
    }
}
