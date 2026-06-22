import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer
import qs.modules.common.functions
import "phone"

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 12
    anchors.fill: parent
    
    // Toggles from Config
    property bool aiChatEnabled: Config.options.policies.ai !== 0  
    property bool translatorEnabled: Config.options.policies.translator !== 0
    property bool mediaEnabled: Config.options.policies.player !== 0
    property bool wallpapersEnabled: Config.options.policies.wallpapers !== 0  
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2

    // Tab and Page mapping
    property var tabs: [
        { icon: "neurology", name: Translation.tr("Intelligence"), enabled: root.aiChatEnabled, component: aiChat },
        { icon: "translate", name: Translation.tr("Translator"), enabled: root.translatorEnabled, component: translator },
        { icon: "music_note", name: Translation.tr("Media"), enabled: root.mediaEnabled, component: media },
        { icon: "wallpaper", name: Translation.tr("Wallpapers"), enabled: root.wallpapersEnabled, component: wallpaperBrowser },
        { icon: "bookmark_heart", name: Translation.tr("Anime"), enabled: root.animeEnabled && !root.animeCloset, component: anime },
        { icon: "smartphone", name: Translation.tr("Phone"), enabled: Config.options.policies.phone !== 0, component: phonePlaceholder }
    ]

    property var activeTabs: tabs.filter(t => t.enabled)
    property var tabButtonList: activeTabs.map(t => ({ icon: t.icon, name: t.name }))
    property int tabCount: activeTabs.length
    // Holds the previously-focused tab index so the bounce-in animation
    // (mirroring the Cheatsheet tab transition) knows the direction.
    property int _prevTabIndex: Persistent.states.sidebar.policies.tab
    Component.onCompleted: {
        root._prevTabIndex = Persistent.states.sidebar.policies.tab
    }

    function validateTabIndex() {
        if (!Persistent.ready) return;
        var t = Persistent.states.sidebar.policies.tab;
        if (tabCount > 0) {
            if (t < 0 || t >= tabCount) {
                Persistent.states.sidebar.policies.tab = 0;
            }
        } else {
            if (t !== 0) {
                Persistent.states.sidebar.policies.tab = 0;
            }
        }
    }

    onActiveTabsChanged: {
        root.validateTabIndex()
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.validateTabIndex()
        }
    }

    Connections {
        target: Persistent.states.sidebar.policies
        ignoreUnknownSignals: true
        function onTabChanged() {
            root.validateTabIndex()
        }
    }

    function focusActiveItem() {
        if (swipeView.currentItem && swipeView.currentItem.item) {
            swipeView.currentItem.item.forceActiveFocus()
        }
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        // Clip to the sidebar bounds. Without this, the Toolbar (with
        // Layout.alignment: Qt.AlignHCenter) overflows visibly past the sidebar
        // edges during width transitions, when the tab count changes at runtime,
        // or when translated strings are wider than the English defaults.
        clip: true
        anchors {
            fill: parent
            leftMargin: sidebarPadding
            rightMargin: sidebarPadding
            bottomMargin: sidebarPadding
            topMargin: 24
        }
        spacing: sidebarPadding

        Toolbar {
            visible: activeTabs.length > 1
            Layout.alignment: Qt.AlignHCenter
            // Cap the toolbar width to the available column width so the
            // tab buttons shrink/wrap rather than extending past the sidebar
            // when there are 5+ tabs or wider translated labels.
            Layout.maximumWidth: parent.width - sidebarPadding * 2
            Layout.preferredWidth: Math.min(implicitWidth, parent.width - sidebarPadding * 2)
            enableShadow: false
            colBackground: Appearance.colors.colLayer3
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                currentIndex: Persistent.states.sidebar.policies.tab
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < root.tabCount && Persistent.states.sidebar.policies.tab !== currentIndex) {
                        Persistent.states.sidebar.policies.tab = currentIndex
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: "transparent"

            SwipeView {
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: Persistent.states.sidebar.policies.tab
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < root.tabCount && Persistent.states.sidebar.policies.tab !== currentIndex) {
                        Persistent.states.sidebar.policies.tab = currentIndex
                    }
                    Qt.callLater(() => {
                        root._prevTabIndex = currentIndex
                    })
                }

                Component.onCompleted: {
                    if (contentItem) {
                        contentItem.highlightMoveDuration = 0
                    }
                }

                implicitWidth: Math.max.apply(null, contentChildren.map(child => child.implicitWidth || 0))
                implicitHeight: Math.max.apply(null, contentChildren.map(child => child.implicitHeight || 0))

                clip: true
                // Cheatsheet pattern: disable expensive layer compositing while swipe is
                // moving to keep the bounce animation at full framerate.
                layer.enabled: !swipeView.moving
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: Math.floor(swipeView.width)
                        height: Math.floor(swipeView.height)
                        radius: Appearance.rounding.small
                    }
                }

                Repeater {
                    model: root.activeTabs
                    Loader {
                        id: tabDelegate
                        required property var modelData
                        required property int index

                        active: SwipeView.isCurrentItem || SwipeView.isNextItem || SwipeView.isPreviousItem
                        sourceComponent: modelData.component

                        transform: Translate {
                            id: trans
                            x: 0
                        }

                        readonly property bool isCurrent: swipeView.currentIndex === index
                        onIsCurrentChanged: {
                            if (isCurrent) {
                                const diff = index - root._prevTabIndex
                                if (diff !== 0) {
                                    bounceAnim.stop()
                                    opacityAnim.stop()
                                    trans.x = diff > 0 ? 120 : -120
                                    tabDelegate.opacity = 0
                                    bounceAnim.start()
                                    opacityAnim.start()
                                }
                            } else {
                                tabDelegate.opacity = 1
                                trans.x = 0
                            }
                        }

                        NumberAnimation {
                            id: bounceAnim
                            target: trans
                            property: "x"
                            to: 0
                            duration: 420
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.45
                        }

                        NumberAnimation {
                            id: opacityAnim
                            target: tabDelegate
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 280
                            easing.type: Easing.OutCubic
                        }

                        onLoaded: {
                            if (item) item.anchors.fill = this
                        }
                    }
                }
            }

            // Show placeholder if no tabs are active
            Loader {
                anchors.fill: parent
                active: root.activeTabs.length === 0
                sourceComponent: placeholder
            }
        }

        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: media
            SidebarPlayerControl {}
        }
        Component {  
            id: wallpaperBrowser  
            WallpaperBrowserUI {}  
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: phonePlaceholder
            Phone {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
