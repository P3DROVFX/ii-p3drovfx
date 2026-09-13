pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One shortcut: which keys, what happens, and the fine print.
 *
 * Unlike everything else in this hub, nothing is written until Save. A shortcut is one Lua
 * statement made of three parts, and writing it after each keystroke would put a bind with no
 * action - or worse, a half-typed action - into a file the compositor reloads immediately.
 *
 * Saving always writes two lines: a release of the key, then the bind. Hyprland's bind is
 * additive, so binding a key something else already holds registers both and both fire on the
 * press; the release is what makes "change this shortcut" mean what it says. It is wrapped in
 * pcall, so it costs nothing on a key that was free.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var draft: HyprlandBinds.draft
    readonly property var actionEntry: HyprlandBinds.catalogueEntry(subPageRoot.draft.actionId ?? "")
    readonly property string combo: HyprlandBinds.comboSource(subPageRoot.draft.mods ?? [],
        subPageRoot.draft.key ?? "")
    readonly property string comboId: HyprlandBinds.bindId(subPageRoot.draft.mods ?? [],
        subPageRoot.draft.key ?? "")
    readonly property var problems: HyprlandBinds.draftProblems

    /// What already sits on the chosen key, not counting the shortcut being edited. Two binds
    /// on one key both fire, so this is the difference between replacing and doubling up.
    readonly property var occupants: {
        if (String(subPageRoot.draft.key ?? "") === "") return [];
        return HyprlandBinds.effective.filter(row => row.kind === "bind" && row.resolved
            && row.canonical === subPageRoot.comboId
            && row.rowId !== HyprlandBinds.editRowId);
    }

    readonly property var current: HyprlandBinds.editing

    /// Somebody who opened this page opened it to change which key does the thing. Eleven
    /// switches about long presses, modifier masks and shortcut inhibitors are for the day they
    /// want one of those specifically, and that day they can turn advanced mode on.
    readonly property bool advanced: Config.options.hyprland.advancedSettings

    readonly property bool isManaged: HyprlandBinds.managedBind(HyprlandBinds.editId) !== null
    readonly property bool lastEssential: subPageRoot.current !== null
        && HyprlandBinds.isLastEssential(subPageRoot.current)

    /**
     * The options hl.bind accepts, from HL.BindOptions in Hyprland's own stub. That list is the
     * only reliable source: an option name it does not know is accepted and silently ignored,
     * so a typo here would produce a switch that does nothing and says nothing. (The shipped
     * config has one - it passes `mouse = true`, which is not an option; the real names for a
     * mouse bind are click and drag.)
     */
    readonly property var options: [
        { "key": "repeating", "icon": "repeat", "label": Translation.tr("Repeat while held"),
          "hint": Translation.tr("For volume and brightness, where holding the key should keep going.") },
        { "key": "locked", "icon": "lock", "label": Translation.tr("Works on the lock screen"),
          "hint": Translation.tr("Media and brightness keys usually want this; anything that opens a window does not.") },
        { "key": "release", "icon": "arrow_upward", "label": Translation.tr("Fire when the key is let go") },
        { "key": "long_press", "icon": "timer", "label": Translation.tr("Fire on a long press") },
        { "key": "non_consuming", "icon": "double_arrow",
          "label": Translation.tr("Let the app see the key too"),
          "hint": Translation.tr("The shortcut runs and the key still reaches whatever is focused.") },
        { "key": "transparent", "icon": "layers_clear",
          "label": Translation.tr("Do not block other shortcuts on this key") },
        { "key": "ignore_mods", "icon": "keyboard_alt",
          "label": Translation.tr("Ignore extra modifiers"),
          "hint": Translation.tr("The shortcut still fires when other modifiers happen to be held.") },
        { "key": "dont_inhibit", "icon": "block",
          "label": Translation.tr("Works even while an app is grabbing shortcuts"),
          "hint": Translation.tr("Remote desktop and virtual machine windows ask to take every key; this one gets through anyway.") },
        { "key": "submap_universal", "icon": "public",
          "label": Translation.tr("Works inside every key mode") },
        { "key": "click", "icon": "mouse", "label": Translation.tr("Mouse: fire on the click") },
        { "key": "drag", "icon": "drag_pan", "label": Translation.tr("Mouse: fire while dragging") }
    ]

    function save() {
        if (!HyprlandBinds.commitDraft()) return;
        subPageRoot.goBack();
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        RowLayout {
            visible: subPageRoot.showBackButton
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: HyprlandBinds.editIsNew ? Translation.tr("New shortcut")
                        : Translation.tr("Shortcut")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: subPageRoot.draft.wasManaged === true
                        ? Translation.tr("Written by this page")
                        : (String(subPageRoot.draft.fromFile ?? "") === "" ? ""
                            : Translation.tr("Comes from %1 line %2")
                                .arg(subPageRoot.draft.fromFile).arg(subPageRoot.draft.fromLine))
                    visible: text !== ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                implicitHeight: 40
                implicitWidth: saveLabel.implicitWidth + 32
                enabled: subPageRoot.problems.length === 0
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: subPageRoot.save()

                StyledText {
                    id: saveLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Save")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimary
                    opacity: parent.enabled ? 1 : 0.4
                }
            }
        }

        // ── The key ───────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("The key")
            icon: "keyboard"

            HyprKeyCapture {
                Layout.fillWidth: true
                mods: subPageRoot.draft.mods ?? []
                key: subPageRoot.draft.key ?? ""
                onChosen: (newMods, newKey) => {
                    HyprlandBinds.putDraft("mods", newMods);
                    HyprlandBinds.putDraft("key", newKey);
                }
            }

            HyprOptionNote {
                notes: {
                    const out = [];
                    // Why the Save button is off, said where the person is looking. It used to be
                    // disabled with no word about it.
                    for (const problem of subPageRoot.problems)
                        out.push({ "icon": "error", "always": true, "text": problem });
                    for (const other of subPageRoot.occupants)
                        out.push({
                            "icon": "warning",
                            "always": true,
                            "text": Translation.tr("%1 is already \"%2\" (%3). Saving replaces it.")
                                .arg(HyprlandBinds.comboLabel(other.mods, other.key))
                                .arg(HyprlandBinds.titleOf(other))
                                .arg(other.managed ? Translation.tr("set here") : other.file)
                        });
                    if (String(subPageRoot.draft.key ?? "").startsWith("code:"))
                        out.push({ "icon": "info", "text": Translation.tr("A physical key is written as its keycode, so it does not move when the keyboard layout changes.") });
                    return out;
                }
            }
        }

        // ── What it does ──────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("What it does")
            icon: "bolt"

            HyprNavRow {
                buttonIcon: subPageRoot.actionEntry ? subPageRoot.actionEntry.icon : "code"
                text: subPageRoot.actionEntry ? subPageRoot.actionEntry.label
                    : Translation.tr("Something written in Lua")
                value: subPageRoot.actionEntry ? "" : Translation.tr("Not editable here")
                onOpenSubPage: subPageOverlay.activeSubPage = Qt.resolvedUrl("HyprActionPickerPage.qml")
            }

            Loader {
                Layout.fillWidth: true
                active: subPageRoot.actionEntry !== null
                    && subPageRoot.actionEntry.param === "direction"
                visible: active

                sourceComponent: ConfigSelectionArray {
                    currentValue: subPageRoot.draft.actionValue ?? ""
                    options: HyprlandBinds.directions.map(direction =>
                        ({ "value": direction.value, "displayName": direction.label }))
                    onSelected: newValue => HyprlandBinds.putDraft("actionValue", newValue)
                }
            }

            Loader {
                Layout.fillWidth: true
                active: subPageRoot.actionEntry !== null
                    && subPageRoot.actionEntry.param !== undefined
                    && subPageRoot.actionEntry.param !== "direction"
                    && subPageRoot.actionEntry.param !== "global"
                visible: active

                sourceComponent: ConfigTextField {
                    id: valueField

                    readonly property string currentValue: String(subPageRoot.draft.actionValue ?? "")

                    icon: subPageRoot.actionEntry.icon
                    text: subPageRoot.actionEntry.param === "command"
                        ? Translation.tr("Command") : Translation.tr("Value")
                    placeholderText: subPageRoot.actionEntry.param === "command"
                        ? Translation.tr("kitty -1") : ""
                    textField.wrapMode: TextInput.NoWrap

                    onCurrentValueChanged: {
                        if (valueField.textField.activeFocus) return;
                        valueField.inputText = valueField.currentValue;
                    }
                    Component.onCompleted: valueField.inputText = valueField.currentValue

                    Connections {
                        target: valueField.textField

                        function onEditingFinished() {
                            if (valueField.inputText === valueField.currentValue) return;
                            HyprlandBinds.putDraft("actionValue", valueField.inputText);
                        }
                    }
                }
            }

            HyprOptionNote {
                notes: {
                    const out = [];
                    if (subPageRoot.actionEntry === null && String(subPageRoot.draft.actionRaw ?? "") !== "")
                        out.push({ "icon": "code", "text": Translation.tr("This shortcut runs Lua written in the config file. Choosing something above replaces it; leaving it alone keeps it exactly as it is.") });
                    else if (subPageRoot.actionEntry && subPageRoot.actionEntry.hint !== undefined)
                        out.push({ "icon": "info", "text": subPageRoot.actionEntry.hint });
                    if (subPageRoot.actionEntry && subPageRoot.actionEntry.param === "global")
                        out.push({ "icon": "widgets", "text": String(subPageRoot.draft.actionValue ?? "") === ""
                            ? Translation.tr("Nothing chosen yet.")
                            : Translation.tr("Currently %1").arg(subPageRoot.draft.actionValue) });
                    return out;
                }
            }
        }

        // ── Name ──────────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Name")
            icon: "label"

            ConfigTextField {
                id: descriptionField
                Layout.fillWidth: true

                readonly property string currentValue: String(subPageRoot.draft.description ?? "")

                icon: "edit_note"
                text: Translation.tr("What to call it")
                placeholderText: Translation.tr("Shell: Toggle the bar")

                onCurrentValueChanged: {
                    if (descriptionField.textField.activeFocus) return;
                    descriptionField.inputText = descriptionField.currentValue;
                }
                Component.onCompleted: descriptionField.inputText = descriptionField.currentValue

                Connections {
                    target: descriptionField.textField

                    function onEditingFinished() {
                        if (descriptionField.inputText === descriptionField.currentValue) return;
                        HyprlandBinds.putDraft("description", descriptionField.inputText);
                    }
                }
            }

            HyprOptionNote {
                notes: [{ "icon": "help", "text": Translation.tr("The name is what the cheatsheet shows. A word and a colon in front of it, like \"Window:\", puts it in that group. A shortcut with no name still works, it just stays out of the list.") }]
            }
        }

        // ── Fine print ────────────────────────────────────────────────────────
        ContentSection {
            visible: subPageRoot.advanced
            title: Translation.tr("Fine print")
            icon: "tune"

            Repeater {
                model: subPageRoot.advanced ? subPageRoot.options : []

                delegate: HyprToggle {
                    required property var modelData

                    buttonIcon: modelData.icon
                    text: modelData.label
                    switchOn: (subPageRoot.draft.opts ?? {})[modelData.key] === true
                    onRequested: wanted => HyprlandBinds.putDraftOption(modelData.key, wanted)
                }
            }

            HyprOptionNote {
                notes: {
                    const hints = subPageRoot.options
                        .filter(option => option.hint !== undefined
                            && (subPageRoot.draft.opts ?? {})[option.key] === true)
                        .map(option => ({ "icon": option.icon, "text": option.hint }));
                    return hints;
                }
            }
        }

        // ── This shortcut ─────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("This shortcut")
            icon: "delete"
            visible: !HyprlandBinds.editIsNew && subPageRoot.current !== null

            HyprNavRow {
                enabled: !subPageRoot.lastEssential
                buttonIcon: subPageRoot.isManaged ? "undo" : "block"
                text: subPageRoot.isManaged ? Translation.tr("Undo what this page set")
                    : Translation.tr("Turn this shortcut off")
                value: subPageRoot.isManaged ? Translation.tr("Back to the config file")
                    : Translation.tr("Releases the key")
                onOpenSubPage: {
                    if (subPageRoot.lastEssential) return;
                    if (subPageRoot.isManaged) HyprlandBinds.removeBind(HyprlandBinds.editId);
                    else HyprlandBinds.releaseOnly(HyprlandBinds.editId, subPageRoot.combo);
                    subPageRoot.goBack();
                }
            }

            HyprOptionNote {
                notes: {
                    if (subPageRoot.lastEssential)
                        return [{ "icon": "shield", "always": true, "text": Translation.tr("This is the only shortcut left that opens a terminal or reaches the session menu. Bind another one first — without either, a keyboard-only mistake can only be undone from a text console.") }];
                    if (subPageRoot.isManaged)
                        return [{ "icon": "info", "text": Translation.tr("Removing it puts back whatever the config files had on this key, if anything.") }];
                    return [{ "icon": "info", "text": Translation.tr("The config file is not touched. A release is written into this page's own block instead, which runs afterwards and takes the key back.") }];
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
