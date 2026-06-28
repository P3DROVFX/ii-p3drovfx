pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
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
    property string filter: ""
    property bool snapBusy: false
    property bool snapSuccess: false
    property bool snapError: false
    property var expandedSlugs: ({})

    readonly property bool isCurrentTab: {
        try {
            return swipeView.currentIndex === index;
        } catch (e) {
            return true;
        }
    }

    readonly property bool isTabActive: root.visible && root.isCurrentTab

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
    readonly property var emojiList: WorkspaceProfileService.presetEmojis

    Component.onCompleted: {
        WorkspaceProfileService.refresh();
    }

    // ── service connections ──────────────────────────────────────────────────
    Connections {
        target: WorkspaceProfileService

        function onSnapshotFinished(success, slug) {
            root.snapBusy = false;
            if (success) {
                root.snapSuccess = true;
                snapFeedbackTimer.restart();
            } else {
                root.snapError = true;
                snapFeedbackTimer.restart();
            }
        }
    }

    Connections {
        target: WorkspaceProfileService.profilesModel
        function onModelReset() {
            gridArea.triggerLayout();
        }
        function onRowsInserted() {
            gridArea.triggerLayout();
        }
        function onRowsRemoved() {
            gridArea.triggerLayout();
        }
        function onRowsMoved() {
            gridArea.triggerLayout();
        }
        function onDataChanged() {
            gridArea.triggerLayout();
        }
    }

    Timer {
        id: snapFeedbackTimer
        interval: 2500
        onTriggered: {
            root.snapSuccess = false;
            root.snapError = false;
        }
    }



    // ── focus ─────────────────────────────────────────────────────────────────
    onFocusChanged: if (focus)
        searchField.forceActiveFocus()
    onVisibleChanged: if (visible)
        searchField.forceActiveFocus()

    Item {
        id: inboxContent
        anchors.fill: parent
        opacity: (workspaceProfileForm.isOpen || workspaceProfileForm.isAnimating) ? 0.0 : 1.0
        enabled: !workspaceProfileForm.isOpen && !workspaceProfileForm.isAnimating

        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.windowRounding
            antialiasing: true
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── profile grid ──────────────────────────────────────────────────────
            Item {
                id: profileListItem
                Layout.fillWidth: true
                Layout.fillHeight: true

                // empty state (no profiles at all)
                PagePlaceholder {
                    shown: !WorkspaceProfileService.loading && WorkspaceProfileService.binaryExists && WorkspaceProfileService.profilesModel.count === 0
                    icon: "dashboard"
                    title: "No profiles yet"
                    description: "Click \"New snapshot\" to save your current workspace layout."
                }

                // filtered empty state
                PagePlaceholder {
                    shown: !WorkspaceProfileService.loading && WorkspaceProfileService.binaryExists && WorkspaceProfileService.profilesModel.count > 0 && gridArea.visibleProfileCount === 0 && root.filter !== ""
                    icon: "search_off"
                    title: "No matches"
                    description: "Try a different search term."
                }

                // loading indicator
                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: WorkspaceProfileService.loading && WorkspaceProfileService.binaryExists && WorkspaceProfileService.profilesModel.count === 0
                    implicitWidth: 40
                    implicitHeight: 40
                }

                StyledFlickable {
                    anchors {
                        fill: parent
                        leftMargin: 16
                        rightMargin: 16
                        topMargin: 16
                        bottomMargin: 70
                    }
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
                        property int visibleProfileCount: 0
                        property int layoutVersion: 0

                        // ── masonry helpers ───────────────────────────────────────

                        Connections {
                            target: root
                            function onIsTabActiveChanged() {
                                gridArea.triggerLayout();
                            }
                        }

                        function recalculateLayout() {
                            var heights = [0, 0];
                            var isActive = root.isTabActive;
                            for (var i = 0; i < profileRepeater.count; i++) {
                                var card = profileRepeater.itemAt(i);
                                if (!card)
                                    continue;
                                if (card.visible) {
                                    if (isActive) {
                                        var minCol = (heights[0] <= heights[1]) ? 0 : 1;
                                        card.x = minCol * (cardWidth + cardSpacing);
                                        card.y = heights[minCol];
                                        heights[minCol] += card.implicitHeight + cardSpacing;
                                    } else {
                                        // Stacked at center and staggered slightly downwards
                                        card.x = (width - cardWidth) / 2;
                                        card.y = i * 20;
                                    }
                                }
                            }
                            var maxH = Math.max(heights[0], heights[1]);
                            gridArea.implicitHeight = (maxH > cardSpacing) ? maxH - cardSpacing : 0;
                            gridArea.layoutVersion++;
                        }

                        function triggerLayout() {
                            layoutTimer.restart();  // debounce
                        }

                        function recountVisible() {
                            var n = 0;
                            for (var i = 0; i < profileRepeater.count; i++) {
                                var item = profileRepeater.itemAt(i);
                                if (item && item.visible)
                                    n++;
                            }
                            visibleProfileCount = n;
                        }

                        // ── profile card repeater ─────────────────────────────────
                        Repeater {
                            id: profileRepeater
                            model: WorkspaceProfileService.profilesModel
                            onCountChanged: gridArea.triggerLayout()

                            delegate: ProfileCard {
                                id: card

                                 hasMatches: {
                                    let q = root.filter.toLowerCase().trim();
                                    if (!q) return true;
                                    let nameMatch = (card.name || "").toLowerCase().includes(q);
                                    let descMatch = (card.description || "").toLowerCase().includes(q);
                                    return nameMatch || descMatch;
                                }

                                onPinnedChanged: gridArea.triggerLayout()

                                shortcutHint: {
                                    var _trigger = gridArea.visibleProfileCount;
                                    var _trigger2 = gridArea.layoutVersion;
                                    if (!card.visible)
                                        return "";
                                    var count = 0;
                                    for (var i = 0; i < profileRepeater.count; i++) {
                                        var other = profileRepeater.itemAt(i);
                                        if (other && other.visible) {
                                            if (other === card)
                                                return count < 9 ? ("Ctrl+" + (count + 1)) : "";
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
                                    gridArea.triggerLayout();
                                    gridArea.recountVisible();
                                }
                                Component.onCompleted: gridArea.recountVisible()
                                Component.onDestruction: Qt.callLater(gridArea.recountVisible)

                                // ── actions ─────────────────────────────────────
                                onRestoreRequested: WorkspaceProfileService.restoreProfile(slug)
                                onDeleteRequested: WorkspaceProfileService.deleteProfile(slug)
                                onEditRequested: {
                                    workspaceProfileForm.openForEdit(slug, name, emoji, description);
                                }
                                onTogglePinRequested: WorkspaceProfileService.togglePin(slug)
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
                            gridArea.triggerLayout();
                        }
                    }
                }

                // binary missing empty state with copyable command
                ColumnLayout {
                    visible: opacity > 0.0
                    opacity: (!WorkspaceProfileService.loading && !WorkspaceProfileService.binaryExists) ? 1.0 : 0.0
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 12

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                        }
                    }

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "terminal"
                        padding: 12
                        iconSize: 56
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Backend Not Compiled"
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.larger
                            variableAxes: Appearance.font.variableAxes.title
                        }
                        color: Appearance.m3colors.m3outline
                        horizontalAlignment: Text.AlignHCenter
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        text: "The workspace manager binary is missing. Please compile it from source to enable workspace profiles:"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3outline
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }

                    // Command box with Copy button
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(parent.width - 40, 520)
                        implicitHeight: 80
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer2
                        border.width: 1
                        border.color: Appearance.colors.colOutline

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 6
                            spacing: 8

                            // Monospace terminal-like code area
                            StyledText {
                                id: commandText
                                Layout.fillWidth: true
                                text: "cd ~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager_src && cargo build --release && cp target/release/workspace_profile_manager ../"
                                font {
                                    family: Appearance.font.family.monospace
                                    pixelSize: Appearance.font.pixelSize.smaller
                                }
                                color: Appearance.colors.colOnSurface
                                wrapMode: Text.Wrap
                            }

                            // Copy button
                            RippleButton {
                                id: copyBtn
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer3
                                colBackgroundHover: Appearance.colors.colLayer3Hover

                                property bool copied: false

                                onClicked: {
                                    Quickshell.clipboardText = commandText.text;
                                    copied = true;
                                    restoreTimer.restart();
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: copyBtn.copied ? "check" : "content_copy"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: copyBtn.copied ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 150
                                        }
                                    }
                                }

                                StyledToolTip {
                                    text: copyBtn.copied ? "Copied!" : "Copy build command"
                                }

                                Timer {
                                    id: restoreTimer
                                    interval: 2000
                                    onTriggered: copyBtn.copied = false
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── bottom floating toolbar (New snapshot + Search) ──────────────────
        // 1. Centered Search/Filter Toolbar
        Toolbar {
            id: searchBarToolbar
            z: 5
            enableShadow: false
            colBackground: Appearance.colors.colSecondaryContainer
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 8
            }

            ToolbarTextField {
                id: searchField
                placeholderText: focus ? qsTr("Search profiles") : qsTr("Hit \"/\" to search")
                clip: true
                font.pixelSize: Appearance.font.pixelSize.small
                onTextChanged: root.filter = text

                Component.onCompleted: forceActiveFocus()
            }

            IconToolbarButton {
                implicitWidth: height
                onClicked: {
                    searchField.text = "";
                    root.filter = "";
                }
                text: "close"
                StyledToolTip {
                    text: qsTr("Clear filter")
                }
            }
        }

        // 2. New snapshot button container to render the button
        Item {
            id: newSnapshotBtnContainer
            z: 5
            width: newSnapshotBtn.width
            height: 56
            anchors {
                right: searchBarToolbar.left
                rightMargin: 12
                verticalCenter: searchBarToolbar.verticalCenter
            }

            RippleButtonWithIcon {
                id: newSnapshotBtn
                anchors.centerIn: parent
                materialIcon: "add_a_photo"
                materialIconFill: true
                mainText: qsTr("New snapshot")
                colText: Appearance.colors.colOnPrimaryContainer
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Qt.lighter(Appearance.colors.colPrimaryContainer, 1.08)
                buttonRadius: Appearance.rounding.small
                buttonRadiusPressed: Appearance.rounding.full
                implicitHeight: 56
                leftPadding: 0
                rightPadding: 0

                readonly property real dw: width - 56
                width: hovered ? (24 + 8 + textLoader.implicitWidth + 32) : 56

                Behavior on width {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }

                contentItem: Item {
                    id: buttonContent
                    clip: true

                    Row {
                        id: contentRow
                        anchors.centerIn: parent
                        spacing: Math.min(8, newSnapshotBtn.dw)

                        MaterialSymbol {
                            text: newSnapshotBtn.materialIcon
                            iconSize: Appearance.font.pixelSize.larger
                            color: newSnapshotBtn.colText
                            fill: newSnapshotBtn.materialIconFill ? 1 : 0
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            id: textLoader
                            text: newSnapshotBtn.mainText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: newSnapshotBtn.colText
                            anchors.verticalCenter: parent.verticalCenter

                            width: Math.max(0, newSnapshotBtn.dw - contentRow.spacing)
                            clip: true
                            opacity: newSnapshotBtn.hovered ? 1 : 0

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
                }

                StyledToolTip {
                    text: qsTr("Ctrl + N")
                }

                onClicked: workspaceProfileForm.openForAdd()
            }
        }

        // 3. Snapshot feedback badge
        Rectangle {
            id: feedbackBadge
            z: 5
            visible: root.snapSuccess || root.snapError
            radius: Appearance.rounding.full
            color: root.snapSuccess ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer
            implicitWidth: fbRow.implicitWidth + 16
            implicitHeight: 56
            anchors {
                right: newSnapshotBtnContainer.left
                rightMargin: 12
                verticalCenter: searchBarToolbar.verticalCenter
            }

            RowLayout {
                id: fbRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    text: root.snapSuccess ? "check_circle" : "error"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    color: root.snapSuccess ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                }
                StyledText {
                    text: root.snapSuccess ? "Saved!" : "Failed"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.snapSuccess ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                }
            }
        }
    }

    WorkspaceProfileForm {
        id: workspaceProfileForm
        anchors.fill: parent
        z: 10
        visible: isOpen || isAnimating
    }

    // ── keyboard shortcuts ───────────────────────────────────────────────────
    function triggerShortcut(index) {
        if (!root.visible || WorkspaceProfileService.restoring)
            return;
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
        if (!root.visible || WorkspaceProfileService.restoring)
            return;
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

    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+1", "Ctrl+&"]
        onActivated: root.triggerShortcut(0)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+2", "Ctrl+é"]
        onActivated: root.triggerShortcut(1)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+3", "Ctrl+\""]
        onActivated: root.triggerShortcut(2)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+4", "Ctrl+'"]
        onActivated: root.triggerShortcut(3)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+5", "Ctrl+("]
        onActivated: root.triggerShortcut(4)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+6", "Ctrl+-"]
        onActivated: root.triggerShortcut(5)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+7", "Ctrl+è"]
        onActivated: root.triggerShortcut(6)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+8", "Ctrl+_"]
        onActivated: root.triggerShortcut(7)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+9", "Ctrl+ç"]
        onActivated: root.triggerShortcut(8)
    }

    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+1", "Ctrl+Alt+&"]
        onActivated: root.triggerDeleteShortcut(0)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+2", "Ctrl+Alt+é"]
        onActivated: root.triggerDeleteShortcut(1)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+3", "Ctrl+Alt+\""]
        onActivated: root.triggerDeleteShortcut(2)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+4", "Ctrl+Alt+'"]
        onActivated: root.triggerDeleteShortcut(3)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+5", "Ctrl+Alt+("]
        onActivated: root.triggerDeleteShortcut(4)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+6", "Ctrl+Alt+-"]
        onActivated: root.triggerDeleteShortcut(5)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+7", "Ctrl+Alt+è"]
        onActivated: root.triggerDeleteShortcut(6)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+8", "Ctrl+Alt+_"]
        onActivated: root.triggerDeleteShortcut(7)
    }
    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequences: ["Ctrl+Alt+9", "Ctrl+Alt+ç"]
        onActivated: root.triggerDeleteShortcut(8)
    }

    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible && !workspaceProfileForm.isOpen
        sequence: "/"
        onActivated: searchField.forceActiveFocus()
    }

    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible && !workspaceProfileForm.isOpen
        sequence: "Ctrl+N"
        onActivated: {
            if (!root.visible || WorkspaceProfileService.restoring)
                return;
            workspaceProfileForm.openForAdd();
        }
    }

    Shortcut {
        enabled: root.isCurrentTab && cheatsheetRoot.visible
        sequence: "Escape"
        onActivated: {
            if (workspaceProfileForm.isOpen) {
                workspaceProfileForm.startClose();
            } else if (root.filter !== "") {
                root.filter = "";
                searchField.forceActiveFocus();
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
