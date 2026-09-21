pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
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
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack()

    readonly property real aspect: PhoneMirrorService.deviceAspect
    readonly property bool capturing: PhoneMirrorService.toplevel !== null && screencopy.hasContent
    readonly property bool failed: PhoneMirrorService.lastError.length > 0
    readonly property bool connecting: !root.capturing && !root.failed

    /** The user can put the cut-out away, which turns the frame back into an
     *  ordinary picture the sidebar can be dragged and scrolled over. */
    property bool touchEnabled: true

    /** A closed sidebar keeps its content loaded, so the page outliving the
     *  panel is the normal case rather than the exception — and a mirror
     *  nobody can see has no business holding an encoder open on the phone. */
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
        PhoneMirrorService.wanted = root.pageLive;
        // A click that lands on scrcpy is a click outside the panel as far as
        // the focus grab is concerned, and the sidebar would close under the
        // finger that was aiming at the phone.
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

    readonly property bool touchActive: root.pageLive && root.settled
        && root.touchEnabled && root.capturing
        && GlobalStates.policiesSurfaceNamespace.length > 0

    function sampleFrame(): void {
        const p = videoArea.mapToItem(null, 0, 0);
        const next = Qt.rect(Math.round(p.x), Math.round(p.y),
                             Math.round(videoArea.width), Math.round(videoArea.height));
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
    onTouchActiveChanged: {
        PhoneMirrorService.touchWanted = root.touchActive;
        GlobalStates.policiesPointerHole = root.touchActive ? root.holeRect : Qt.rect(0, 0, 0, 0);
    }
    onSettledChanged: if (root.settled && root.touchActive)
        GlobalStates.policiesPointerHole = root.holeRect

    // ─── Entrance ─────────────────────────────────────────────
    opacity: 0
    transform: Translate {
        id: pageTranslate
        y: 18
    }

    ParallelAnimation {
        id: pageEntrance
        NumberAnimation {
            target: root
            property: "opacity"
            from: 0
            to: 1
            duration: 260
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pageTranslate
            property: "y"
            from: 18
            to: 0
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    // ─── Header ───────────────────────────────────────────────
    RowLayout {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Phone screen")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (root.failed)
                        return PhoneMirrorService.lastError.split("\n")[0];
                    if (!root.capturing)
                        return Translation.tr("Starting the mirror…");
                    if (!root.touchEnabled)
                        return Translation.tr("Touch control off — the panel takes the clicks");
                    if (!root.touchActive)
                        return Translation.tr("Settling…");
                    return PhoneMirrorService.deviceWidth > 0
                        ? Translation.tr("%1 × %2 · touch and keyboard live")
                            .arg(PhoneMirrorService.deviceWidth).arg(PhoneMirrorService.deviceHeight)
                        : Translation.tr("Touch and keyboard live");
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.preferredHeight: 28
            Layout.preferredWidth: statusRow.implicitWidth + 20
            radius: Appearance.rounding.full
            color: root.failed ? Appearance.colors.colErrorContainer
                : root.capturing ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colLayer3

            RowLayout {
                id: statusRow
                anchors.centerIn: parent
                spacing: 5

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.failed ? "error" : (root.touchActive ? "touch_app" : "smartphone")
                    iconSize: 15
                    color: root.failed ? Appearance.colors.colOnErrorContainer
                        : root.capturing ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer3
                }

                StyledText {
                    text: root.failed ? Translation.tr("Error")
                        : root.touchActive ? Translation.tr("Live")
                        : root.capturing ? Translation.tr("View only")
                        : Translation.tr("Connecting")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.failed ? Appearance.colors.colOnErrorContainer
                        : root.capturing ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer3
                }
            }
        }
    }

    // ─── The phone ────────────────────────────────────────────
    Item {
        id: stage
        anchors.top: header.bottom
        anchors.topMargin: 14
        anchors.bottom: controlBar.top
        anchors.bottomMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right

        readonly property real bezel: 7
        // The frame carries the phone's own aspect ratio, so scrcpy never has
        // to letterbox inside a window the panel drew to a different shape.
        readonly property real innerH: Math.max(80, Math.min(
            stage.height - stage.bezel * 2,
            (stage.width - stage.bezel * 2) / Math.max(0.2, root.aspect)))
        readonly property real innerW: stage.innerH * Math.max(0.2, root.aspect)

        onWidthChanged: root.sampleFrame()
        onHeightChanged: root.sampleFrame()

        Rectangle {
            id: bezelRect
            anchors.centerIn: parent
            width: Math.round(stage.innerW) + stage.bezel * 2
            height: Math.round(stage.innerH) + stage.bezel * 2
            radius: Appearance.rounding.large + stage.bezel
            // Opaque on purpose: the scrcpy window is directly behind this
            // frame, and anything translucent here would let its corners show
            // through the panel's blur.
            color: "#0a0a0c"

            ClippingRectangle {
                id: videoArea
                anchors.centerIn: parent
                width: Math.round(stage.innerW)
                height: Math.round(stage.innerH)
                radius: Appearance.rounding.large
                color: "black"
                antialiasing: true

                onWidthChanged: root.sampleFrame()
                onHeightChanged: root.sampleFrame()

                ScreencopyView {
                    id: screencopy
                    anchors.fill: parent
                    captureSource: PhoneMirrorService.toplevel
                    live: true
                    paintCursor: false
                    // Capturing above what is shown buys nothing: the frame is
                    // already the phone's aspect ratio, so one device pixel per
                    // displayed pixel is the whole of it.
                    constraintSize: Qt.size(
                        Math.max(1, Math.round(videoArea.width * root.captureScale)),
                        Math.max(1, Math.round(videoArea.height * root.captureScale)))
                }

                // Shown until the first frame lands, so the frame is never a
                // black rectangle with no explanation.
                Rectangle {
                    anchors.fill: parent
                    color: "#0a0a0c"
                    visible: !root.capturing
                    opacity: visible ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        spacing: 10

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.failed ? "phonelink_off" : "smartphone"
                            iconSize: 40
                            color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext

                            RotationAnimator on rotation {
                                running: root.connecting && PhoneMirrorService.launching
                                loops: Animation.Infinite
                                from: -4
                                to: 4
                                duration: 900
                                easing.type: Easing.InOutSine
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: root.failed
                                ? PhoneMirrorService.lastError
                                : (!KdeConnectService.adbReachable
                                    ? Translation.tr("Waiting for ADB — connect the phone over USB or wireless debugging")
                                    : Translation.tr("Starting the mirror…"))
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        RippleButton {
                            Layout.alignment: Qt.AlignHCenter
                            visible: root.failed
                            implicitHeight: 34
                            implicitWidth: retryText.implicitWidth + 28
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
        }
    }

    readonly property real captureScale: Math.max(1, Math.min(2, Screen.devicePixelRatio))

    // ─── Phone keys ───────────────────────────────────────────
    ColumnLayout {
        id: controlBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: 4
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { "icon": "arrow_back_ios_new", "tip": Translation.tr("Back"), "act": "back" },
                    { "icon": "circle", "tip": Translation.tr("Home"), "act": "home" },
                    { "icon": "square", "tip": Translation.tr("Recents"), "act": "recents" },
                    { "icon": "expand_more", "tip": Translation.tr("Notifications"), "act": "notifications" }
                ]

                delegate: RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    enabled: KdeConnectService.adbReachable
                    opacity: enabled ? 1 : 0.5

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: modelData.icon
                        iconSize: 19
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledToolTip {
                        text: modelData.tip
                    }

                    onClicked: {
                        switch (modelData.act) {
                        case "back": PhoneMirrorService.goBack(); break;
                        case "home": PhoneMirrorService.goHome(); break;
                        case "recents": PhoneMirrorService.goRecents(); break;
                        case "notifications": PhoneMirrorService.openNotifications(); break;
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { "icon": "volume_down", "tip": Translation.tr("Volume down"), "act": "voldown" },
                    { "icon": "volume_up", "tip": Translation.tr("Volume up"), "act": "volup" },
                    { "icon": "power_settings_new", "tip": Translation.tr("Power"), "act": "power" },
                    { "icon": "screenshot_monitor", "tip": Translation.tr("Screenshot"), "act": "shot" },
                    { "icon": "open_in_new", "tip": Translation.tr("Open in a window"), "act": "detach" }
                ]

                delegate: RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    enabled: KdeConnectService.adbReachable
                    opacity: enabled ? 1 : 0.5

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: modelData.icon
                        iconSize: 19
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledToolTip {
                        text: modelData.tip
                    }

                    onClicked: {
                        switch (modelData.act) {
                        case "voldown": PhoneMirrorService.volumeDown(); break;
                        case "volup": PhoneMirrorService.volumeUp(); break;
                        case "power": PhoneMirrorService.togglePower(); break;
                        case "shot": KdeConnectService.adbScreenshot(); break;
                        case "detach":
                            PhoneMirrorService.detachToWindow();
                            root.goBack();
                            break;
                        }
                    }
                }
            }
        }

        // The cut-out is the one thing here that changes how the sidebar
        // itself behaves, so it gets a switch of its own rather than being
        // something the user has to leave the page to undo.
        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            buttonRadius: Appearance.rounding.normal
            colBackground: root.touchEnabled
                ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colLayer2
            colBackgroundHover: root.touchEnabled
                ? Appearance.colors.colPrimaryContainerHover
                : Appearance.colors.colLayer2Hover

            contentItem: RowLayout {
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 12
                    text: root.touchEnabled ? "touch_app" : "do_not_touch"
                    iconSize: 18
                    color: root.touchEnabled
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.touchEnabled
                        ? Translation.tr("Touch control on")
                        : Translation.tr("Touch control off")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.touchEnabled
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer2
                }
            }

            onClicked: root.touchEnabled = !root.touchEnabled
        }
    }
}
