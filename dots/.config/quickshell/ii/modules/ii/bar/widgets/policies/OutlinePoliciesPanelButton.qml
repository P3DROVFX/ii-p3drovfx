pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Outline policies panel button.
 *
 * No surface at all: a dashed ring around the icon, and the bar showing through
 * it. The previous attempt here was a filled plate, and a filled square inside a
 * float-style bar reads as spilling out of the group — its corners meet the
 * group's rounded edge and there is nowhere for them to go. A ring drawn
 * *inside* the widget's own box cannot touch the edge in any bar style.
 *
 *   closed   dashed ring, bar ink
 *   hover    the gaps close — the dashes grow until the ring is nearly solid
 *   open     the ring is solid and takes the accent, and so does the icon
 *
 * The hover is the whole reason this design has a dashed ring rather than a
 * plain one: closing the gaps is a state change you can read at 34px without
 * moving, filling, or scaling anything.
 *
 * > [!NOTE]
 * > **Sanctioned stroke.** Drawing with a stroke is otherwise forbidden in this
 * > repo. It is used here because "a dashed border with no background" is the
 * > request: there is no fill left to carry the shape. The exception stops at
 * > this file and the dashboard `outline` orbs.
 */
Item {
    id: root

    property bool vertical: false
    readonly property string screenName: root.QsWindow?.window?.screen?.name ?? ""

    property bool showPing: false
    readonly property bool open: GlobalStates.sidebarLeftOpen

    readonly property real side: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8
    readonly property real contentScale: root.vertical
        ? Appearance.sizes.verticalBarContentScale
        : Appearance.sizes.barContentScale

    implicitWidth: root.side
    implicitHeight: root.side

    // Phone integration in-use state (scrcpy mirror, phone webcam or phone mic).
    // While any of these is running the ring switches to the error colour, as
    // the RecordIndicator does. The "connecting"/"launching" states are included
    // so the colour flips on click instead of waiting 5-6s for the verify
    // timers. Gated by Config.options.policies.phone so a disabled integration
    // never instantiates those singletons on boot.
    readonly property bool phoneIntegrationActive:
        Config.options.policies.phone !== 0
        && (KdeConnectService.scrcpyRunning
            || KdeConnectService.scrcpyLaunching
            || PhoneCameraService.connecting
            || PhoneCameraService.running
            || PhoneMicService.connecting
            || PhoneMicService.running)

    // ── The one number the ring is made of ───────────────────────────────────
    // 0 = fully dashed, 1 = solid. Hover walks it most of the way; opening the
    // panel takes it the rest. Two states on one driver means they can never
    // disagree about how solid the ring currently is.
    readonly property real solidityTarget: root.open ? 1.0 : (mouseArea.containsMouse ? 0.72 : 0.0)
    property real solidity: root.solidityTarget

    Behavior on solidity {
        enabled: !Appearance.reducedMotion
        NumberAnimation {
            duration: Math.round(260 * Appearance.animMultiplier)
            easing.type: Easing.OutQuad
        }
    }

    readonly property real ringWidth: Math.max(1.5, Math.round(root.side * 0.07))
    // Half the stroke sits outside the path, so the radius has to give it room:
    // this is what keeps the drawing inside the widget in every bar style.
    readonly property real ringRadius: (root.side - root.ringWidth) / 2 - 1

    readonly property color colRing: {
        if (root.phoneIntegrationActive)
            return Appearance.colors.colError;
        if (root.open)
            return Appearance.colors.colPrimary;
        return mouseArea.containsMouse
            ? Appearance.colors.colOnLayer0
            : Appearance.colors.colOnLayer1;
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen)
                return;
            root.showPing = true;
        }
    }
    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen)
                return;
            root.showPing = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    Shape {
        id: ring
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.smooth: true

        // The dash and the gap trade with each other, so the ring's perimeter of
        // ink grows while its circumference stays put.
        readonly property real dashLength: 1.4 + 9.0 * root.solidity
        readonly property real gapLength: Math.max(0.01, 1.9 * (1.0 - root.solidity))

        ShapePath {
            strokeColor: root.colRing
            strokeWidth: root.ringWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [ring.dashLength, ring.gapLength]

            PathAngleArc {
                centerX: root.side / 2
                centerY: root.side / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: -90
                sweepAngle: 360
            }
        }
    }

    CustomIcon {
        id: distroIcon
        anchors.centerIn: parent
        visible: !Config.options.bar.useMaterialSymbolForTopLeftIcon
        width: Math.round((root.vertical ? 15 : 13) * root.contentScale)
        height: distroIcon.width
        source: {
            const icon = Config.options.bar.topLeftIcon;
            if (icon === 'distro')
                return SystemInfo.distroIcon;
            if (icon === 'docker')
                return 'docker.svg';
            if (icon.endsWith('.svg') || icon.endsWith('.png'))
                return icon;
            return `${icon}-symbolic`;
        }
        colorize: true
        color: root.colRing
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: Config.options.bar.useMaterialSymbolForTopLeftIcon
        text: Config.options.bar.topLeftIcon
        iconSize: Math.round((root.vertical ? 17 : 15) * root.contentScale)
        fill: 1
        color: root.colRing
    }

    // With no surface to tint, the ping needs a mark of its own. It sits inside
    // the ring's own box, so it cannot push the widget past its bounds either.
    Rectangle {
        id: pingDot
        opacity: root.showPing ? 1 : 0
        visible: opacity > 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Math.round(root.side * 0.1)
        anchors.bottomMargin: Math.round(root.side * 0.1)
        implicitWidth: Math.round(root.side * 0.2)
        implicitHeight: pingDot.implicitWidth
        radius: Appearance.rounding.full
        color: Appearance.colors.colError

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pingDot)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: GlobalStates.toggleLeftSidebar(root.screenName)
    }
}
