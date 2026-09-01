pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The Material 3 FAB menu the Hyprland hub carries in its corner.
 *
 * What used to live here was a strip across the top of the page listing, in prose, everything
 * the hub had written and everything that might stop it taking effect. It was the first thing
 * on every tab, it was four lines tall, and none of it was something you act on while changing
 * a setting - so it is now a menu you open when you want it, and nothing at all when you don't.
 *
 * One primary FAB opens a column of items above it, each an icon and a word; a transparent
 * outside-click target closes the menu wherever the next press lands. `checkable` items stay
 * open, because a switch you have to reopen the menu to see the result of is a switch that lies.
 */
Item {
    id: root

    /// `[{ icon, label, danger, checkable, checked }]`, drawn bottom-up in the order given.
    property var actions: []
    property bool expanded: false
    property string icon: "code"
    property string tooltipText: ""
    /// Where the outside-click target goes. The menu itself is a small item in a corner; the
    /// target has to cover the page, which is several parents up.
    property Item scrimParent: null

    signal triggered(int index)

    implicitWidth: mainFab.implicitWidth
    implicitHeight: mainFab.implicitHeight

    function close() {
        root.expanded = false;
    }

    MouseArea {
        parent: root.scrimParent ?? root
        anchors.fill: parent
        z: -1
        // Keep the outside-click target without dimming the settings page behind the menu.
        visible: root.expanded
        enabled: root.expanded
        onClicked: root.close()
    }

    ColumnLayout {
        id: menuColumn
        anchors.bottom: mainFab.top
        anchors.bottomMargin: 12
        anchors.right: mainFab.right
        spacing: 8

        Repeater {
            model: root.actions

            delegate: RippleButton {
                id: item

                required property var modelData
                required property int index

                readonly property bool danger: item.modelData.danger === true
                // `checkable` itself is AbstractButton's and is FINAL, so this cannot borrow the name.
                readonly property bool togglable: item.modelData.checkable === true
                readonly property bool checkedOn: item.modelData.checked === true

                Layout.alignment: Qt.AlignRight
                implicitHeight: 44
                implicitWidth: itemRow.implicitWidth + 36
                buttonRadius: Appearance.rounding.full
                visible: opacity > 0
                enabled: root.expanded

                colBackground: item.checkedOn ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: item.checkedOn ? Appearance.colors.colPrimaryContainerHover
                    : Appearance.colors.colSurfaceContainerHighest
                colRipple: item.checkedOn ? Appearance.colors.colPrimaryContainerActive
                    : Appearance.colors.colSurfaceContainerHighestActive

                // One-shot entrance, staggered from the FAB outwards: opacity and a short lift,
                // no scale and nothing that keeps moving once the menu has arrived.
                opacity: root.expanded ? 1 : 0
                transform: Translate {
                    y: root.expanded ? 0 : 12

                    Behavior on y {
                        NumberAnimation {
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                onClicked: {
                    root.triggered(item.index);
                    if (!item.togglable) root.close();
                }

                contentItem: Item {
                    anchors.fill: parent

                    RowLayout {
                        id: itemRow
                        anchors.centerIn: parent
                        spacing: 10

                        StyledText {
                            text: item.modelData.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: item.danger ? Appearance.colors.colError
                                : (item.checkedOn ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurface)
                        }

                        MaterialSymbol {
                            text: item.togglable
                                ? (item.checkedOn ? "check_circle" : "circle")
                                : (item.modelData.icon ?? "")
                            iconSize: 20
                            fill: item.checkedOn ? 1 : 0
                            color: item.danger ? Appearance.colors.colError
                                : (item.checkedOn ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurface)
                        }
                    }
                }
            }
        }
    }

    FloatingActionButton {
        id: mainFab
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        iconText: root.expanded ? "close" : root.icon
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
        colRipple: Appearance.colors.colSurfaceContainerHighestActive
        colOnBackground: Appearance.colors.colOnSurface
        onClicked: root.expanded = !root.expanded

        StyledToolTip {
            text: root.tooltipText
            extraVisibleCondition: !root.expanded
        }
    }
}
