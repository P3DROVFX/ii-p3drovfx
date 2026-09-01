import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    anchors.fill: parent
    property real baseWidth: 600
    property bool forceWidth: false
    property real bottomContentPadding: 100
    readonly property bool scrollFadeEnabled: Config.options?.appearance?.scrollFadeMask ?? true
    readonly property bool settingsPerformanceMode: Config.options?.appearance?.settingsPerformanceMode ?? false
    readonly property bool allowScrollFade: root.scrollFadeEnabled && !root.settingsPerformanceMode

    property alias contentY: flickable.contentY
    property alias atYBeginning: flickable.atYBeginning
    property alias atYEnd: flickable.atYEnd
    /// For anything that has to scroll the page itself, such as a drag reaching its edge.
    readonly property alias flickable: flickable

    default property alias contentData: contentColumn.data

    Item {
        id: headerContainer
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: (children.length > 0 && children[0].visible) ? children[0].implicitHeight : 0
        z: 2
    }

    StyledFlickable {
        id: flickable
        anchors.top: headerContainer.bottom
        anchors.topMargin: headerContainer.height > 0 ? 12 : 0
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true

        // Performance Mode leaves the entire mask subtree unloaded, including
        // the offscreen layer texture. Normal Mode retains the existing fade.
        layer.enabled: root.allowScrollFade && flickable.contentHeight > flickable.height
        layer.effect: fadeMaskLoader.item

        Loader {
            id: fadeMaskLoader
            active: root.allowScrollFade
            sourceComponent: fadeMaskComponent
        }

        Component {
            id: fadeMaskComponent

            OpacityMask {
                maskSource: Item {
                    id: maskRoot
                    width: flickable.width
                    height: flickable.height

                    property bool fadeEnabled: root.allowScrollFade
                    property color topFadeColor: (fadeEnabled && !flickable.atYBeginning) ? "transparent" : "white"
                    property color bottomFadeColor: (fadeEnabled && !flickable.atYEnd) ? "transparent" : "white"

                    Behavior on topFadeColor {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on bottomFadeColor {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    Column {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            width: parent.width
                            height: Math.min(36, parent.height / 2)
                            topLeftRadius: Appearance.rounding.normal
                            topRightRadius: Appearance.rounding.normal
                            color: "transparent"
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: maskRoot.topFadeColor }
                                GradientStop { position: 1.0; color: "white" }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: Math.max(0, parent.height - Math.min(36, parent.height / 2) * 2)
                            color: "white"
                        }

                        Rectangle {
                            width: parent.width
                            height: Math.min(36, parent.height / 2)
                            bottomLeftRadius: Appearance.rounding.normal
                            bottomRightRadius: Appearance.rounding.normal
                            color: "transparent"
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "white" }
                                GradientStop { position: 1.0; color: maskRoot.bottomFadeColor }
                            }
                        }
                    }
                }
            }
        }
        contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
        implicitWidth: contentColumn.implicitWidth
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: contentColumn
            width: root.forceWidth ? root.baseWidth : (parent ? parent.width - (anchors.leftMargin + anchors.rightMargin) : 600)
            anchors {
                top: parent.top
                left: root.forceWidth ? undefined : parent.left
                right: root.forceWidth ? undefined : parent.right
                horizontalCenter: root.forceWidth ? parent.horizontalCenter : undefined
                leftMargin: root.forceWidth ? 20 : 0
                rightMargin: root.forceWidth ? 20 : 0
                topMargin: root.forceWidth ? 20 : 0
                bottomMargin: root.forceWidth ? 20 : 0
            }
            spacing: 12
        }
    }

    Component.onCompleted: {
        if (root.hasOwnProperty("goBack") && contentColumn.children.length > 0) {
            let firstChild = contentColumn.children[0];
            if (firstChild.toString().indexOf("RowLayout") !== -1) {
                firstChild.parent = headerContainer;

                firstChild.anchors.top = headerContainer.top;

                if (root.forceWidth) {
                    firstChild.anchors.left = headerContainer.horizontalCenter;
                    firstChild.anchors.leftMargin = -root.baseWidth / 2;
                } else {
                    firstChild.anchors.left = headerContainer.left;
                    firstChild.anchors.leftMargin = 0;
                }
            }
        }
    }
}
