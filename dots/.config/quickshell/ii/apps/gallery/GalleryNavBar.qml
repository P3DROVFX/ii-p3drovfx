pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Floating M3 Expressive bottom navigation pill (borderless).
 * Clean inline badges + proper M3 state-layer hover colors.
 */
Rectangle {
    id: root

    required property string activeTab
    property int todayCount: 0
    property bool phoneConnected: false
    signal tabSelected(string tabId)

    readonly property var tabs: [
        { id: "home",     icon: "photo_library", label: Translation.tr("Home") },
        { id: "albums",   icon: "folder_copy",   label: Translation.tr("Albums") },
        { id: "phone",    icon: "smartphone",    label: Translation.tr("Phone") },
        { id: "settings", icon: "tune",          label: Translation.tr("Settings") }
    ]

    readonly property int activeIndex: {
        for (let i = 0; i < tabs.length; i++) {
            if (tabs[i].id === root.activeTab)
                return i;
        }
        return 0;
    }

    readonly property int tabWidth: 138
    readonly property int tabHeight: 52
    readonly property int pad: 7

    implicitWidth: tabs.length * tabWidth + pad * 2
    implicitHeight: tabHeight + pad * 2
    radius: Appearance.rounding.full
    color: Appearance.m3colors.m3surfaceContainerHigh

    // Sliding active pill indicator
    Rectangle {
        id: indicator
        y: root.pad
        x: root.pad + root.activeIndex * root.tabWidth
        width: root.tabWidth
        height: root.tabHeight
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary

        Behavior on x {
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutBack
                easing.overshoot: 1.15
            }
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 0

        Repeater {
            model: root.tabs

            delegate: Item {
                id: tabBtn
                required property var modelData
                required property int index

                readonly property bool isActive: root.activeTab === modelData.id
                readonly property bool showTodayBadge: modelData.id === "home" && root.todayCount > 0
                readonly property bool showPhoneDot: modelData.id === "phone" && root.phoneConnected

                width: root.tabWidth
                height: root.tabHeight

                // Proper M3 state-layer hover (subtle translucent onSurface for inactive, onPrimary for active)
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: tabMouse.containsMouse
                        ? (tabBtn.isActive
                            ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.90)
                            : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.90))
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 7

                    MaterialSymbol {
                        text: tabBtn.modelData.icon
                        iconSize: 20
                        fill: tabBtn.isActive ? 1 : 0
                        color: tabBtn.isActive
                            ? Appearance.colors.colOnPrimary
                            : (tabMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    StyledText {
                        text: tabBtn.modelData.label
                        font.family: Appearance.font.family.main
                        font.pixelSize: 15
                        font.variableAxes: tabBtn.isActive
                            ? ({ "wght": 760, "wdth": 110, "ROND": 100 })
                            : ({ "wght": 520, "wdth": 100, "ROND": 100 })
                        color: tabBtn.isActive
                            ? Appearance.colors.colOnPrimary
                            : (tabMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    // Clean inline badge (never overlaps the icon or label)
                    Rectangle {
                        visible: tabBtn.showTodayBadge
                        implicitWidth: Math.max(20, badgeText.implicitWidth + 10)
                        implicitHeight: 20
                        radius: 10
                        color: tabBtn.isActive
                            ? Appearance.colors.colOnPrimary
                            : Appearance.m3colors.m3tertiary

                        StyledText {
                            id: badgeText
                            anchors.centerIn: parent
                            text: root.todayCount > 99 ? "99+" : String(root.todayCount)
                            font.family: Appearance.font.family.main
                            font.pixelSize: 11
                            font.variableAxes: ({ "wght": 780, "wdth": 85, "ROND": 100 })
                            color: tabBtn.isActive
                                ? Appearance.colors.colPrimary
                                : Appearance.m3colors.m3onTertiary
                        }
                    }

                    // Subtle connected dot on Phone tab
                    Rectangle {
                        visible: tabBtn.showPhoneDot
                        width: 8
                        height: 8
                        radius: 4
                        color: tabBtn.isActive
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colPrimary
                    }
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tabSelected(tabBtn.modelData.id)
                }
            }
        }
    }
}
