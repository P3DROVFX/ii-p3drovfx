import qs.modules.ii.bar.popups.activeWindow
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    property bool vertical: false
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    readonly property bool isFixedSize: Config.options.bar.activeWindow.fixedSize

    readonly property int maxSize: 350
    property int popupWidth: 350
    property int maxPopupWidth: 600
    readonly property int fixedSize: Config.options.bar.activeWindow.customSize

    readonly property bool activeWindowOpen: (ToplevelManager.toplevels?.values ?? []).includes(root.activeWindow)

    readonly property bool shouldShowActiveWindow: !!(root.activeWindow?.activated && root.activeWindowOpen && (
        Config.options.bar.activeWindow.showOnAllMonitors
            || (root.focusingThisMonitor && root.biggestWindow)
    ))

    property string appClassText: root.shouldShowActiveWindow ?
                (root.activeWindow?.appId ?? "") : (root.biggestWindow?.class) ?? Translation.tr("Desktop")

    property string appTitleText: root.shouldShowActiveWindow ?
                (root.activeWindow?.title ?? "") : (root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`

    property string currentClass: ""
    property string currentTitle: ""
    property string outgoingClass: ""
    property string outgoingTitle: ""
    property bool initialized: false

    readonly property real travelDistance: 24
    readonly property int animDuration: Math.max(150, Math.round(320 * (Appearance.animMultiplier ?? 1)))
    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1
    property int currentDisplayedWsId: activeWsId
    property int slideSign: -1

    implicitHeight: root.vertical && isFixedSize ? fixedSize : (root.vertical ? Math.max(incomingText.implicitWidth) + 30 : Appearance.sizes.baseBarHeight)
    implicitWidth: !root.vertical && isFixedSize ? fixedSize : (root.vertical ? Appearance.sizes.verticalBarWidth : Math.min(Math.max(incomingText.implicitWidth) + 30, maxSize))
    clip: true

    property bool containsMouse: mouseArea.containsMouse

    Timer {
        id: transitionCoalesceTimer
        interval: 0
        repeat: false
        onTriggered: root.triggerTransition()
    }

    onAppClassTextChanged: transitionCoalesceTimer.restart()
    onAppTitleTextChanged: transitionCoalesceTimer.restart()
    onActiveWsIdChanged: transitionCoalesceTimer.restart()

    Component.onCompleted: {
        root.currentClass = root.appClassText;
        root.currentTitle = root.appTitleText;
        root.currentDisplayedWsId = root.activeWsId;
        root.initialized = true;
    }

    function triggerTransition(): void {
        if (!root.initialized) {
            root.currentClass = root.appClassText;
            root.currentTitle = root.appTitleText;
            root.currentDisplayedWsId = root.activeWsId;
            root.initialized = true;
            return;
        }

        const targetClass = root.appClassText;
        const targetTitle = root.appTitleText;
        const targetWsId = root.activeWsId;

        if (targetClass === root.currentClass && targetTitle === root.currentTitle && targetWsId === root.currentDisplayedWsId)
            return;

        if (targetWsId !== root.currentDisplayedWsId) {
            root.slideSign = (targetWsId > root.currentDisplayedWsId) ? -1 : 1;
            root.currentDisplayedWsId = targetWsId;
        }

        const animEnabled = Config.options.bar.activeWindow.animateTransition ?? true;
        if (!animEnabled || (Appearance.animMultiplier ?? 1) <= 0) {
            transitionAnim.stop();
            outgoingWrapper.visible = false;
            incomingWrapper.opacity = 1.0;
            incomingTranslate.x = 0;
            incomingTranslate.y = 0;
            outgoingTranslate.x = 0;
            outgoingTranslate.y = 0;
            root.currentClass = targetClass;
            root.currentTitle = targetTitle;
            return;
        }

        transitionAnim.stop();

        root.outgoingClass = root.currentClass;
        root.outgoingTitle = root.currentTitle;
        root.currentClass = targetClass;
        root.currentTitle = targetTitle;

        outgoingWrapper.visible = true;
        outgoingWrapper.opacity = 1.0;
        outgoingTranslate.x = 0;
        outgoingTranslate.y = 0;

        incomingWrapper.opacity = 0.0;
        incomingTranslate.x = root.vertical ? 0 : (-root.slideSign * root.travelDistance);
        incomingTranslate.y = root.vertical ? (-root.slideSign * root.travelDistance) : 0;

        transitionAnim.start();
    }

    ParallelAnimation {
        id: transitionAnim
        alwaysRunToEnd: true

        NumberAnimation {
            target: outgoingWrapper
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: root.animDuration
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: outgoingTranslate
            property: "x"
            from: 0
            to: root.vertical ? 0 : (root.slideSign * root.travelDistance)
            duration: root.animDuration
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: outgoingTranslate
            property: "y"
            from: 0
            to: root.vertical ? (root.slideSign * root.travelDistance) : 0
            duration: root.animDuration
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: incomingWrapper
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: root.animDuration
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: incomingTranslate
            property: "x"
            from: root.vertical ? 0 : (-root.slideSign * root.travelDistance)
            to: 0
            duration: root.animDuration
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: incomingTranslate
            property: "y"
            from: root.vertical ? (-root.slideSign * root.travelDistance) : 0
            to: 0
            duration: root.animDuration
            easing.type: Easing.OutQuad
        }

        onFinished: {
            outgoingWrapper.visible = false;
            outgoingTranslate.x = 0;
            outgoingTranslate.y = 0;
            incomingTranslate.x = 0;
            incomingTranslate.y = 0;
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !BarInteraction.clickToShow
    }

    ActiveWindowPopup {
        id: titlePopup
        // The MouseArea, not the Item around it: the popup opens from a real press now, and
        // only the MouseArea has one to raise. Its geometry is the Item's, so nothing moves.
        targetItem: mouseArea
        appClassText: root.appClassText
        appTitleText: root.appTitleText
        activeWindowAddress: root.activeWindowAddress
        monitor: root.monitor
        popupWidth: root.popupWidth
        maxPopupWidth: root.maxPopupWidth
    }

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Appearance.rounding.full
        color: "transparent"
        border.color: Appearance.colors.colTertiaryContainer
        border.width: 2
        clip: true

        Item {
            id: incomingWrapper
            anchors.fill: parent
            opacity: 1.0
            transform: Translate {
                id: incomingTranslate
            }

            StyledText {
                id: incomingText
                anchors.centerIn: parent
                rotation: root.vertical ? -90 : 0
                text: root.vertical ? root.currentClass : root.currentTitle
                font.family: Appearance.font.family.expressive
                font.variableAxes: Appearance.font.variableAxes.rounded
                font.weight: Font.Bold
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
                width: root.vertical ? parent.height - 20 : parent.width - 20
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Item {
            id: outgoingWrapper
            anchors.fill: parent
            opacity: 0.0
            visible: false
            transform: Translate {
                id: outgoingTranslate
            }

            StyledText {
                id: outgoingText
                anchors.centerIn: parent
                rotation: root.vertical ? -90 : 0
                text: root.vertical ? root.outgoingClass : root.outgoingTitle
                font.family: Appearance.font.family.expressive
                font.variableAxes: Appearance.font.variableAxes.rounded
                font.weight: Font.Bold
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
                width: root.vertical ? parent.height - 20 : parent.width - 20
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
