pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.modules.ii.bar.shared

Item {
    id: root
    width: screenWidth
    height: screenHeight

    BarThemes {
        id: barThemes
    }
    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    property var screen: null
    property var panelWindow: null
    property bool barVertical: false
    property bool barBottom: false
    property bool barOnLeft: false
    property bool barOnRight: false
    property bool usingWrappedFrame: false
    property int frameThickness: 0
    property int barHeight: Appearance.sizes.barHeight
    property int verticalBarWidth: Appearance.sizes.verticalBarWindowWidth
    property real barMargin: 0
    property real hBarHiddenAmount: 0
    property real vBarHiddenAmount: 0
    property real animatedLeftSidebarWidth: 0
    property real animatedRightSidebarWidth: 0
    property bool leftSidebarActiveOnMonitor: false
    property bool rightSidebarActiveOnMonitor: false
    property bool hasFullscreenWindow: false

    readonly property bool isOpen: GlobalStates.osdVolumeOpen && screen.name === (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0])?.name
    readonly property bool isWidgetActive: isOpen || openProgress > 0.001
    readonly property string mode: isWidgetActive ? "osd" : "idle"

    readonly property real screenWidth: screen ? screen.width : 1920
    readonly property real screenHeight: screen ? screen.height : 1080

    readonly property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "playerVolume",
            sourceUrl: "indicators/PlayerVolumeIndicator.qml"
        },
        {
            id: "gamma",
            sourceUrl: "indicators/GammaIndicator.qml"
        },
        {
            id: "keyboardBrightness",
            sourceUrl: "indicators/KeyboardBrightnessIndicator.qml"
        }
    ]

    readonly property real launcherContentWidth: osdIndicatorLoader.item ? osdIndicatorLoader.item.implicitWidth : Appearance.sizes.osdWidth + 2 * Appearance.sizes.elevationMargin
    readonly property real launcherContentHeight: contentColumn.implicitHeight

    OsdDropState {
        id: dropState
        mode: root.mode
        contentWidth: root.launcherContentWidth
        contentHeight: root.launcherContentHeight
        screenWidth: root.screenWidth
    }

    OsdDropPositioner {
        id: positioner
        barVertical: root.barVertical
        barBottom: root.barBottom
        barOnLeft: root.barOnLeft
        barOnRight: root.barOnRight
        usingWrappedFrame: root.usingWrappedFrame
        frameThickness: root.frameThickness
        barHeight: root.barHeight
        verticalBarWidth: root.verticalBarWidth
        barMargin: root.barMargin
        hBarHiddenAmount: root.hBarHiddenAmount
        vBarHiddenAmount: root.vBarHiddenAmount
        screenWidth: root.screenWidth
        screenHeight: root.screenHeight
        dropWidth: dropState.targetW
        dropHeight: dropState.targetH
        hasFullscreenWindow: root.hasFullscreenWindow
    }

    readonly property int _animDurationOpen: Math.round(450 * Appearance.animMultiplier)
    readonly property int _animDurationClose: Math.round(280 * Appearance.animMultiplier)
    readonly property var _openBezier: Appearance.animationCurves.emphasizedDecel
    readonly property var _closeBezier: Appearance.animationCurves.emphasizedDecel

    property real openProgress: 0.0
    readonly property real animHeight: openProgress * dropState.targetH

    state: isOpen ? "open" : "closed"

    states: [
        State {
            name: "closed"
            PropertyChanges {
                target: root
                openProgress: 0.0
            }
        },
        State {
            name: "open"
            PropertyChanges {
                target: root
                openProgress: 1.0
            }
        }
    ]

    transitions: [
        Transition {
            from: "closed"
            to: "open"
            NumberAnimation {
                target: root
                property: "openProgress"
                duration: root._animDurationOpen
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root._openBezier
            }
        },
        Transition {
            from: "open"
            to: "closed"
            NumberAnimation {
                target: root
                property: "openProgress"
                duration: root._animDurationClose
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root._closeBezier
            }
        }
    ]

    Item {
        id: dropContainer
        x: positioner.anchorX
        y: positioner.anchorY
        width: dropState.targetW
        height: root.animHeight
        visible: root.animHeight > 0.001

        onXChanged: root._updateBlurExclusion()
        onYChanged: root._updateBlurExclusion()
        onWidthChanged: root._updateBlurExclusion()
        onHeightChanged: root._updateBlurExclusion()

        Notch {
            id: dropNotch
            width: dropContainer.width
            height: dropContainer.height
            y: barBottom ? (dropContainer.height - height) : 0
            disableBehaviors: true
            readonly property real _wr: Appearance.rounding.windowRounding
            topRadius: Math.min(_wr, root.animHeight * 0.8)
            bottomRadius: Math.min(_wr, root.animHeight)
            fillColor: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            transform: Scale {
                xScale: 1
                yScale: barBottom ? -1 : 1
                origin.y: dropNotch.height / 2
            }
        }

        readonly property real _cornerRadius: Math.min(Appearance.rounding.windowRounding, root.animHeight)
        readonly property bool _showCorners: !root.barVertical && root.animHeight > 0.5 && !root.hasFullscreenWindow

        RoundCorner {
            id: topLeftCorner
            visible: false
            implicitSize: dropContainer._cornerRadius
            color: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.BottomRight
            anchors.right: parent.left
            anchors.top: parent.top
        }

        RoundCorner {
            id: topRightCorner
            visible: false
            implicitSize: dropContainer._cornerRadius
            color: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.BottomLeft
            anchors.left: parent.right
            anchors.top: parent.top
        }

        RoundCorner {
            id: bottomLeftCorner
            visible: dropContainer._showCorners && root.barBottom
            implicitSize: dropContainer._cornerRadius
            color: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.TopRight
            extendHorizontal: true
            extendVertical: true
            anchors.right: parent.left
            anchors.bottom: parent.bottom
        }

        RoundCorner {
            id: bottomRightCorner
            visible: dropContainer._showCorners && root.barBottom
            implicitSize: dropContainer._cornerRadius
            color: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.TopLeft
            extendHorizontal: true
            extendVertical: true
            anchors.left: parent.right
            anchors.bottom: parent.bottom
        }

        Item {
            id: clippingClip
            x: -200
            width: parent.width + 400
            height: parent.height
            clip: true

            Item {
                id: contentWrapper
                x: 200
                width: dropContainer.width
                height: dropState.targetH
                y: barBottom ? parent.height - height : 0

                Column {
                    id: contentColumn
                    width: parent.width

                    Loader {
                        id: osdIndicatorLoader
                        width: parent.width
                        active: root.isWidgetActive
                        source: {
                            const item = root.indicators.find(i => i.id === GlobalStates.osdCurrentIndicator);
                            if (!item)
                                return "";
                            return Quickshell.shellPath("modules/ii/topLayer/osd/" + item.sourceUrl);
                        }
                    }

                    Item {
                        id: protectionMessageWrapper
                        width: parent.width
                        height: GlobalStates.osdProtectionMessage !== "" ? protectionMessageBackground.implicitHeight + 10 : 0
                        opacity: GlobalStates.osdProtectionMessage !== "" ? 1 : 0
                        visible: height > 0

                        Rectangle {
                            id: protectionMessageBackground
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Appearance.m3colors.m3error
                            property real padding: 10
                            implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                            implicitWidth: Math.min(parent.width - 20, protectionMessageRowLayout.implicitWidth + padding * 2)
                            radius: Appearance.rounding.normal

                            RowLayout {
                                id: protectionMessageRowLayout
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    text: "dangerous"
                                    iconSize: Appearance.font.pixelSize.hugeass
                                    color: Appearance.m3colors.m3onError
                                }
                                StyledText {
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Appearance.m3colors.m3onError
                                    wrapMode: Text.Wrap
                                    text: GlobalStates.osdProtectionMessage
                                }
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onPressed: event => {
                event.accepted = false;
            }
        }
    }

    readonly property var maskItem: dropContainer

    function _updateBlurExclusion() {
        var active = root.isOpen && dropContainer.width > 0 && dropContainer.height > 0;
        var sx = dropContainer.x;
        var sy = dropContainer.y;
        var sw = dropContainer.width;
        var sh = dropContainer.height;

        const topR = dropNotch.topRadius;
        const bottomR = dropNotch.bottomRadius;
        if (GlobalStates.osdDropActive !== active || GlobalStates.osdDropExclusionX !== sx || GlobalStates.osdDropExclusionY !== sy || GlobalStates.osdDropExclusionWidth !== sw || GlobalStates.osdDropExclusionHeight !== sh || GlobalStates.osdDropTopRadius !== topR || GlobalStates.osdDropBottomRadius !== bottomR) {
            GlobalStates.osdDropActive = active;
            GlobalStates.osdDropExclusionX = sx;
            GlobalStates.osdDropExclusionY = sy;
            GlobalStates.osdDropExclusionWidth = sw;
            GlobalStates.osdDropExclusionHeight = sh;
            GlobalStates.osdDropTopRadius = topR;
            GlobalStates.osdDropBottomRadius = bottomR;
        }
    }

    onIsOpenChanged: Qt.callLater(_updateBlurExclusion)
    Component.onCompleted: Qt.callLater(_updateBlurExclusion)
}
