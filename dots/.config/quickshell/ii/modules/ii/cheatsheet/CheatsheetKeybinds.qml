pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.overview.typing
import "../../common/functions/KeyboardMap.js" as KeyboardMap

/**
 * Multipage shortcut library.
 *
 * The generated Hyprland page remains read-only. Personal pages are selected
 * from the rail and delegated to CheatsheetCustomKeybindsPage, whose writes all
 * pass through KeybindsService.
 */
Item {
    id: root

    property Item keyNavTarget: null
    readonly property bool isCurrentTab: {
        try {
            return swipeView.currentIndex === index;
        } catch (error) {
            return true;
        }
    }
    readonly property bool isTabActive: root.visible && root.isCurrentTab
    property string selectedPageId: Persistent.states.cheatsheet.keybindPageId
    property string displayedPageId: Persistent.states.cheatsheet.keybindPageId
    property string toastMessage: ""
    property bool toastError: false
    property bool keyboardDetectionRequested: false
    readonly property bool sidebarVisible: Persistent.states.cheatsheet.keybindSidebarVisible
    readonly property real sidebarWidth: Math.max(230, Math.min(280, root.width * 0.18))
    readonly property bool pageFormShowing: pageForm.isOpen || pageForm.isAnimating
    readonly property bool lookupReady: contentLoader.status === Loader.Ready
    readonly property bool hyprlandSelected: root.displayedPageId === "" || !KeybindsService.ready
    readonly property var activeAppPage: {
        const toplevel = ToplevelManager.activeToplevel;
        if (!toplevel || !KeybindsService.ready)
            return null;
        const appId = String(toplevel.appId ?? "").toLowerCase().trim();
        const title = String(toplevel.title ?? "").toLowerCase().trim();
        for (const page of KeybindsService.pages ?? []) {
            if (page.kind === "keyboard") continue;
            const pageApp = String(page.programId || page.program || page.name).toLowerCase().trim();
            if (pageApp && (appId.includes(pageApp) || pageApp.includes(appId) || title.includes(pageApp)))
                return page;
        }
        return null;
    }
    readonly property var appPages: {
        const revision = KeybindsService.revision;
        return (KeybindsService.pages ?? []).filter(page => page.kind !== "keyboard" && Boolean(page.program || page.programId || (page.sourceKind && page.sourceKind !== "manual")));
    }
    readonly property var personalPages: {
        const revision = KeybindsService.revision;
        return (KeybindsService.pages ?? []).filter(page => page.kind !== "keyboard" && !page.program && !page.programId && (!page.sourceKind || page.sourceKind === "manual"));
    }
    readonly property var keyboardPages: {
        const revision = KeybindsService.revision;
        return (KeybindsService.pages ?? []).filter(page => page.kind === "keyboard");
    }
    function createKeyboard(): void {
        KeybindsService.createKeyboardPage(KeyboardMap.manual(TypingKeyboardLayouts.rowsFor("qwerty"), "qwerty"));
    }

    Connections {
        target: VialKeyboard
        function onReadFinished(success) {
            if (!root.keyboardDetectionRequested) return;
            root.keyboardDetectionRequested = false;
            KeybindsService.importKeyboardSnapshot(success ? VialKeyboard.snapshot : null);
        }
    }

    readonly property int personalShortcutCount: {
        const revision = KeybindsService.revision;
        return KeybindsService.pages.reduce((total, page) => total + (page.keybinds ?? []).length, 0);
    }
    readonly property int hyprlandShortcutCount: {
        const defaults = HyprlandKeybinds.defaultKeybinds?.children ?? [];
        const users = HyprlandKeybinds.userKeybinds?.children ?? [];
        function count(nodes) {
            let total = 0;
            for (const node of nodes ?? []) {
                total += (node.keybinds ?? []).length;
                total += count(node.children ?? []);
            }
            return total;
        }
        return count(defaults) + count(users);
    }
    readonly property int totalShortcutCount: root.personalShortcutCount + root.hyprlandShortcutCount
    readonly property var selectedPage: {
        const revision = KeybindsService.revision;
        return root.hyprlandSelected ? null : KeybindsService.pageById(root.displayedPageId);
    }

    readonly property var orderedPages: root.appPages.concat(root.keyboardPages, root.personalPages)

    KeybindPageNavigation {
        enabled: root.isTabActive && KeybindsService.ready && !root.pageFormShowing
            && !(contentLoader.item?.navigationLocked ?? false)
        groups: [[""], root.appPages.map(page => page.id), root.keyboardPages.map(page => page.id), root.personalPages.map(page => page.id)]
        currentPageId: root.selectedPageId
        onPageRequested: pageId => root.selectPage(pageId)
    }

    function focusSelectedPage(): void {
        if (root.isTabActive && !root.pageFormShowing && contentLoader.item)
            contentLoader.item.forceActiveFocus();
    }

    function selectPage(pageId): void {
        const next = String(pageId ?? "");
        if (next && !KeybindsService.pageById(next)) return;
        if (next === root.selectedPageId && next === root.displayedPageId) return;
        // Update immediately. Repeated key presses never queue exit animations.
        root.selectedPageId = next;
        root.displayedPageId = next;
        Persistent.states.cheatsheet.keybindPageId = next;
        Qt.callLater(root.focusSelectedPage);
        if (!root.sidebarVisible)
            collapsedPagesList.positionViewAtIndex(root.orderedPages.findIndex(page => page.id === next), ListView.Contain);
    }

    function ensureValidSelection(): void {
        if (!KeybindsService.ready)
            return;
        if (root.selectedPageId && !KeybindsService.pageById(root.selectedPageId))
            root.selectPage("");
    }

    function showToast(message, error): void {
        root.toastMessage = String(message ?? "");
        root.toastError = Boolean(error);
        if (root.toastMessage)
            toastTimer.restart();
    }

    function setSidebarVisible(visible): void {
        Persistent.states.cheatsheet.keybindSidebarVisible = Boolean(visible);
    }

    function pageSubtitle(page): string {
        const program = String(page?.program ?? "").trim();
        const sourceKind = String(page?.sourceKind ?? "");
        if (program && program !== String(page?.name ?? ""))
            return program;
        if (sourceKind === "template") return Translation.tr("Starter collection");
        if (sourceKind === "json") return Translation.tr("Imported collection");
        if (sourceKind === "neovim-static") return Translation.tr("Local config · partial");
        if (sourceKind === "vscode" || sourceKind === "jetbrains") return Translation.tr("Local config");
        return Translation.tr("Personal collection");
    }

    function pageProgramIcon(program, programId = ""): string {
        const wanted = String(program ?? "").trim();
        const wantedId = String(programId ?? "").trim();
        if (!wanted && !wantedId)
            return "";
        const normalized = wanted.toLowerCase();
        const normalizedId = wantedId.toLowerCase();
        for (const app of AppSearch.list ?? []) {
            if ((normalizedId && String(app?.id ?? "").trim().toLowerCase() === normalizedId)
                    || (normalized && String(app?.name ?? "").trim().toLowerCase() === normalized)
                    || (normalized && String(app?.id ?? "").trim().toLowerCase() === normalized)) {
                let icon = String(app?.icon ?? "").trim();
                if (icon && icon !== "image-missing" && icon !== "application-x-executable" && AppSearch.iconExists(icon))
                    return icon;
                icon = AppSearch.guessIcon(wantedId || wanted);
                if (!icon || icon === "image-missing" || icon === "application-x-executable" || !AppSearch.iconExists(icon))
                    return "";
                return icon;
            }
        }
        const guessed = AppSearch.guessIcon(wantedId || wanted);
        if (!guessed || guessed === "image-missing" || guessed === "application-x-executable")
            return "";
        return AppSearch.iconExists(guessed) ? guessed : "";
    }

    onFocusChanged: {
        if (focus && contentLoader.item)
            contentLoader.item.forceActiveFocus();
    }

    Component.onCompleted: root.ensureValidSelection()

    Connections {
        target: KeybindsService

        function onPagesChanged() {
            root.ensureValidSelection();
        }

        function onReadyChanged() {
            root.ensureValidSelection();
        }

        function onOperationFinished(success, message, pageId) {
            root.showToast(message, !success);
            if (success && pageId)
                root.selectPage(pageId);
        }
    }

    Timer {
        id: toastTimer
        interval: 3200
        repeat: false
        onTriggered: root.toastMessage = ""
    }

    component PageButton: RippleButton {
        id: pageButton
        required property string pageId
        required property string pageName
        required property string pageIcon
        required property int shortcutCount
        property string pageSubtitle: ""
        property string countLabel: Translation.tr("shortcuts")
        property string pageProgram: ""
        property string pageProgramId: ""
        property bool pageUseProgramIcon: false
        readonly property string resolvedProgramIcon: pageUseProgramIcon
            ? root.pageProgramIcon(pageProgram, pageProgramId)
            : ""
        property bool pageSelected: root.selectedPageId === pageId
        property bool revealSelection: true
        onPageSelectedChanged: {
            if (!pageSelected || !revealSelection) return;
            Qt.callLater(() => {
                if (!root.sidebarVisible || !pageButton.visible) return;
                const top = pageButton.mapToItem(railContentColumn, 0, 0).y;
                const bottom = top + pageButton.height;
                if (top < railFlickable.contentY) railFlickable.contentY = top;
                else if (bottom > railFlickable.contentY + railFlickable.height)
                    railFlickable.contentY = Math.min(bottom - railFlickable.height, Math.max(0, railFlickable.contentHeight - railFlickable.height));
            });
        }

        Layout.fillWidth: true
        implicitHeight: 62
        // Keep the rail item inside its clipped surface; tonal hover is the
        // affordance, so a transform scale is unnecessary and clips corners.
        scale: 1
        buttonRadius: Appearance.rounding.large
        toggled: pageSelected
        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHighest, 1)
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
        Accessible.name: pageButton.pageName + ", " + String(pageButton.shortcutCount) + " " + pageButton.countLabel
        onClicked: root.selectPage(pageId)

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 10

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 36
                implicitHeight: 36

                Loader {
                    anchors.fill: parent
                    active: pageButton.resolvedProgramIcon.length > 0
                    visible: active
                    sourceComponent: IconImage {
                        source: Quickshell.iconPath(pageButton.resolvedProgramIcon, "image-missing")
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: pageButton.resolvedProgramIcon.length === 0
                    text: pageButton.pageIcon || "keyboard"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: pageButton.pageSelected ? 1 : 0
                    color: pageButton.pageSelected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: pageButton.pageName
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: pageButton.pageSelected ? Font.Bold : Font.Medium
                    color: pageButton.pageSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Boolean(pageButton.pageSubtitle)
                    text: pageButton.pageSubtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: pageButton.pageSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                    opacity: 0.78

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            Row {
                id: pageCountRow
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "keyboard"
                    iconSize: Appearance.font.pixelSize.small
                    color: pageButton.pageSelected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(pageButton.shortcutCount)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: pageButton.pageSelected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }

    component RailSectionHeader: RowLayout {
        id: sectionHeader
        property string symbol: ""
        property string label: ""
        property int count: -1

        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 6
        Layout.topMargin: 4
        spacing: 7

        MaterialSymbol {
            text: sectionHeader.symbol
            iconSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: sectionHeader.label.toUpperCase()
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            visible: sectionHeader.count >= 0
            text: String(sectionHeader.count)
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colPrimary
        }
    }

    component CollapsedPageButton: RippleButton {
        id: collapsedPageButton
        required property string pageId
        required property string pageName
        required property string pageIcon
        property string pageProgram: ""
        property string pageProgramId: ""
        property bool pageUseProgramIcon: false
        readonly property string resolvedProgramIcon: pageUseProgramIcon
            ? root.pageProgramIcon(pageProgram, pageProgramId)
            : ""
        property bool pageSelected: root.selectedPageId === pageId

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 42
        implicitHeight: 42
        scale: 1
        buttonRadius: Appearance.rounding.full
        toggled: pageSelected
        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
        Accessible.name: collapsedPageButton.pageName
        onClicked: root.selectPage(pageId)

        contentItem: Item {
            anchors.fill: parent

            Loader {
                anchors.fill: parent
                active: collapsedPageButton.resolvedProgramIcon.length > 0
                visible: active
                sourceComponent: IconImage {
                    source: Quickshell.iconPath(collapsedPageButton.resolvedProgramIcon, "image-missing")
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: collapsedPageButton.resolvedProgramIcon.length === 0
                text: collapsedPageButton.pageIcon || "keyboard"
                iconSize: Appearance.font.pixelSize.larger
                fill: collapsedPageButton.pageSelected ? 1 : 0
                color: collapsedPageButton.pageSelected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        StyledToolTip {
            text: collapsedPageButton.pageName
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
    }

    Item {
        id: libraryContent
        anchors.fill: parent
        opacity: root.pageFormShowing ? 0 : 1
        enabled: !root.pageFormShowing

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

        Rectangle {
            id: pageRail
            Layout.fillHeight: true
            Layout.preferredWidth: root.sidebarVisible ? root.sidebarWidth : 0
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerHigh
            clip: true

            Behavior on Layout.preferredWidth {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(pageRail)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 2
                    Layout.topMargin: 4
                    spacing: 10

                    MaterialShape {
                        implicitSize: 44
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "library_books"
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Shortcut library")
                            elide: Text.ElideRight
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("%1 pages · %2 shortcuts")
                                .arg(String(KeybindsService.pages.length + 1))
                                .arg(String(root.totalShortcutCount))
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    RippleButton {
                        implicitWidth: 38
                        implicitHeight: 38
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        Accessible.name: Translation.tr("Hide pages")
                        onClicked: root.setSidebarVisible(false)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "view_sidebar"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        StyledToolTip { text: Translation.tr("Hide pages") }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("↑ / ↓  Pages · Ctrl + ↑ / ↓  Groups")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.Wrap
                }

                StyledFlickable {
                    id: railFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: railContentColumn.implicitHeight + 6

                    ColumnLayout {
                        id: railContentColumn
                        width: railFlickable.width
                        spacing: 6

                        ColumnLayout {
                            visible: root.activeAppPage !== null
                            Layout.fillWidth: true
                            spacing: 4

                            RailSectionHeader {
                                symbol: "bolt"
                                label: Translation.tr("Now (in focus)")
                            }

                            PageButton {
                                revealSelection: false
                                visible: root.activeAppPage !== null
                                pageId: String(root.activeAppPage?.id ?? "")
                                pageName: String(root.activeAppPage?.name ?? Translation.tr("Active App"))
                                pageIcon: String(root.activeAppPage?.icon ?? "keyboard")
                                pageProgram: String(root.activeAppPage?.program ?? "")
                                pageProgramId: String(root.activeAppPage?.programId ?? "")
                                pageUseProgramIcon: Boolean(root.activeAppPage?.useProgramIcon)
                                shortcutCount: (root.activeAppPage?.keybinds ?? []).length
                                pageSubtitle: Translation.tr("Active application")
                            }
                        }

                        RailSectionHeader {
                            symbol: "computer"
                            label: Translation.tr("System")
                        }

                        PageButton {
                            pageId: ""
                            pageName: Translation.tr("Hyprland")
                            pageIcon: "desktop_windows"
                            pageSubtitle: Translation.tr("Generated keymap · read only")
                            shortcutCount: root.hyprlandShortcutCount
                        }

                        ColumnLayout {
                            visible: root.appPages.length > 0
                            Layout.fillWidth: true
                            spacing: 4

                            RailSectionHeader {
                                symbol: "apps"
                                label: Translation.tr("Applications")
                                count: root.appPages.length
                            }

                            Repeater {
                                model: root.appPages

                                delegate: PageButton {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    pageId: String(modelData.id ?? "")
                                    pageName: String(modelData.name ?? Translation.tr("Shortcuts"))
                                    pageIcon: String(modelData.icon ?? "keyboard")
                                    pageProgram: String(modelData.program ?? "")
                                    pageProgramId: String(modelData.programId ?? "")
                                    pageUseProgramIcon: Boolean(modelData.useProgramIcon)
                                    shortcutCount: (modelData.keybinds ?? []).length
                                    pageSubtitle: root.pageSubtitle(modelData)
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RailSectionHeader {
                                symbol: "keyboard"
                                label: Translation.tr("Keyboards")
                                count: root.keyboardPages.length
                            }
                            Repeater {
                                model: root.keyboardPages
                                delegate: PageButton {
                                    required property var modelData
                                    pageId: modelData.id
                                    pageName: modelData.name
                                    pageIcon: "keyboard"
                                    pageSubtitle: Translation.tr("%1 layers").arg(String(modelData.keyboard.layers.length))
                                    shortcutCount: modelData.keyboard.keys.length
                                    countLabel: Translation.tr("keys")
                                }
                            }
                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                materialIcon: "language"
                                mainText: KeybindsService.detectingSystemKeyboard ? Translation.tr("Reading…") : Translation.tr("Detect layout")
                                buttonRadius: Appearance.rounding.full
                                enabled: KeybindsService.ready && KeybindsService.writable && !KeybindsService.detectingSystemKeyboard
                                onClicked: KeybindsService.detectSystemKeyboard()
                            }
                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                materialIcon: "usb"
                                mainText: VialKeyboard.loading ? Translation.tr("Reading…") : Translation.tr("Detect Vial")
                                buttonRadius: Appearance.rounding.full
                                enabled: KeybindsService.ready && KeybindsService.writable && !VialKeyboard.loading
                                onClicked: {
                                    root.keyboardDetectionRequested = true;
                                    VialKeyboard.refresh();
                                }
                            }
                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                materialIcon: "add"
                                mainText: Translation.tr("New keyboard")
                                buttonRadius: Appearance.rounding.full
                                enabled: KeybindsService.ready && KeybindsService.writable
                                onClicked: root.createKeyboard()
                            }
                        }

                        ColumnLayout {
                            visible: root.personalPages.length > 0 || KeybindsService.pages.length === 0
                            Layout.fillWidth: true
                            spacing: 4

                            RailSectionHeader {
                                symbol: "person"
                                label: Translation.tr("Your collection")
                                count: root.personalPages.length
                            }

                            Repeater {
                                model: root.personalPages

                                delegate: PageButton {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    pageId: String(modelData.id ?? "")
                                    pageName: String(modelData.name ?? Translation.tr("Shortcuts"))
                                    pageIcon: String(modelData.icon ?? "keyboard")
                                    pageProgram: String(modelData.program ?? "")
                                    pageProgramId: String(modelData.programId ?? "")
                                    pageUseProgramIcon: Boolean(modelData.useProgramIcon)
                                    shortcutCount: (modelData.keybinds ?? []).length
                                    pageSubtitle: root.pageSubtitle(modelData)
                                }
                            }

                            PagePlaceholder {
                                shown: KeybindsService.ready && KeybindsService.pages.length === 0
                                icon: "book_2"
                                title: Translation.tr("Your pages live here")
                                description: Translation.tr("Start blank, use a template, or import an app.")
                                Layout.fillWidth: true
                                Layout.topMargin: 24
                                Layout.bottomMargin: 12
                                Layout.preferredHeight: 160
                                titlePixelSize: Appearance.font.pixelSize.normal
                                descriptionPixelSize: Appearance.font.pixelSize.smallest
                                animateIconOnShow: false
                            }
                        }
                    }
                }

                Rectangle {
                    visible: Boolean(KeybindsService.lastError)
                    Layout.fillWidth: true
                    implicitHeight: storageErrorRow.implicitHeight + 16
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colErrorContainer

                    RowLayout {
                        id: storageErrorRow
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        MaterialSymbol {
                            text: "error"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnErrorContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: KeybindsService.lastError
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 44
                        centerContent: true
                        buttonRadius: Appearance.rounding.full
                        materialIcon: "upload_file"
                        mainText: Translation.tr("Import")
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colText: Appearance.colors.colOnSecondaryContainer
                        enabled: KeybindsService.ready && KeybindsService.writable
                        onClicked: KeybindsService.openImportDialog()
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1.35
                        implicitHeight: 44
                        centerContent: true
                        buttonRadius: Appearance.rounding.full
                        materialIcon: "add"
                        mainText: Translation.tr("New page")
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colBackgroundActive: Appearance.colors.colPrimaryActive
                        colText: Appearance.colors.colOnPrimary
                        enabled: KeybindsService.ready && KeybindsService.writable
                        onClicked: pageForm.openCreate()
                    }
                }
            }
        }

        Item {
            id: collapsedRailSlot
            Layout.fillHeight: true
            Layout.preferredWidth: root.sidebarVisible ? 0 : 44
            visible: Layout.preferredWidth > 1
            clip: true

            Behavior on Layout.preferredWidth {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(collapsedRailSlot)
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    Accessible.name: Translation.tr("Show pages")
                    onClicked: root.setSidebarVisible(true)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "view_sidebar"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip { text: Translation.tr("Show pages") }
                }

                CollapsedPageButton {
                    pageId: ""
                    pageName: Translation.tr("Hyprland")
                    pageIcon: "desktop_windows"
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colLayer2
                }

                StyledListView {
                    id: collapsedPagesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.orderedPages

                    delegate: CollapsedPageButton {
                        required property var modelData
                        width: collapsedPagesList.width
                        pageId: String(modelData.id ?? "")
                        pageName: String(modelData.name ?? Translation.tr("Shortcuts"))
                        pageIcon: String(modelData.icon ?? "keyboard")
                        pageProgram: String(modelData.program ?? "")
                        pageProgramId: String(modelData.programId ?? "")
                        pageUseProgramIcon: Boolean(modelData.useProgramIcon)
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 4
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    Accessible.name: Translation.tr("New page")
                    enabled: KeybindsService.ready && KeybindsService.writable
                    onClicked: pageForm.openCreate()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnPrimary
                    }

                    StyledToolTip { text: Translation.tr("New page") }
                }
            }
        }

        Loader {
            id: contentLoader
            // Avoid constructing a transient Hyprland page before saved maps load.
            active: KeybindsService.ready
            Layout.fillWidth: true
            Layout.fillHeight: true
            asynchronous: true
            onLoaded: Qt.callLater(root.focusSelectedPage)
            sourceComponent: root.hyprlandSelected ? hyprlandPage : root.selectedPage?.kind === "keyboard" ? keyboardPage : customPage

        }
        }
    }

    Component {
        id: hyprlandPage
        CheatsheetHyprlandKeybinds {
            keyNavTarget: root.keyNavTarget
            tabActive: root.isTabActive
        }
    }

    Component {
        id: keyboardPage
        CheatsheetKeyboardPage {
            pageId: root.displayedPageId
            keyNavTarget: root.keyNavTarget
            tabActive: root.isTabActive && !root.pageFormShowing
        }
    }

    Component {
        id: customPage
        CheatsheetCustomKeybindsPage {
            pageId: root.displayedPageId
            keyNavTarget: root.keyNavTarget
            tabActive: root.isTabActive
            onRequestEditPage: pageForm.openEdit(root.displayedPageId)
        }
    }

    Loader {
        id: pageForm
        anchors.fill: parent
        z: 20
        active: false
        readonly property bool isOpen: item?.isOpen ?? false
        readonly property bool isAnimating: item?.isAnimating ?? false
        function ensureForm() {
            if (!item) {
                active = true;
                setSource(Qt.resolvedUrl("CheatsheetKeybindsPageForm.qml"));
            }
            return item;
        }
        function openCreate() { ensureForm()?.openCreate(); }
        function openEdit(pageId) { ensureForm()?.openEdit(pageId); }
        function releaseClosedForm() {
            if (!isOpen && !isAnimating) active = false;
        }
        Connections {
            target: pageForm.item
            function onPageChosen(pageId) { root.selectPage(pageId); }
            function onCloseRequested() { Qt.callLater(pageForm.releaseClosedForm); }
        }
    }

    Rectangle {
        z: 40
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        implicitWidth: Math.min(root.width - 48, toastRow.implicitWidth + 28)
        implicitHeight: toastRow.implicitHeight + 18
        radius: Appearance.rounding.full
        color: root.toastError ? Appearance.colors.colErrorContainer : Appearance.colors.colTertiaryContainer
        visible: opacity > 0
        opacity: root.toastMessage ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            id: toastRow
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                text: root.toastError ? "error" : "check_circle"
                iconSize: Appearance.font.pixelSize.normal
                color: root.toastError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnTertiaryContainer
            }

            StyledText {
                text: root.toastMessage
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.toastError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnTertiaryContainer
            }
        }
    }
}
