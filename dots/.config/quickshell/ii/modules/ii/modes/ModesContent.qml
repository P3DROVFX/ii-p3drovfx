import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The body of the Modes overlay: a three-tab bar and the page under it.
 *
 * Pages are loaded on demand and kept once built, so switching back to a tab
 * does not rebuild its editor state. The tab itself is remembered in the
 * config so the overlay reopens where it was left.
 */
Item {
    id: root

    property string initialTab: "modes"
    readonly property var tabs: ["modes", "routines", "activity"]
    property string tab: root.initialTab

    signal requestClose()

    implicitWidth: 1200
    implicitHeight: 640

    onInitialTabChanged: root.tab = root.initialTab

    onTabChanged: {
        if (Config.options.modes.lastTab !== root.tab)
            Config.options.modes.lastTab = root.tab;
    }

    function currentPage() {
        switch (root.tab) {
        case "routines":
            return routinesLoader.item;
        case "activity":
            return activityLoader.item;
        }
        return modesLoader.item;
    }

    // True when a picker or an inline confirm swallowed the Escape.
    function handleEscape() {
        const page = root.currentPage();
        return page && page.handleEscape ? page.handleEscape() : false;
    }

    function handleKey(key, modifiers) {
        const page = root.currentPage();
        return page && page.handleKey ? page.handleKey(key, modifiers) : false;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // The tabs name the overlay, so there is no title beside them.
        Item {
            Layout.fillWidth: true
            implicitHeight: viewTabs.implicitHeight

            SecondaryTabBar {
                id: viewTabs

                width: 420
                anchors.horizontalCenter: parent.horizontalCenter
                currentIndex: Math.max(0, root.tabs.indexOf(root.tab))

                onCurrentIndexChanged: {
                    const next = root.tabs[viewTabs.currentIndex] ?? "modes";
                    if (root.tab !== next)
                        root.tab = next;
                }

                Repeater {
                    model: [Translation.tr("Modes"), Translation.tr("Routines"), Translation.tr("Activity")]

                    delegate: SecondaryTabButton {
                        required property string modelData

                        buttonText: modelData
                    }
                }
            }

            // Engine switched off: every surface still works by hand, but
            // nothing starts on its own. Said here rather than discovered.
            Rectangle {
                visible: !Modes.enabled
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                implicitWidth: disabledRow.implicitWidth + 20
                implicitHeight: 30
                radius: Appearance.rounding.full
                color: Appearance.colors.colErrorContainer

                RowLayout {
                    id: disabledRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "motion_photos_paused"
                        iconSize: 16
                        color: Appearance.colors.colOnErrorContainer
                    }

                    StyledText {
                        text: Translation.tr("Automatic starts are off")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                id: modesLoader
                anchors.fill: parent
                active: root.tab === "modes" || item !== null
                visible: root.tab === "modes"
                sourceComponent: ModesPage {
                    onRequestClose: root.requestClose()
                }
            }

            Loader {
                id: routinesLoader
                anchors.fill: parent
                active: root.tab === "routines" || item !== null
                visible: root.tab === "routines"
                sourceComponent: RoutinesPage {
                    onRequestClose: root.requestClose()
                }
            }

            Loader {
                id: activityLoader
                anchors.fill: parent
                active: root.tab === "activity" || item !== null
                visible: root.tab === "activity"
                sourceComponent: ActivityPage {
                    onRequestClose: root.requestClose()
                }
            }
        }
    }
}
