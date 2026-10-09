pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.island
import qs.modules.settings.configs.workspaces

/**
 * Where the two sidebars sit. One connected group picks the arrangement; the header
 * says in words what the chosen one does, so the four options need no tooltips.
 */
WorkspacesPane {
    id: root

    readonly property real segmentHeight: 56
    readonly property real labelMinWidth: 110
    readonly property var arrangements: [
        {
            value: "default",
            label: Translation.tr("Default"),
            icon: "vertical_align_center",
            shape: "Cookie9Sided",
            summary: Translation.tr("Policies on the left, dashboard on the right")
        },
        {
            value: "inverted",
            label: Translation.tr("Inverted"),
            icon: "swap_horiz",
            shape: "Flower",
            summary: Translation.tr("Policies on the right, dashboard on the left")
        },
        {
            value: "left",
            label: Translation.tr("Left"),
            icon: "keyboard_arrow_left",
            shape: "SoftBurst",
            summary: Translation.tr("Both on the left, one at a time")
        },
        {
            value: "right",
            label: Translation.tr("Right"),
            icon: "keyboard_arrow_right",
            shape: "Clover4Leaf",
            summary: Translation.tr("Both on the right, one at a time")
        }
    ]

    readonly property string current: Config.options.sidebar.position
    readonly property var currentEntry: root.arrangements.find(entry => entry.value === root.current) ?? root.arrangements[0]
    readonly property string summary: root.currentEntry.summary

    symbol: "side_navigation"
    title: Translation.tr("Sidebar position")
    subtitle: root.summary
    engaged: paneHover.hovered

    HoverHandler {
        id: paneHover
    }

    IslandSegmentedToggle {
        Layout.fillWidth: true
        segmentHeight: root.segmentHeight
        labelMinWidth: root.labelMinWidth
        options: root.arrangements
        currentValue: root.current
        onSelected: value => Config.options.sidebar.position = value
    }
}
