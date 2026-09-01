pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One rule, in full: what it selects, and every setting Hyprland will accept on it.
 *
 * Which rule is being edited comes from HyprlandRules rather than from a property, because a
 * sub-page is loaded by URL and there is nowhere to put an argument. The page is deliberately
 * one screen for all three kinds - a window rule, a layer rule and a workspace rule differ in
 * what they select and in their vocabulary, not in how you work on them.
 *
 * Every setting except a switch is a text box. Hyprland's own rule values are text - "0.9
 * override 0.8", "(monitor_w*0.5) (monitor_h*0.5)", "3 silent" - and a spin box cannot express
 * any of them. Numbers are converted on the way out so the Lua stays typed, and an empty box
 * means the setting is not in the rule at all.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    readonly property string kind: HyprlandRules.editKind
    readonly property string ruleId: HyprlandRules.editId
    readonly property var spec: HyprlandRules.find(subPageRoot.kind, subPageRoot.ruleId) ?? ({})
    readonly property var match: subPageRoot.spec.match ?? ({})
    readonly property var effects: HyprlandRules.effectsOf(subPageRoot.kind, subPageRoot.spec)
    readonly property var catalogue: HyprlandRules.effectsFor(subPageRoot.kind)
    property string addQuery: ""

    /// Settings added on this visit but still empty. Without this an added text setting would
    /// vanish the moment it appeared, because nothing is written until you type into it.
    property var revealed: []

    readonly property var shownKeys: {
        const out = Object.keys(subPageRoot.effects);
        for (const key of Array.from(subPageRoot.revealed))
            if (!out.includes(key)) out.push(key);
        return out;
    }

    function entryFor(key: string): var {
        return subPageRoot.catalogue.find(effect => effect.key === key)
            ?? ({ "key": key, "type": "string", "icon": "code", "label": key });
    }

    property var _memo: ({})

    /// Kept by identity: these feed the Repeaters below, and typing a value into one field
    /// must not rebuild every other row on the page.
    readonly property var shownSwitches: ObjectUtils.keep(subPageRoot._memo, "shownSwitches",
        subPageRoot.shownKeys
            .filter(key => subPageRoot.entryFor(key).type === "bool")
            .map(key => subPageRoot.entryFor(key)))
    readonly property var shownFields: ObjectUtils.keep(subPageRoot._memo, "shownFields",
        subPageRoot.shownKeys
            .filter(key => subPageRoot.entryFor(key).type !== "bool")
            .map(key => subPageRoot.entryFor(key)))

    /// Whether one catalogue chip is offered right now. The chips are built once from the
    /// whole catalogue and hide themselves instead of being rebuilt: fifty buttons torn down
    /// per keystroke was what made typing in the add box stutter.
    function offerable(effect: var): bool {
        if (subPageRoot.shownKeys.includes(effect.key)) return false;
        const query = subPageRoot.addQuery.trim().toLowerCase();
        if (query === "") return true;
        return effect.key.indexOf(query) >= 0 || effect.label.toLowerCase().indexOf(query) >= 0;
    }

    readonly property string title: {
        if (subPageRoot.kind === "layerrule")
            return Translation.tr("Layer rule");
        if (subPageRoot.kind === "workspacerule")
            return Translation.tr("Workspace rule");
        const cls = HyprlandRules.patternLabel(String(subPageRoot.match.class ?? ""));
        return cls === "" ? Translation.tr("Window rule") : HyprlandRules.appLabel(cls);
    }

    // --------------------------------------------------------------------- writing

    function put(key: string, raw: var) {
        const effect = subPageRoot.entryFor(key);
        if (raw === undefined) {
            HyprlandRules.putEffect(subPageRoot.kind, subPageRoot.ruleId, key, undefined);
            return;
        }
        if (effect.type === "int") {
            const number = parseInt(raw, 10);
            HyprlandRules.putEffect(subPageRoot.kind, subPageRoot.ruleId, key,
                isNaN(number) ? undefined : number);
            return;
        }
        if (effect.type === "float") {
            const number = parseFloat(raw);
            HyprlandRules.putEffect(subPageRoot.kind, subPageRoot.ruleId, key,
                isNaN(number) ? undefined : number);
            return;
        }
        HyprlandRules.putEffect(subPageRoot.kind, subPageRoot.ruleId, key, raw);
    }

    function reveal(key: string) {
        const effect = subPageRoot.entryFor(key);
        if (effect.type === "bool") {
            HyprlandRules.putEffect(subPageRoot.kind, subPageRoot.ruleId, key, true);
            return;
        }
        subPageRoot.revealed = Array.from(subPageRoot.revealed).concat([key]);
    }

    function drop(key: string) {
        subPageRoot.revealed = Array.from(subPageRoot.revealed).filter(other => other !== key);
        HyprlandRules.putEffect(subPageRoot.kind, subPageRoot.ruleId, key, undefined);
    }

    function putMatch(key: string, newValue: var) {
        const next = Object.assign({}, subPageRoot.spec);
        const match = Object.assign({}, subPageRoot.match);
        if (newValue === undefined || newValue === "") delete match[key];
        else match[key] = newValue;
        next.match = match;
        HyprlandRules.save(subPageRoot.kind, subPageRoot.ruleId, next);
    }

    function putSelector(newValue: string) {
        const next = Object.assign({}, subPageRoot.spec);
        next.workspace = newValue;
        HyprlandRules.save(subPageRoot.kind, subPageRoot.ruleId, next);
    }

    /// The hint under a text setting: what it wants, and what it will accept.
    function hintFor(effect: var): string {
        if (effect.hint !== undefined) return effect.hint;
        if (effect.type === "enum") return Translation.tr("One of: %1").arg(effect.values.join(", "));
        if (effect.type === "int") return Translation.tr("A whole number.");
        if (effect.type === "float") return Translation.tr("A number, decimals allowed.");
        if (effect.type === "vec2") return Translation.tr("Two values separated by a space.");
        if (effect.type === "gradient") return Translation.tr("A colour like rgba(ff0000ff).");
        return "";
    }

    // ------------------------------------------------------------------ shared rows

    /// A rule setting as a text box. Empty takes the setting out of the rule entirely.
    component EffectField: ConfigTextField {
        id: effectField

        required property var effect
        readonly property string currentValue: {
            const held = subPageRoot.effects[effectField.effect.key];
            return held === undefined ? "" : String(held);
        }

        icon: effectField.effect.icon
        text: effectField.effect.label
        placeholderText: effectField.effect.placeholder ?? Translation.tr("Not set")
        tooltip: subPageRoot.hintFor(effectField.effect)

        onCurrentValueChanged: {
            if (effectField.textField.activeFocus) return;
            effectField.inputText = effectField.currentValue;
        }
        Component.onCompleted: effectField.inputText = effectField.currentValue

        rightAction: RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: subPageRoot.drop(effectField.effect.key)

            MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: 16
                color: Appearance.colors.colSubtext
            }
        }

        Connections {
            target: effectField.textField

            function onEditingFinished() {
                if (effectField.inputText === effectField.currentValue) return;
                subPageRoot.put(effectField.effect.key,
                    effectField.inputText === "" ? undefined : effectField.inputText);
            }
        }
    }

    component MatchField: ConfigTextField {
        id: matchField

        required property var field
        readonly property string currentValue: String(subPageRoot.match[matchField.field.key] ?? "")

        icon: matchField.field.icon
        text: matchField.field.label
        placeholderText: matchField.field.placeholder ?? Translation.tr("Any")

        onCurrentValueChanged: {
            if (matchField.textField.activeFocus) return;
            matchField.inputText = matchField.currentValue;
        }
        Component.onCompleted: matchField.inputText = matchField.currentValue

        Connections {
            target: matchField.textField

            function onEditingFinished() {
                if (matchField.inputText === matchField.currentValue) return;
                subPageRoot.putMatch(matchField.field.key, matchField.inputText);
            }
        }
    }

    ContentPage {
        id: page
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
                    text: subPageRoot.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 of %2 settings in use")
                        .arg(Object.keys(subPageRoot.effects).length).arg(subPageRoot.catalogue.length)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // ── What it selects ───────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("What it matches")
            icon: "filter_alt"
            visible: subPageRoot.kind === "windowrule"

            Repeater {
                model: HyprlandRules.windowMatchFields.filter(field => field.type === "regex")

                delegate: MatchField {
                    required property var modelData

                    field: modelData
                }
            }

            HyprMatchPreview {
                match: subPageRoot.match
            }
        }

        Repeater {
            model: subPageRoot.kind === "windowrule"
                ? HyprlandRules.windowMatchFields.filter(field => field.type === "tri") : []

            delegate: HyprSelect {
                required property var modelData

                title: modelData.label
                icon: modelData.icon
                currentOverride: subPageRoot.match[modelData.key] === undefined
                    ? "" : String(subPageRoot.match[modelData.key])
                options: [
                    { "displayName": Translation.tr("Either"), "value": "" },
                    { "displayName": Translation.tr("Yes"), "value": "1" },
                    { "displayName": Translation.tr("No"), "value": "0" }
                ]
                onSelected: newValue => subPageRoot.putMatch(modelData.key,
                    newValue === "" ? undefined : Number(newValue))
            }
        }

        ContentSection {
            title: Translation.tr("Which layer")
            icon: "layers"
            visible: subPageRoot.kind === "layerrule"

            ConfigTextField {
                id: namespaceField

                readonly property string currentValue: String(subPageRoot.match.namespace ?? "")

                icon: "label"
                text: Translation.tr("Namespace")
                placeholderText: "^(waybar)$"
                tooltip: Translation.tr("A regular expression over the layer surface's namespace.")

                onCurrentValueChanged: {
                    if (namespaceField.textField.activeFocus) return;
                    namespaceField.inputText = namespaceField.currentValue;
                }
                Component.onCompleted: namespaceField.inputText = namespaceField.currentValue

                Connections {
                    target: namespaceField.textField

                    function onEditingFinished() {
                        if (namespaceField.inputText === namespaceField.currentValue) return;
                        subPageRoot.putMatch("namespace", namespaceField.inputText);
                    }
                }
            }

            HyprOptionNote {
                notes: {
                    const pattern = String(subPageRoot.match.namespace ?? "");
                    if (pattern === "") return [];
                    const out = [];
                    if (HyprlandGui.shellOwnedNamespace(pattern))
                        out.push({ "icon": "lock", "text": Translation.tr("This shell re-applies its own rules for quickshell: namespaces after every reload, so anything set here is overwritten within the second. Change these on the shell's own pages instead.") });
                    const regex = HyprlandRules.compile(pattern);
                    if (regex === null) {
                        out.push({ "icon": "error", "text": Translation.tr("That is not a valid pattern.") });
                        return out;
                    }
                    const hits = HyprlandRules.liveNamespaces.filter(name => regex.test(name));
                    out.push(hits.length === 0
                        ? { "icon": "search",
                            "text": Translation.tr("No layer on screen right now has a matching namespace.") }
                        : { "icon": "check",
                            "text": Translation.tr("Matches on screen now: %1").arg(hits.join(", ")) });
                    return out;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Which workspace")
            icon: "space_dashboard"
            visible: subPageRoot.kind === "workspacerule"

            ConfigTextField {
                id: workspaceField

                readonly property string currentValue: String(subPageRoot.spec.workspace ?? "")

                icon: "tag"
                text: Translation.tr("Workspace")
                placeholderText: "3"
                tooltip: Translation.tr("A number, a name, or special:magic.")

                onCurrentValueChanged: {
                    if (workspaceField.textField.activeFocus) return;
                    workspaceField.inputText = workspaceField.currentValue;
                }
                Component.onCompleted: workspaceField.inputText = workspaceField.currentValue

                Connections {
                    target: workspaceField.textField

                    function onEditingFinished() {
                        if (workspaceField.inputText === workspaceField.currentValue) return;
                        subPageRoot.putSelector(workspaceField.inputText);
                    }
                }
            }

            HyprOptionNote {
                notes: HyprlandRules.workspaceIsMapped(String(subPageRoot.spec.workspace ?? ""))
                    && subPageRoot.effects.monitor !== undefined
                    ? [{ "icon": "info", "text": Translation.tr("hyprland/lib/init.lua already writes a screen for workspaces 1 to 100 on every start. This rule loads afterwards, so the screen chosen here wins - but both are setting it.") }]
                    : []
            }
        }

        // ── Settings ──────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Settings in use")
            icon: "tune"

            StyledText {
                Layout.fillWidth: true
                visible: subPageRoot.shownKeys.length === 0
                text: Translation.tr("This rule does nothing yet. Add a setting below.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: subPageRoot.shownSwitches

                delegate: HyprToggle {
                    required property var modelData

                    buttonIcon: modelData.icon
                    text: modelData.label
                    switchOn: subPageRoot.effects[modelData.key] === true
                    onRequested: wanted => {
                        if (wanted) subPageRoot.put(modelData.key, true);
                        else subPageRoot.drop(modelData.key);
                    }
                }
            }

            Repeater {
                model: subPageRoot.shownFields

                delegate: EffectField {
                    required property var modelData

                    effect: modelData
                }
            }
        }

        ContentSection {
            title: Translation.tr("Add a setting")
            icon: "add"

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search %1 settings").arg(subPageRoot.catalogue.length)
                onTextChanged: subPageRoot.addQuery = text
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: subPageRoot.catalogue

                    delegate: RippleButton {
                        required property var modelData

                        visible: subPageRoot.offerable(modelData)
                        implicitHeight: 32
                        implicitWidth: addRow.implicitWidth + 22
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: subPageRoot.reveal(modelData.key)

                        contentItem: RowLayout {
                            id: addRow
                            spacing: 5

                            MaterialSymbol {
                                Layout.leftMargin: 11
                                text: modelData.icon
                                iconSize: 15
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.rightMargin: 11
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }
            }
        }

        // ── The rule itself ───────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("This rule")
            icon: "code"

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Written to the block at the end of ~/.config/hypr/custom/rules.lua, which loads after the shell's own rules and after anything you wrote above it.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 40
                useDynamicRadius: true
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colErrorContainer
                colRipple: Appearance.colors.colErrorContainerActive
                onClicked: {
                    HyprlandRules.remove(subPageRoot.kind, subPageRoot.ruleId);
                    subPageRoot.goBack();
                }

                contentItem: RowLayout {
                    spacing: 8

                    MaterialSymbol {
                        Layout.leftMargin: 16
                        text: "delete"
                        iconSize: 18
                        color: Appearance.colors.colError
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.rightMargin: 16
                        text: Translation.tr("Delete this rule")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colError
                    }
                }
            }
        }
    }
}
