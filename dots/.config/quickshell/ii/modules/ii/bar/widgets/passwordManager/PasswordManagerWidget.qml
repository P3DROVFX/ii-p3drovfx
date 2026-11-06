import qs
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.passwordManager
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Passwords — default bar style: a glyph for the vault state and, after a
 * copy, the seconds until the clipboard clears. The BarGroup supplies the
 * background. Click opens the popup, right click locks.
 */
MouseArea {
    id: root

    property bool vertical: false
    // Keeps the right press away from the popup's click toggle.
    readonly property bool rightClickCycles: true
    readonly property string screenName: root.QsWindow?.window?.screen?.name ?? ""

    readonly property color contentColor: Appearance.colors.colOnLayer1
    readonly property string glyph: {
        switch (PasswordManager.state) {
        case "unlocked": return "key";
        case "missing": return "key_off";
        default: return "lock";
        }
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : content.implicitWidth + 10
    implicitHeight: root.vertical ? content.implicitHeight + 10 : Appearance.sizes.baseBarHeight
    hoverEnabled: !BarInteraction.clickToShow
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton && PasswordManager.unlocked)
            PasswordManager.lock();
    }

    GridLayout {
        id: content
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        columnSpacing: 4
        rowSpacing: 0

        Item {
            implicitWidth: 24
            implicitHeight: 24
            Layout.alignment: Qt.AlignCenter

            CircularProgress {
                anchors.centerIn: parent
                visible: PasswordManager.clipActive
                implicitSize: 24
                lineWidth: 2
                value: PasswordManager.clipSeconds > 0 ? PasswordManager.clipRemaining / PasswordManager.clipSeconds : 0
                colPrimary: root.contentColor
                colSecondary: "transparent"
                animationDuration: 1000
                easingType: Easing.Linear
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: PasswordManager.clipActive ? "content_paste" : root.glyph
                iconSize: PasswordManager.clipActive ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.larger
                fill: PasswordManager.unlocked ? 1 : 0
                color: root.contentColor
            }
        }

        StyledText {
            visible: PasswordManager.clipActive
            text: String(PasswordManager.clipRemaining)
            font.pixelSize: root.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            font.weight: Font.Bold
            color: root.contentColor
            Layout.alignment: Qt.AlignCenter
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
