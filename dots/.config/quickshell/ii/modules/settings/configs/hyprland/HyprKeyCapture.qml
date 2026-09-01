pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Choose the key a shortcut sits on, by pressing it or by typing its name.
 *
 * Capture alone is not enough on a layout that is not US. Qt reports the character the key
 * produces, and on this machine's AZERTY the digits never arrive unshifted at all, so a naive
 * capture writes a shortcut that does not match what Hyprland sees. Three things follow from
 * that: what was captured is always shown as text before it is saved, the text is editable, and
 * a key whose meaning moves with the layout can be written as the physical key instead
 * (`code:38`), which is the same key on every layout.
 */
ColumnLayout {
    id: root

    property var mods: []
    property string key: ""
    property bool capturing: false
    /// The last physical key seen, so "use the physical key" can be offered after the fact.
    property int lastScanCode: 0

    signal chosen(var newMods, string newKey)

    spacing: 8

    /// Qt key codes that mean the same thing on every layout. Letters and digits are handled
    /// separately: those are the ones a layout moves around.
    readonly property var namedKeys: ({
        [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "KP_Enter", [Qt.Key_Space]: "Space",
        [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab", [Qt.Key_Backspace]: "BackSpace",
        [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert", [Qt.Key_Home]: "Home",
        [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down",
        [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
        [Qt.Key_Print]: "Print", [Qt.Key_Pause]: "Pause", [Qt.Key_Menu]: "Menu",
        [Qt.Key_ScrollLock]: "Scroll_Lock",
        [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume", [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
        [Qt.Key_VolumeMute]: "XF86AudioMute", [Qt.Key_MediaPlay]: "XF86AudioPlay",
        [Qt.Key_MediaStop]: "XF86AudioStop", [Qt.Key_MediaNext]: "XF86AudioNext",
        [Qt.Key_MediaPrevious]: "XF86AudioPrev",
        [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp",
        [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown"
    })

    /// The character a key produced, as XKB names it. Only for the punctuation people really
    /// bind; anything else falls back to the physical key.
    readonly property var characterKeys: ({
        "/": "Slash", ".": "Period", ",": "Comma", ";": "Semicolon", "'": "Apostrophe",
        "-": "Minus", "=": "Equal", "[": "bracketleft", "]": "bracketright",
        "\\": "Backslash", "`": "grave", ":": "colon", "*": "asterisk", "+": "plus",
        "<": "less", ">": "greater", "!": "exclam", "?": "question", "&": "ampersand",
        "$": "dollar", "#": "numbersign", "@": "at", "%": "percent", "^": "asciicircum",
        "~": "asciitilde", "_": "underscore", "\"": "quotedbl"
    })

    readonly property var modifierKeys: [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta,
        Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_Super_L, Qt.Key_Super_R]

    function modsFromEvent(modifiers: int): var {
        const out = [];
        if (modifiers & Qt.ControlModifier) out.push("CTRL");
        if (modifiers & Qt.MetaModifier) out.push("SUPER");
        if (modifiers & Qt.AltModifier) out.push("ALT");
        if (modifiers & Qt.ShiftModifier) out.push("SHIFT");
        return HyprlandBinds.sortMods(out);
    }

    function keyNameFor(event: var): string {
        if (root.namedKeys[event.key] !== undefined) return root.namedKeys[event.key];
        if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35)
            return `F${event.key - Qt.Key_F1 + 1}`;
        if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            return String.fromCharCode(event.key);
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
            return String.fromCharCode(event.key);
        const text = String(event.text ?? "");
        if (root.characterKeys[text] !== undefined) return root.characterKeys[text];
        if (/^[a-zA-Z]$/.test(text)) return text.toUpperCase();
        if (/^[0-9]$/.test(text)) return text;
        // Nothing readable came through, which is exactly the case the physical key is for.
        return event.nativeScanCode > 0 ? `code:${event.nativeScanCode}` : "";
    }

    /// Reports outwards and nothing else. `mods` and `key` stay bound to whatever the page
    /// holds, so assigning them here would break that binding on the first capture and leave
    /// the field showing a value the page has since moved on from.
    function apply(newMods: var, newKey: string) {
        root.chosen(newMods, newKey);
    }

    function usePhysicalKey() {
        if (root.lastScanCode <= 0) return;
        root.apply(root.mods, `code:${root.lastScanCode}`);
    }

    readonly property bool isPhysical: /^code:\d+$/.test(root.key)

    /**
     * While the button is listening, every shortcut that already exists has to stop working, or
     * pressing one runs it instead of recording it - which is exactly what made this unusable
     * for the shortcuts people actually want to change.
     *
     * Hyprland matches binds before the key reaches this window, so nothing on this side can
     * get in front of them. A submap can: inside one, only that submap's own binds fire and
     * every other key falls through to whatever has focus. The submap holds a single Escape
     * bind that leaves it again, so even a shell that dies mid-capture leaves a way out - and
     * a config reload drops the submap on its own. That bind is non-consuming, so Escape still
     * reaches the button below and stops it listening rather than leaving it armed over a
     * submap it has already left.
     */
    function inhibitShortcuts(on: bool) {
        const name = HyprlandBinds.captureSubmap;
        if (!on) {
            Quickshell.execDetached(["hyprctl", "eval",
                `if hl.get_current_submap() == "${name}" then hl.dispatch(hl.dsp.submap("reset")) end`]);
            return;
        }
        const define = HyprlandBinds.captureSubmapDefined ? ""
            : `hl.define_submap("${name}", function() hl.bind("ESCAPE", function() `
                + `hl.dispatch(hl.dsp.submap("reset")) end, { non_consuming = true }) end) `;
        HyprlandBinds.captureSubmapDefined = true;
        Quickshell.execDetached(["hyprctl", "eval", define
            + `if hl.get_current_submap() == "" then hl.dispatch(hl.dsp.submap("${name}")) end`]);
    }

    onCapturingChanged: root.inhibitShortcuts(root.capturing)
    Component.onDestruction: {
        if (root.capturing) root.inhibitShortcuts(false);
    }

    /// Nothing else would notice a window that lost focus without saying so, and being left in
    /// the submap means a keyboard that does nothing.
    Timer {
        running: root.capturing
        interval: 30000
        onTriggered: root.capturing = false
    }

    /// The manual field, the physical-key escape hatch and the sentence explaining the
    /// difference are all for a keyboard layout that moves its keys around. Somebody who opened
    /// this page to move one shortcut off F1 does not need any of it.
    readonly property bool advanced: Config.options.hyprland.advancedSettings

    RippleButton {
        id: captureButton
        Layout.fillWidth: true
        implicitHeight: 92
        buttonRadius: Appearance.rounding.large
        colBackground: root.capturing ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: root.capturing ? Appearance.colors.colPrimaryContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: root.capturing ? Appearance.colors.colPrimaryContainerActive
            : Appearance.colors.colLayer2Active

        onClicked: {
            root.capturing = !root.capturing;
            if (root.capturing) captureButton.forceActiveFocus();
        }

        // Losing focus while armed leaves a button that looks like it is listening and is not.
        onActiveFocusChanged: {
            if (!captureButton.activeFocus) root.capturing = false;
        }

        Keys.onPressed: event => {
            if (!root.capturing) return;
            event.accepted = true;
            if (event.isAutoRepeat) return;
            if (event.key === Qt.Key_Escape) {
                root.capturing = false;
                return;
            }
            if (root.modifierKeys.includes(event.key)) return;
            root.lastScanCode = event.nativeScanCode ?? 0;
            const name = root.keyNameFor(event);
            if (name === "") return;
            root.apply(root.modsFromEvent(event.modifiers), name);
            root.capturing = false;
        }

        /**
         * A record button that looks like one.
         *
         * What was here before showed the keys and, underneath, "Click to record a different
         * one" - so it read as a preview of the shortcut with a caption, and people looked at
         * it without ever realising it was the control. The dot and the word "Record" are on
         * the same line as the keys now, on the right, where every recorder in every other
         * program puts them.
         */
        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 16

                Flow {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: !root.capturing && root.key !== ""
                    spacing: 4

                    Repeater {
                        model: root.mods

                        delegate: HyprKeyChip {
                            required property var modelData

                            subdued: true
                            symbolKey: modelData
                            text: HyprlandBinds.modLabels[modelData] ?? modelData
                        }
                    }

                    HyprKeyChip {
                        symbolKey: root.key
                        text: HyprlandBinds.keyLabel(root.key)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.capturing || root.key === ""
                    text: root.capturing ? Translation.tr("Press the shortcut now — Esc to stop")
                        : Translation.tr("No shortcut yet")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: root.capturing ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colSubtext
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    implicitWidth: recordRow.implicitWidth + 28
                    radius: Appearance.rounding.full
                    color: root.capturing ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colPrimary

                    RowLayout {
                        id: recordRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: root.capturing ? "stop_circle" : "fiber_manual_record"
                            iconSize: 20
                            fill: 1
                            color: root.capturing ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            text: root.capturing ? Translation.tr("Listening")
                                : Translation.tr("Record")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: root.capturing ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.advanced
        spacing: 8

        ConfigTextField {
            id: manualField
            Layout.fillWidth: true
            placeholderText: Translation.tr("SUPER + SHIFT + A")

            readonly property string currentValue: HyprlandBinds.comboSource(root.mods, root.key)

            onCurrentValueChanged: {
                if (manualField.textField.activeFocus) return;
                manualField.inputText = manualField.currentValue;
            }

            Component.onCompleted: manualField.inputText = manualField.currentValue

            Connections {
                target: manualField.textField

                function onEditingFinished() {
                    if (manualField.inputText === manualField.currentValue) return;
                    const parts = HyprlandBinds.splitCombo(manualField.inputText);
                    root.apply(parts.mods, parts.key);
                }
            }
        }

        // A sentence-long button next to a text field made the row look broken. The idea is
        // one action on one key, so it is one round button with the explanation on hover.
        RippleButton {
            visible: root.lastScanCode > 0 && !root.isPhysical
            implicitHeight: 44
            implicitWidth: 44
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.usePhysicalKey()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "pin_drop"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledToolTip {
                text: Translation.tr("Use the key in this position instead, so it survives a layout change")
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.advanced
        text: root.isPhysical
            ? Translation.tr("This is the key in that position on the keyboard, whatever it prints. It keeps working if you change layout.")
            : Translation.tr("This is the character the key produces, so it moves if you change keyboard layout. Digits and punctuation are the ones that move most.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.WordWrap
    }
}
