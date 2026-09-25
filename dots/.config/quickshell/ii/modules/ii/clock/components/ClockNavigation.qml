pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The app's destinations: a bottom navigation bar on narrow windows, a rail on wide
 * ones. Same items, same indicator — only the axis changes.
 */
Rectangle {
    id: root

    property var tabs: []
    property string currentTab: ""
    property bool vertical: false

    signal selected(string tabId)

    implicitWidth: root.vertical ? ClockStyle.navRailWidth : 0
    implicitHeight: root.vertical ? 0 : ClockStyle.navBarHeight
    color: root.vertical ? "transparent" : ClockStyle.colSurface

    GridLayout {
        anchors {
            fill: parent
            topMargin: root.vertical ? ClockStyle.gapHuge : ClockStyle.gapSmall
            bottomMargin: root.vertical ? ClockStyle.gapHuge : ClockStyle.gapSmall
        }
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.vertical ? root.tabs.length + 1 : 1
        columns: root.vertical ? 1 : root.tabs.length
        rowSpacing: ClockStyle.gap
        columnSpacing: 0

        Repeater {
            model: root.tabs

            Item {
                id: navItem
                required property var modelData
                required property int index
                readonly property bool active: root.currentTab === navItem.modelData.id

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                implicitWidth: ClockStyle.navRailWidth
                implicitHeight: navColumn.implicitHeight

                ColumnLayout {
                    id: navColumn
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: ClockStyle.gapTiny

                    RippleButton {
                        id: indicator
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: navItem.active ? ClockStyle.navIndicatorWidth : ClockStyle.navIndicatorHeight + ClockStyle.gapSmall
                        implicitHeight: ClockStyle.navIndicatorHeight
                        buttonRadius: ClockStyle.pill(ClockStyle.navIndicatorHeight)
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
                        Layout.maximumWidth: root.vertical ? ClockStyle.navRailWidth - ClockStyle.gapSmall : navItem.width - ClockStyle.gapTiny
                        text: navItem.modelData.label
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: navItem.active ? Font.DemiBold : Font.Medium
                        color: navItem.active ? ClockStyle.colOnSurface : ClockStyle.colOnSurfaceVariant

                        Behavior on color {
                            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                        }
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

        Item {
            visible: root.vertical
            Layout.fillHeight: true
        }
    }
}
