import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Wi-Fi, Bluetooth, hotspot and wired settings, on one page.
 *
 * Each tab lives in its own file under configs/network/ and is built only
 * while it is the visible tab. Those files are indexed for search through the
 * page's `searchSources`, so a hit inside a tab that isn't open still arrives
 * here — `focusSectionTab` then brings the tab that owns the section forward.
 */
Item {
    id: root
    anchors.fill: parent

    property alias activeSubPage: subPageOverlay.activeSubPage
    property alias currentTab: tabBar.currentIndex

    // How the settings window restores a page's scroll position.
    property real contentY: 0

    /**
     * The wired tab is only built where there is a socket to talk about, so the
     * list is computed rather than fixed. The port is appended last so that
     * unplugging a USB adapter cannot renumber the three tabs that are always
     * there.
     */
    readonly property var tabs: NetworkState.hasWiredDevice
        ? [...root.baseTabs, root.wiredTab] : root.baseTabs

    readonly property var baseTabs: [
        {
            "source": "network/WifiTab.qml",
            "icon": "wifi",
            "name": Translation.tr("Wi-Fi"),
            "sections": [Translation.tr("Wi-Fi"), Translation.tr("Connected network"),
                Translation.tr("Available networks"), Translation.tr("Saved networks"),
                Translation.tr("Hidden network"), Translation.tr("Connection details")]
        },
        {
            "source": "network/BluetoothTab.qml",
            "icon": "bluetooth",
            "name": Translation.tr("Bluetooth"),
            "sections": [Translation.tr("Bluetooth"), Translation.tr("Connected"),
                Translation.tr("Nearby devices"), Translation.tr("Paired devices"),
                Translation.tr("BudsLink"), Translation.tr("Earbuds"), Translation.tr("Noise control")]
        },
        {
            "source": "network/HotspotTab.qml",
            "icon": "wifi_tethering",
            "name": Translation.tr("Hotspot"),
            "sections": [Translation.tr("Hotspot"), Translation.tr("Access point"),
                Translation.tr("Connected devices")]
        }
    ]

    readonly property var wiredTab: ({
        "source": "network/WiredTab.qml",
        "icon": "settings_ethernet",
        "name": Translation.tr("Wired"),
        "sections": [Translation.tr("Ethernet ports"), Translation.tr("Saved connections"),
            Translation.tr("Addressing")]
    })

    readonly property Item currentPage: tabHost.currentPage

    readonly property string currentSearch: SearchRegistry.currentSearch

    // A search result or a deep link only names a section. Bring the tab that
    // owns it forward, or the highlight plays out on a page nobody can see.
    function focusSectionTab(title: string): void {
        if (!title || title.length === 0)
            return;
        const needle = title.toLowerCase();
        for (let i = 0; i < root.tabs.length; i++) {
            if (root.tabs[i].sections.some(section => section.toLowerCase() === needle)) {
                root.selectTab(i);
                return;
            }
        }
    }

    /**
     * The tab the user is on, held here rather than read back off the bar.
     *
     * Settings pages are loaded asynchronously, so this page finishes well
     * before its tab buttons have been incubated: `Component.onCompleted` runs
     * against a bar with no buttons in it at all. Setting an index on an empty
     * bar does nothing, and the bar then drags its index along behind each
     * button as it appears, so the page ends up on whichever tab was built
     * last. That is what kept opening this page on Hotspot, and why it only
     * happened some of the time — incubation does not always lose the race.
     */
    property int wantedTab: 0

    /** False while the bar is still filling, when its index means nothing. */
    readonly property bool barReady: tabBar.count === root.tabs.length

    /** True once the filled bar has been put where this page wants it. */
    property bool barSettled: false

    function selectTab(index: int): void {
        if (index < 0 || index >= root.tabs.length)
            return;
        root.wantedTab = index;
        GlobalStates.settingsNetworkTab = index;
        root.applyWantedTab();
    }

    function applyWantedTab(): void {
        if (!root.barReady)
            return;
        if (root.wantedTab < 0 || root.wantedTab >= root.tabs.length)
            root.wantedTab = 0;
        tabBar.currentIndex = root.wantedTab;
        root.barSettled = true;
    }

    onContentYChanged: {
        const page = root.currentPage;
        if (page && page.contentY !== undefined)
            page.contentY = root.contentY;
    }
    onCurrentSearchChanged: root.focusSectionTab(root.currentSearch)

    // Come back to the tab this page was left on, but let a deep link or a
    // search hit override it — those name a section and mean to go there.
    Component.onCompleted: {
        const remembered = GlobalStates.settingsNetworkTab;
        root.selectTab(remembered >= 0 && remembered < root.tabs.length ? remembered : 0);
        root.focusSectionTab(SearchRegistry.currentSearch);
    }

    // The moment the bar holds every tab it is put where it should have been
    // all along. This is also what puts it back when a wired port appears and
    // adds a fourth button underneath it.
    onBarReadyChanged: {
        if (!root.barReady) {
            root.barSettled = false;
            return;
        }
        Qt.callLater(root.applyWantedTab);
    }

    /**
     * True while a sub-page covers the whole page, bar included.
     *
     * Nothing that reaches the bar's index in that state can be the user
     * picking a tab, because there is no bar on screen to pick from.
     */
    readonly property bool subPageOpen: subPageOverlay.isOpen

    // Coming back from a sub-page lands on the tab it was opened from, not on
    // whatever the bar drifted to while it was hidden underneath.
    onSubPageOpenChanged: if (!root.subPageOpen) Qt.callLater(root.applyWantedTab)

    // A move made by a settled bar is the user's — a click, the wheel or the
    // arrow keys — and is the one thing worth remembering. Everything the bar
    // does to itself on the way up happens before it settles and is ignored,
    // and so is anything that moves it while a sub-page is in the way.
    onCurrentTabChanged: {
        if (!root.barSettled || root.currentTab < 0 || root.currentTab === root.wantedTab)
            return;
        if (root.subPageOpen) {
            Qt.callLater(root.applyWantedTab);
            return;
        }
        root.wantedTab = root.currentTab;
        GlobalStates.settingsNetworkTab = root.currentTab;
    }

    SecondaryTabBar {
        id: tabBar
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        // Fading the bar out behind a sub-page still leaves it hit-testable,
        // and it carries a wheel handler that switches tabs. Scrolling near the
        // top of a sub-page was landing on that handler and changing the tab
        // underneath, so the page came back on a different tab than it left.
        // Opacity is for looks; this is what takes it out of input.
        visible: root.tabs.length > 1 && subPageOverlay.slideProgress > 0
        enabled: subPageOverlay.slideProgress > 0
        height: root.tabs.length > 1 ? tabBar.implicitHeight : 0
        opacity: subPageOverlay.slideProgress

        // The model is the number of tabs, not the list itself. The list is a
        // binding, so it is rebuilt whenever a translation or the wired device
        // changes, and handing a rebuilt list to a Repeater destroys and
        // recreates every button under the bar — which leaves the bar pointing
        // at whichever button was added last. That is what kept dropping this
        // page on Hotspot. A count only changes when a tab really appears or
        // disappears, and the labels stay live through the index below.
        Repeater {
            model: root.tabs.length

            delegate: SecondaryTabButton {
                required property int index
                readonly property var tab: root.tabs[index] ?? null

                buttonText: tab?.name ?? ""
                buttonIcon: tab?.icon ?? ""
            }
        }
    }

    Item {
        id: tabHost

        // Set by whichever tab last finished loading. A binding through
        // Repeater.itemAt() cannot work here: it is a function call, so it
        // never re-runs when the delegate it would have returned appears.
        property Item currentPage: null

        anchors {
            top: tabBar.bottom
            topMargin: tabBar.visible ? 8 : 0
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // Counted rather than listed for the same reason as the bar above, and
        // for one more: a rebuilt list would tear down the open tab and load it
        // again from scratch every time a translation changed.
        Repeater {
            id: tabRepeater
            model: root.tabs.length

            delegate: Loader {
                id: tabLoader
                required property int index
                readonly property var tab: root.tabs[index] ?? null

                anchors.fill: parent
                active: root.currentTab === index
                asynchronous: true
                source: tabLoader.tab ? Qt.resolvedUrl(tabLoader.tab.source) : ""
                onItemChanged: if (item) tabHost.currentPage = item

                // A tab is unloaded as soon as another one is picked, so the
                // sub-pages it opens have to be owned by this page instead.
                Connections {
                    target: tabLoader.item
                    ignoreUnknownSignals: true

                    function onOpenSubPage(page): void {
                        root.activeSubPage = page;
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
