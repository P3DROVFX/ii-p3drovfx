import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Several dock widgets in one slot, one page at a time. The wheel turns the
 * page with a vertical slide; a column of dots in the slot's side gutter says
 * how many pages there are and which one is up.
 *
 * Only the page on show exists. The page that leaves lives exactly as long
 * as its slide, so a stack of five widgets costs one widget at rest - the
 * media card's colour extraction and a live preview's capture stop the moment
 * their page is turned away.
 *
 * The slot is as wide as the widest member, so turning a page never moves
 * the rest of the dock; narrower widgets sit centred in it.
 */
Item {
    id: root

    property var dockContent: null
    property int delegateIndex: -1
    property bool isVertical: false
    property var members: []
    // Which member is up, by type, owned by the dock so a model rebuild (an
    // app opening) does not throw the stack back to its first page.
    property string currentType: ""
    signal currentTypeRequested(string type)

    // Found by the members' _getSlotMagScale() walk, which only climbs a few
    // parents: re-published here so a page widget is close enough to it.
    readonly property real _magnificationScale: root.dockContent ? root.dockContent._getSlotMagScale(root.parent) : 1.0

    readonly property int pageCount: root.members.length
    readonly property int currentIndex: Math.max(0, root.members.indexOf(root.currentType))
    readonly property string shownType: root.pageCount > 0 ? root.members[root.currentIndex] : ""

    readonly property real dotMargin: root.dockContent?.dotMargin ?? 8
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin

    // ── Pages ──────────────────────────────────────────────────────────────
    // Two loaders take turns: `front` holds the page on show, `back` the page
    // coming in. When the slide ends they swap roles and the leaving page is
    // unloaded.
    property bool frontIsA: true
    readonly property Loader frontLoader: frontIsA ? pageA : pageB
    readonly property Loader backLoader: frontIsA ? pageB : pageA
    property real slideProgress: 0
    // +1: the new page rises from below (next); -1: it drops from above.
    property int slideDirection: 1
    readonly property bool sliding: slideAnimation.running
    readonly property real travel: clipBox.height

    function _componentFor(type) {
        switch (type) {
        case "media": return mediaPage;
        case "weather": return weatherPage;
        case "sports": return sportsPage;
        case "livePreview": return livePreviewPage;
        case "tasks": return tasksPage;
        default: return null;
        }
    }

    // Set by turn() just before the type changes; any other change (a member
    // appearing or leaving) slides forward.
    property int _pendingDirection: 1

    function turn(step) {
        if (root.pageCount < 2 || root.sliding)
            return false;
        const next = (root.currentIndex + step + root.pageCount) % root.pageCount;
        root._pendingDirection = step < 0 ? -1 : 1;
        root.currentTypeRequested(root.members[next]);
        return true;
    }

    // The page on show follows `shownType`; a change slides unless nothing is
    // on screen yet (first build) or the stack has a single page.
    onShownTypeChanged: root._present(root.shownType)
    Component.onCompleted: {
        root.frontLoader.pageType = root.shownType;
    }

    function _present(type) {
        if (root.frontLoader.pageType === type)
            return;
        if (!root.frontLoader.pageType || Appearance.reducedMotion || !root.visible) {
            slideAnimation.stop();
            root.backLoader.pageType = "";
            root.frontLoader.pageType = type;
            root.slideProgress = 0;
            return;
        }
        if (root.sliding) {
            // Finish the running slide at once; the new target starts from rest.
            slideAnimation.stop();
            root._finishSlide();
        }
        root.slideDirection = root._pendingDirection;
        root._pendingDirection = 1;
        root.backLoader.pageType = type;
        root.slideProgress = 0;
        slideAnimation.restart();
    }

    function _finishSlide() {
        const leaving = root.frontLoader;
        root.frontIsA = !root.frontIsA;
        root.slideProgress = 0;
        leaving.pageType = "";
    }

    NumberAnimation {
        id: slideAnimation
        target: root
        property: "slideProgress"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveSmall.duration
        easing.type: Appearance.animation.elementMoveSmall.type
        easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
        onFinished: root._finishSlide()
    }

    // Pages only overflow the card while they slide; clipping the rest of the
    // time would also cut the magnified card, which grows past the slot. The
    // clip is the card's box scaled by the lens around the same origin the
    // members scale around, so a magnified card is not cut mid-slide.
    readonly property int _origin: root.dockContent?.magnificationTransformOrigin ?? Item.Bottom
    readonly property point _originPoint: root._origin === Item.Top ? Qt.point(root.width / 2, 0)
        : root._origin === Item.Left ? Qt.point(0, root.height / 2)
        : root._origin === Item.Right ? Qt.point(root.width, root.height / 2)
        : Qt.point(root.width / 2, root.height)
    Item {
        id: clipBox
        readonly property real m: root._magnificationScale
        x: root._originPoint.x - root._originPoint.x * m
        y: root._originPoint.y + (root.dotMarginV - root._originPoint.y) * m
        width: root.width * m
        height: (root.height - root.dotMarginV * 2) * m
        clip: root.sliding

        PageLoader {
            id: pageA
            isFront: root.frontIsA
        }
        PageLoader {
            id: pageB
            isFront: !root.frontIsA
        }
    }

    component PageLoader: Loader {
        id: page
        property string pageType: ""
        property bool isFront: false
        readonly property real _magnificationScale: root._magnificationScale

        // In the stack's own coordinates, whatever the clip box does.
        x: -clipBox.x
        width: root.width
        height: root.height
        // The front page moves out the way the new one comes in; the
        // overshoot of the expressive curve carries both.
        y: -clipBox.y + (page.isFront
            ? -root.slideDirection * root.travel * root.slideProgress
            : root.slideDirection * root.travel * (1 - root.slideProgress))
        opacity: page.isFront ? 1 - Math.min(1, root.slideProgress * 1.4)
            : Math.min(1, root.slideProgress * 1.4)
        active: page.pageType !== ""
        visible: active
        sourceComponent: root._componentFor(page.pageType)
    }

    // ── Wheel ──────────────────────────────────────────────────────────────
    // A notch turns one page. Touchpads report many small deltas, so they add
    // up to a notch first, and nothing turns while a slide is still running.
    // Members that scroll their own content (the task list) take the wheel
    // first and only let it through at their ends.
    property real _wheelAccumulator: 0
    WheelHandler {
        target: null
        enabled: root.pageCount > 1
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            event.accepted = true;
            const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
            if (root.sliding) {
                root._wheelAccumulator = 0;
                return;
            }
            root._wheelAccumulator += delta;
            if (Math.abs(root._wheelAccumulator) < 120)
                return;
            const step = root._wheelAccumulator < 0 ? 1 : -1;
            root._wheelAccumulator = 0;
            root.turn(step);
        }
    }

    // ── Page indicator ─────────────────────────────────────────────────────
    // In the slot's side gutter, outside the card, scaled with the lens so it
    // keeps to the card's edge while magnified.
    Item {
        anchors.fill: parent
        visible: root.pageCount > 1
        scale: root._magnificationScale
        transformOrigin: root.dockContent?.magnificationTransformOrigin ?? Item.Bottom

        Item {
            id: gutter
            // Beside the card on a horizontal dock, under it on a vertical one.
            readonly property bool below: root.isVertical
            x: below ? 0 : parent.width - root.dotMargin
            y: below ? parent.height - root.dotMarginV : 0
            width: below ? parent.width : root.dotMargin
            height: below ? root.dotMarginV : parent.height

            Grid {
                anchors.centerIn: parent
                columns: gutter.below ? root.pageCount : 1
                spacing: 3

                Repeater {
                    model: root.pageCount

                    delegate: Rectangle {
                        required property int index
                        readonly property bool current: index === root.currentIndex
                        readonly property real dot: Math.max(3, Math.round(Math.min(root.dotMargin, root.dotMarginV) * 0.42))
                        width: gutter.below && current ? dot * 3 : dot
                        height: !gutter.below && current ? dot * 3 : dot
                        radius: dot / 2
                        color: current ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                        Behavior on width {
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                        }
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.turn(1)
            }
        }
    }

    // ── Page components ────────────────────────────────────────────────────
    Component {
        id: mediaPage
        Item {
            Loader {
                anchors.centerIn: parent
                active: root.dockContent?.dockWidgetsActive ?? true
                sourceComponent: DockMediaWidget {
                    isVertical: root.isVertical
                    dockContent: root.dockContent
                    delegateIndex: root.delegateIndex
                }
            }
        }
    }
    Component {
        id: weatherPage
        Item {
            DockWeatherWidget {
                anchors.centerIn: parent
                isVertical: root.isVertical
                dockContent: root.dockContent
                delegateIndex: root.delegateIndex
            }
        }
    }
    Component {
        id: sportsPage
        Item {
            DockSportsWidget {
                anchors.centerIn: parent
                isVertical: root.isVertical
                dockContent: root.dockContent
                delegateIndex: root.delegateIndex
            }
        }
    }
    Component {
        id: livePreviewPage
        Item {
            Loader {
                anchors.centerIn: parent
                active: root.dockContent?.dockWidgetsActive ?? true
                sourceComponent: DockLivePreviewWidget {
                    isVertical: root.isVertical
                    dockContent: root.dockContent
                    dockRevealed: root.dockContent?.dockRevealed ?? true
                    dockWindowVisible: root.dockContent?.dockWindowVisible ?? true
                    delegateIndex: root.delegateIndex
                }
            }
        }
    }
    Component {
        id: tasksPage
        Item {
            DockTasksWidget {
                anchors.centerIn: parent
                isVertical: root.isVertical
                dockContent: root.dockContent
                delegateIndex: root.delegateIndex
            }
        }
    }
}
