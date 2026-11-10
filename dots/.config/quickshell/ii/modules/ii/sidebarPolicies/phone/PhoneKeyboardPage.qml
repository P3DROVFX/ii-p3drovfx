pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Type on the phone from the PC keyboard, without a mirror.
 *
 * KDE Connect's Remote Keyboard plugin types into whatever text field has the phone's
 * "KDE Connect Remote Keyboard" input method. The pad below takes the keyboard focus and
 * forwards every key: printable text as text (accents and dead keys arrive composed),
 * the editing keys by KDE Connect's own codes, and Ctrl shortcuts as such. Ctrl+V sends
 * the PC's clipboard as text.
 */
ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    readonly property bool active: KdeConnectService.remoteKeyboardActive
    /** What was sent, so the pad shows something; the phone's field is the truth. */
    property string echo: ""

    function _remember(text) {
        root.echo = (root.echo + text).slice(-240);
    }

    // ─── Header ─────────────────────────────────────────────
    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
            onClicked: root.goBack()
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Type on phone")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: statusRow.implicitWidth + 22
            radius: Appearance.rounding.full
            color: root.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3

            RowLayout {
                id: statusRow
                anchors.centerIn: parent
                spacing: 5

                MaterialSymbol {
                    text: root.active ? "keyboard" : "keyboard_off"
                    iconSize: 16
                    color: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                }
                StyledText {
                    text: root.active ? Translation.tr("Ready") : Translation.tr("Waiting")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                }
            }
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: !root.active
        materialIcon: "info"
        text: Translation.tr("On the phone, switch the keyboard to \"KDE Connect Remote Keyboard\" and tap a text field. Keys typed here then land there.")
    }

    // ─── The pad ────────────────────────────────────────────
    Rectangle {
        id: pad
        Layout.fillWidth: true
        Layout.preferredHeight: 180
        radius: Appearance.rounding.normal
        color: keyCatcher.activeFocus ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        opacity: root.active ? 1 : 0.6

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pad)
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Component.onCompleted: keyCatcher.forceActiveFocus()

            Keys.onPressed: event => {
                if (!root.active) {
                    event.accepted = false;
                    return;
                }
                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                const alt = (event.modifiers & Qt.AltModifier) !== 0;
                const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                const special = ({
                    [Qt.Key_Backspace]: "backspace", [Qt.Key_Tab]: "tab",
                    [Qt.Key_Left]: "left", [Qt.Key_Up]: "up", [Qt.Key_Right]: "right", [Qt.Key_Down]: "down",
                    [Qt.Key_PageUp]: "pageup", [Qt.Key_PageDown]: "pagedown",
                    [Qt.Key_Home]: "home", [Qt.Key_End]: "end",
                    [Qt.Key_Return]: "enter", [Qt.Key_Enter]: "enter",
                    [Qt.Key_Delete]: "delete", [Qt.Key_Escape]: "escape"
                })[event.key];

                if (special) {
                    KdeConnectService.sendRemoteKey(special, shift, ctrl, alt);
                    if (special === "backspace")
                        root.echo = root.echo.slice(0, -1);
                    else if (special === "enter")
                        root._remember("\n");
                } else if (ctrl && event.key === Qt.Key_V) {
                    const text = Quickshell.clipboardText ?? "";
                    KdeConnectService.sendRemoteText(text);
                    root._remember(text);
                } else if ((ctrl || alt) && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                    KdeConnectService.sendRemoteKey(String.fromCharCode(event.key).toLowerCase(), shift, ctrl, alt);
                } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
                    KdeConnectService.sendRemoteText(event.text);
                    root._remember(event.text);
                } else {
                    event.accepted = false;
                    return;
                }
                event.accepted = true;
            }

            TapHandler {
                onTapped: keyCatcher.forceActiveFocus()
            }
        }

        StyledText {
            anchors.fill: parent
            anchors.margins: 14
            text: root.echo.length > 0 ? root.echo
                : keyCatcher.activeFocus ? Translation.tr("Start typing…")
                : Translation.tr("Click here, then type")
            color: root.echo.length > 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.normal
            wrapMode: Text.Wrap
            elide: Text.ElideLeft
            verticalAlignment: Text.AlignBottom
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Ctrl+V sends the PC clipboard")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }

        RippleButtonWithIcon {
            materialIcon: "content_paste"
            mainText: Translation.tr("Paste")
            enabled: root.active
            onClicked: {
                const text = Quickshell.clipboardText ?? "";
                KdeConnectService.sendRemoteText(text);
                root._remember(text);
                keyCatcher.forceActiveFocus();
            }
        }
    }
}
