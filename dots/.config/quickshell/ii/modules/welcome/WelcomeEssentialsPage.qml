import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    signal openSettingsTarget(string pageId, string subPageId, string sectionId)

    property string nestedPageId: ""
    property bool nestedTransitionRunning: false
    property bool nestedTransitionReady: false
    // Do not hide the global navigation while the nested Loader is still
    // incubating. A failed or long-running page must not strand the user on
    // the catalog with the bottom navigation removed.
    readonly property bool nestedPageRequested: root.nestedPageId.length > 0
        || root.nestedTransitionRunning
    readonly property bool nestedPageOpen: root.nestedPageId.length > 0
        && (!root.nestedTransitionRunning || root.nestedTransitionReady)
    readonly property bool nestedBlurEnabled: true

    function nestedOffset(): real {
        return WelcomeMotion.offsetFor(root.width);
    }

    function prepareCatalog(): void {
        catalogLayer.visible = true;
        catalogLayer.x = 0;
        catalogLayer.opacity = 1;
        catalogLayer.visualBlur = 0;
        catalogLayer.scale = 1;
    }

    function prepareNestedPage(): void {
        nestedLayer.visible = true;
        nestedLayer.x = root.nestedPageRequested ? nestedOffset() : 0;
        nestedLayer.opacity = root.nestedPageRequested ? WelcomeMotion.pageOpacityIn : 1;
        nestedLayer.visualBlur = 0;
        nestedLayer.scale = root.nestedPageRequested ? WelcomeMotion.pageScale : 1;
    }

    function startNestedPageOpen(): void {
        if (!root.nestedPageOpen || !root.nestedTransitionReady)
            return;
        if (openNestedPageAnimation.running)
            return;

        // Hide the catalog as soon as the nested page is ready. The animation
        // is visual only; it must never decide whether two page trees can be
        // visible at the same time.
        catalogLayer.visible = false;
        nestedLayer.visualBlur = WelcomeMotion.blurProgress;
        if (!WelcomeMotion.motionEnabled) {
            nestedLayer.x = 0;
            nestedLayer.opacity = 1;
            nestedLayer.visualBlur = 0;
            nestedLayer.scale = 1;
            root.nestedTransitionRunning = false;
            return;
        }
        openNestedPageAnimation.start();
    }

    function openNestedPage(pageId: string): void {
        if (root.nestedPageOpen || root.nestedTransitionRunning)
            return;
        if (pageId !== "keyboard" && pageId !== "languageTime")
            return;

        openNestedPageAnimation.stop();
        closeNestedPageAnimation.stop();
        root.nestedTransitionRunning = true;
        root.nestedTransitionReady = false;
        // Set the lifecycle state before changing the source key. The
        // Language & Time Loader is synchronous, so changing the key first
        // can emit Ready before the host is marked as transitioning.
        root.nestedPageId = pageId;
        prepareCatalog();
        prepareNestedPage();

        // Cover the case where a synchronous Loader reaches Ready before its
        // status signal is observed by this host.
        Qt.callLater(() => {
            if (root.nestedTransitionRunning && nestedLoader.status === Loader.Ready)
                root.markNestedPageReady();
        });
    }

    function markNestedPageReady(): void {
        if (!root.nestedTransitionRunning || root.nestedTransitionReady)
            return;
        root.nestedTransitionReady = true;
        // Let the source-change binding finish before touching the animation
        // targets. This also covers synchronous Loader status notifications.
        Qt.callLater(() => {
            if (root.nestedTransitionRunning && root.nestedTransitionReady)
                root.startNestedPageOpen();
        });
    }

    function finishNestedPageClose(): void {
        nestedLayer.visible = false;
        root.nestedPageId = "";
        root.nestedTransitionReady = false;
        root.nestedTransitionRunning = false;
        prepareCatalog();
    }

    function cancelNestedPageOpen(): void {
        openNestedPageAnimation.stop();
        closeNestedPageAnimation.stop();
        nestedLayer.visible = false;
        root.nestedPageId = "";
        root.nestedTransitionReady = false;
        root.nestedTransitionRunning = false;
        prepareCatalog();
    }

    function closeNestedPage(): bool {
        if (root.nestedPageId.length === 0 && !root.nestedTransitionRunning)
            return false;

        if (root.nestedTransitionRunning && !root.nestedTransitionReady) {
            root.cancelNestedPageOpen();
            return true;
        }

        if (root.nestedTransitionRunning)
            return false;

        const nestedPage = nestedLoader.item;
        if (nestedPage && nestedPage.closeNestedPage && nestedPage.closeNestedPage())
            return true;

        openNestedPageAnimation.stop();
        closeNestedPageAnimation.stop();
        root.nestedTransitionRunning = true;
        root.nestedTransitionReady = true;
        prepareCatalog();
        catalogLayer.x = -nestedOffset();
        catalogLayer.opacity = WelcomeMotion.pageOpacityOut;
        catalogLayer.visualBlur = WelcomeMotion.blurProgress;
        catalogLayer.scale = WelcomeMotion.pageScale;
        nestedLayer.visible = true;
        nestedLayer.x = 0;
        nestedLayer.opacity = 1;
        nestedLayer.visualBlur = 0;
        nestedLayer.scale = 1;
        if (!WelcomeMotion.motionEnabled) {
            root.finishNestedPageClose();
            return true;
        }
        closeNestedPageAnimation.start();
        return true;
    }

    Item {
        id: catalogLayer
        anchors.fill: parent
        clip: true

        property real visualBlur: 0
        layer.enabled: visualBlur > 0.01 && WelcomeMotion.blurAllowed && root.nestedBlurEnabled
        layer.effect: MultiEffect {
            blurEnabled: catalogLayer.visualBlur > 0.01
                && WelcomeMotion.blurAllowed
                && root.nestedBlurEnabled
            blurMax: WelcomeMotion.blurMax
            blur: catalogLayer.visualBlur
        }

        Flickable {
            id: essentialsFlickable
            anchors.fill: parent
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + Appearance.rounding.normal
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: Appearance.rounding.normal

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Configure the essentials")
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.weight: Font.Bold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.rounding.small

                    WelcomeActionCard {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        materialIcon: "keyboard"
                        title: Translation.tr("Keyboard layout")
                        description: Translation.tr("Add layouts, variants and switch between them")
                        statusText: HyprlandXkb.currentLayoutCode.length > 0
                            ? Translation.tr("Current: %1").arg(HyprlandXkb.currentLayoutCode)
                            : Translation.tr("Configure in Hyprland")
                        onClicked: root.openNestedPage("keyboard")
                    }

                    WelcomeActionCard {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        materialIcon: "language"
                        title: Translation.tr("Language & Time")
                        description: Translation.tr("Set interface language, clock and date formats")
                        statusText: Config.options.language.ui === "auto"
                            ? Translation.tr("Using system language")
                            : Config.options.language.ui
                        onClicked: root.openNestedPage("languageTime")
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Explore")
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.weight: Font.Bold
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.rounding.unsharpenmore
                    Layout.rightMargin: Appearance.rounding.unsharpenmore
                    columns: width >= 780 ? 2 : 1
                    columnSpacing: Appearance.rounding.small
                    rowSpacing: Appearance.rounding.small

                    Repeater {
                        model: WelcomeKeybindRegistry.exploreActions

                        delegate: WelcomeKeybindCard {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            title: Translation.tr(modelData.labelKey)
                            materialIcon: modelData.icon
                            keys: WelcomeKeybindRegistry.keysFor(modelData.id)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.rounding.small

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Need help later?")
                        color: Appearance.colors.colOnLayer1
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.weight: Font.Bold
                    }

                    StyledText {
                        text: Translation.tr("Four useful places")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.rounding.unsharpenmore
                    Layout.rightMargin: Appearance.rounding.unsharpenmore
                    columns: width >= 780 ? 4 : 2
                    columnSpacing: Appearance.rounding.small
                    rowSpacing: Appearance.rounding.small

                    WelcomeActionCard {
                        Layout.fillWidth: true
                        materialIcon: "menu_book"
                        title: Translation.tr("Cheatsheet")
                        description: Translation.tr("All shortcuts and shell actions")
                        onClicked: root.openSettingsTarget("cheatSheet", "", "keyboard")
                    }

                    WelcomeActionCard {
                        Layout.fillWidth: true
                        materialIcon: "description"
                        title: Translation.tr("Documentation")
                        description: Translation.tr("Setup guides and feature documentation")
                        onClicked: Qt.openUrlExternally(WelcomeProjectLinks.documentationUrl)
                    }

                    WelcomeActionCard {
                        Layout.fillWidth: true
                        materialIcon: "code"
                        title: Translation.tr("GitHub")
                        description: Translation.tr("Source code, releases and issues")
                        onClicked: Qt.openUrlExternally(WelcomeProjectLinks.repositoryUrl)
                    }

                    WelcomeActionCard {
                        Layout.fillWidth: true
                        materialIcon: "forum"
                        title: Translation.tr("Discord")
                        description: Translation.tr("Community and support")
                        onClicked: Qt.openUrlExternally(WelcomeProjectLinks.discordUrl)
                    }
                }
            }

            TouchpadScrollHandler {
                flickable: essentialsFlickable
            }
        }
    }

    Item {
        id: nestedLayer
        anchors.fill: parent
        visible: false
        clip: true

        property real visualBlur: 0
        layer.enabled: visualBlur > 0.01 && WelcomeMotion.blurAllowed && root.nestedBlurEnabled
        layer.effect: MultiEffect {
            blurEnabled: nestedLayer.visualBlur > 0.01
                && WelcomeMotion.blurAllowed
                && root.nestedBlurEnabled
            blurMax: WelcomeMotion.blurMax
            blur: nestedLayer.visualBlur
        }

        Loader {
            id: nestedLoader
            anchors.fill: parent
            active: root.nestedPageRequested || closeNestedPageAnimation.running
            // The compact Language & Time page has no backend work to wait for.
            // Keep it synchronous so an empty loading state cannot be exposed
            // during the nested transition; the keyboard editor may still
            // incubate its Hyprland-backed tree asynchronously.
            asynchronous: root.nestedPageId === "keyboard"
            source: root.nestedPageId === "keyboard"
                ? Qt.resolvedUrl("WelcomeKeyboardLayoutPage.qml")
                : root.nestedPageId === "languageTime"
                    ? Qt.resolvedUrl("WelcomeLanguageTimePage.qml")
                    : ""

            onStatusChanged: {
                if (status === Loader.Ready) {
                    root.markNestedPageReady();
                } else if (status === Loader.Error) {
                    console.warn("[Welcome] Could not load nested page:", source);
                    root.cancelNestedPageOpen();
                }
            }

            onLoaded: root.markNestedPageReady()

            Connections {
                target: nestedLoader.item
                ignoreUnknownSignals: true

                function onBackRequested() {
                    root.closeNestedPage();
                }
            }
        }
    }

    ParallelAnimation {
        id: openNestedPageAnimation

        NumberAnimation {
            target: catalogLayer
            property: "x"
            to: -root.nestedOffset()
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: catalogLayer
            property: "opacity"
            to: WelcomeMotion.pageOpacityOut
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: catalogLayer
            property: "visualBlur"
            to: WelcomeMotion.blurProgress
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: nestedLayer
            property: "x"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: nestedLayer
            property: "opacity"
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: nestedLayer
            property: "visualBlur"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        onFinished: {
            catalogLayer.visible = false;
            root.nestedTransitionRunning = false;
        }
    }

    ParallelAnimation {
        id: closeNestedPageAnimation

        NumberAnimation {
            target: catalogLayer
            property: "x"
            to: 0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: catalogLayer
            property: "opacity"
            to: 1
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: catalogLayer
            property: "visualBlur"
            to: 0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: nestedLayer
            property: "x"
            to: root.nestedOffset()
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: nestedLayer
            property: "opacity"
            to: 0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: nestedLayer
            property: "visualBlur"
            to: WelcomeMotion.blurProgress
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        onFinished: root.finishNestedPageClose()
    }
}
