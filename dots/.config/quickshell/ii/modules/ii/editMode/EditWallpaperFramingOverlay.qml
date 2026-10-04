import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Edit Mode's wallpaper, moved by hand: the overlay the desktop card turns into
 * while the Wallpaper catalogue is open on the Desktop tab.
 *
 * Drawn on the widgets surface (BackgroundWidgetsWindow), in the desktop's own
 * coordinates, because that is the surface that takes the pointer over the
 * card; the picture it moves is on the wallpaper surface below. The two meet
 * in WallpaperLayout's live values: a drag writes them, the wallpaper surface
 * draws from them, and the release is the one config write (and history
 * entry) the gesture makes.
 *
 * Gestures: drag to move, wheel or pinch to zoom about the pointer, double
 * click to start over. Everything else - turn, mirror, centre, the exact zoom -
 * is a button on the dock at the bottom of the card and on the panel.
 *
 * Things it shows so nothing happens behind the user's back:
 *   - the thirds while dragging, and the centre lines when the picture snaps
 *     to them;
 *   - a glow on any edge the picture is pressed against (there is no further
 *     to go that way - the picture always covers the screen);
 *   - a coach line naming the gestures, which turns into the reason when a
 *     gesture did nothing (no room to move at 100%, the zoom's floor and why
 *     it is there) and says "Centred" while a drag holds the centre.
 *
 * Nothing here is scaled by the card: the dock, the coach line and the guides
 * undo the card's shrink (`counterScale`) and draw at 1:1. The guides are also
 * clipped to the card's rounded corner (`cardRadius`, in screen pixels).
 */
Item {
    id: root

    required property string screenName
    // The surface's net content scale (the mode's shrink): undone by the
    // controls so they draw at native size on the card.
    property real contentScale: 1
    readonly property real counterScale: 1 / Math.max(0.05, root.contentScale)
    // The card's corner on screen (EditModeCard's), for the guides' clip.
    property real cardRadius: 0

    readonly property string sourcePath: WallpaperLayout.livePath
    readonly property var geometry: WallpaperLayout.geometryFor(root.screenName)
    readonly property bool ready: root.geometry !== null
    readonly property var frame: root.ready
        ? WallpaperFraming.layout(root.geometry.planeWidth, root.geometry.planeHeight,
            root.geometry.imageWidth, root.geometry.imageHeight,
            WallpaperLayout.liveFraming, WallpaperLayout.liveAngle)
        : null
    readonly property var target: WallpaperLayout.gestureTarget()
    readonly property bool canMoveX: root.frame !== null && root.frame.rangeX > 0.5
    readonly property bool canMoveY: root.frame !== null && root.frame.rangeY > 0.5
    readonly property bool canMove: root.canMoveX || root.canMoveY
    readonly property bool identity: WallpaperFraming.isIdentity(WallpaperLayout.liveFraming)

    // ── Gesture state ────────────────────────────────────────────────────────
    property bool dragging: false
    property var dragStart: null
    property real pressX: 0
    property real pressY: 0
    property bool snappedX: false
    property bool snappedY: false
    property bool atLeft: false
    property bool atRight: false
    property bool atTop: false
    property bool atBottom: false

    // A pointer from the plane's centre: the card is the screen, and in the
    // mode the plane sits centred on it (the parallax is held at the centre).
    function fromCentre(x, y) {
        return Qt.point(x - root.width / 2, y - root.height / 2);
    }

    function clearWalls() {
        root.atLeft = false;
        root.atRight = false;
        root.atTop = false;
        root.atBottom = false;
        root.snappedX = false;
        root.snappedY = false;
    }

    // The line under the strip, for a gesture that could not do what it was
    // asked. Shown for a moment, then the usual hint comes back.
    property string notice: ""
    function say(text) {
        root.notice = text;
        noticeTimer.restart();
    }
    Timer {
        id: noticeTimer
        interval: 2200
        onTriggered: root.notice = ""
    }

    function zoomBy(factor, px, py) {
        if (!root.ready)
            return;
        const base = WallpaperLayout.gestureTarget();
        const wanted = base.zoom * factor;
        if (wanted < WallpaperFraming.zoomMin - 0.0001 && base.zoom <= WallpaperFraming.zoomMin + 0.0001) {
            root.say(Translation.tr("100% is the smallest zoom: the lock screen zooms out to it"));
            return;
        }
        if (wanted > WallpaperFraming.zoomMax + 0.0001 && base.zoom >= WallpaperFraming.zoomMax - 0.0001) {
            root.say(Translation.tr("That is as far as it zooms"));
            return;
        }
        const g = root.geometry;
        const next = WallpaperFraming.zoomAt(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight, base, wanted, px, py);
        WallpaperLayout.stepGesture(next);
    }

    function zoomTo(zoom) {
        if (!root.ready)
            return;
        const g = root.geometry;
        WallpaperLayout.stepGesture(WallpaperFraming.zoomAt(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight,
            WallpaperLayout.gestureTarget(), zoom, 0, 0));
    }

    // The card's widgets are still there, dimmed; the pointer belongs to the
    // picture for as long as this is up.
    MouseArea {
        id: gestureArea
        anchors.fill: parent
        enabled: root.ready
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: mouse => {
            WallpaperLayout.beginGesture();
            root.dragStart = WallpaperFraming.normalize(WallpaperLayout.liveFraming);
            root.pressX = mouse.x;
            root.pressY = mouse.y;
            root.clearWalls();
            root.dragging = true;
            if (!root.canMove)
                root.say(Translation.tr("Zoom in first to make room to move it"));
        }
        onPositionChanged: mouse => {
            if (!root.dragging || root.frame === null)
                return;
            // The snap is a few pixels ON THE CARD, whatever the shrink.
            const result = WallpaperFraming.panTo(root.dragStart, mouse.x - root.pressX, mouse.y - root.pressY,
                root.frame.rangeX, root.frame.rangeY, 8 * root.counterScale);
            root.snappedX = result.snappedX;
            root.snappedY = result.snappedY;
            root.atLeft = result.atLeft;
            root.atRight = result.atRight;
            root.atTop = result.atTop;
            root.atBottom = result.atBottom;
            WallpaperLayout.updateGesture(Object.assign({}, root.dragStart, { "x": result.x, "y": result.y }));
        }
        onReleased: root.finishDrag()
        onCanceled: root.finishDrag()
        onDoubleClicked: {
            if (root.identity)
                return;
            WallpaperLayout.resetFraming(root.screenName);
            root.say(Translation.tr("Back to the full picture"));
        }
        onWheel: wheel => {
            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
            if (delta === 0)
                return;
            const p = root.fromCentre(wheel.x, wheel.y);
            root.zoomBy(Math.pow(1.0012, delta), p.x, p.y);
        }
    }

    function finishDrag() {
        if (!root.dragging)
            return;
        root.dragging = false;
        root.clearWalls();
        WallpaperLayout.endGesture();
    }

    // Touchpad and touchscreen pinches, about where the fingers are.
    PinchHandler {
        id: pinch
        target: null
        enabled: root.ready
        property var startFraming: null
        property point startCentre: Qt.point(0, 0)

        onActiveChanged: {
            if (pinch.active) {
                WallpaperLayout.beginGesture();
                pinch.startFraming = WallpaperFraming.normalize(WallpaperLayout.liveFraming);
                pinch.startCentre = root.fromCentre(pinch.centroid.position.x, pinch.centroid.position.y);
                return;
            }
            WallpaperLayout.endGesture();
        }
        onActiveScaleChanged: {
            if (!pinch.active || pinch.startFraming === null || !root.ready)
                return;
            const g = root.geometry;
            const next = WallpaperFraming.zoomAt(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight,
                pinch.startFraming, pinch.startFraming.zoom * pinch.activeScale, pinch.startCentre.x, pinch.startCentre.y);
            WallpaperLayout.updateGesture(next);
        }
    }

    // ── Guides ───────────────────────────────────────────────────────────────
    // Everything drawn over the picture lives inside the card's own corner:
    // the card is a rounded rectangle on screen, and a square guide or glow
    // laid over it leaked past the curve as a sliver of light in each corner.
    ClippingRectangle {
        id: guides
        anchors.fill: parent
        color: "transparent"
        radius: root.cardRadius * root.counterScale

        // Thirds while the picture is being moved: where a composition is
        // usually read from, which is the question a drag is answering.
        Item {
            anchors.fill: parent
            opacity: root.dragging ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Repeater {
                model: [1 / 3, 2 / 3]
                delegate: Item {
                    id: thirds
                    required property real modelData
                    anchors.fill: parent

                    Rectangle {
                        x: parent.width * thirds.modelData - width / 2
                        width: root.counterScale
                        height: parent.height
                        color: Appearance.colors.colOnSurface
                        opacity: 0.35
                    }
                    Rectangle {
                        y: parent.height * thirds.modelData - height / 2
                        width: parent.width
                        height: root.counterScale
                        color: Appearance.colors.colOnSurface
                        opacity: 0.35
                    }
                }
            }
        }

        // The centre lines, lit when the drag snaps to them.
        Rectangle {
            x: parent.width / 2 - width / 2
            width: 2 * root.counterScale
            height: parent.height
            color: Appearance.colors.colPrimary
            opacity: root.dragging && root.snappedX ? 0.9 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
        Rectangle {
            y: parent.height / 2 - height / 2
            width: parent.width
            height: 2 * root.counterScale
            color: Appearance.colors.colPrimary
            opacity: root.dragging && root.snappedY ? 0.9 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        // The walls: a soft glow fading in from an edge the picture is pressed
        // against. A gradient, not an outline.
        EdgeGlow {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: depth
            lit: root.dragging && root.atLeft
        }
        EdgeGlow {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: depth
            reversed: true
            lit: root.dragging && root.atRight
        }
        EdgeGlow {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: depth
            vertical: true
            lit: root.dragging && root.atTop
        }
        EdgeGlow {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: depth
            vertical: true
            reversed: true
            lit: root.dragging && root.atBottom
        }
    }

    component EdgeGlow: Rectangle {
        id: glow
        property bool lit: false
        property bool vertical: false
        property bool reversed: false
        readonly property real depth: 48 * root.counterScale
        opacity: glow.lit ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        gradient: Gradient {
            orientation: glow.vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop {
                position: 0
                color: glow.reversed ? "transparent" : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
            }
            GradientStop {
                position: 1
                color: glow.reversed ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) : "transparent"
            }
        }
    }

    // ── The coach line and the dock ──────────────────────────────────────────
    // Bottom centre of the card, at native size. Above the gesture area in
    // declaration order, so the dock's buttons take their own clicks.
    readonly property real controlHeight: 44
    readonly property bool hasNotice: root.notice !== ""
    // While a drag snaps to the centre, the coach line says so instead of
    // getting out of the way.
    readonly property bool showsSnap: root.dragging && (root.snappedX || root.snappedY) && !root.hasNotice

    ColumnLayout {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 * root.counterScale
        spacing: 10
        scale: root.counterScale
        transformOrigin: Item.Bottom

        // What the hand can do: three gestures as three tokens, each its own
        // shape, the verb in weight and the rest in the regular cut. A
        // gesture that did nothing turns the line tertiary and says why.
        Rectangle {
            id: coach
            Layout.alignment: Qt.AlignHCenter
            readonly property Item content: root.hasNotice || root.showsSnap ? messageRow : gestureRow
            implicitWidth: coach.content.implicitWidth + 12 + 18
            implicitHeight: 40
            radius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
            color: root.hasNotice ? Appearance.colors.colTertiaryContainer
                : root.showsSnap ? Appearance.colors.colPrimaryContainer
                : Appearance.m3colors.m3surfaceContainerHigh
            opacity: root.dragging && !root.showsSnap && !root.hasNotice ? 0 : 1
            visible: opacity > 0
            clip: true

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on implicitWidth {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }

            StyledRectangularShadow {
                target: coach
            }

            Row {
                id: gestureRow
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                opacity: coach.content === gestureRow ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                CoachToken {
                    symbol: "pan_tool"
                    shape: MaterialShape.Shape.Cookie4Sided
                    verb: !root.ready ? Translation.tr("Measuring") : Translation.tr("Drag")
                    rest: !root.ready ? Translation.tr("the wallpaper…") : Translation.tr("to move")
                }
                CoachToken {
                    visible: root.ready
                    symbol: "pinch"
                    shape: MaterialShape.Shape.Clover4Leaf
                    verb: Translation.tr("Scroll")
                    rest: Translation.tr("or pinch to zoom")
                }
                CoachToken {
                    visible: root.ready
                    symbol: "ads_click"
                    shape: MaterialShape.Shape.Sunny
                    verb: Translation.tr("Double-click")
                    rest: Translation.tr("to reset")
                }
            }

            Row {
                id: messageRow
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                opacity: coach.content === messageRow ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialShapeWrappedMaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hasNotice ? "info" : "center_focus_strong"
                    iconSize: 16
                    padding: 6
                    shape: root.hasNotice ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Gem
                    color: root.hasNotice ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
                    colSymbol: root.hasNotice ? Appearance.colors.colOnTertiary : Appearance.colors.colOnPrimary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hasNotice ? root.notice : Translation.tr("Centred")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: root.hasNotice ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        // The dock: three groups on one floating surface, told apart by gaps
        // and by how each one is built - a tonal stepper around the zoom in
        // expressive digits, a connected group for the orientation whose
        // mirrors morph into a shape when on, and the way back as a filled
        // action that only exists while there is something to undo.
        Rectangle {
            id: dock
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: dockRow.implicitWidth + 16
            implicitHeight: root.controlHeight + 16
            radius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
            color: Appearance.m3colors.m3surfaceContainer
            enabled: root.ready

            StyledRectangularShadow {
                target: dock
            }

            RowLayout {
                id: dockRow
                anchors.centerIn: parent
                spacing: 10

                // ── Zoom ─────────────────────────────────────────────────
                RowLayout {
                    spacing: 3

                    Segment {
                        position: "first"
                        symbol: "remove"
                        tooltip: Translation.tr("Zoom out")
                        enabled: root.target.zoom > WallpaperFraming.zoomMin + 0.0001
                        onClicked: root.zoomBy(1 / 1.1, 0, 0)
                    }

                    // The one number this dock is about. Bold and condensed
                    // while zoomed, a lighter cut at 100%; a click goes back
                    // to the full picture.
                    Segment {
                        id: readout
                        position: "middle"
                        tooltip: Translation.tr("Back to 100%")
                        enabled: root.target.zoom > WallpaperFraming.zoomMin + 0.0001
                        // Disabled at 100% reads as dimmed; the number itself
                        // must not fade with it.
                        opacity: 1
                        Layout.preferredWidth: 78
                        property real boldness: WallpaperLayout.liveZoom > WallpaperFraming.zoomMin + 0.005 ? 1 : 0
                        Behavior on boldness {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        onClicked: root.zoomTo(WallpaperFraming.zoomMin)

                        contentItem: Item {
                            Row {
                                anchors.centerIn: parent
                                spacing: 1

                                StyledText {
                                    anchors.baseline: percentSign.baseline
                                    text: String(Math.round(WallpaperLayout.liveZoom * 100))
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 26
                                    font.variableAxes: ({
                                        "wght": Math.round(560 + 200 * readout.boldness),
                                        "wdth": Math.round(30 + 10 * readout.boldness),
                                        "ROND": 100
                                    })
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    id: percentSign
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: 3
                                    text: "%"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSecondaryContainer
                                    opacity: 0.7
                                }
                            }
                        }
                    }

                    Segment {
                        position: "last"
                        symbol: "add"
                        tooltip: Translation.tr("Zoom in")
                        enabled: root.target.zoom < WallpaperFraming.zoomMax - 0.0001
                        onClicked: root.zoomBy(1.1, 0, 0)
                    }
                }

                // ── Orientation ──────────────────────────────────────────
                RowLayout {
                    spacing: 3

                    Segment {
                        position: "first"
                        tonal: false
                        symbol: "rotate_left"
                        tooltip: Translation.tr("Turn left")
                        onClicked: WallpaperLayout.rotate(root.screenName, -1)
                    }
                    Segment {
                        position: "middle"
                        tonal: false
                        symbol: "rotate_right"
                        tooltip: Translation.tr("Turn right")
                        onClicked: WallpaperLayout.rotate(root.screenName, 1)
                    }
                    Segment {
                        position: "middle"
                        tonal: false
                        symbol: "flip"
                        activeShape: MaterialShape.Shape.Cookie7Sided
                        toggled: WallpaperLayout.liveFlipH
                        tooltip: Translation.tr("Mirror horizontally")
                        onClicked: WallpaperLayout.flip(root.screenName, "horizontal")
                    }
                    Segment {
                        position: "last"
                        tonal: false
                        symbol: "flip"
                        symbolRotation: 90
                        activeShape: MaterialShape.Shape.Clover4Leaf
                        toggled: WallpaperLayout.liveFlipV
                        tooltip: Translation.tr("Mirror vertically")
                        onClicked: WallpaperLayout.flip(root.screenName, "vertical")
                    }
                }

                // ── Position ─────────────────────────────────────────────
                RippleButton {
                    id: centreButton
                    implicitWidth: root.controlHeight
                    implicitHeight: root.controlHeight
                    buttonRadius: height / 2
                    enabled: Math.abs(root.target.x) > 0.0005 || Math.abs(root.target.y) > 0.0005
                    colBackground: ColorUtils.transparentize(Appearance.colors.colOnSurface, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: WallpaperLayout.centre(root.screenName)

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "center_focus_strong"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip {
                        requireOverlay: false
                        text: Translation.tr("Centre")
                    }
                }

                // The way back, as the dock's one filled action. It grows in
                // from nothing once the picture has been touched and folds
                // away again at the full picture, so an untouched dock never
                // offers to undo nothing.
                Item {
                    id: resetSlot
                    readonly property bool wanted: !root.identity
                    property real reveal: resetSlot.wanted ? 1 : 0
                    Behavior on reveal {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Layout.preferredWidth: resetButton.implicitWidth * resetSlot.reveal
                    Layout.leftMargin: -dockRow.spacing * (1 - resetSlot.reveal)
                    implicitHeight: root.controlHeight
                    clip: true
                    visible: resetSlot.reveal > 0.001

                    RippleButton {
                        id: resetButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: resetRow.implicitWidth + 32
                        implicitHeight: root.controlHeight
                        buttonRadius: height / 2
                        opacity: resetSlot.reveal
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: WallpaperLayout.resetFraming(root.screenName)

                        contentItem: Item {
                            RowLayout {
                                id: resetRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: "restart_alt"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Reset")
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }

                        StyledToolTip {
                            requireOverlay: false
                            text: Translation.tr("Reset position, zoom and orientation")
                        }
                    }
                }
            }
        }
    }

    // One gesture on the coach line: a small shape around its glyph, the verb
    // in weight, the rest in the regular cut.
    component CoachToken: Row {
        id: token
        property string symbol: ""
        property var shape: MaterialShape.Shape.Circle
        property string verb: ""
        property string rest: ""
        spacing: 7

        MaterialShapeWrappedMaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: token.symbol
            iconSize: 14
            padding: 6
            shape: token.shape
            color: Appearance.colors.colPrimaryContainer
            colSymbol: Appearance.colors.colOnPrimaryContainer
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: token.verb
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurface
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: token.rest
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    // A segment of a connected button group: the outer ends pill, the joins
    // tight; a toggled segment rounds all the way into a pill and its glyph
    // morphs from a plain circle into the segment's own shape.
    component Segment: RippleButton {
        id: segment
        property string position: "middle"   // "first", "middle" or "last"
        // Tonal segments sit on the secondary container (the zoom stepper);
        // the others are quiet until toggled (the orientation group).
        property bool tonal: true
        property string symbol: ""
        property real symbolRotation: 0
        property var activeShape: MaterialShape.Shape.Circle
        property string tooltip: ""

        readonly property real outer: Config.options.appearance.sharpMode ? Appearance.rounding.verysmall : height / 2
        property real inner: segment.toggled ? segment.outer : Appearance.rounding.verysmall
        Behavior on inner {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        readonly property bool openLeft: segment.position !== "first"
        readonly property bool openRight: segment.position !== "last"

        implicitWidth: root.controlHeight + (segment.position === "middle" ? 0 : 4)
        implicitHeight: root.controlHeight
        topLeftRadius: segment.openLeft ? segment.inner : segment.outer
        bottomLeftRadius: segment.openLeft ? segment.inner : segment.outer
        topRightRadius: segment.openRight ? segment.inner : segment.outer
        bottomRightRadius: segment.openRight ? segment.inner : segment.outer

        colBackground: segment.tonal ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: segment.tonal ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
        colBackgroundActive: segment.tonal ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active
        colRipple: segment.tonal ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        contentItem: Item {
            MaterialShapeWrappedMaterialSymbol {
                anchors.centerIn: parent
                visible: segment.symbol !== ""
                text: segment.symbol
                rotation: segment.symbolRotation
                iconSize: 20
                padding: 4
                fill: segment.toggled ? 1 : 0
                shape: segment.toggled ? segment.activeShape : MaterialShape.Shape.Circle
                color: segment.toggled ? Appearance.colors.colPrimary : "transparent"
                colSymbol: segment.toggled ? Appearance.colors.colOnPrimary
                    : segment.tonal ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        StyledToolTip {
            requireOverlay: false
            text: segment.tooltip
        }
    }
}
