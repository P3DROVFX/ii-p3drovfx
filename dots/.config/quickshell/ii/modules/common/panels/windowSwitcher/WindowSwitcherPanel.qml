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
 * slides between them; the keys never wait for it. Over the cards, while the list is narrowed
 * down, the search line; under them the selected window said in full - a shrunken card cuts
 * its title short - and the hints line.
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
            /// The search line over the cards, while there is a query or Alt+` keeps to one app.
            readonly property bool narrowed: panelWindow.searching || WindowSwitcher.appFilter !== ""
            readonly property real headerHeight: panelWindow.narrowed ? 40 : 0
            /// Under the cards: the selected window in full, then the hints line if it has anything to say.
            readonly property bool hintsShown: WindowSwitcher.showKeyHints || panelWindow.scrolls
            readonly property real footerHeight: 10 + 24 + (panelWindow.hintsShown ? 20 : 0)
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
            // Up while peeking too, as the island is: the peek is something to look past, and a
            // switcher that vanished the moment you held still left you nothing to steer by.
            readonly property bool open: panelWindow.entered && root.showing
            Component.onCompleted: Qt.callLater(() => panelWindow.entered = true)

            StyledRectangularShadow {
                target: panelBackground
            }

            Rectangle {
                id: panelBackground
                anchors.centerIn: parent
                width: Math.max(panelWindow.narrowed || panelWindow.hintsShown ? 380 : 260,
                    panelWindow.viewportWidth + panelWindow.padding * 2)
                height: panelWindow.headerHeight + panelWindow.gridHeight + panelWindow.footerHeight + panelWindow.padding * 2
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

                // What has been typed (and whose windows, with Alt+`), over the cards it filters.
                Item {
                    id: searchHeader
                    x: panelWindow.padding
                    y: panelWindow.padding
                    width: parent.width - panelWindow.padding * 2
                    height: panelWindow.headerHeight
                    visible: panelWindow.narrowed
                    opacity: panelWindow.narrowed ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.standard
                        }
                    }

                    SwitcherSearchLine {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -4
                        maxWidth: searchHeader.width - 8
                    }
                }

                // The selected window in full, and the hints line, under the cards.
                Item {
                    id: footer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: panelWindow.padding
                    anchors.rightMargin: panelWindow.padding
                    anchors.bottomMargin: panelWindow.padding
                    height: panelWindow.footerHeight

                    SwitcherTitleLine {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10
                        height: 24
                        maxWidth: footer.width
                        entry: WindowSwitcher.selectedEntry
                    }
                    SwitcherHints {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10 + 24
                        width: footer.width
                        height: 20
                        showPosition: panelWindow.scrolls
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
                    anchors.bottomMargin: panelWindow.padding + panelWindow.footerHeight
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
                        // Centred when the panel is wider than the cards (its header and footer
                        // keep it from getting too narrow), scrolled once they overflow it.
                        x: panelWindow.scrolls ? -panelWindow.scrollTarget
                            : Math.round((viewport.width - panelWindow.gridWidth) / 2)

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
