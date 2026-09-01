import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.portWatcher
import qs.services
import QtQuick

/**
 * Port Watcher — expressive bar style.
 *
 * The same pill grammar the other expressive widgets use: a container-tinted
 * capsule holding the count, with a filled shape as the indicator on the
 * trailing edge.
 *
 * The palette is fixed. It cannot key off the popup either, because the popup
 * opens on hover — an "active" tint would be a hover tint wearing a different
 * name. The only thing hovering does is morph the shape in the indicator.
 */
MouseArea {
    id: root

    property bool vertical: false

    readonly property int portCount: PortWatcher.enabled ? PortWatcher.count : 0
    readonly property bool shown: PortWatcher.enabled
        && (!(Config.options.bar.portWatcher.hideWhenEmpty ?? false) || root.portCount > 0)

    readonly property color colContainer: ColorUtils.mix(Appearance.colors.colSecondaryContainer,
        Appearance.colors.colOnSecondaryContainer, 0.9)
    readonly property color colOnContainer: Appearance.colors.colOnSecondaryContainer
    readonly property color colIndicator: Appearance.colors.colSecondary
    readonly property color colOnIndicator: Appearance.colors.colOnSecondary

    // Hover is a shape change, nothing else. The spin sells the swap as a
    // morph instead of a hard cut between two silhouettes.
    readonly property string indicatorShape: root.containsMouse ? "Clover4Leaf" : "Circle"

    visible: root.shown
    implicitWidth: !root.shown ? 0 : (root.vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth)
    implicitHeight: !root.shown ? 0 : (root.vertical ? pillVertical.implicitHeight : Appearance.sizes.baseBarHeight)
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    onClicked: PortWatcher.refresh()

    // Drive the morph from the hover itself. Re-declaring onShapeStringChanged
    // on the MaterialShape would override the handler inside MaterialShape.qml
    // that turns shapeString into a polygon, and the shape would stop updating.
    onContainsMouseChanged: {
        morph.restart();
        morphVertical.restart();
    }

    // ── Horizontal capsule ───────────────────────────────────────────────────
    Rectangle {
        id: pill

        visible: !root.vertical
        anchors.centerIn: parent
        radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
        implicitHeight: Appearance.sizes.baseBarHeight - 8
        height: implicitHeight
        implicitWidth: countText.implicitWidth + indicator.width + 22
        width: implicitWidth
        color: root.colContainer

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on implicitWidth {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }

        StyledText {
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
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
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
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                // The shape spins; the glyph stays upright.
                rotation: -indicator.rotation
                text: "lan"
                iconSize: Appearance.font.pixelSize.small
                fill: 1
                color: root.colOnIndicator
            }
        }
    }

    // ── Vertical capsule ─────────────────────────────────────────────────────
    Rectangle {
        id: pillVertical

        visible: root.vertical
        anchors.centerIn: parent
        radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
        implicitWidth: Appearance.sizes.verticalBarWidth - 8
        width: implicitWidth
        implicitHeight: countTextVertical.implicitHeight + indicatorVertical.height + 16
        height: implicitHeight
        color: root.colContainer

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        StyledText {
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
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
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
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
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

    PortWatcherPopup {
        id: popup
        hoverTarget: root
    }
}
