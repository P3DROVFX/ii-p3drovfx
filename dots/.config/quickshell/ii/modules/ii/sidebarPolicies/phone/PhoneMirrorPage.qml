pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * The phone, inside the sidebar.
 *
 * The picture is a live capture of scrcpy's own window, drawn here like any
 * other item, and the touches are the real window sitting exactly underneath
 * this frame with the panel's input region cut open over it. So the frame is
 * the contract: whatever rectangle it settles on is where the window is put,
 * and the cut-out is only opened once it has stopped moving and there is a
 * picture covering every pixel of it — an open cut-out with nothing painted
 * over it would be a hole straight through the sidebar.
 *
 * Everything else on the page gets out of the frame's way: one header line,
 * one row of keys that slides between primary and secondary, and no bezel —
 * the window itself is rounded to match, so the frame is only the picture.
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack()

    /** One phone key. Same pill everywhere, so a row of them reads as a
     *  keypad rather than as a stack of separate controls. */
    component KeyButton: RippleButton {
        id: key
        property string keyIcon: ""
        property string keyTip: ""
        property bool accent: false

        Layout.fillWidth: true
        Layout.preferredHeight: 44
        buttonRadius: Appearance.rounding.full
        colBackground: key.accent ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: key.accent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
        enabled: KdeConnectService.adbReachable
        opacity: enabled ? 1 : 0.45

        MaterialSymbol {
            anchors.centerIn: parent
            text: key.keyIcon
            iconSize: 19
            color: key.accent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: key.keyTip
        }
    }

    readonly property real sidePadding: 6
    readonly property real frameRadius: Appearance.rounding.verylarge

    readonly property real aspect: PhoneMirrorService.deviceAspect
    readonly property bool capturing: PhoneMirrorService.toplevel !== null && screencopy.hasContent
    readonly property bool failed: PhoneMirrorService.lastError.length > 0

    /** A closed sidebar keeps its content loaded, so the page outliving the
     *  panel is the normal case rather than the exception. */
    readonly property bool pageLive: root.visible
        && (GlobalStates.sidebarLeftOpen || GlobalStates.policiesPinned
            || GlobalStates.policiesDetached)

    onPageLiveChanged: {
        PhoneMirrorService.wanted = root.pageLive;
        if (!root.pageLive) {
            root.settled = false;
            GlobalStates.policiesPointerHole = Qt.rect(0, 0, 0, 0);
        }
    }

    // ─── Session lease ────────────────────────────────────────
    Component.onCompleted: {
        PhoneMirrorService.layerNamespace = GlobalStates.policiesSurfaceNamespace;
        PhoneMirrorService.screenName = GlobalStates.policiesSurfaceScreen;
        PhoneMirrorService.cornerRadius = Math.round(root.frameRadius);
        PhoneMirrorService.wanted = root.pageLive;
        // Something the sidebar opened is about to hold the keyboard.
        GlobalStates.policiesHoldOpen += 1;
        pageEntrance.start();
    }

    Component.onDestruction: {
        PhoneMirrorService.touchWanted = false;
        PhoneMirrorService.wanted = false;
        GlobalStates.policiesPointerHole = Qt.rect(0, 0, 0, 0);
        GlobalStates.policiesHoldOpen = Math.max(0, GlobalStates.policiesHoldOpen - 1);
    }

    Connections {
        target: GlobalStates
        function onPoliciesSurfaceNamespaceChanged(): void {
            PhoneMirrorService.layerNamespace = GlobalStates.policiesSurfaceNamespace;
        }
        function onPoliciesSurfaceScreenChanged(): void {
            PhoneMirrorService.screenName = GlobalStates.policiesSurfaceScreen;
        }
    }

    // ─── Where the frame is ───────────────────────────────────
    // An ancestor sliding this page into place moves the frame without
    // anything here being told, so the position is sampled until it stops
    // changing rather than bound to something that never updates.
    property rect holeRect: Qt.rect(0, 0, 0, 0)
    property bool settled: false

    /**
     * The window may sit under the frame as soon as the frame has stopped
     * moving. It must not wait for the picture: the window waits off the side
     * of every monitor, where Hyprland renders nothing for the capture to
     * copy, so waiting for a frame before moving it on screen is a deadlock —
     * no picture until it moves, and no move until there is a picture. The
     * frame is opaque from the start, so it covers the window either way.
     */
    readonly property bool placementWanted: root.pageLive && root.settled
        && GlobalStates.policiesSurfaceNamespace.length > 0

    /** The cut-out does wait for the picture. A hole in the panel with nothing
     *  painted over it is a hole straight through the sidebar. */
    readonly property bool touchActive: root.placementWanted && root.capturing

    function sampleFrame(): void {
        const p = frame.mapToItem(null, 0, 0);
        const next = Qt.rect(Math.round(p.x), Math.round(p.y),
                             Math.round(frame.width), Math.round(frame.height));
        if (next.x === root.holeRect.x && next.y === root.holeRect.y
            && next.width === root.holeRect.width && next.height === root.holeRect.height)
            return;
        root.holeRect = next;
        root.settled = false;
        settleTimer.restart();
    }

    // Stops on its own the moment the frame comes to rest, and only ever runs
    // again when something moves it.
    Timer {
        id: frameSampler
        interval: 60
        repeat: true
        running: root.pageLive && !root.settled
        onTriggered: root.sampleFrame()
    }

    Timer {
        id: settleTimer
        interval: 200
        repeat: false
        onTriggered: root.settled = true
    }

    onHoleRectChanged: PhoneMirrorService.touchRect = root.holeRect
    onPlacementWantedChanged: PhoneMirrorService.touchWanted = root.placementWanted
    onTouchActiveChanged: {
        GlobalStates.policiesPointerHole = root.touchActive ? root.holeRect : Qt.rect(0, 0, 0, 0);
    }
    onSettledChanged: if (root.settled && root.touchActive)
        GlobalStates.policiesPointerHole = root.holeRect

    // ─── Entrance ─────────────────────────────────────────────
    opacity: 0
    transform: Translate {
        id: pageTranslate
        y: 14
    }

    ParallelAnimation {
        id: pageEntrance
        NumberAnimation {
            target: root
            property: "opacity"
            from: 0
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pageTranslate
            property: "y"
            from: 14
            to: 0
            duration: 280
            easing.type: Easing.OutCubic
        }
    }

    // ─── Header ───────────────────────────────────────────────
    RowLayout {
        id: header
        anchors.top: parent.top
        // Without this the button's ripple circle is flush with the page's
        // top edge, and whatever clips the page clips the top off it.
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.sidePadding
        anchors.rightMargin: root.sidePadding
        spacing: 10

        RippleButton {
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: 19
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: -1

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Phone screen")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                // The error itself belongs in the frame, where there is room
                // for it; repeating it here only cost the title its line.
                text: root.failed ? Translation.tr("Disconnected")
                    : !root.capturing ? Translation.tr("Connecting…")
                    : PhoneMirrorService.deviceWidth > 0
                        ? Translation.tr("%1 × %2").arg(PhoneMirrorService.deviceWidth).arg(PhoneMirrorService.deviceHeight)
                        : Translation.tr("Live")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        // A dot says the same as a labelled pill in a fraction of the width.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 8
            implicitHeight: 8
            radius: width / 2
            color: root.failed ? Appearance.colors.colError
                : root.touchActive ? Appearance.colors.colPrimary
                : Appearance.colors.colSubtext

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            SequentialAnimation on opacity {
                running: !root.capturing && !root.failed
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
        }
    }

    // ─── The phone ────────────────────────────────────────────
    Item {
        id: stage
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        // The frame carries the phone's own aspect ratio, so scrcpy never has
        // to letterbox inside a window the panel drew to a different shape.
        readonly property real ratio: Math.max(0.2, root.aspect)
        readonly property real keyBarHeight: 44

        // One margin everywhere: either side of the frame and the keys, above
        // the frame, and below the keys. A phone this tall in a panel this
        // narrow is limited by width, never by height, so the frame comes out
        // as wide as the margin allows and the height left over is shared
        // evenly above and below it. That is what keeps the gap to the keys
        // from being the one tight edge on the page.
        readonly property real margin: 22
        readonly property real boxWidth: Math.max(40, stage.width - stage.margin * 2)
        readonly property real boxHeight: Math.max(80,
            stage.height - stage.margin * 3 - stage.keyBarHeight)

        readonly property real innerH: Math.max(80, Math.min(stage.boxHeight, stage.boxWidth / stage.ratio))
        readonly property real innerW: stage.innerH * stage.ratio
        readonly property real frameTop: stage.margin + (stage.boxHeight - stage.innerH) / 2

        onWidthChanged: root.sampleFrame()
        onHeightChanged: root.sampleFrame()

        ClippingRectangle {
            id: frame
            anchors.horizontalCenter: parent.horizontalCenter
            y: stage.frameTop
            width: Math.round(stage.innerW)
            height: Math.round(stage.innerH)
            radius: root.frameRadius
            antialiasing: true
            // Opaque: the scrcpy window is directly behind this rectangle, and
            // anything see-through here would let it smear through the panel's
            // blur. The window is rounded to the same radius, so there is no
            // bezel to hide its corners with.
            color: ColorUtils.applyAlpha(root.capturing ? "#000000" : Appearance.colors.colLayer2, 1)

            onWidthChanged: root.sampleFrame()
            onHeightChanged: root.sampleFrame()

            ScreencopyView {
                id: screencopy
                anchors.fill: parent
                // Only once the window is on screen. Asking to copy one that
                // is parked off the side of every monitor gets a capture
                // session with nothing to copy, and it does not pick itself up
                // again when the window finally arrives.
                captureSource: (PhoneMirrorService.attached && root.captureArmed)
                    ? PhoneMirrorService.toplevel : null
                live: true
                paintCursor: false
                onStopped: {
                    root.captureArmed = false;
                    captureRetry.restart();
                }
                // Capturing above what is shown buys nothing: the frame is
                // already the phone's aspect ratio, so one device pixel per
                // displayed pixel is the whole of it.
                // Hyprland's resize_on_border means a drag at the very edge of
                // the picture grabs the window underneath it instead, and
                // nothing says so over the IPC — no event is emitted for a
                // resize at all. The capture's own source size is the window's
                // size, so the moment it stops matching the frame, the window
                // has been pulled out from under it.
                onSourceSizeChanged: root.checkSourceSize()
                constraintSize: Qt.size(
                    Math.max(1, Math.round(frame.width * root.captureScale)),
                    Math.max(1, Math.round(frame.height * root.captureScale)))
            }

            // Shown until the first frame lands, so the frame is never a dark
            // rectangle with no explanation.
            Item {
                anchors.fill: parent
                visible: opacity > 0
                opacity: root.capturing ? 0 : 1

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 260)
                    spacing: 14

                    MaterialLoadingIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !root.failed
                        implicitSize: 42
                        loading: visible
                    }

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.failed
                        text: "phonelink_off"
                        iconSize: 38
                        color: Appearance.colors.colError
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.failed
                            ? PhoneMirrorService.lastError
                            : (!KdeConnectService.adbReachable
                                ? Translation.tr("Waiting for ADB — plug the phone in or turn on wireless debugging")
                                : Translation.tr("Starting the mirror…"))
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    RippleButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.failed
                        implicitHeight: 32
                        implicitWidth: retryText.implicitWidth + 30
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover

                        StyledText {
                            id: retryText
                            anchors.centerIn: parent
                            text: Translation.tr("Try again")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        onClicked: {
                            PhoneMirrorService.wanted = false;
                            PhoneMirrorService.wanted = true;
                        }
                    }
                }
            }
        }

    // ─── Phone keys ───────────────────────────────────────────
    // One row, two pages. The keys a phone is actually driven with are on the
    // first; everything else waits behind the chevron rather than taking a
    // second and third row away from the picture.
        Item {
            id: keyBar
            anchors.bottom: parent.bottom
            anchors.bottomMargin: stage.margin
            anchors.horizontalCenter: parent.horizontalCenter
            // Same width as the frame: the keys belong to the picture above
            // them, not to the panel's edges.
            width: Math.round(stage.innerW)
            height: stage.keyBarHeight
            clip: true

            property bool showMore: false
            readonly property real slide: keyBar.width + 8

            RowLayout {
                id: primaryKeys
                width: keyBar.width
                height: keyBar.height
                x: keyBar.showMore ? -keyBar.slide : 0
                spacing: 6
                opacity: keyBar.showMore ? 0 : 1

                Behavior on x {
                    NumberAnimation { duration: 380; easing.type: Easing.OutExpo }
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                KeyButton {
                    keyIcon: "arrow_back_ios_new"
                    keyTip: Translation.tr("Back")
                    onClicked: PhoneMirrorService.goBack()
                }
                KeyButton {
                    keyIcon: "circle"
                    keyTip: Translation.tr("Home")
                    onClicked: PhoneMirrorService.goHome()
                }
                KeyButton {
                    keyIcon: "square"
                    keyTip: Translation.tr("Recents")
                    onClicked: PhoneMirrorService.goRecents()
                }
                KeyButton {
                    keyIcon: "more_horiz"
                    keyTip: Translation.tr("More")
                    accent: true
                    enabled: true
                    opacity: 1
                    Layout.fillWidth: false
                    Layout.preferredWidth: 52
                    onClicked: keyBar.showMore = true
                }
            }

            RowLayout {
                id: secondaryKeys
                width: keyBar.width
                height: keyBar.height
                x: keyBar.showMore ? 0 : keyBar.slide
                spacing: 6
                opacity: keyBar.showMore ? 1 : 0

                Behavior on x {
                    NumberAnimation { duration: 380; easing.type: Easing.OutExpo }
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                KeyButton {
                    keyIcon: "chevron_left"
                    keyTip: Translation.tr("Back to keys")
                    accent: true
                    enabled: true
                    opacity: 1
                    Layout.fillWidth: false
                    Layout.preferredWidth: 52
                    onClicked: keyBar.showMore = false
                }
                KeyButton {
                    keyIcon: "volume_down"
                    keyTip: Translation.tr("Volume down")
                    onClicked: PhoneMirrorService.volumeDown()
                }
                KeyButton {
                    keyIcon: "volume_up"
                    keyTip: Translation.tr("Volume up")
                    onClicked: PhoneMirrorService.volumeUp()
                }
                KeyButton {
                    keyIcon: "expand_more"
                    keyTip: Translation.tr("Notifications")
                    onClicked: PhoneMirrorService.openNotifications()
                }
                KeyButton {
                    keyIcon: "power_settings_new"
                    keyTip: Translation.tr("Power")
                    onClicked: PhoneMirrorService.togglePower()
                }
                KeyButton {
                    keyIcon: "open_in_new"
                    keyTip: Translation.tr("Open in a window")
                    onClicked: {
                        PhoneMirrorService.detachToWindow();
                        root.goBack();
                    }
                }
            }
        }
    }

    readonly property real captureScale: Math.max(1, Math.min(2, Screen.devicePixelRatio))

    /** A capture that gave up is re-armed rather than left dark: dropping the
     *  source and asking again is the only way to restart one. */
    property bool captureArmed: true

    Timer {
        interval: 1500
        repeat: true
        running: root.pageLive
        onTriggered: console.warn("[MirrorProbe] attached=", PhoneMirrorService.attached,
            "hasContent=", screencopy.hasContent, "capturing=", root.capturing,
            "settled=", root.settled, "ns=", GlobalStates.policiesSurfaceNamespace,
            "placementWanted=", root.placementWanted, "touchActive=", root.touchActive,
            "published=", GlobalStates.policiesPointerHole.width, GlobalStates.policiesPointerHole.height,
            "holeActive=", GlobalStates.policiesPointerHoleActive)
    }

    Timer {
        id: captureRetry
        interval: 400
        repeat: false
        onTriggered: root.captureArmed = true
    }

    /** The window's buffer is the frame's size in device pixels. Anything else
     *  is somebody dragging its border. */
    function checkSourceSize(): void {
        if (!root.touchActive)
            return;
        const s = screencopy.sourceSize;
        if (s.width <= 0 || s.height <= 0)
            return;
        const dpr = Screen.devicePixelRatio;
        if (Math.abs(s.width - frame.width * dpr) <= 2
            && Math.abs(s.height - frame.height * dpr) <= 2) {
            sizeGuard.stop();
            return;
        }
        sizeGuard.restart();
    }

    // Snapping back on every intermediate size would fight the drag frame by
    // frame; waiting for it to stop lets the window rubber-band and then go
    // back where it belongs.
    Timer {
        id: sizeGuard
        interval: 180
        repeat: false
        onTriggered: if (root.touchActive) PhoneMirrorService.reassertGeometry()
    }

}
