import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

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
        { icon: "bookmark_heart", name: Translation.tr("Anime"), enabled: root.animeEnabled && !root.animeCloset, component: anime }
    ]

    property var activeTabs: tabs.filter(t => t.enabled)
    property var tabButtonList: activeTabs.map(t => ({ icon: t.icon, name: t.name }))
    property int tabCount: activeTabs.length

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
                }

                clip: true
                layer.enabled: true
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
                        active: SwipeView.isCurrentItem || SwipeView.isNextItem || SwipeView.isPreviousItem
                        sourceComponent: modelData.component
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
