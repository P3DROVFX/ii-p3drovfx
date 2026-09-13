pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Rules.
 *
 * Four lists over one file. Apps come first because that is what a rule is nearly always for -
 * this window should float, that one should never be blurred - and the raw window, layer and
 * workspace lists underneath are the same machinery without the friendly names.
 *
 * Everything here is written into the block at the end of ~/.config/hypr/custom/rules.lua, which
 * loads after the shell's own rules and after anything hand-written above it, so a rule made here
 * wins. The two exceptions are stated where they apply: layer rules on quickshell's own surfaces,
 * which Appearance.qml re-pushes after every reload, and the screen assigned to workspaces 1 to
 * 100, which hyprland/lib/init.lua also writes.
 */
ContentPage {
    id: tab

    forceWidth: false

    /// A window rule that is not "this app should behave differently" is something a person
    /// goes looking for, not something they should have to scroll past. Apps is the tab in
    /// basic mode; the raw window, layer and workspace lists are behind advanced.
    readonly property bool advanced: Config.options.hyprland.advancedSettings

    readonly property url editorPage: Qt.resolvedUrl("HyprRuleEditorPage.qml")
    readonly property url pickerPage: Qt.resolvedUrl("HyprAppPickerPage.qml")

    /// The host that owns the slide-in overlay is the hub, several files up; this page cannot
    /// see it by name.
    function openSubPage(page: url) {
        let node = tab.parent;
        while (node) {
            if (typeof node.activeSubPage !== "undefined") {
                node.activeSubPage = page;
                return;
            }
            node = node.parent;
        }
    }

    function edit(kind: string, id: string) {
        HyprlandRules.beginEdit(kind, id);
        tab.openSubPage(tab.editorPage);
    }

    /// The app's own page, which holds the card the list used to inline.
    function editApp(id: string) {
        HyprlandRules.beginEdit("windowrule", id);
        tab.openSubPage(Qt.resolvedUrl("HyprAppRulePage.qml"));
    }

    function addRule(kind: string, prefix: string, spec: var) {
        const id = HyprlandRules.freeId(kind, prefix);
        HyprlandRules.save(kind, id, spec);
        tab.edit(kind, id);
    }

    /// One row per rule: what it selects, what it does, and a way in. Looked up by id so a
    /// change to one rule leaves every other row alone.
    component RuleRow: HyprNavRow {
        id: ruleRow

        required property string ruleKind
        required property string ruleId

        readonly property var spec: HyprlandRules.find(ruleRow.ruleKind, ruleRow.ruleId) ?? ({})

        buttonIcon: ruleRow.ruleKind === "layerrule" ? "layers"
            : (ruleRow.ruleKind === "workspacerule" ? "space_dashboard" : "filter_alt")
        text: HyprlandRules.matchSummary(ruleRow.ruleKind, ruleRow.spec)
        value: HyprlandRules.effectSummary(ruleRow.ruleKind, ruleRow.spec)
        onOpenSubPage: tab.edit(ruleRow.ruleKind, ruleRow.ruleId)
    }

    // ── Apps ──────────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Apps")
        icon: "apps"

        StyledText {
            Layout.fillWidth: true
            visible: tab.advanced
            text: Translation.tr("Rules for one application's windows. Each card is a single line in your config, and the list under it shows which of your open windows it currently catches.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        /**
         * One row per app, not one card per app.
         *
         * Every rule used to be its whole editor, inline: sixteen controls each, stacked, so
         * three apps filled the tab and the list of which apps have rules at all - the reason
         * anybody opens this tab - was not visible anywhere. Each row now says what it catches
         * and what it does, and opens the controls on its own page.
         */
        Repeater {
            model: HyprlandRules.appIds

            delegate: HyprNavRow {
                id: appRow

                required property var modelData

                readonly property var spec: HyprlandRules.find("windowrule", appRow.modelData) ?? ({})
                readonly property string windowClass:
                    HyprlandRules.patternLabel(String((appRow.spec.match ?? {}).class ?? ""))

                buttonIcon: "widgets"
                text: HyprlandRules.appEntry(appRow.windowClass)?.name
                    ?? (appRow.windowClass === "" ? Translation.tr("New rule") : appRow.windowClass)
                description: HyprlandRules.effectSummary("windowrule", appRow.spec)
                onOpenSubPage: tab.editApp(appRow.modelData)
            }
        }

        HyprNavRow {
            buttonIcon: "add"
            text: Translation.tr("Add an app")
            value: HyprlandRules.apps.length === 0 ? Translation.tr("None yet") : ""
            onOpenSubPage: tab.openSubPage(tab.pickerPage)
        }
    }

    // ── Raw window rules ──────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Window rules")
        icon: "filter_alt"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("For everything the app cards do not cover: matching on a title, a tag or a state instead of a class, and the settings that are too rare to put on a card.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: HyprlandRules.rawWindowRuleIds

            delegate: RuleRow {
                required property var modelData

                ruleKind: "windowrule"
                ruleId: modelData
            }
        }

        HyprNavRow {
            buttonIcon: "add"
            text: Translation.tr("Add a window rule")
            value: HyprlandRules.rawWindowRules.length === 0 ? Translation.tr("None yet") : ""
            onOpenSubPage: tab.addRule("windowrule", "win:", { "match": {} })
        }

        HyprOptionNote {
            notes: {
                const hand = HyprlandRules.inheritedRules.filter(rule => rule.kind === "windowrule");
                if (hand.length === 0) return [];
                return [{ "icon": "edit_note", "text": Translation.tr("%1 window rules are written by hand higher up in custom/rules.lua. They are left exactly as they are; anything set here loads afterwards and wins.").arg(hand.length) }];
            }
        }
    }

    // ── Layer rules ───────────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Layer rules")
        icon: "layers"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Layers are the surfaces that are not windows: this shell's own panels, a launcher, a notification. A layer rule decides how one of them is blurred, ordered or animated.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: HyprlandRules.layerRuleIds

            delegate: RuleRow {
                required property var modelData

                ruleKind: "layerrule"
                ruleId: modelData
            }
        }

        HyprNavRow {
            buttonIcon: "add"
            text: Translation.tr("Add a layer rule")
            value: HyprlandRules.layerRules.length === 0 ? Translation.tr("None yet") : ""
            onOpenSubPage: tab.addRule("layerrule", "layer:", { "match": {} })
        }

        HyprOptionNote {
            notes: {
                const out = [{ "icon": "lock", "text": Translation.tr("Namespaces starting with quickshell: belong to this shell. It re-applies its own blur, order and animation for them after every reload, so a rule written here for one of them is overwritten within the second.") }];
                const hand = HyprlandRules.inheritedRules.filter(rule => rule.kind === "layerrule");
                if (hand.length > 0)
                    out.push({ "icon": "edit_note", "text": Translation.tr("%1 layer rules are written by hand higher up in custom/rules.lua, and are left alone.").arg(hand.length) });
                if (HyprlandRules.liveNamespaces.length > 0)
                    out.push({ "icon": "search", "text": Translation.tr("On screen right now: %1")
                        .arg(HyprlandRules.liveNamespaces.join(", ")) });
                return out;
            }
        }
    }

    // ── Workspace rules ───────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Workspace rules")
        icon: "space_dashboard"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Settings that belong to one workspace rather than to one window: which screen it lives on, whether it stays when empty, its own gaps or its own tiling engine.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: HyprlandRules.workspaceRuleIds

            delegate: RuleRow {
                required property var modelData

                ruleKind: "workspacerule"
                ruleId: modelData
            }
        }

        HyprNavRow {
            buttonIcon: "add"
            text: Translation.tr("Add a workspace rule")
            value: HyprlandRules.workspaceRules.length === 0 ? Translation.tr("None yet") : ""
            onOpenSubPage: tab.addRule("workspacerule", "ws:", {})
        }

        HyprOptionNote {
            notes: [{ "icon": "info", "text": Translation.tr("Workspaces 1 to 100 are already given a screen on every start by hyprland/lib/init.lua, from the workspace map. Rules written here load afterwards and win, but both are setting it.") }]
        }
    }

    // ── Related ───────────────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Related settings")
        icon: "link"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Opacity, blur, gaps and borders for every window at once live on the shell's own pages, not here. This page is for the exceptions.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            RelatedChip {
                pageId: "windows"
                label: Translation.tr("Windows")
            }

            RelatedChip {
                pageId: "tiling"
                label: Translation.tr("Window tiling")
            }

            RelatedChip {
                pageId: "workspaces"
                label: Translation.tr("Workspaces")
            }

            RelatedChip {
                pageId: "overlays"
                label: Translation.tr("Overlays")
            }
        }
    }
}
