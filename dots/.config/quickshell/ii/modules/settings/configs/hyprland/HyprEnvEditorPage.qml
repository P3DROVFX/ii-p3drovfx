pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One environment variable.
 *
 * A variable already written by hand is edited here too, and the edit does not touch that line:
 * it writes one into the block at the end of the same file, which runs afterwards and wins. That
 * keeps the promise the rest of this hub makes - nothing outside the block is ever rewritten -
 * and it is why a hand-written line stays visible underneath after a change.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    readonly property string original: HyprlandEnv.editName
    readonly property string name: String(HyprlandEnv.draft.name ?? "")
    readonly property bool isNew: subPageRoot.original === ""
    readonly property string source: subPageRoot.name === "" ? ""
        : HyprlandEnv.envSource(subPageRoot.name)
    readonly property var below: HyprlandGui.inheritedEnv[subPageRoot.name]
        ?? HyprlandEnv.upstreamMap[subPageRoot.name] ?? null
    readonly property int generation: HyprlandEnv.editGeneration

    /// Fill the fields from the draft. Called when the editor is pointed at something, never in
    /// response to the draft changing - the fields are what changes it.
    function seed() {
        nameField.inputText = String(HyprlandEnv.draft.name ?? "");
        valueField.inputText = String(HyprlandEnv.draft.value ?? "");
    }

    onGenerationChanged: subPageRoot.seed()
    Component.onCompleted: subPageRoot.seed()

    function save() {
        if (!HyprlandEnv.commitDraft()) return;
        subPageRoot.goBack();
    }

    function remove() {
        if (subPageRoot.original !== "") HyprlandEnv.clearVariable(subPageRoot.original);
        subPageRoot.goBack();
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false

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
                    text: subPageRoot.isNew ? Translation.tr("New variable")
                        : subPageRoot.original
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Written into custom/env.lua")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // ── The variable ──────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Variable")
            icon: "code"

            ConfigTextField {
                id: nameField
                Layout.fillWidth: true

                icon: "label"
                text: Translation.tr("Name")
                placeholderText: "EDITOR"
                // Written on every keystroke rather than when the field is left, so that what is
                // wrong with a name is said while it is being typed and the save button below
                // means what it says by the time it is reached.
                textField.wrapMode: TextInput.NoWrap
                textField.onTextChanged: HyprlandEnv.putDraft("name", nameField.textField.text)
            }

            ConfigTextField {
                id: valueField
                Layout.fillWidth: true

                icon: "edit"
                text: Translation.tr("Value")
                placeholderText: "nvim"
                textField.wrapMode: TextInput.NoWrap
                textField.onTextChanged: HyprlandEnv.putDraft("value", valueField.textField.text)
            }

            HyprOptionNote {
                notes: {
                    const out = [];
                    for (const problem of HyprlandEnv.draftProblems)
                        out.push({ "icon": "error", "text": problem });
                    if (subPageRoot.below !== null)
                        out.push({ "icon": "edit_note", "text": Translation.tr("%1 is already set to %2 at line %3 of a file that loads first. What you write here runs after it and replaces it.")
                            .arg(subPageRoot.name)
                            .arg(HyprlandEnv.plainValue(subPageRoot.below.value) || Translation.tr("nothing"))
                            .arg(subPageRoot.below.line ?? 0) });
                    if (HyprlandEnv.claimedNames[subPageRoot.name] === true)
                        out.push({ "icon": "widgets", "text": Translation.tr("A control on the page behind this one also sets %1. Both write the same line, and whichever you touch last is what is there.")
                            .arg(subPageRoot.name) });
                    out.push({ "icon": "schedule", "text": Translation.tr("Programs already running keep the value they were started with. This reaches whatever you open next, and the whole session after a re-login.") });
                    return out;
                }
            }
        }

        // ── Doing it ──────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("This variable")
            icon: "check"

            HyprNavRow {
                buttonIcon: "save"
                enabled: HyprlandEnv.draftProblems.length === 0
                text: subPageRoot.isNew ? Translation.tr("Add it") : Translation.tr("Save it")
                value: subPageRoot.name === "" ? "" : subPageRoot.name
                onOpenSubPage: subPageRoot.save()
            }

            HyprNavRow {
                visible: subPageRoot.source === "managed"
                buttonIcon: "delete"
                text: Translation.tr("Remove it")
                value: subPageRoot.below !== null
                    ? Translation.tr("The older line takes over again")
                    : Translation.tr("Nothing sets it afterwards")
                onOpenSubPage: subPageRoot.remove()
            }

            HyprOptionNote {
                notes: {
                    if (subPageRoot.source === "hand")
                        return [{ "icon": "shield", "text": Translation.tr("This one was written by hand. Saving leaves that line exactly where it is and adds one below it — this page never edits anything outside its own block.") }];
                    if (subPageRoot.source === "upstream")
                        return [{ "icon": "inventory", "text": Translation.tr("This one comes from hyprland/env.lua, which every update replaces. That is why the new value goes into custom/env.lua instead.") }];
                    return [];
                }
            }
        }
    }
}
