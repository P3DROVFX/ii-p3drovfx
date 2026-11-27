import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.portWatcher
import qs.services
import QtQuick

/**
 * Port Watcher — expressive bar style.
 *
 * Single lazy orientation via Loader: avoids instantiating two MaterialShapes,
 * two AnimatedStyledTexts, and 8 dynamic Behavior animations (or any of them
 * when hidden).
 */
MouseArea {
    id: root

    property bool vertical: false

    readonly property int portCount: PortWatcher.enabled ? PortWatcher.count : 0
    readonly property bool shown: PortWatcher.enabled
        && (!(Config.options.bar.portWatcher.hideWhenEmpty ?? false) || root.portCount > 0)

    BarWidgetPalette {
        id: widgetPalette
        colorMode: Config.options.bar.portWatcher.colorMode
    }

    readonly property color colContainer: root.containsMouse ? widgetPalette.colBackgroundHover : widgetPalette.colBackground
    readonly property color colOnContainer: widgetPalette.colOnBackground
    readonly property color colIndicator: widgetPalette.colBackgroundVariant
    readonly property color colOnIndicator: widgetPalette.colOnBackgroundVariant
    readonly property string indicatorShape: root.containsMouse ? "Clover4Leaf" : "Circle"

    visible: root.shown
    implicitWidth: !root.shown ? 0 : (root.vertical ? Appearance.sizes.verticalBarWidth : (pillLoader.item?.implicitWidth ?? 0))
    implicitHeight: !root.shown ? 0 : (root.vertical ? (pillLoader.item?.implicitHeight ?? 0) : Appearance.sizes.baseBarHeight)
    hoverEnabled: !BarInteraction.clickToShow

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.barResize.duration
            easing.type: Appearance.animation.barResize.type
            easing.bezierCurve: Appearance.animation.barResize.bezierCurve
        }
    }

    onClicked: PortWatcher.refresh()
    onContainsMouseChanged: {
        if (pillLoader.item && typeof pillLoader.item.restartMorph === "function")
            pillLoader.item.restartMorph();
    }

    Loader {
        id: pillLoader
        anchors.centerIn: parent
        active: root.shown
        sourceComponent: root.vertical ? pillVerticalComp : pillHorizontalComp
    }

    Component {
        id: pillHorizontalComp
        Rectangle {
            id: pill
            function restartMorph() { morph.restart(); }

            radius: (typeof rootItem !== "undefined" ? rootItem.groupStyle : Config.options.bar.barGroupStyle) === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
            implicitHeight: Appearance.sizes.baseBarHeight - 8
            height: implicitHeight
            implicitWidth: countText.implicitWidth + indicator.width + 22
            width: implicitWidth
            color: root.colContainer

            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }
            Behavior on implicitWidth {
                NumberAnimation {
                    duration: Appearance.animation.barResize.duration
                    easing.type: Appearance.animation.barResize.type
                    easing.bezierCurve: Appearance.animation.barResize.bezierCurve
                }
            }

            AnimatedStyledText {
                id: countText
                anchors.left: parent.left
                anchors.leftMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                text: String(root.portCount)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                color: root.colOnContainer
                animateChange: true

                Behavior on color {
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                }
            }

            MaterialShape {
                id: indicator
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                shapeString: root.indicatorShape
                implicitSize: parent.height - 8
                color: root.colIndicator

                NumberAnimation {
                    id: morph
                    target: indicator
                    property: "rotation"
                    from: -40
                    to: 0
                    duration: 340
                    easing.type: Easing.OutBack
                }

                Behavior on color {
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    rotation: -indicator.rotation
                    text: "lan"
                    iconSize: Appearance.font.pixelSize.small
                    fill: 1
                    color: root.colOnIndicator
                }
            }
        }
    }

    Component {
        id: pillVerticalComp
        Rectangle {
            id: pillVertical
            function restartMorph() { morphVertical.restart(); }

            radius: (typeof rootItem !== "undefined" ? rootItem.groupStyle : Config.options.bar.barGroupStyle) === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
            implicitWidth: Appearance.sizes.verticalBarWidth - 8
            width: implicitWidth
            implicitHeight: countTextVertical.implicitHeight + indicatorVertical.height + 16
            height: implicitHeight
            color: root.colContainer

            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            AnimatedStyledText {
                id: countTextVertical
                anchors.top: parent.top
                anchors.topMargin: 7
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(root.portCount)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: root.colOnContainer
                animateChange: true

                Behavior on color {
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                }
            }

            MaterialShape {
                id: indicatorVertical
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                anchors.horizontalCenter: parent.horizontalCenter
                shapeString: root.indicatorShape
                implicitSize: parent.width - 6
                color: root.colIndicator

                NumberAnimation {
                    id: morphVertical
                    target: indicatorVertical
                    property: "rotation"
                    from: -40
                    to: 0
                    duration: 340
                    easing.type: Easing.OutBack
                }

                Behavior on color {
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    rotation: -indicatorVertical.rotation
                    text: "lan"
                    iconSize: Appearance.font.pixelSize.small
                    fill: 1
                    color: root.colOnIndicator
                }
            }
        }
    }

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    PopupLoader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || held)
        sourceComponent: PortWatcherPopup {
            hoverTarget: root
        }
    }
}
