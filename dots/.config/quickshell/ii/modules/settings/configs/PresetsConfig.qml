import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.configs.presets

Item {
    id: presetsConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    // 0 the presets on this machine · 1 what other people published · 2 yours
    property alias currentTab: tabBar.currentIndex

    function restoreSubPage(name) {
        const index = name === "store" ? 1 : name === "published" ? 2 : name === "mine" ? 0 : -1;
        if (index < 0)
            return false;
        tabBar.currentIndex = index;
        return true;
    }

    property var _pendingSubPageInit: null

    function openPublish(name) {
        _pendingSubPageInit = (item) => {
            if (item && item.setPreset)
                item.setPreset(name);
        };
        subPageOverlay.open(Qt.resolvedUrl("presets/PublishSubPage.qml"));
        if (subPageOverlay.subPageItem && subPageOverlay.subPageItem.setPreset)
            subPageOverlay.subPageItem.setPreset(name);
    }

    function openDetail(entry) {
        _pendingSubPageInit = (item) => {
            if (item && item.setEntry)
                item.setEntry(entry);
        };
        subPageOverlay.open(Qt.resolvedUrl("presets/PresetDetailSubPage.qml"));
        if (subPageOverlay.subPageItem && subPageOverlay.subPageItem.setEntry)
            subPageOverlay.subPageItem.setEntry(entry);
    }

    function openPush(name) {
        _pendingSubPageInit = (item) => {
            if (item && item.setPreset) {
                item.setPreset(name);
                item.requestDiff.connect(openDiff);
            }
        };
        subPageOverlay.open(Qt.resolvedUrl("presets/PushUpdateSubPage.qml"));
        if (subPageOverlay.subPageItem && subPageOverlay.subPageItem.setPreset) {
            subPageOverlay.subPageItem.setPreset(name);
            subPageOverlay.subPageItem.requestDiff.connect(openDiff);
        }
    }

    function openDiff(name, incoming) {
        _pendingSubPageInit = (item) => {
            if (item && item.setDiff)
                item.setDiff(name, incoming === true);
        };
        subPageOverlay.open(Qt.resolvedUrl("presets/PresetDiffSubPage.qml"));
        if (subPageOverlay.subPageItem && subPageOverlay.subPageItem.setDiff)
            subPageOverlay.subPageItem.setDiff(name, incoming === true);
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true

            SecondaryTabButton {
                buttonIcon: "style"
                buttonText: Translation.tr("My presets")
            }

            SecondaryTabButton {
                buttonIcon: "storefront"
                buttonText: PresetStore.updateCount > 0
                    ? Translation.tr("Store (%1)").arg(PresetStore.updateCount)
                    : Translation.tr("Store")
            }

            SecondaryTabButton {
                buttonIcon: "cloud_upload"
                buttonText: Translation.tr("Published")
            }
        }

        ContentSection {
            icon: "style"
            title: Translation.tr("Presets")
            Layout.fillWidth: true
            visible: presetsConfigRoot.currentTab === 0

            ConfigPresetsView {
                id: presetsView
                text: Translation.tr("Preset Manager")
                onPublishRequested: name => {
                    if (PresetStore.isOwned(name))
                        presetsConfigRoot.openPush(name);
                    else
                        presetsConfigRoot.openPublish(name);
                }
                onUpdateRequested: name => PresetStore.pull(name, false)
            }
        }

        Loader {
            Layout.fillWidth: true
            active: presetsConfigRoot.currentTab === 1
            visible: active
            sourceComponent: storeTabComponent
        }

        Component {
            id: storeTabComponent

            PresetStoreTab {
                onOpenDetails: entry => presetsConfigRoot.openDetail(entry)
            }
        }

        Loader {
            Layout.fillWidth: true
            active: presetsConfigRoot.currentTab === 2
            visible: active
            sourceComponent: publishedTabComponent
        }

        Component {
            id: publishedTabComponent

            PublishedPresetsTab {
                onPushRequested: name => presetsConfigRoot.openPush(name)
                onDiffRequested: name => presetsConfigRoot.openDiff(name, false)
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.topMargin: -20
            visible: PresetStore.lastError.length > 0
            materialIcon: "error"
            text: PresetStore.lastError

            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.small
                materialIcon: "close"
                mainText: Translation.tr("Dismiss")
                onClicked: PresetStore.lastError = ""
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.topMargin: -20
            visible: presetsConfigRoot.currentTab === 0
            text: Translation.tr('Not all options are available in this app. You should also check the config file by hitting the "Config file" button on the topleft corner or opening ~/.config/illogical-impulse/config.json manually.')

            RippleButtonWithIcon {
                id: copyPathButton
                property bool justCopied: false
                buttonRadius: Appearance.rounding.small
                materialIcon: justCopied ? "check" : "content_copy"
                mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
                onClicked: {
                    copyPathButton.justCopied = true;
                    Quickshell.clipboardText = FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                    revertTextTimer.restart();
                }
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive

                Timer {
                    id: revertTextTimer
                    interval: 1500
                    onTriggered: {
                        copyPathButton.justCopied = false;
                    }
                }
            }
        }
    }

    Connections {
        target: Config.options.appearance.palette
        function onTypeChanged() {
            presetsConfigRoot.showRestartFab = true;
        }
    }

    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            presetsConfigRoot.showRestartFab = true;
        }
    }

    property bool showRestartFab: false

    FloatingActionButton {
        id: restartFab
        parent: presetsConfigRoot.parent ? presetsConfigRoot.parent : presetsConfigRoot
        anchors {
            right: parent ? parent.right : undefined
            bottom: parent ? parent.bottom : undefined
            margins: 30
        }
        z: 100
        iconText: "restart_alt"
        buttonText: Translation.tr("Restart Shell")
        expanded: false
        visible: opacity > 0
        opacity: (presetsConfigRoot.showRestartFab && !subPageOverlay.isOpen) ? 1 : 0
        scale: opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        colBackground: Appearance.colors.colTertiaryContainer
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colRipple: Appearance.colors.colTertiaryContainerActive
        colOnBackground: Appearance.colors.colOnTertiaryContainer

        onClicked: {
            Quickshell.execDetached(["bash", "-c", "qs kill -c ii && qs -c ii &"]);
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: restartFab.expanded = true
            onExited: restartFab.expanded = false
        }
    }

    // ── The Store Feedback & Actions ─────────────────────────────────────────

    Connections {
        target: PresetStore

        function onPullFinished(name, ok, changed, error) {
            if (ok && changed && name === PresetStore.activePreset) {
                PresetStore.applyPreset(name);
            }
        }
    }

    // Revert FAB (Direct Undo without popup)
    FloatingActionButton {
        id: revertFab
        parent: presetsConfigRoot.parent ? presetsConfigRoot.parent : presetsConfigRoot
        anchors {
            right: parent ? parent.right : undefined
            bottom: parent ? parent.bottom : undefined
            rightMargin: 30
            bottomMargin: restartFab.visible ? 30 + restartFab.height + 12 : 30
        }
        z: 100
        iconText: "undo"
        buttonText: Translation.tr("Undo preset")
        expanded: false
        visible: opacity > 0
        opacity: (PresetStore.activePreset.length > 0 && !PresetStore.busy && !subPageOverlay.isOpen) ? 1 : 0
        scale: opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        colOnBackground: Appearance.colors.colOnSecondaryContainer

        onClicked: {
            PresetStore.revert();
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: revertFab.expanded = true
            onExited: revertFab.expanded = false
        }

        StyledToolTip {
            text: Translation.tr("Go back to the settings you had before applying %1")
                .arg(PresetStore.activePreset)
        }
    }



    // Sub-page host for slide-in navigation
    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 100
        onSubPageLoaded: item => {
            if (presetsConfigRoot._pendingSubPageInit) {
                presetsConfigRoot._pendingSubPageInit(item);
                presetsConfigRoot._pendingSubPageInit = null;
            }
        }
    }
}
