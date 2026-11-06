import qs
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.passwordManager
import qs.services
import QtQuick

/**
 * Passwords — expressive bar style.
 *
 * A capsule holding one shape, and the shape is the state: a circle while
 * locked, the vault's Cookie7 when open, a SoftBurst while a copied secret
 * waits on the clipboard — with the seconds left in condensed digits beside
 * it and a ring draining around it. Hover morphs the shape, nothing spins.
 * Click opens the popup, right click locks.
 */
MouseArea {
    id: root

    property bool vertical: false
    readonly property bool rightClickCycles: true
    readonly property string screenName: root.QsWindow?.window?.screen?.name ?? ""

    BarWidgetPalette {
        id: palette
        colorMode: Config.options.bar.passwordManager?.colorMode ?? "primary"
    }

    readonly property bool clip: PasswordManager.clipActive
    readonly property color colContainer: root.containsMouse ? palette.colBackgroundHover : palette.colBackground
    readonly property color colOnContainer: palette.colOnBackground
    readonly property color colIndicator: PasswordManager.unlocked || root.clip ? palette.colBackgroundVariant : root.colContainer
    readonly property color colOnIndicator: PasswordManager.unlocked || root.clip ? palette.colOnBackgroundVariant : root.colOnContainer

    readonly property string indicatorShape: {
        if (root.clip)
            return "SoftBurst";
        if (root.containsMouse)
            return "Cookie12Sided";
        return PasswordManager.unlocked ? "Cookie7Sided" : "Circle";
    }
    readonly property string glyph: {
        if (root.clip)
            return PasswordManager.clipField === "username" ? "person" : PasswordManager.clipField === "totp" ? "pin" : "content_paste";
        switch (PasswordManager.state) {
        case "unlocked": return "key";
        case "missing": return "key_off";
        default: return "lock";
        }
    }

    readonly property int thickness: (root.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) - 8
    readonly property real groupRadius: (typeof rootItem !== "undefined" ? rootItem.groupStyle : Config.options.bar.barGroupStyle) === 1
        ? Appearance.rounding.windowRounding : Appearance.rounding.full

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : capsule.width + 4
    implicitHeight: root.vertical ? capsule.height + 4 : Appearance.sizes.baseBarHeight
    hoverEnabled: !BarInteraction.clickToShow
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton && PasswordManager.unlocked)
            PasswordManager.lock();
    }

    Rectangle {
        id: capsule

        // One value drives the capsule's growth when the countdown appears.
        property real reveal: root.clip ? 1 : 0
        Behavior on reveal {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        readonly property real extra: Math.round((digits.implicitWidth + 10) * capsule.reveal)
        readonly property real extraV: Math.round((digits.implicitHeight + 2) * capsule.reveal)

        anchors.centerIn: parent
        width: root.vertical ? root.thickness : root.thickness + capsule.extra
        height: root.vertical ? root.thickness + capsule.extraV : root.thickness
        radius: Math.min(root.groupRadius, root.thickness / 2)
        color: root.colContainer

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Item {
            id: indicatorSlot
            width: root.thickness
            height: root.thickness
            anchors.left: parent.left
            anchors.top: parent.top

            CircularProgress {
                anchors.centerIn: parent
                visible: root.clip
                implicitSize: root.thickness - 2
                lineWidth: 2
                value: PasswordManager.clipSeconds > 0 ? PasswordManager.clipRemaining / PasswordManager.clipSeconds : 0
                colPrimary: root.colOnContainer
                colSecondary: "transparent"
                animationDuration: 1000
                easingType: Easing.Linear
            }

            MaterialShape {
                id: indicator
                anchors.centerIn: parent
                implicitSize: root.thickness - (root.clip ? 9 : 4)
                shapeString: root.indicatorShape
                color: root.colIndicator

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.glyph
                    iconSize: Appearance.font.pixelSize.small
                    fill: 1
                    color: root.colOnIndicator
                }
            }
        }

        StyledText {
            id: digits
            x: root.vertical ? (capsule.width - width) / 2 : root.thickness + 2
            y: root.vertical ? root.thickness : (capsule.height - height) / 2
            opacity: capsule.reveal
            visible: capsule.reveal > 0.01
            text: String(PasswordManager.clipRemaining)
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
            font.pixelSize: root.vertical ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
            color: root.colOnContainer
        }
    }

    PopupLoader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || held
                || GlobalStates.isBarPopupOpen("passwords", root.screenName))
        sourceComponent: PasswordManagerPopup {
            hoverTarget: root
        }
    }
}
