pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything this page can do to one application's windows.
 *
 * A card is one `hl.window_rule` call: one match, and every setting turned on for it. Hyprland
 * takes several settings in a single call, so the file gets one readable line per app rather than
 * one per switch, and the whole card is undone by deleting that line.
 *
 * Turning a switch off removes its setting instead of writing `false`. The two are not the same
 * thing in Hyprland - `float = false` forces a window to tile, which is a different intention
 * from not having an opinion - and a card whose switches are all off should leave nothing behind.
 * The full vocabulary, including the explicit `false`, is a tap away in the rule editor.
 */
ColumnLayout {
    id: card

    /// Looked up by id rather than passed as a row object, so the card only hears about its
    /// own rule and the list of cards keeps its identity while the set of ids is unchanged.
    required property string ruleId

    readonly property var spec: HyprlandRules.find("windowrule", card.ruleId) ?? ({})
    readonly property var match: card.spec.match ?? ({})
    readonly property string windowClass: HyprlandRules.patternLabel(String(card.match.class ?? ""))
    readonly property var entry: HyprlandRules.appEntry(card.windowClass)

    signal removeRequested
    signal editRequested

    readonly property string cardTitle: card.entry?.name
        ?? (card.windowClass === "" ? Translation.tr("New rule") : card.windowClass)
    /// Off on the app's own page, where the name is already the page title.
    property bool showHeader: true
    Layout.fillWidth: true

    // Rule controls own their surfaces. The rule identity stays a lightweight heading rather
    // than placing several full-width toggles inside another subsection card.
    RowLayout {
        visible: card.showHeader
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        spacing: 10

        MaterialSymbol {
            text: "widgets"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            text: card.cardTitle
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }
    }

    function value(key: string, fallback: var): var {
        return card.spec[key] !== undefined ? card.spec[key] : fallback;
    }

    /// `undefined` takes the field out of the rule. Off means "no opinion" here rather than
    /// "false": a rule that says `float = false` is not the same as one that says nothing.
    function put(key: string, newValue: var) {
        HyprlandRules.putEffect("windowrule", card.ruleId, key, newValue);
    }

    function putMatch(key: string, newValue: var) {
        const next = Object.assign({}, card.spec);
        const match = Object.assign({}, card.match);
        if (newValue === undefined || newValue === "") delete match[key];
        else match[key] = newValue;
        next.match = match;
        HyprlandRules.save("windowrule", card.ruleId, next);
    }

    /// Fields that are only written when they hold something, so an empty box means "not set".
    component TextSetting: ConfigTextField {
        id: setting

        required property string settingKey
        readonly property string currentValue: String(card.value(setting.settingKey, "") ?? "")

        // Typing into a box that is being rewritten underneath is maddening, so an edit in
        // progress always wins over an incoming value.
        onCurrentValueChanged: {
            if (setting.textField.activeFocus) return;
            setting.inputText = setting.currentValue;
        }
        Component.onCompleted: setting.inputText = setting.currentValue

        Connections {
            target: setting.textField

            function onEditingFinished() {
                if (setting.inputText === setting.currentValue) return;
                card.put(setting.settingKey, setting.inputText === "" ? undefined : setting.inputText);
            }
        }
    }

    ConfigTextField {
        id: classField

        icon: "widgets"
        text: Translation.tr("Window class")
        placeholderText: "^(firefox)$"
        tooltip: Translation.tr("A regular expression. Anchoring it with ^( )$ is what stops \"code\" from also catching \"codium\".")

        readonly property string currentValue: String(card.match.class ?? "")
        onCurrentValueChanged: {
            if (classField.textField.activeFocus) return;
            classField.inputText = classField.currentValue;
        }
        Component.onCompleted: classField.inputText = classField.currentValue

        Connections {
            target: classField.textField

            function onEditingFinished() {
                if (classField.inputText === classField.currentValue) return;
                card.putMatch("class", classField.inputText);
            }
        }
    }

    ConfigTextField {
        id: titleField

        icon: "title"
        text: Translation.tr("Only when the title matches")
        placeholderText: Translation.tr("Any title")

        readonly property string currentValue: String(card.match.title ?? "")
        onCurrentValueChanged: {
            if (titleField.textField.activeFocus) return;
            titleField.inputText = titleField.currentValue;
        }
        Component.onCompleted: titleField.inputText = titleField.currentValue

        Connections {
            target: titleField.textField

            function onEditingFinished() {
                if (titleField.inputText === titleField.currentValue) return;
                card.putMatch("title", titleField.inputText);
            }
        }
    }

    HyprToggle {
        buttonIcon: "picture_in_picture"
        text: Translation.tr("Always float")
        switchOn: card.value("float", false) === true
        onRequested: wanted => card.put("float", wanted ? true : undefined)
    }

    HyprToggle {
        buttonIcon: "grid_view"
        text: Translation.tr("Always tile")
        switchOn: card.value("tile", false) === true
        onRequested: wanted => card.put("tile", wanted ? true : undefined)
    }

    HyprToggle {
        buttonIcon: "center_focus_weak"
        text: Translation.tr("Open centred")
        switchOn: card.value("center", false) === true
        onRequested: wanted => card.put("center", wanted ? true : undefined)

        StyledToolTip {
            text: Translation.tr("Only does anything to a floating window.")
        }
    }

    HyprToggle {
        buttonIcon: "blur_off"
        text: Translation.tr("No blur behind it")
        switchOn: card.value("no_blur", false) === true
        onRequested: wanted => card.put("no_blur", wanted ? true : undefined)
    }

    HyprToggle {
        buttonIcon: "animation"
        text: Translation.tr("No open or close animation")
        switchOn: card.value("no_anim", false) === true
        onRequested: wanted => card.put("no_anim", wanted ? true : undefined)
    }

    HyprToggle {
        buttonIcon: "bolt"
        text: Translation.tr("Allow tearing")
        switchOn: card.value("immediate", false) === true
        onRequested: wanted => card.put("immediate", wanted ? true : undefined)

        StyledToolTip {
            text: Translation.tr("Lets a frame reach the screen mid-refresh. Lower latency in a game, visible tearing in anything else.")
        }
    }

    HyprToggle {
        buttonIcon: "bedtime_off"
        text: Translation.tr("Keep the screen awake while it is focused")
        switchOn: String(card.value("idle_inhibit", "none")) !== "none"
        onRequested: wanted => card.put("idle_inhibit", wanted ? "focus" : undefined)

        StyledToolTip {
            text: Translation.tr("The rule editor also offers \"always\" and \"only while fullscreen\".")
        }
    }

    TextSetting {
        settingKey: "opacity"
        icon: "opacity"
        text: Translation.tr("Opacity")
        placeholderText: "0.9"
        tooltip: Translation.tr("One number for every state, or three for active, inactive and fullscreen. Put \"override\" after a number to ignore the shell's own opacity.")
    }

    TextSetting {
        settingKey: "workspace"
        icon: "space_dashboard"
        text: Translation.tr("Always open on workspace")
        placeholderText: Translation.tr("Wherever it is")
        tooltip: Translation.tr("A number, a name, or special:magic. Add \" silent\" to send it there without following it.")
    }

    TextSetting {
        settingKey: "size"
        icon: "resize"
        text: Translation.tr("Size")
        placeholderText: "1200 800"
        tooltip: Translation.tr("Width then height, separated by a space. Pixels, percentages, or an expression like (monitor_w*0.5).")
    }

    TextSetting {
        settingKey: "move"
        icon: "drag_pan"
        text: Translation.tr("Position")
        placeholderText: Translation.tr("Wherever it lands")
        tooltip: Translation.tr("Only applies to a floating window.")
    }

    HyprNavRow {
        buttonIcon: "tune"
        text: Translation.tr("All window rule settings")
        value: Translation.tr("%1 set").arg(Object.keys(HyprlandRules.effectsOf("windowrule", card.spec)).length)
        onOpenSubPage: card.editRequested()
    }

    HyprMatchPreview {
        match: card.match
    }

    RippleButton {
        Layout.fillWidth: true
        implicitHeight: 40
        useDynamicRadius: true
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colErrorContainer
        colRipple: Appearance.colors.colErrorContainerActive
        onClicked: card.removeRequested()

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
                text: Translation.tr("Remove every rule for this app")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colError
            }
        }
    }
}
