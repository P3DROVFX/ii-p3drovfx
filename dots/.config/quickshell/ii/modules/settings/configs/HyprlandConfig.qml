pragma ComponentBehavior: Bound

import QtQuick
import qs
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.hyprland

/**
 * Settings -> Hyprland.
 *
 * One page over a compact row of tabs, because the compositor's settings do not split cleanly into
 * sidebar entries and nothing else in Settings is this deep. The tabs are peers; anything
 * that needs a whole screen of its own - a rule editor, one keybind, the full option list -
 * opens as a sub-page instead, so drilling down stays a push and switching stays a tab.
 *
 * Everything written from here lands in a fenced block at the end of the matching file in
 * ~/.config/hypr/custom/. Where that is, how much of it there is and how old the backup is used
 * to be a strip across the top of every tab; it is a page of its own now, reached from the menu
 * in the corner, because none of it is something you act on while changing a setting.
 *
 * An edit is staged, not written. The two buttons in the corner are the only things that touch
 * the files, and they only appear once there is something to touch them for.
 */
Item {
    id: hubRoot
    anchors.fill: parent

    property alias activeSubPage: subPageOverlay.activeSubPage
    /// The settings window pushes a restored scroll position onto whatever page it loaded.
    /// Hand it to the tab that is actually showing.
    property real contentY: 0
    onContentYChanged: hubRoot.pushContentY()

    function pushContentY() {
        const page = tabLoader.item;
        if (page && page.contentY !== undefined)
            page.contentY = hubRoot.contentY;
    }
    /**
     * Whether this page shows everything the compositor can be told, or the part of it a
     * desktop actually needs.
     *
     * Hyprland has 353 options and this hub grew a control for most of them. Nearly none of
     * that is something a person setting up a laptop will ever touch, and putting it all on
     * screen at once made the settings that do matter - the touchpad, the shortcut you want to
     * change - impossible to find among them. So the rare half is behind this, and the switch
     * lives in the menu in the corner.
     */
    readonly property bool advanced: Config.options.hyprland.advancedSettings

    /// `name` is the untranslated key, translated in the tab delegate — the same split the page
    /// registry uses. Putting Translation.tr in here instead would rebuild the model on every
    /// language switch, and a rebuilt tab model drops SwipeView back to a different tab.
    ///
    /// The raw option list is a tab for people who already know what they are looking for, so
    /// it only exists in advanced mode - and the page opens on Input, which is the one thing
    /// everybody changes.
    readonly property var allTabs: [
        { "id": "input", "name": "Input", "icon": "keyboard", "file": "hyprland/InputTab.qml",
          "advanced": false },
        { "id": "layout", "name": "Layout", "icon": "dashboard", "file": "hyprland/LayoutTab.qml",
          "advanced": false },
        { "id": "shortcuts", "name": "Shortcuts", "icon": "keyboard_command_key",
          "file": "hyprland/ShortcutsTab.qml", "advanced": false },
        { "id": "defaultApps", "name": "Default apps", "icon": "apps",
          "file": "hyprland/DefaultAppsTab.qml", "advanced": false },
        { "id": "rules", "name": "Rules", "icon": "filter_alt", "file": "hyprland/RulesTab.qml",
          "advanced": false },
        { "id": "environment", "name": "Environment", "icon": "terminal",
          "file": "hyprland/EnvironmentTab.qml", "advanced": false },
        { "id": "allOptions", "name": "All options", "icon": "tune",
          "file": "hyprland/AllOptionsTab.qml", "advanced": true }
    ]

    readonly property var tabs: hubRoot.allTabs.filter(tab => !tab.advanced || hubRoot.advanced)

    // Turning advanced mode off takes a tab away, so the current index may fall past the end
    // - or point at a different tab entirely. The selection lives on the bar and follows it;
    // clamping first avoids a one-frame load of whatever was at the clipped index.
    onTabsChanged: {
        if (hubRoot.currentTab >= hubRoot.tabs.length)
            hubRoot.currentTab = 0;
    }

    // Only the selected tab owns a tree. Delay its first construction until
    // the placeholder has a frame and the managed values are available.
    property bool tabLoadArmed: false
    readonly property bool tabBarReady: tabBar.count === hubRoot.tabs.length
    /// The tab this page is showing. The bar and the page load both read this one source of
    /// truth; indexes emitted while the bar fills are the bar's, not the user's.
    property int currentTab: 0

    function selectTab(index: int) {
        if (index < 0 || index >= hubRoot.tabs.length)
            return;
        hubRoot.currentTab = index;
    }

    function syncTabBar() {
        if (!hubRoot.tabBarReady)
            return;
        tabBar.setCurrentIndex(hubRoot.currentTab);
    }

    onTabBarReadyChanged: hubRoot.syncTabBar()

    Timer {
        id: tabActivation
        interval: 16
        onTriggered: hubRoot.tabLoadArmed = true
    }

    function scheduleTab() {
        hubRoot.tabLoadArmed = false;
        tabActivation.restart();
    }

    /// A settings search result knows the file its section was indexed from, not the tab. Map
    /// it back, otherwise every hit on this page would land on whichever tab happened to be open.
    function tabIndexForSource(sourceKey: string): int {
        const name = String(sourceKey ?? "").split("/").pop();
        return hubRoot.tabs.findIndex(tab => tab.file.split("/").pop() === name);
    }

    /// A deep link from elsewhere in the shell names the tab outright, so it does not have to
    /// guess at a translated section title. Any sub-page open at the time is closed: the link
    /// asked for a tab, and landing behind an editor would look like nothing happened.
    function showTab(id: string) {
        if (!id || id === "")
            return;
        const index = hubRoot.tabs.findIndex(tab => tab.id === id);
        if (index < 0)
            return;
        subPageOverlay.close();
        hubRoot.selectTab(index);
    }

    function takePendingTab() {
        hubRoot.showTab(HyprlandGui.takePendingTab());
    }

    function revealSection(title: string) {
        if (!title || title === "")
            return;
        for (const section of Array.from(SearchRegistry.sections ?? [])) {
            if (section.pageId !== "hyprland" || section.title !== title)
                continue;
            const index = hubRoot.tabIndexForSource(section.sourceKey);
            hubRoot.selectTab(index);
            return;
        }
    }

    /// Screenshot capture hides the window without ending the editing session.
    readonly property bool onScreen: GlobalStates.settingsOpen || GlobalStates.settingsSuspendedForScreenshot
    property bool subscribed: false

    function syncSubscription() {
        if (hubRoot.onScreen === hubRoot.subscribed)
            return;
        hubRoot.subscribed = hubRoot.onScreen;
        if (hubRoot.subscribed)
            HyprlandGui.attach();
        else
            HyprlandGui.detach();
    }

    onOnScreenChanged: hubRoot.syncSubscription()

    Component.onCompleted: {
        hubRoot.syncSubscription();
        hubRoot.takePendingTab();
        hubRoot.syncTabBar();
        hubRoot.scheduleTab();
    }
    Component.onDestruction: {
        if (hubRoot.subscribed) {
            hubRoot.subscribed = false;
            HyprlandGui.detach();
        }
    }

    Connections {
        target: SearchRegistry
        function onCurrentSearchChanged() {
            hubRoot.revealSection(SearchRegistry.currentSearch);
        }
    }

    // The page outlives the settings window being hidden, so a second deep link arrives while
    // this is already built and never reaches Component.onCompleted.
    Connections {
        target: HyprlandGui
        function onPendingTabChanged() {
            hubRoot.takePendingTab();
        }
    }

    ColumnLayout {
        id: pageLayout
        anchors.fill: parent
        spacing: 10
        opacity: subPageOverlay.slideProgress

        /// The one thing the old strip said that cannot wait to be asked for: a write that did
        /// not take. Nothing is shown while everything is fine.
        Rectangle {
            Layout.fillWidth: true
            visible: HyprlandGui.lastError !== ""
            implicitHeight: errorRow.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colErrorContainer

            RowLayout {
                id: errorRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 16
                    rightMargin: 16
                }
                spacing: 10

                MaterialSymbol {
                    text: "sync_problem"
                    iconSize: 20
                    color: Appearance.colors.colOnErrorContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: HyprlandGui.lastError.split("\n")[0]
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true
            enabled: !subPageOverlay.isOpen

            onCurrentIndexChanged: {
                if (!hubRoot.tabBarReady)
                    return;
                hubRoot.selectTab(currentIndex);
            }

            Repeater {
                model: hubRoot.tabs.length

                delegate: SecondaryTabButton {
                    required property int index
                    readonly property var tab: hubRoot.tabs[index]
                    buttonText: Translation.tr(tab.name)
                    buttonIcon: tab.icon
                }
            }
        }

        Item {
            id: tabHost

            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                id: tabLoader

                anchors.fill: parent

                readonly property bool armed: hubRoot.tabBarReady && hubRoot.tabLoadArmed
                    && HyprlandGui.ready

                active: armed && hubRoot.currentTab >= 0
                    && hubRoot.currentTab < hubRoot.tabs.length
                asynchronous: true
                source: active
                    ? Qt.resolvedUrl(hubRoot.tabs[hubRoot.currentTab].file) : ""

                onLoaded: hubRoot.pushContentY()
            }

            HyprlandTabPlaceholder {
                anchors.fill: parent
                visible: tabLoader.status !== Loader.Ready
                icon: {
                    const tab = hubRoot.tabs[hubRoot.currentTab];
                    return tab ? tab.icon : "";
                }
                title: {
                    const tab = hubRoot.tabs[hubRoot.currentTab];
                    return Translation.tr(tab ? tab.name : "");
                }
                description: Translation.tr("Just a moment…")
            }
        }
    }

    // ── Remove one hand-written line ──────────────────────────────────────────
    /// Sections ask for this by walking up the parent chain: they are several files deep and a
    /// confirmation has to live where it can cover the window.
    property string dropKey: ""
    property string dropDiff: ""
    property string dropError: ""

    function requestDropInherited(key: string) {
        hubRoot.dropKey = key;
        hubRoot.dropDiff = "";
        hubRoot.dropError = "";
        dropDialog.show = true;
        HyprlandGui.dropInherited(key, true, result => {
            if (hubRoot.dropKey !== key) return;
            hubRoot.dropDiff = result.diff ?? "";
            hubRoot.dropError = result.ok ? "" : (result.error ?? "");
        });
    }

    WindowDialog {
        id: dropDialog
        parent: hubRoot.parent ?? hubRoot
        anchors.fill: parent
        show: false
        backgroundWidth: 620
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            text: Translation.tr("Remove the hand-written line?")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("This page already sets %1, and its block loads after that line, so the line has no effect any more. Removing it changes nothing about how Hyprland behaves. The file is backed up first.").arg(hubRoot.dropKey)
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: dropText.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colSurfaceContainerHigh

            StyledText {
                id: dropText
                anchors.fill: parent
                anchors.margins: 8
                text: hubRoot.dropError !== "" ? hubRoot.dropError
                    : (hubRoot.dropDiff === "" ? Translation.tr("Working out what would change…") : hubRoot.dropDiff)
                font.family: Appearance.font.family.monospace || "monospace"
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: hubRoot.dropError !== "" ? Appearance.colors.colError : Appearance.colors.colOnSurface
                wrapMode: Text.WrapAnywhere
            }
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: dropDialog.show = false
            }
            DialogButton {
                buttonText: Translation.tr("Remove the line")
                enabled: hubRoot.dropDiff !== "" && hubRoot.dropError === ""
                colText: Appearance.colors.colError
                onClicked: {
                    HyprlandGui.dropInherited(hubRoot.dropKey, false, result => {
                        if (!result.ok) hubRoot.dropError = result.error ?? "";
                    });
                    dropDialog.show = false;
                }
            }
        }
    }

    // ── Remove-all confirmation ───────────────────────────────────────────────
    WindowDialog {
        id: removeDialog
        parent: hubRoot.parent ?? hubRoot
        anchors.fill: parent
        show: false
        backgroundWidth: 400
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            text: Translation.tr("Remove every managed setting?")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("The block this page writes is deleted from every file in ~/.config/hypr/custom/. Your own Lua above it is left alone, and each file is backed up first.")
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: removeDialog.show = false
            }
            DialogButton {
                buttonText: Translation.tr("Remove")
                colText: Appearance.colors.colError
                onClicked: {
                    HyprlandGui.stripAll();
                    removeDialog.show = false;
                }
            }
        }
    }

    // ── The corner ────────────────────────────────────────────────────────────
    /// Above the sub-page overlay rather than inside the page, because a rule or a keybind is
    /// edited on a sub-page and there is no sense in having to come back out to save it.
    ///
    /// Three things live here: the menu, and - only once there is something to write - rollback
    /// and save. Everything the old strip said is either in the menu's review page or on the
    /// save button, which counts what it is about to write.
    Item {
        id: fabHost
        parent: hubRoot.parent ?? hubRoot
        anchors.fill: parent
        z: 9999

        RowLayout {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 25
            spacing: 12

            HyprFabMenu {
                Layout.alignment: Qt.AlignBottom
                icon: "code"
                tooltipText: Translation.tr("Review, advanced settings and cleanup")
                scrimParent: fabHost
                actions: [
                    { "icon": "code", "label": Translation.tr("Review") },
                    { "icon": "tune", "label": Translation.tr("Advanced settings"),
                      "checkable": true, "checked": hubRoot.advanced },
                    { "icon": "delete_sweep", "label": Translation.tr("Remove all"), "danger": true }
                ]
                onTriggered: index => {
                    if (index === 0) hubRoot.activeSubPage = Qt.resolvedUrl("hyprland/HyprReviewPage.qml");
                    else if (index === 1) Config.options.hyprland.advancedSettings = !hubRoot.advanced;
                    else removeDialog.show = true;
                }
            }

            FadeLoader {
                Layout.alignment: Qt.AlignBottom
                shown: HyprlandGui.dirty

                sourceComponent: RowLayout {
                    spacing: 12

                    FloatingActionButton {
                        iconText: "history"
                        buttonText: Translation.tr("Rollback")
                        expanded: hovered
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        colOnBackground: Appearance.colors.colOnSurface
                        onClicked: HyprlandGui.rollback()

                        StyledToolTip {
                            text: Translation.tr("Forget the changes above and go back to what the files say")
                        }
                    }

                    FloatingActionButton {
                        iconText: "save"
                        // The count is the whole of what the strip's "N change(s) staged" line
                        // used to say, in the one place it is already being looked at.
                        buttonText: Translation.tr("Save %1 change(s)").arg(Math.max(1, HyprlandGui.pending.count))
                        expanded: hovered
                        enabled: !HyprlandGui.busy
                        onClicked: HyprlandGui.save()

                        StyledToolTip {
                            text: Translation.tr("Write the changes to ~/.config/hypr/custom/ and reload Hyprland")
                        }
                    }
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
