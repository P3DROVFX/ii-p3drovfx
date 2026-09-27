pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The clock's rail, the Notes rail's twin: the destinations as one shaped group, and
 * Settings at the bottom — the only thing here that is not a place. Each tab's main
 * action is the large FAB in the page's corner, not a button here.
 *
 * Collapsed it is an icon column; expanded it adds labels and live badges.
 */
Item {
    id: root

    property var tabs: []
    property string currentTab: ""
    property bool expanded: true
    property bool settingsOpen: false
    property var badges: ({})

    signal selected(string tabId)
    signal settingsRequested()

    clip: true

    Rectangle {
        anchors.fill: parent
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.panePadding
        spacing: 0

        // ── Destinations ────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 2

            Repeater {
                model: root.tabs

                ClockRailItem {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    expanded: root.expanded
                    symbol: modelData.icon
                    label: modelData.label
                    badge: String(root.badges?.[modelData.id] ?? "")
                    current: !root.settingsOpen && root.currentTab === modelData.id
                    isFirst: index === 0
                    isLast: index === root.tabs.length - 1
                    prevIsCurrent: !root.settingsOpen && index > 0 && root.currentTab === root.tabs[index - 1].id
                    nextIsCurrent: !root.settingsOpen && index < root.tabs.length - 1 && root.currentTab === root.tabs[index + 1].id
                    onTriggered: root.selected(modelData.id)
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        // ── Settings ────────────────────────────────────────────────────
        RippleButton {
            id: settingsButton
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: ClockStyle.rowHeight
            buttonRadius: Math.min(ClockStyle.rowHeight / 2, ClockStyle.radiusLarge)
            toggled: root.settingsOpen
            colBackground: ClockStyle.colSecondaryContainer
            colBackgroundHover: ClockStyle.colSecondaryContainerHover
            colBackgroundActive: ClockStyle.colSecondaryContainerActive
            colBackgroundToggled: ClockStyle.colPrimary
            colBackgroundToggledHover: ClockStyle.colPrimaryHover
            colRipple: ClockStyle.colPrimaryActive
            onClicked: root.settingsRequested()

            scale: settingsButton.down ? 0.95 : (settingsButton.hovered ? 1.02 : 1)
            Behavior on scale {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }

            contentItem: Item {
                anchors.fill: parent

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    MaterialSymbol {
                        text: "settings"
                        iconSize: Appearance.font.pixelSize.huge
                        fill: root.settingsOpen ? 1 : 0
                        color: root.settingsOpen ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                        rotation: settingsButton.hovered ? 60 : 0

                        Behavior on rotation {
                            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                    }

                    StyledText {
                        visible: root.expanded
                        text: Translation.tr("Settings")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: root.settingsOpen ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                    }
                }
            }

            StyledToolTip {
                text: Translation.tr("Clock settings")
                extraVisibleCondition: !root.expanded
            }
        }
    }
}
