pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.appDrawer

/**
 * Alt+Tab on the island: a cover flow of live window previews over the selected title.
 *
 * A view on WindowSwitcher and nothing more - every key is a compositor bind that lands in
 * the service. The selected window faces the user in the middle; its neighbours turn
 * towards it, shrink and dim. The flow is a loop: past the last window comes the first
 * again, sliding in from the side Tab is heading to.
 *
 * Every cover keeps its own offset from the selection and slides it back to its slot along
 * the shorter way round the loop. A burst of Tabs therefore retargets instead of queueing,
 * and a window closing mid-switch lets the others close the gap instead of popping.
 *
 * Only covers within `reach` of the middle capture their window, so fifteen windows cost
 * seven streams at most.
 *
 * Its size is not its own to declare: NotchContent works it out from the screen and the
 * window count, because the island has to start growing the moment the switcher takes it,
 * before this face has even been built.
 */
Item {
    id: root

    property bool shown: false
    /// The box of the middle cover; each window keeps its own aspect inside it.
    property real coverWidth: 300
    property real coverHeight: 188
    property real topPadding: 16
    property real titleGap: 10
    property real titleHeight: 22

    readonly property int count: WindowSwitcher.count
    readonly property int selectedIndex: WindowSwitcher.selectedIndex
    /// Two windows only ever swap places; three or more go round.
    readonly property bool loops: root.count > 2
    /// Covers this many slots either side of the middle are drawn and captured.
    readonly property int reach: 3
    readonly property bool thumbnails: Config.options.windowSwitcher.showThumbnails
    /// The first neighbour's distance from the middle, in pixels.
    readonly property real neighbourStep: root.coverWidth * 0.62
    /**
     * Two windows have no neighbour on one side: the pair moves over to sit in the middle
     * of the island, and the selection and its title move with it. The turned neighbour
     * is about half a cover wide, so the pair's middle is a fifth of a cover off the
     * selection's.
     */
    readonly property real pairShift: root.count === 2 ? (root.selectedIndex - 0.5) * root.coverWidth * 0.4 : 0
    property real flowShift: root.pairShift
    Behavior on flowShift {
        NumberAnimation {
            duration: Appearance.animation.elementMoveSnap.duration
            easing.type: Appearance.animation.elementMoveSnap.type
            easing.bezierCurve: Appearance.animation.elementMoveSnap.bezierCurve
        }
    }

    /// The offset `d` brought round the loop into (-count/2, count/2].
    function wrap(d: real): real {
        if (!root.loops)
            return d;
        return d - root.count * Math.round(d / root.count);
    }

    // Wheel or swipe steps through the flow. Under the covers, so clicks still reach them.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        property real wheelDelta: 0
        onWheel: wheel => {
            const delta = wheel.angleDelta.x !== 0 ? -wheel.angleDelta.x : wheel.angleDelta.y;
            wheelDelta += delta;
            while (Math.abs(wheelDelta) >= 120) {
                WindowSwitcher.step(wheelDelta < 0 ? 1 : -1);
                wheelDelta -= wheelDelta < 0 ? -120 : 120;
            }
        }
    }

    Item {
        id: stage
        anchors.fill: parent
        clip: true

        readonly property real fadePx: Math.min(root.coverWidth * 0.45, stage.width * 0.18)
        // From five windows the covers run off both ends of the pill; fade them out rather
        // than cut them. Fewer all fit, and would only lose their outer edges to the fade.
        layer.enabled: root.count > 4
        layer.effect: TabletEdgeFade {
            horizontal: 1
            startAlpha: 0
            endAlpha: 0
            startStop: stage.width > 0 ? stage.fadePx / stage.width : 0
            endStop: stage.width > 0 ? 1 - stage.fadePx / stage.width : 1
        }

        Repeater {
            model: ScriptModel {
                values: WindowSwitcher.entries
                objectProp: "address"
            }

            delegate: Item {
                id: cover
                required property var modelData
                required property int index

                readonly property var entry: WindowSwitcher.entries[cover.index] ?? cover.modelData
                readonly property bool selected: cover.index === root.selectedIndex

                /// Where this cover belongs, in slots from the middle.
                readonly property real goal: root.wrap(cover.index - root.selectedIndex)
                /// The slot it is sliding back to, and how far from it the slide still has to go.
                property real base: cover.goal
                property real lag: 0
                /// Where it is drawn: the slot plus what is left of the slide, round the loop.
                readonly property real d: root.wrap(cover.base + cover.lag)
                readonly property real c: Math.max(-1, Math.min(1, cover.d))
                readonly property real a: Math.abs(cover.d)

                // Start the slide from where the cover is now, whatever it was doing, and go
                // the short way round: Tab past the end carries the flow on, never back.
                onGoalChanged: {
                    let offset = cover.base + cover.lag - cover.goal;
                    if (root.loops)
                        offset -= root.count * Math.round(offset / root.count);
                    settle.stop();
                    cover.base = cover.goal;
                    cover.lag = offset;
                    settle.start();
                }
                NumberAnimation {
                    id: settle
                    target: cover
                    property: "lag"
                    to: 0
                    duration: Appearance.animation.elementMoveSnap.duration
                    easing.type: Appearance.animation.elementMoveSnap.type
                    easing.bezierCurve: Appearance.animation.elementMoveSnap.bezierCurve
                }

                // The first neighbour sits most of a cover away; the ones past it stack closer.
                x: Math.round(root.width / 2 - root.coverWidth / 2 + root.flowShift
                    + cover.c * root.neighbourStep + (cover.d - cover.c) * root.coverWidth * 0.24)
                y: root.topPadding
                z: -cover.a
                width: root.coverWidth
                height: root.coverHeight
                visible: cover.a < root.reach + 0.75 && cover.opacity > 0.001
                antialiasing: true

                // With few windows the loop's seam is on screen: a cover crossing it fades out
                // on one side and back in on the other.
                readonly property real seamFade: root.loops
                    ? Math.max(0, Math.min(1, (root.count / 2 - cover.a) / 0.5)) : 1
                // A window opened mid-switch fades in rather than appearing.
                property real born: 0
                opacity: cover.born * cover.seamFade
                Component.onCompleted: cover.born = 1
                Behavior on born {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                scale: 1 - Math.min(cover.a, 1) * 0.16
                transform: Rotation {
                    origin.x: root.coverWidth / 2
                    origin.y: root.coverHeight / 2
                    axis {
                        x: 0
                        y: 1
                        z: 0
                    }
                    angle: -cover.c * 50
                }

                readonly property string iconPath: {
                    const _ = TaskbarApps.iconThemeRevision;
                    return Quickshell.iconPath(AppSearch.guessIcon(cover.entry?.appClass ?? ""), "image-missing");
                }
                // The window's own aspect: the captured frame once there is one, Hyprland's size until then.
                readonly property real sourceAspect: {
                    if (screencopy.hasContent && screencopy.sourceSize.width > 0 && screencopy.sourceSize.height > 0)
                        return screencopy.sourceSize.width / screencopy.sourceSize.height;
                    return (cover.entry?.width ?? 16) / Math.max(1, cover.entry?.height ?? 9);
                }

                ClippingRectangle {
                    id: picture
                    anchors.centerIn: parent
                    width: root.thumbnails
                        ? Math.round(Math.min(root.coverWidth, root.coverHeight * cover.sourceAspect)) : root.coverWidth
                    height: root.thumbnails
                        ? Math.round(Math.min(root.coverHeight, root.coverWidth / cover.sourceAspect)) : root.coverHeight
                    radius: Appearance.rounding.normal
                    // Without a picture the cover is the box itself; lift it off the island.
                    color: root.thumbnails ? Appearance.colors.colLayer1 : Appearance.colors.colLayer2
                    antialiasing: true

                    ScreencopyView {
                        id: screencopy
                        anchors.fill: parent
                        // Let go of windows far round the loop; the near ones keep streaming.
                        captureSource: root.thumbnails && cover.a < root.reach + 1 && cover.entry?.toplevel
                            ? cover.entry.toplevel : null
                        live: root.shown && cover.a < root.reach + 0.5
                        constraintSize: Qt.size(Math.round(root.coverWidth), Math.round(root.coverHeight))
                    }

                    // Until the first frame lands, for windows that cannot be captured, and
                    // as the whole cover with thumbnails off.
                    Image {
                        anchors.centerIn: parent
                        visible: !screencopy.hasContent
                        source: cover.iconPath
                        width: Math.round(Math.min(96, parent.height * 0.45))
                        height: width
                        sourceSize: Qt.size(width, height)
                        asynchronous: true
                    }

                    // Neighbours sink back into the island.
                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.m3colors.m3shadow
                        opacity: Math.min(cover.a, 2) * 0.22
                    }
                }

                // The selection ring, fading as the cover leaves the middle.
                Rectangle {
                    anchors.centerIn: picture
                    width: picture.width + 6
                    height: picture.height + 6
                    radius: picture.radius + 3
                    color: "transparent"
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
                    opacity: Math.max(0, 1 - cover.a * 1.5)
                }

                MouseArea {
                    anchors.fill: picture
                    acceptedButtons: Qt.LeftButton
                    onClicked: WindowSwitcher.activate(cover.index)
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
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.flowShift
        y: root.topPadding + root.coverHeight + root.titleGap
        width: Math.min(root.width - 48, root.coverWidth * 1.6)
        height: root.titleHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.normal
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
