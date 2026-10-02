pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.appDrawer

/**
 * Alt+Tab as a floating panel: the face used when the Dynamic Island is off (or is not on
 * the monitor being used). Every family loads it, because WindowSwitcher's binds have to be
 * taken away again when the setting goes off, and something has to hold the service for that.
 *
 * Cards sit in a grid of at most two rows. With more windows than fit, the cards shrink to a
 * floor and the grid then scrolls sideways to keep the selection in view. One highlight
 * slides between them; the keys never wait for it.
 *
 * The window is built in the background from Alt+Tab, so it is ready when the quick-tap
 * window runs out, and torn down after its exit - nothing of it exists while closed.
 */
Scope {
    id: root

    component SnapBehaviorAnimation: NumberAnimation {
        duration: Appearance.animation.elementMoveSnap.duration
        easing.type: Appearance.animation.elementMoveSnap.type
        easing.bezierCurve: Appearance.animation.elementMoveSnap.bezierCurve
    }
    component ResizeAnimation: NumberAnimation {
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    readonly property bool mine: WindowSwitcher.presenter === "panel"
    readonly property bool showing: root.mine && WindowSwitcher.shown
    /// Kept for the exit animation after the switcher itself has closed.
    property bool lingering: false

    // The peek belongs to both faces; this module is the one every family loads.
    WindowSwitcherPeek {}

    onShowingChanged: {
        if (root.showing) {
            lingerTimer.stop();
            root.lingering = false;
        } else if (switcherLoader.item) {
            root.lingering = true;
            lingerTimer.restart();
        }
    }

    Timer {
        id: lingerTimer
        interval: Appearance.animation.elementMoveExit.duration + 40
        onTriggered: root.lingering = false
    }

    Loader {
        id: switcherLoader
        active: WindowSwitcher.enabled && ((root.mine && WindowSwitcher.active) || root.lingering)
        asynchronous: true

        sourceComponent: PanelWindow {
            id: panelWindow

            readonly property var targetScreen: Quickshell.screens.find(s => s.name === WindowSwitcher.screenName)
                ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

            visible: root.showing || root.lingering
            screen: panelWindow.targetScreen
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:windowSwitcher"
            WlrLayershell.layer: WlrLayer.Overlay
            // Never the keyboard: the keys are binds (see WindowSwitcher), and taking focus
            // would take it from the window being switched away from.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {
                item: panelBackground
            }

            // ---------------------------------------------------------- layout

            readonly property bool thumbnails: Config.options.windowSwitcher.showThumbnails
            readonly property real screenWidth: panelWindow.targetScreen?.width ?? 1920
            readonly property real screenHeight: panelWindow.targetScreen?.height ?? 1080
            readonly property real padding: 14
            readonly property real cardPadding: 10
            readonly property real gap: 6
            readonly property real titleHeight: 22
            readonly property bool searching: WindowSwitcher.query.length > 0
            /// The search line over the cards, only while there is a query.
            readonly property real headerHeight: panelWindow.searching ? 40 : 0
            /// The widest the card area may get before it scrolls.
            readonly property real maxGridWidth: Math.round(panelWindow.screenWidth * 0.86) - panelWindow.padding * 2

            readonly property real baseBoxHeight: panelWindow.thumbnails
                ? Math.round(Math.min(170, panelWindow.screenHeight * 0.16)) : 64
            readonly property real baseBoxWidth: panelWindow.thumbnails
                ? Math.round(panelWindow.baseBoxHeight * 1.6) : 112
            readonly property real baseCellWidth: panelWindow.baseBoxWidth + panelWindow.cardPadding * 2

            readonly property int count: WindowSwitcher.count
            readonly property int fitColumns: Math.max(1, Math.floor((panelWindow.maxGridWidth + panelWindow.gap)
                / (panelWindow.baseCellWidth + panelWindow.gap)))
            readonly property int rows: panelWindow.count <= panelWindow.fitColumns ? 1 : 2
            readonly property int columns: panelWindow.rows === 1 ? Math.max(1, panelWindow.count)
                : Math.ceil(panelWindow.count / 2)
            /// Shrinks the cards (never below 62 %) before resorting to scrolling.
            readonly property real cardScale: {
                const needed = panelWindow.columns * (panelWindow.baseCellWidth + panelWindow.gap) - panelWindow.gap;
                return Math.max(0.62, Math.min(1, panelWindow.maxGridWidth / needed));
            }
            readonly property real boxWidth: Math.round(panelWindow.baseBoxWidth * panelWindow.cardScale)
            readonly property real boxHeight: Math.round(panelWindow.baseBoxHeight * panelWindow.cardScale)
            readonly property real cellWidth: panelWindow.boxWidth + panelWindow.cardPadding * 2
            readonly property real cellHeight: panelWindow.boxHeight + panelWindow.titleHeight + panelWindow.cardPadding * 3
            readonly property real gridWidth: panelWindow.columns * (panelWindow.cellWidth + panelWindow.gap) - panelWindow.gap
            readonly property real gridHeight: panelWindow.rows * (panelWindow.cellHeight + panelWindow.gap) - panelWindow.gap
            readonly property real viewportWidth: Math.min(panelWindow.gridWidth, panelWindow.maxGridWidth)
            readonly property bool scrolls: panelWindow.gridWidth > panelWindow.maxGridWidth + 0.5

            function cellX(index: int): real {
                return (index % panelWindow.columns) * (panelWindow.cellWidth + panelWindow.gap);
            }
            function cellY(index: int): real {
                return Math.floor(index / panelWindow.columns) * (panelWindow.cellHeight + panelWindow.gap);
            }

            Binding {
                target: WindowSwitcher
                property: "columns"
                value: panelWindow.rows > 1 ? panelWindow.columns : 0
                when: root.mine
                restoreMode: Binding.RestoreValue
            }

            /// Keeps the selection centred once the grid is wider than the viewport.
            readonly property real scrollTarget: {
                if (!panelWindow.scrolls)
                    return 0;
                const centre = panelWindow.cellX(WindowSwitcher.selectedIndex) + panelWindow.cellWidth / 2;
                return Math.max(0, Math.min(panelWindow.gridWidth - panelWindow.viewportWidth,
                    centre - panelWindow.viewportWidth / 2));
            }

            // ---------------------------------------------------------- motion

            /// Set a turn after mapping, so the first frame is the closed state and the entry animates.
            property bool entered: false
            // Out of the way while peeking: the panel sits right over the window being peeked at.
            // Not while searching, though - a pause to read the matches must not hide them.
            readonly property bool open: panelWindow.entered && root.showing
                && (!WindowSwitcher.peeking || panelWindow.searching)
            Component.onCompleted: Qt.callLater(() => panelWindow.entered = true)

            StyledRectangularShadow {
                target: panelBackground
            }

            Rectangle {
                id: panelBackground
                anchors.centerIn: parent
                width: Math.max(panelWindow.searching ? 320 : 0, panelWindow.viewportWidth + panelWindow.padding * 2)
                height: panelWindow.headerHeight + panelWindow.gridHeight + panelWindow.padding * 2
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                opacity: panelWindow.open ? 1 : 0
                scale: panelWindow.open ? 1 : 0.94

                // Enter decelerates in, exit accelerates out: the same short duration both
                // ways, so a quick re-open meets the panel where it is.
                Behavior on opacity {
                    NumberAnimation {
                        duration: panelWindow.open ? Appearance.animation.elementMoveFast.duration
                            : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: panelWindow.open ? Appearance.animationCurves.emphasizedDecel
                            : Appearance.animationCurves.emphasizedAccel
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: panelWindow.open ? Appearance.animation.elementMoveFast.duration
                            : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: panelWindow.open ? Appearance.animationCurves.emphasizedDecel
                            : Appearance.animationCurves.emphasizedAccel
                    }
                }
                // A window closing or arriving reflows the grid; the panel follows.
                Behavior on width {
                    ResizeAnimation {}
                }
                Behavior on height {
                    ResizeAnimation {}
                }

                // What has been typed, over the cards it filters.
                Item {
                    id: searchHeader
                    x: panelWindow.padding
                    y: panelWindow.padding
                    width: parent.width - panelWindow.padding * 2
                    height: panelWindow.headerHeight
                    visible: panelWindow.searching
                    opacity: panelWindow.searching ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.standard
                        }
                    }

                    MaterialSymbol {
                        id: searchIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -4
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        anchors.left: searchIcon.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.verticalCenter: searchIcon.verticalCenter
                        elide: Text.ElideLeft
                        text: WindowSwitcher.query
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                    }
                }

                StyledText {
                    anchors.centerIn: viewport
                    visible: panelWindow.searching && WindowSwitcher.count === 0
                    text: Translation.tr("No windows match")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Item {
                    id: viewport
                    anchors.fill: parent
                    anchors.margins: panelWindow.padding
                    anchors.topMargin: panelWindow.padding + panelWindow.headerHeight
                    clip: panelWindow.scrolls

                    // Faded edges where cards run on past the viewport. Only while it scrolls:
                    // the layer re-renders every live thumbnail into a texture.
                    readonly property real fadePx: 32
                    layer.enabled: panelWindow.scrolls
                    layer.effect: TabletEdgeFade {
                        horizontal: 1
                        startAlpha: grid.x < -1 ? 0 : 1
                        endAlpha: grid.x + panelWindow.gridWidth > viewport.width + 1 ? 0 : 1
                        startStop: viewport.width > 0 ? viewport.fadePx / viewport.width : 0
                        endStop: viewport.width > 0 ? 1 - viewport.fadePx / viewport.width : 1
                    }

                    Item {
                        id: grid
                        width: panelWindow.gridWidth
                        height: panelWindow.gridHeight
                        x: -panelWindow.scrollTarget

                        Behavior on x {
                            SnapBehaviorAnimation {}
                        }

                        // The one selection: it retargets from wherever it is, so a burst of
                        // Tabs is one motion towards the last card, never a queue of legs.
                        Rectangle {
                            id: highlight
                            visible: WindowSwitcher.count > 0
                            x: panelWindow.cellX(WindowSwitcher.selectedIndex)
                            y: panelWindow.cellY(WindowSwitcher.selectedIndex)
                            width: panelWindow.cellWidth
                            height: panelWindow.cellHeight
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSecondaryContainer

                            Behavior on x {
                                SnapBehaviorAnimation {}
                            }
                            Behavior on y {
                                SnapBehaviorAnimation {}
                            }
                            Behavior on width {
                                ResizeAnimation {}
                            }
                            Behavior on height {
                                ResizeAnimation {}
                            }
                        }

                        Repeater {
                            model: ScriptModel {
                                values: WindowSwitcher.entries
                                objectProp: "address"
                            }

                            delegate: SwitcherCard {
                                id: card
                                required property var modelData
                                required property int index

                                // The live entry: the model keeps the delegate by address, the
                                // service keeps the title current.
                                entry: WindowSwitcher.entries[card.index] ?? card.modelData
                                selected: card.index === WindowSwitcher.selectedIndex
                                thumbnails: panelWindow.thumbnails
                                boxWidth: panelWindow.boxWidth
                                boxHeight: panelWindow.boxHeight
                                padding: panelWindow.cardPadding
                                capturing: root.showing && panelWindow.thumbnails && !WindowSwitcher.peeking
                                    && card.x + card.width >= panelWindow.scrollTarget
                                    && card.x <= panelWindow.scrollTarget + panelWindow.viewportWidth

                                x: panelWindow.cellX(card.index)
                                y: panelWindow.cellY(card.index)
                                width: panelWindow.cellWidth
                                height: panelWindow.cellHeight

                                Behavior on x {
                                    SnapBehaviorAnimation {}
                                }
                                Behavior on y {
                                    SnapBehaviorAnimation {}
                                }

                                onHovered: scenePos => WindowSwitcher.hover(card.index, scenePos)
                                onClicked: WindowSwitcher.activate(card.index)
                                onCloseRequested: WindowSwitcher.closeAt(card.index)
                            }
                        }
                    }

                }
            }
        }
    }
}
