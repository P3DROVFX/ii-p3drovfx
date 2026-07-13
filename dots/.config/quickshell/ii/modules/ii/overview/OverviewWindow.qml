pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item { // Window
    id: root
    property int windowRounding
    property var toplevel
    property var windowData
    property var monitorData
    property var scale
    property bool restrictToWorkspace: true
    property real widthRatio: {
        if (!widgetMonitor || !monitorData) return 1.0;
        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return (widgetWidth * monitorData.scale) / (monitorWidth * widgetMonitor.scale);
    }
    property real heightRatio: {
        if (!widgetMonitor || !monitorData) return 1.0;
        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale);
    }
    property real initX: Math.max(((windowData ? windowData.at[0] : 0) - (monitorData ? monitorData.x : 0) - (monitorData ? (monitorData.reserved?.[0] ?? 0) : 0)) * widthRatio * root.scale, 0) + xOffset
    property real initY: Math.max(((windowData ? windowData.at[1] : 0) - (monitorData ? monitorData.y : 0) - (monitorData ? (monitorData.reserved?.[1] ?? 0) : 0)) * heightRatio * root.scale, 0) + yOffset
    property real xOffset: 0
    property real yOffset: 0
    property var widgetMonitor
    property int widgetMonitorId: widgetMonitor.id

    property real targetWindowWidth: (windowData ? windowData.size[0] : 0) * scale * widthRatio
    property real targetWindowHeight: (windowData ? windowData.size[1] : 0) * scale * heightRatio
    property bool hovered: false
    property bool pressed: false

    property bool centerIcons: Config.options.overview.centerIcons
    property bool showIcons: Config.options.overview.showIcons
    property real iconGapRatio: 0.06
    property real iconToWindowRatio: centerIcons ? 0.35 : 0.15
    property real xwaylandIndicatorToIconRatio: 0.35
    property real iconToWindowRatioCompact: 0.6
    property string iconPath: {
        const _ = TaskbarApps.iconThemeRevision;
        return Quickshell.iconPath(AppSearch.guessIcon(windowData?.class), "image-missing");
    }
    property bool compactMode: Appearance.font.pixelSize.smaller * 4 > targetWindowHeight || Appearance.font.pixelSize.smaller * 4 > targetWindowWidth

    property bool indicateXWayland: windowData?.xwayland ?? false

    property bool hyprscrollingEnabled: false
    property int scrollWidth
    property int scrollHeight
    property int scrollX
    property int scrollY

    property real topLeftRadius
    property real topRightRadius
    property real bottomLeftRadius
    property real bottomRightRadius

    x: hyprscrollingEnabled ? scrollX : initX
    y: hyprscrollingEnabled ? scrollY : initY
    width: !windowData.floating && hyprscrollingEnabled ? scrollWidth : targetWindowWidth
    height: !windowData.floating && hyprscrollingEnabled ? scrollHeight : targetWindowHeight
    opacity: windowData.monitor == widgetMonitorId ? 1 : 0.4

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height

            topLeftRadius: !hyprscrollingEnabled ? root.topLeftRadius : root.windowRounding
            topRightRadius: !hyprscrollingEnabled ? root.topRightRadius : root.windowRounding
            bottomLeftRadius: !hyprscrollingEnabled ? root.bottomLeftRadius : root.windowRounding
            bottomRightRadius: !hyprscrollingEnabled ? root.bottomRightRadius : root.windowRounding
        }
    }

    // We have to disable animations in the first frame or else some strange animations shows up
    property bool initialized: false
    Component.onCompleted: Qt.callLater(() => root.initialized = true)

    // Re-capture the frozen ScreencopyView whenever HyprlandData refetches
    // client list and assigns a fresh windowData object (different reference
    // after every `hyprctl clients -j` parse). This is the live recapture hook
    // for retiles that don't emit a movewindowv2 event — e.g. when a sibling
    // window lands on our workspace and Hyprland silently shrinks us to half
    // width. Without this the live:false texture stays letterboxed at the old
    // aspect, producing the "empty space above/below" bug after drops.
    onWindowDataChanged: {
        if (root.initialized && root.toplevel)
            recaptureDebounce.restart()
    }

    function requestRecapture() {
        recaptureDebounce.restart()
    }

    Timer {
        id: recaptureDebounce
        interval: 60
        repeat: false
        onTriggered: {
            if (root.toplevel && windowPreview.captureSource)
                windowPreview.captureFrame()
        }
    }

    Behavior on x {
        enabled: root.initialized
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        enabled: root.initialized
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        enabled: root.initialized
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        enabled: root.initialized
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    // Soft shadow behind the window
    StyledRectangularShadow {
        target: root
        blur: 16
        opacity: 0.3
        offset: Qt.vector2d(0, 4)
    }

    // Windows are not always rendered in scrolling mode, so background stays transparent. This fallback is needed to make sure the window is visible
    Loader {
        z: 0
        active: root.hyprscrollingEnabled
        anchors.fill: parent
        sourceComponent: Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.1, 0.1, 0.1, 1.0)
        }
    }

    ScreencopyView {
        id: windowPreview
        anchors.fill: parent
        captureSource: (root.toplevel && Config.options.overview.showWindowPreviews) ? root.toplevel : null
        // Performance: live false to avoid continuous screencopy overhead
        live: false
        z: 1

        // Color overlay for interactions
        Rectangle {
            anchors.fill: parent

            topLeftRadius: !hyprscrollingEnabled ? root.topLeftRadius : root.windowRounding
            topRightRadius: !hyprscrollingEnabled ? root.topRightRadius : root.windowRounding
            bottomLeftRadius: !hyprscrollingEnabled ? root.bottomLeftRadius : root.windowRounding
            bottomRightRadius: !hyprscrollingEnabled ? root.bottomRightRadius : root.windowRounding

            color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) : hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) : ColorUtils.transparentize(Appearance.colors.colLayer2)
        }

        Loader {
            active: root.showIcons
            anchors.centerIn: root.centerIcons ? parent : undefined
            sourceComponent: Image {
                id: windowIcon
                property real baseSize: Math.min(root.targetWindowWidth, root.targetWindowHeight)
                anchors {
                    top: root.centerIcons ? undefined : parent.top
                    left: root.centerIcons ? undefined : parent.left
                    centerIn: root.centerIcons ? parent : undefined
                    margins: baseSize * root.iconGapRatio
                }
                property var iconSize: {
                    // console.log("-=-=-", root.toplevel.title, "-=-=-")
                    // console.log("Target window size:", targetWindowWidth, targetWindowHeight)
                    // console.log("Icon ratio:", root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio)
                    // console.log("Scale:", root.monitorData.scale)
                    // console.log("Final:", Math.min(targetWindowWidth, targetWindowHeight) * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio) / root.monitorData.scale)
                    return baseSize * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio);
                }
                // mipmap: true
                Layout.alignment: Qt.AlignHCenter
                source: root.iconPath
                width: iconSize
                height: iconSize
                sourceSize: Qt.size(iconSize + TaskbarApps.iconThemeRevision, iconSize + TaskbarApps.iconThemeRevision)

                Behavior on width {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
    }
}
