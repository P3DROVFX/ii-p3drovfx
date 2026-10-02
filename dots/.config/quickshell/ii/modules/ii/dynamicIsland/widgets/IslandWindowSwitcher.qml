pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.appDrawer

/**
 * Alt+Tab on the island: one row of app icons over the selected window's title.
 *
 * A view on WindowSwitcher and nothing more - every key is a compositor bind that lands in
 * the service. One container slides behind the selected icon, which grows a little; the
 * title below crossfades as the selection moves. When the icons outrun the island the row
 * scrolls to keep the selection centred and fades out at the edges.
 *
 * Its size is not its own to declare: NotchContent works it out from the window count
 * (`slot`, the paddings), because the island has to start growing the moment the switcher
 * takes it, before this face has even been built.
 */
Item {
    id: root

    property bool shown: false
    property real slot: 52
    property real iconSize: 36
    property real sidePadding: 14
    property real topPadding: 12
    property real rowHeight: 52
    property real titleGap: 4
    property real titleHeight: 20

    readonly property int count: WindowSwitcher.count
    readonly property int selectedIndex: WindowSwitcher.selectedIndex
    readonly property real rowWidth: root.count * root.slot
    readonly property real viewWidth: Math.max(0, root.width - root.sidePadding * 2)
    readonly property bool overflows: root.rowWidth > root.viewWidth + 0.5
    /**
     * Where the row sits: centred while it fits, otherwise scrolled so the selection is in
     * the middle, clamped at both ends.
     */
    readonly property real rowX: {
        if (!root.overflows)
            return Math.round((root.viewWidth - root.rowWidth) / 2);
        const centre = root.selectedIndex * root.slot + root.slot / 2;
        return -Math.max(0, Math.min(root.rowWidth - root.viewWidth, centre - root.viewWidth / 2));
    }

    component SnapAnimation: NumberAnimation {
        duration: Appearance.animation.elementMoveSnap.duration
        easing.type: Appearance.animation.elementMoveSnap.type
        easing.bezierCurve: Appearance.animation.elementMoveSnap.bezierCurve
    }

    Item {
        id: viewport
        x: root.sidePadding
        y: root.topPadding
        width: root.viewWidth
        height: root.rowHeight
        clip: true

        readonly property real fadePx: 40
        // Only while it overflows: with every icon in view there is nothing to fade.
        layer.enabled: root.overflows
        layer.effect: TabletEdgeFade {
            horizontal: 1
            startAlpha: row.x < -1 ? 0 : 1
            endAlpha: row.x + root.rowWidth > viewport.width + 1 ? 0 : 1
            startStop: viewport.width > 0 ? viewport.fadePx / viewport.width : 0
            endStop: viewport.width > 0 ? 1 - viewport.fadePx / viewport.width : 1
        }

        Item {
            id: row
            x: root.rowX
            width: root.rowWidth
            height: root.rowHeight

            Behavior on x {
                SnapAnimation {}
            }

            // The one selection; retargets from wherever it is, so a burst of Tabs is one
            // motion towards the last icon rather than a queue of legs.
            Rectangle {
                id: highlight
                visible: root.count > 0
                readonly property real size: root.rowHeight - 4
                x: root.selectedIndex * root.slot + (root.slot - highlight.size) / 2
                y: (root.rowHeight - highlight.size) / 2
                width: highlight.size
                height: highlight.size
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSecondaryContainer

                Behavior on x {
                    SnapAnimation {}
                }
            }

            Repeater {
                model: ScriptModel {
                    values: WindowSwitcher.entries
                    objectProp: "address"
                }

                delegate: Item {
                    id: slotItem
                    required property var modelData
                    required property int index

                    readonly property var entry: WindowSwitcher.entries[slotItem.index] ?? slotItem.modelData
                    readonly property bool selected: slotItem.index === root.selectedIndex
                    readonly property string iconPath: {
                        const _ = TaskbarApps.iconThemeRevision;
                        return Quickshell.iconPath(AppSearch.guessIcon(slotItem.entry?.appClass ?? ""), "image-missing");
                    }

                    x: slotItem.index * root.slot
                    width: root.slot
                    height: root.rowHeight

                    // A window opened mid-switch fades in rather than appearing.
                    property bool born: false
                    opacity: slotItem.born ? 1 : 0
                    Component.onCompleted: Qt.callLater(() => slotItem.born = true)
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                    }
                    Behavior on x {
                        SnapAnimation {}
                    }

                    Image {
                        anchors.centerIn: parent
                        width: root.iconSize
                        height: root.iconSize
                        source: slotItem.iconPath
                        sourceSize: Qt.size(Math.round(root.iconSize * 1.2), Math.round(root.iconSize * 1.2))
                        asynchronous: true
                        scale: slotItem.selected ? 1.18 : 1
                        Behavior on scale {
                            SnapAnimation {}
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: mouse => WindowSwitcher.hover(slotItem.index, mapToItem(null, mouse.x, mouse.y))
                        onClicked: WindowSwitcher.activate(slotItem.index)
                    }
                }
            }
        }
    }

    // ── Title ────────────────────────────────────────────────────────────────
    // Two labels trade places: the new title fades in over the old one fading out. Both
    // animations restart from wherever they are, so a held Tab never queues fades.
    readonly property var selectedEntry: WindowSwitcher.selectedEntry
    readonly property string selectedTitle: root.selectedEntry
        ? (root.selectedEntry.toplevel?.title || root.selectedEntry.title || root.selectedEntry.appClass) : ""
    property bool firstLabel: true

    onSelectedTitleChanged: {
        root.firstLabel = !root.firstLabel;
        (root.firstLabel ? titleA : titleB).text = root.selectedTitle;
    }
    Component.onCompleted: titleA.text = root.selectedTitle

    component TitleLabel: StyledText {
        required property bool current
        x: root.sidePadding
        y: root.topPadding + root.rowHeight + root.titleGap
        width: root.viewWidth
        height: root.titleHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer0
        opacity: current ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveSnap.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.standard
            }
        }
    }

    TitleLabel {
        id: titleA
        current: root.firstLabel
    }
    TitleLabel {
        id: titleB
        current: !root.firstLabel
    }
}
