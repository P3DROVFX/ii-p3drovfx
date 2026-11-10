pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The bottom navigation bar a narrow window falls back to once the rail no longer fits.
 * Same destinations as the rail; the active one wears a pill that widens into place.
 */
Rectangle {
    id: root

    property var tabs: []
    property string currentTab: ""

    signal selected(string tabId)

    implicitHeight: ClockStyle.navBarHeight
    radius: ClockStyle.radiusLarge
    color: ClockStyle.colPane

    RowLayout {
        anchors {
            fill: parent
            topMargin: ClockStyle.gapSmall
            bottomMargin: ClockStyle.gapSmall
        }
        spacing: 0

        Repeater {
            model: root.tabs

            Item {
                id: navItem
                required property var modelData
                readonly property bool active: root.currentTab === navItem.modelData.id

                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapTiny

                    RippleButton {
                        id: indicator
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: navItem.active ? 56 : 40
                        implicitHeight: 32
                        buttonRadius: ClockStyle.pill(32)
                        colBackground: navItem.active ? ClockStyle.colSecondaryContainer : "transparent"
                        colBackgroundHover: navItem.active ? ClockStyle.colSecondaryContainerHover : ClockStyle.colSurfaceHover
                        colRipple: ClockStyle.colSecondaryContainerActive
                        onClicked: root.selected(navItem.modelData.id)

                        Behavior on implicitWidth {
                            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                        }

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: navItem.modelData.icon
                                iconSize: ClockStyle.iconNormal
                                fill: navItem.active ? 1 : 0
                                color: navItem.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: navItem.width - ClockStyle.gapTiny
                        text: navItem.modelData.label
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: navItem.active ? Font.DemiBold : Font.Medium
                        color: navItem.active ? ClockStyle.colOnSurface : ClockStyle.colOnSurfaceVariant
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(navItem.modelData.id)
                }
            }
        }
    }
}
