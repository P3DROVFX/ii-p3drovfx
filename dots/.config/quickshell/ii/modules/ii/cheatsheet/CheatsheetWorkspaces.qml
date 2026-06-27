pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "workspaces"

/**
 * CheatsheetWorkspaces — the "Workspaces" tab in the cheatsheet.
 *
 * Lists saved workspace profiles and lets the user:
 *   - Snapshot the current layout as a new profile
 *   - Restore a profile (move running apps to saved workspaces)
 *   - Rename or delete profiles
 *
 * Layout: 2-column masonry grid. The new-snapshot form occupies slot 0
 * as an inline card when open, shifting profile cards to the right.
 */
Item {
    id: root

    // ── state ────────────────────────────────────────────────────────────────
    property string filter:        ""
    property bool   showNewForm:   false
    property string newName:       ""
    property string newEmoji:      "🗂️"
    property string newDesc:       ""
    property bool   snapBusy:      false
    property bool   snapSuccess:   false
    property bool   snapError:     false
    property var    expandedSlugs: ({})

    property var    filteredProfiles: []
    property int    loadedProfilesCount: 10
    readonly property var slicedProfiles: root.filteredProfiles.slice(0, root.loadedProfilesCount)

    function updateFiltered() {
        let list = [];
        let q = root.filter.toLowerCase().trim();
        for (let i = 0; i < WorkspaceProfileService.profilesModel.count; i++) {
            let item = WorkspaceProfileService.profilesModel.get(i);
            if (!item) continue;
            let nameMatch = (item.name || "").toLowerCase().includes(q);
            let descMatch = (item.description || "").toLowerCase().includes(q);
            if (!q || nameMatch || descMatch) {
                list.push(item);
            }
        }
        root.filteredProfiles = list;
    }

    function loadMore() {
        if (root.loadedProfilesCount < root.filteredProfiles.length) {
            root.loadedProfilesCount = Math.min(root.loadedProfilesCount + 10, root.filteredProfiles.length);
        }
    }

    onFilterChanged: {
        root.loadedProfilesCount = 10;
        root.updateFiltered();
    }

    function isProfileExpanded(slug) {
        return !!root.expandedSlugs[slug];
    }

    function setProfileExpanded(slug, isExp) {
        let copy = Object.assign({}, root.expandedSlugs);
        if (isExp) {
            copy[slug] = true;
        } else {
            delete copy[slug];
        }
        root.expandedSlugs = copy;
    }

    // Preset emojis for the picker
    readonly property var emojiList: [
        "🗂️","📚","💻","🎮","🎵","🎬","📝","🔬","🎨","🏋️",
        "☕","🌙","🚀","🏠","🌊","🔧","📊","✉️","🎓","🧠"
    ]

    Component.onCompleted: {
        WorkspaceProfileService.refresh();
        root.updateFiltered();
    }

    // ── service connections ──────────────────────────────────────────────────
    Connections {
        target: WorkspaceProfileService

        function onSnapshotFinished(success, slug) {
            root.snapBusy = false;
            if (success) {
                root.snapSuccess = true;
                root.showNewForm = false;
                root.newName  = "";
                root.newEmoji = "🗂️";
                root.newDesc  = "";
                snapFeedbackTimer.restart();
            } else {
                root.snapError = true;
                snapFeedbackTimer.restart();
            }
        }
    }

    Connections {
        target: WorkspaceProfileService.profilesModel
        function onModelReset() { root.updateFiltered() }
        function onRowsInserted() { root.updateFiltered() }
        function onRowsRemoved() { root.updateFiltered() }
        function onDataChanged() { root.updateFiltered() }
    }

    Timer {
        id: snapFeedbackTimer
        interval: 2500
        onTriggered: { root.snapSuccess = false; root.snapError = false; }
    }

    // ── focus ─────────────────────────────────────────────────────────────────
    onFocusChanged: if (focus) searchField.forceActiveFocus()

    // ── layout ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── toolbar: search + new snapshot button ─────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.bottomMargin: 14
            spacing: 10

            ToolbarTextField {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.fillHeight: false
                placeholderText: "Search profiles…"
                text: root.filter
                onTextChanged: root.filter = text
            }

            // snapshot feedback badge
            Rectangle {
                visible: root.snapSuccess || root.snapError
                radius: Appearance.rounding.full
                color: root.snapSuccess
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colErrorContainer
                implicitWidth:  fbRow.implicitWidth + 16
                implicitHeight: 36

                RowLayout {
                    id: fbRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: root.snapSuccess ? "check_circle" : "error"
                        iconSize: Appearance.font.pixelSize.normal
                        fill: 1
                        color: root.snapSuccess
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        text: root.snapSuccess ? "Saved!" : "Failed"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.snapSuccess
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnErrorContainer
                    }
                }
            }

            // new snapshot / cancel button
            RippleButtonWithIcon {
                id: newSnapshotBtn
                materialIcon: root.showNewForm ? "close" : "add_a_photo"
                materialIconFill: !root.showNewForm
                mainText: root.showNewForm ? "Cancel" : "New snapshot (Ctrl+N)"
                colText: root.showNewForm
                    ? Appearance.colors.colOnSurfaceVariant
                    : Appearance.colors.colOnPrimary
                colBackground: root.showNewForm
                    ? Appearance.colors.colLayer2
                    : Appearance.colors.colPrimary
                colBackgroundHover: root.showNewForm
                    ? Appearance.colors.colLayer2Hover
                    : Appearance.colors.colPrimaryHover
                buttonRadius: Appearance.rounding.full
                implicitHeight: 36

                onClicked: root.showNewForm = !root.showNewForm
            }
        }

        // ── profile grid ──────────────────────────────────────────────────────
        Item {
            id: profileListItem
            Layout.fillWidth: true
            Layout.fillHeight: true

            // empty state (no profiles at all)
            PagePlaceholder {
                shown: !WorkspaceProfileService.loading
                    && WorkspaceProfileService.profilesModel.count === 0
                    && !root.showNewForm
                icon: "dashboard"
                title: "No profiles yet"
                description: "Click \"New snapshot\" to save your current workspace layout."
            }

            // filtered empty state
            PagePlaceholder {
                shown: !WorkspaceProfileService.loading
                    && WorkspaceProfileService.profilesModel.count > 0
                    && gridArea.visibleProfileCount === 0
                    && root.filter !== ""
                icon: "search_off"
                title: "No matches"
                description: "Try a different search term."
            }

            // loading indicator
            MaterialLoadingIndicator {
                anchors.centerIn: parent
                visible: WorkspaceProfileService.loading
                implicitWidth: 40; implicitHeight: 40
            }

            StyledFlickable {
                anchors.fill: parent
                contentHeight: gridArea.implicitHeight
                clip: true
                onContentYChanged: {
                    if (contentHeight > height && contentY + height >= contentHeight - 150) {
                        root.loadMore();
                    }
                }

                // ── 2-column masonry grid ─────────────────────────────────────
                Item {
                    id: gridArea
                    width: parent.width

                    readonly property real cardSpacing: 12
                    readonly property real cardWidth: (width - cardSpacing) / 2
                    property int visibleProfileCount: root.filteredProfiles.length

                    // ── masonry helpers ───────────────────────────────────────

                    // Returns the height of the form card (slot 0 when showNewForm)
                    function formSlotHeight() {
                        return root.showNewForm ? (formCard.implicitHeight + cardSpacing) : 0
                    }

                    function recalculateLayout() {
                        var heights = [formSlotHeight(), 0]
                        for (var i = 0; i < profileRepeater.count; i++) {
                            var card = profileRepeater.itemAt(i)
                            if (!card) continue
                            if (card.visible) {
                                var minCol = (heights[0] <= heights[1]) ? 0 : 1
                                card.x = minCol * (cardWidth + cardSpacing)
                                card.y = heights[minCol]
                                heights[minCol] += card.implicitHeight + cardSpacing
                            }
                        }
                        var maxH = Math.max(heights[0], heights[1])
                        gridArea.implicitHeight = (maxH > cardSpacing) ? maxH - cardSpacing : 0
                    }

                    function triggerLayout() {
                        layoutTimer.restart()  // debounce
                    }

                    function recountVisible() {
                        var n = 0
                        for (var i = 0; i < profileRepeater.count; i++) {
                            var item = profileRepeater.itemAt(i)
                            if (item && item.visible) n++
                        }
                        visibleProfileCount = n
                    }

                    // Re-lay when form visibility toggles
                    Connections {
                        target: root
                        function onShowNewFormChanged() {
                            gridArea.triggerLayout()
                        }
                    }

                    // ── inline form card (slot 0) ─────────────────────────────
                    Rectangle {
                        id: formCard
                        x: 0
                        y: 0
                        width: gridArea.cardWidth
                        visible: root.showNewForm
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer4
                        border { width: 1; color: Appearance.colors.colOutlineVariant }
                        clip: true

                        implicitHeight: formCardLayout.implicitHeight + 32

                        onImplicitHeightChanged: gridArea.triggerLayout()

                        // top accent gradient
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop {
                                    position: 0.0
                                    color: Qt.rgba(
                                        Appearance.colors.colPrimary.r,
                                        Appearance.colors.colPrimary.g,
                                        Appearance.colors.colPrimary.b,
                                        0.08
                                    )
                                }
                                GradientStop { position: 0.6; color: "transparent" }
                            }
                        }

                        // entrance animation
                        opacity: 0.0
                        scale: 0.97
                        onVisibleChanged: {
                            if (visible) {
                                formEnterOp.start()
                                formEnterScale.start()
                                nameField.forceActiveFocus()
                            }
                        }
                        NumberAnimation {
                            id: formEnterOp; target: formCard; property: "opacity"
                            from: 0.0; to: 1.0; duration: 300
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            id: formEnterScale; target: formCard; property: "scale"
                            from: 0.97; to: 1.0; duration: 300
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }

                        ColumnLayout {
                            id: formCardLayout
                            anchors {
                                left: parent.left; right: parent.right; top: parent.top
                                margins: 16
                            }
                            spacing: 12

                            // form header
                            RowLayout {
                                spacing: 8

                                MaterialSymbol {
                                    text: "add_a_photo"
                                    iconSize: Appearance.font.pixelSize.large
                                    fill: 1
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: "New Workspace Snapshot"
                                    font {
                                        pixelSize: Appearance.font.pixelSize.large
                                        weight: Font.Bold
                                    }
                                    color: Appearance.colors.colOnSurface
                                }
                            }

                            // divider
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Appearance.colors.colOutlineVariant
                                opacity: 0.5
                            }

                            // emoji picker + name/desc column
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                // emoji grid
                                Flow {
                                    id: emojiFlow
                                    Layout.preferredWidth: 160
                                    spacing: 4

                                    Repeater {
                                        model: root.emojiList
                                        delegate: RippleButton {
                                            required property var modelData
                                            implicitWidth: 30; implicitHeight: 30
                                            buttonRadius: Appearance.rounding.small
                                            toggled: root.newEmoji === modelData
                                            colBackgroundToggled: Appearance.colors.colPrimaryContainer

                                            scale: toggled ? 1.15 : 1.0
                                            Behavior on scale {
                                                NumberAnimation {
                                                    duration: 150
                                                    easing.type: Easing.BezierSpline
                                                    easing.bezierCurve: Appearance.animationCurves.emphasized
                                                }
                                            }

                                            onClicked: root.newEmoji = modelData

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: parent.modelData
                                                font.pixelSize: 15
                                            }
                                        }
                                    }
                                }

                                // name + description
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    MaterialTextField {
                                        id: nameField
                                        Layout.fillWidth: true
                                        hint: "Profile name (required)…"
                                        text: root.newName
                                        onTextChanged: root.newName = text
                                        Keys.onReturnPressed: if (root.newName.trim().length > 0) _doSnapshot()
                                        Component.onCompleted: if (root.showNewForm) forceActiveFocus()
                                    }

                                    MaterialTextField {
                                        Layout.fillWidth: true
                                        hint: "Description (optional)…"
                                        text: root.newDesc
                                        onTextChanged: root.newDesc = text
                                    }
                                }
                            }

                            // save row
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }

                                MaterialLoadingIndicator {
                                    visible: root.snapBusy
                                    implicitWidth: 24; implicitHeight: 24
                                }

                                RippleButtonWithIcon {
                                    materialIcon: "save"
                                    materialIconFill: true
                                    mainText: "Save snapshot"
                                    enabled: root.newName.trim().length > 0 && !root.snapBusy
                                    colText: Appearance.colors.colOnPrimary
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    buttonRadius: Appearance.rounding.full
                                    implicitHeight: 40
                                    leftPadding: 16; rightPadding: 16
                                    onClicked: _doSnapshot()
                                }
                            }
                        }
                    }

                    // ── profile card repeater ─────────────────────────────────
                    Repeater {
                        id: profileRepeater
                        model: root.slicedProfiles
                        onCountChanged: gridArea.triggerLayout()

                        delegate: ProfileCard {
                            id: card

                            onPinnedChanged: gridArea.triggerLayout()

                            shortcutHint: {
                                var _trigger = gridArea.visibleProfileCount;
                                if (!card.visible) return "";
                                var count = 0;
                                for (var i = 0; i < profileRepeater.count; i++) {
                                    var other = profileRepeater.itemAt(i);
                                    if (other && other.visible) {
                                        if (other === card) return count < 9 ? ("Ctrl+" + (count + 1)) : "";
                                        count++;
                                    }
                                }
                                return "";
                            }

                            // ── masonry positioning ─────────────────────────
                            width: gridArea.cardWidth

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

                            onImplicitHeightChanged: gridArea.triggerLayout()
                            onVisibleChanged: {
                                gridArea.triggerLayout()
                                gridArea.recountVisible()
                            }
                            Component.onCompleted: gridArea.recountVisible()
                            Component.onDestruction: Qt.callLater(gridArea.recountVisible)

                            // ── expand state ────────────────────────────────
                            expanded: root.isProfileExpanded(slug)
                            onToggleExpandedRequested: {
                                root.setProfileExpanded(slug, !root.isProfileExpanded(slug))
                            }

                            // ── actions ─────────────────────────────────────
                            onRestoreRequested:  WorkspaceProfileService.restoreProfile(slug)
                            onDeleteRequested:   WorkspaceProfileService.deleteProfile(slug)
                            onRenameRequested: (newName) =>
                                WorkspaceProfileService.renameProfile(slug, newName)
                            onUpdateEmojiRequested: (newEmoji) =>
                                WorkspaceProfileService.updateEmoji(slug, newEmoji)
                            onUpdateDescriptionRequested: (newDesc) =>
                                WorkspaceProfileService.updateDescription(slug, newDesc)
                            onTogglePinRequested:
                                WorkspaceProfileService.togglePin(slug)
                        }
                    }

                    // layout debounce timer
                    Timer {
                        id: layoutTimer
                        interval: 20
                        repeat: false
                        onTriggered: gridArea.recalculateLayout()
                    }

                    // initial layout trigger
                    Component.onCompleted: {
                        gridArea.triggerLayout()
                    }
                }
            }
        }

        // ── global shortcut hints ─────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: hintText.implicitHeight + 8
            Layout.bottomMargin: 8
            visible: WorkspaceProfileService.profilesModel.count > 0

            StyledText {
                id: hintText
                anchors.centerIn: parent
                text: "<b>Ctrl+[1-9]</b>: Restore  •  <b>Ctrl+Alt+[1-9]</b>: Delete"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                textFormat: Text.RichText
            }
        }
    }

    // ── keyboard shortcuts ───────────────────────────────────────────────────
    function triggerShortcut(index) {
        if (!root.visible || WorkspaceProfileService.restoring) return;
        var count = 0;
        for (var i = 0; i < profileRepeater.count; i++) {
            var card = profileRepeater.itemAt(i);
            if (card && card.visible) {
                if (count === index) {
                    WorkspaceProfileService.restoreProfile(card.slug);
                    return;
                }
                count++;
            }
        }
    }

    function triggerDeleteShortcut(index) {
        if (!root.visible || WorkspaceProfileService.restoring) return;
        var count = 0;
        for (var i = 0; i < profileRepeater.count; i++) {
            var card = profileRepeater.itemAt(i);
            if (card && card.visible) {
                if (count === index) {
                    card.requestDeleteAction();
                    return;
                }
                count++;
            }
        }
    }

    Shortcut { sequences: ["Ctrl+1", "Ctrl+&"]; onActivated: root.triggerShortcut(0) }
    Shortcut { sequences: ["Ctrl+2", "Ctrl+é"]; onActivated: root.triggerShortcut(1) }
    Shortcut { sequences: ["Ctrl+3", "Ctrl+\""]; onActivated: root.triggerShortcut(2) }
    Shortcut { sequences: ["Ctrl+4", "Ctrl+'"]; onActivated: root.triggerShortcut(3) }
    Shortcut { sequences: ["Ctrl+5", "Ctrl+("]; onActivated: root.triggerShortcut(4) }
    Shortcut { sequences: ["Ctrl+6", "Ctrl+-"]; onActivated: root.triggerShortcut(5) }
    Shortcut { sequences: ["Ctrl+7", "Ctrl+è"]; onActivated: root.triggerShortcut(6) }
    Shortcut { sequences: ["Ctrl+8", "Ctrl+_"]; onActivated: root.triggerShortcut(7) }
    Shortcut { sequences: ["Ctrl+9", "Ctrl+ç"]; onActivated: root.triggerShortcut(8) }

    Shortcut { sequences: ["Ctrl+Alt+1", "Ctrl+Alt+&"]; onActivated: root.triggerDeleteShortcut(0) }
    Shortcut { sequences: ["Ctrl+Alt+2", "Ctrl+Alt+é"]; onActivated: root.triggerDeleteShortcut(1) }
    Shortcut { sequences: ["Ctrl+Alt+3", "Ctrl+Alt+\""]; onActivated: root.triggerDeleteShortcut(2) }
    Shortcut { sequences: ["Ctrl+Alt+4", "Ctrl+Alt+'"]; onActivated: root.triggerDeleteShortcut(3) }
    Shortcut { sequences: ["Ctrl+Alt+5", "Ctrl+Alt+("]; onActivated: root.triggerDeleteShortcut(4) }
    Shortcut { sequences: ["Ctrl+Alt+6", "Ctrl+Alt+-"]; onActivated: root.triggerDeleteShortcut(5) }
    Shortcut { sequences: ["Ctrl+Alt+7", "Ctrl+Alt+è"]; onActivated: root.triggerDeleteShortcut(6) }
    Shortcut { sequences: ["Ctrl+Alt+8", "Ctrl+Alt+_"]; onActivated: root.triggerDeleteShortcut(7) }
    Shortcut { sequences: ["Ctrl+Alt+9", "Ctrl+Alt+ç"]; onActivated: root.triggerDeleteShortcut(8) }

    Shortcut {
        sequence: "Ctrl+N"
        onActivated: {
            if (!root.visible || WorkspaceProfileService.restoring) return;
            root.showNewForm = true;
            nameField.forceActiveFocus();
        }
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    function _doSnapshot() {
        const name = root.newName.trim()
        if (!name) return
        root.snapBusy = true
        WorkspaceProfileService.snapshot(name, root.newEmoji, root.newDesc, {})
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.filter !== "") {
                root.filter = "";
                searchField.forceActiveFocus();
            } else if (root.showNewForm) {
                root.showNewForm = false;
            } else {
                let win = root.Window.window;
                if (win && typeof win.hide === "function") {
                    win.hide();
                } else {
                    GlobalStates.cheatsheetOpen = false;
                }
            }
        }
    }
}
