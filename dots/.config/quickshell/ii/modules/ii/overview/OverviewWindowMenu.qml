pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The window menu that drops from an app chip.
 *
 * Two groups with a gap between them instead of a divider: what to do with
 * the window, then how to end it. `progress` (0 → 1) unrolls it from the edge
 * that faces the chip, so it opens downwards or, with `upwards`, from below.
 */
Item {
    id: root

    property bool floating: false
    property bool fullscreen: false
    property bool pinned: false
    property bool canScreenshot: true
    property bool upwards: false
    property real progress: 0
    property bool animationsEnabled: true

    signal actionTriggered(string id)

    readonly property var groups: [
        [
            { id: "screenshot", symbol: "screenshot_region", label: Translation.tr("Screenshot"), toggled: false, shown: root.canScreenshot, danger: false },
            { id: "float", symbol: root.floating ? "grid_view" : "picture_in_picture", label: root.floating ? Translation.tr("Tile") : Translation.tr("Float"), toggled: false, shown: true, danger: false },
            { id: "fullscreen", symbol: root.fullscreen ? "fullscreen_exit" : "fullscreen", label: Translation.tr("Fullscreen"), toggled: root.fullscreen, shown: true, danger: false },
            { id: "pin", symbol: "keep", label: root.pinned ? Translation.tr("Unpin") : Translation.tr("Pin"), toggled: root.pinned, shown: root.floating, danger: false }
        ],
        [
            { id: "close", symbol: "close", label: Translation.tr("Close"), toggled: false, shown: true, danger: true },
            { id: "kill", symbol: "skull", label: Translation.tr("Force quit"), toggled: false, shown: true, danger: true }
        ]
    ].map(group => group.filter(item => item.shown))

    implicitWidth: OverviewStyle.menuWidth
    implicitHeight: content.implicitHeight
    opacity: Math.min(1, root.progress * 2)

    // Unrolls from the chip's side; the content keeps its size and is revealed.
    Item {
        id: slot
        width: parent.width
        height: content.implicitHeight * root.progress
        y: root.upwards ? parent.height - height : 0
        clip: true

        Column {
            id: content
            width: parent.width
            y: root.upwards ? 0 : slot.height - implicitHeight
            spacing: OverviewStyle.menuSectionGap
            transform: Translate {
                y: (1 - root.progress) * (root.upwards ? OverviewStyle.menuSlide : -OverviewStyle.menuSlide)
            }

            Repeater {
                model: root.groups
                delegate: Item {
                    id: group
                    required property var modelData
                    width: content.width
                    height: rows.implicitHeight + OverviewStyle.menuPadding * 2

                    StyledRectangularShadow {
                        target: groupShape
                    }
                    Rectangle {
                        id: groupShape
                        anchors.fill: parent
                        radius: OverviewStyle.menuRadiusOuter
                        color: OverviewStyle.colMenuContainer
                    }

                    Column {
                        id: rows
                        x: OverviewStyle.menuPadding
                        y: OverviewStyle.menuPadding
                        width: parent.width - OverviewStyle.menuPadding * 2
                        spacing: OverviewStyle.menuGroupGap

                        Repeater {
                            model: group.modelData
                            delegate: OverviewMenuItem {
                                required property var modelData
                                required property int index
                                width: rows.width
                                symbol: modelData.symbol
                                label: modelData.label
                                toggled: modelData.toggled
                                danger: modelData.danger
                                first: index === 0
                                last: index === group.modelData.length - 1
                                animationsEnabledHere: root.animationsEnabled
                                onClicked: root.actionTriggered(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
