import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Fullscreen screenshot viewer on the Settings window's screen. Controlled:
 * the owner holds which picture is shown and whether it is open, and gets
 * asked to change either. The layer surface only exists while shown.
 *
 * Esc/Space/click close, ←/→ step.
 */
Loader {
    id: root

    // Image URLs, in order.
    property var sources: []
    property int index: 0
    property bool shown: false

    signal closeRequested
    signal stepRequested(int delta)

    readonly property string current: String(root.sources[root.index] ?? "")

    active: root.shown && root.current.length > 0

    sourceComponent: PanelWindow {
        id: lightbox
        screen: (root.QsWindow.window as QsWindow)?.screen ?? null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:presetLightbox"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            id: lightboxContent
            anchors.fill: parent
            color: ColorUtils.transparentize("black", 0.1)
            focus: true
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space) {
                    root.closeRequested();
                } else if (event.key === Qt.Key_Left) {
                    root.stepRequested(-1);
                } else if (event.key === Qt.Key_Right) {
                    root.stepRequested(1);
                } else {
                    return;
                }
                event.accepted = true;
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: root.closeRequested()
            }

            Image {
                anchors.fill: parent
                anchors.margins: 32
                source: root.current
                asynchronous: true
                retainWhileLoading: true
                fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(lightbox.width * lightbox.devicePixelRatio,
                    lightbox.height * lightbox.devicePixelRatio)
            }

            StyledText {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                visible: root.sources.length > 1
                text: `${root.index + 1} / ${root.sources.length}`
                color: "white"
                font.pixelSize: Appearance.font.pixelSize.small
            }

            component LightboxNavButton: RippleButton {
                id: navButton
                property string symbol
                visible: root.sources.length > 1
                implicitWidth: 48
                implicitHeight: 48
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize("black", 0.5)
                colBackgroundHover: ColorUtils.transparentize("black", 0.3)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: navButton.symbol
                    iconSize: 28
                    color: "white"
                }
            }

            LightboxNavButton {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                symbol: "chevron_left"
                onClicked: root.stepRequested(-1)
            }

            LightboxNavButton {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                symbol: "chevron_right"
                onClicked: root.stepRequested(1)
            }

            LightboxNavButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 24
                visible: true
                symbol: "close"
                onClicked: root.closeRequested()
            }
        }
    }
}
