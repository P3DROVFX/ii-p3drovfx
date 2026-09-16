import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The body of the Modes overlay: a three-tab bar and the page under it.
 *
 * Pages are loaded on demand. Only the selected page stays alive, keeping a
 * retained overlay cheap while closed and avoiding three editor trees in RAM.
 * The host restores the last page; only completed tab navigation is persisted.
 */
Item {
    id: root

    property string initialTab: "modes"
    readonly property var tabs: ["modes", "routines", "activity"]
    property string tab: root.tabs.includes(root.initialTab) ? root.initialTab : "modes"

    signal requestClose()
    readonly property real headerHeight: viewTabs.implicitHeight + contentLayout.spacing

    implicitWidth: 1200
    implicitHeight: 640 + root.headerHeight

    onInitialTabChanged: root.tab = root.tabs.includes(root.initialTab) ? root.initialTab : "modes"

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
        id: contentLayout
        anchors.fill: parent
        spacing: 12

        // The tabs name the overlay, so there is no title beside them.
        Item {
            Layout.fillWidth: true
            implicitHeight: viewTabs.implicitHeight

            SecondaryTabBar {
                id: viewTabs
                requestOnly: true

                width: 420
                anchors.horizontalCenter: parent.horizontalCenter
                selectedIndex: Math.max(0, root.tabs.indexOf(root.tab))

                onIndexSelected: index => {
                    const next = root.tabs[index] ?? "modes";
                    root.tab = next;
                    Config.options.modes.lastTab = next;
                }

                Repeater {
                    model: [Translation.tr("Modes"), Translation.tr("Routines"), Translation.tr("Activity")]

                    delegate: SecondaryTabButton {
                        required property string modelData
                        required property int index
                        current: index === viewTabs.selectedIndex
                        checkable: false
                        autoExclusive: false
                        Keys.forwardTo: [viewTabs]
                        onClicked: viewTabs.selectIndex(index)

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
                active: root.tab === "modes"
                visible: root.tab === "modes"
                asynchronous: true
                sourceComponent: ModesPage {
                    onRequestClose: root.requestClose()
                }
            }

            Loader {
                id: routinesLoader
                anchors.fill: parent
                active: root.tab === "routines"
                visible: root.tab === "routines"
                asynchronous: true
                sourceComponent: RoutinesPage {
                    onRequestClose: root.requestClose()
                }
            }

            Loader {
                id: activityLoader
                anchors.fill: parent
                active: root.tab === "activity"
                visible: root.tab === "activity"
                asynchronous: true
                sourceComponent: ActivityPage {
                    onRequestClose: root.requestClose()
                }
            }
        }
    }
}
