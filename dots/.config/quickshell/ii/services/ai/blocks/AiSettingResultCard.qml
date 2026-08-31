pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * A small, local Settings control backed by one generated index entry.
 *
 * This is deliberately useful without a model: callers hand it a SettingRef
 * from AiSettingsIntegration and it validates every direct write with the
 * same strict path used by the approved AI diff.
 */
Rectangle {
    id: root

    required property var setting
    property bool compact: false
    property bool expressiveStyle: false
    // The launcher presents settings beside program rows, while chat uses a
    // calmer layer card. Keep both surfaces in this shared control without
    // giving the launcher an unframed, visually floating result.
    property bool launcherStyle: false
    // SearchItem's grouped radius is based on these ListView positions. The
    // card is also used in chat, where they intentionally remain unset.
    property int listIndex: -1
    property int listCount: 0
    property int listCurrentIndex: -1
    /**
     * What the config holds right now.
     *
     * A binding, never assigned. `writeValue` used to set this to the value it
     * had just written, which broke the binding on the first change — after
     * that the card showed its own last write and stopped following the
     * setting, so a change made in the Settings window never reached it.
     */
    readonly property var currentValue: root.readCurrentValue()
    property string writeError: ""

    readonly property string key: String(root.setting?.key ?? "")
    readonly property string settingType: String(root.setting?.type ?? "")
    readonly property var range: root.setting?.range ?? ({})
    readonly property var enumOptions: Array.from(root.setting?.options ?? []).map(option => ({
                displayName: String(option?.label ?? option?.value ?? ""),
                value: option?.value
            }))
    readonly property bool hasRange: root.range?.from !== undefined && root.range?.from !== null
        && root.range?.to !== undefined && root.range?.to !== null
    // The launcher groups its rows per section, so "first" and "last" are
    // section-scoped and only the host knows them. Chat has no sections and
    // keeps the positional default.
    property var groupFirst: null
    property var groupLast: null
    readonly property bool isFirst: root.groupFirst !== null
        ? root.groupFirst === true
        : (root.listIndex === 0 && root.listCount > 0)
    readonly property bool isLast: root.groupLast !== null
        ? root.groupLast === true
        : (root.listIndex >= 0 && root.listIndex === root.listCount - 1)
    readonly property bool isSelected: root.listIndex >= 0 && root.listIndex === root.listCurrentIndex
    readonly property bool isAboveSelected: root.listIndex >= 0 && root.listCurrentIndex === root.listIndex + 1
    readonly property bool isBelowSelected: root.listIndex >= 0 && root.listCurrentIndex === root.listIndex - 1
    readonly property real pillRadius: Math.min(root.height / 2, Appearance.rounding.large)
    readonly property bool canEditInline: root.setting?.hasUi === true
    readonly property bool supportsHorizontalNavigation: root.canEditInline && (root.settingType === "bool"
        || root.settingType === "int"
        || root.settingType === "real"
        || (root.settingType === "enum" && root.enumOptions.length > 0))
    readonly property color selectedSurfaceColor: Appearance.colors.colPrimaryContainer
    readonly property color selectedAccentColor: Appearance.colors.colPrimary
    readonly property color idleAccentColor: Appearance.colors.colSecondaryContainer
    readonly property color foregroundColor: root.expressiveStyle && root.isSelected
        ? Appearance.colors.colOnPrimaryContainer
        : (root.launcherStyle && root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2)
    readonly property color secondaryColor: root.expressiveStyle && root.isSelected
        ? Appearance.colors.colOnPrimaryContainer
        : (root.launcherStyle && root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext)
    readonly property bool isHovered: cardHover.hovered
    // One label, already in the language the interface is showing. The index
    // used to carry two and pick between them here, which is how an English
    // interface displayed Portuguese names.
    readonly property string displayLabel: String(root.setting?.label ?? "") || root.key
    readonly property string settingIcon: String(root.setting?.icon ?? "").trim() || "tune"
    readonly property string sectionTitle: String(root.setting?.sectionTitle ?? "")
    readonly property string sectionPath: [
        root.setting?.pageName ?? "",
        root.sectionTitle
    ].filter(part => String(part).length > 0).join(" › ")

    function readCurrentValue(): var {
        if (root.key.length === 0)
            return undefined;
        return Config.getNestedValue(Config.options, root.key.split("."));
    }

    function writeValue(value: var): bool {
        if (!root.canEditInline || root.key.length === 0)
            return false;
        const verdict = Ai.settingsIntegration.validate(root.key, value);
        if (!verdict.ok) {
            root.writeError = Ai.settingsIntegration.reasonText(verdict);
            return false;
        }
        try {
            // Nothing is assigned back: `currentValue` reads the config, so
            // writing it is what updates the card, here and everywhere else
            // showing the same setting.
            Config.setNestedValue(root.key, value, true);
            root.writeError = "";
            return true;
        } catch (error) {
            root.writeError = String(error);
            return false;
        }
    }

    function numericStep(): real {
        const configured = Number(root.range?.step ?? 0);
        if (isFinite(configured) && configured > 0)
            return configured;
        if (root.settingType === "real" && root.hasRange) {
            const span = Math.abs(Number(root.range.to) - Number(root.range.from));
            if (isFinite(span) && span > 0)
                return span / 100;
        }
        return 1;
    }

    function boundedNumericValue(value: real): real {
        let result = Number(value);
        if (!isFinite(result))
            result = Number(root.currentValue ?? 0);
        if (root.hasRange)
            result = Math.max(Number(root.range.from), Math.min(Number(root.range.to), result));
        return root.settingType === "int" ? Math.round(result) : result;
    }

    /**
     * Commits a number a control produced, ignoring the echo.
     *
     * A control gets `value` assigned both when someone presses its button and
     * when the setting it is bound to changes. Writing on every change would
     * send the second case straight back to the config; comparing against what
     * is stored tells the two apart.
     */
    function commitNumber(value: real): bool {
        const wanted = root.boundedNumericValue(value);
        if (Number(root.currentValue) === wanted)
            return false;
        return root.writeValue(wanted);
    }

    /** Applies one horizontal keyboard move without giving the control focus. */
    function adjustBy(direction: int): bool {
        if (!root.canEditInline)
            return false;
        const stepDirection = direction < 0 ? -1 : (direction > 0 ? 1 : 0);
        if (stepDirection === 0)
            return false;

        if (root.settingType === "bool") {
            const wanted = stepDirection > 0;
            return Boolean(root.currentValue) === wanted ? false : root.writeValue(wanted);
        }

        if (root.settingType === "int" || root.settingType === "real") {
            const next = root.boundedNumericValue(Number(root.currentValue ?? 0) + root.numericStep() * stepDirection);
            return Number(root.currentValue) === next ? false : root.writeValue(next);
        }

        if (root.settingType === "enum" && root.enumOptions.length > 0) {
            let index = root.enumOptions.findIndex(option => option.value === root.currentValue);
            if (index < 0)
                index = stepDirection > 0 ? -1 : root.enumOptions.length;
            const nextIndex = Math.max(0, Math.min(root.enumOptions.length - 1, index + stepDirection));
            return nextIndex === index ? false : root.writeValue(root.enumOptions[nextIndex].value);
        }

        return false;
    }

    /**
     * Opens Settings on the page, at the section, with it highlighted.
     *
     * The section is matched by its title against the ContentSection on the
     * page, so it has to be the title as the running interface shows it. When
     * the index was built in another language this silently did nothing but
     * open the page.
     */
    function openInSettings(): bool {
        Ai.toolSettingsOpen({
            args: {
                pageId: String(root.setting?.pageId ?? ""),
                subPage: String(root.setting?.subPage ?? ""),
                sectionTitle: root.sectionTitle
            }
        });
        return true;
    }

    /**
     * The action for Enter on a selected launcher result. Toggles change in
     * place; a text field takes keyboard focus; the remaining controls are
     * adjusted with Left/Right and open their source on Enter.
     */
    function activate(): bool {
        if (!root.canEditInline) {
            root.openInSettings();
            return true;
        }
        if (root.settingType === "bool")
            return root.writeValue(!Boolean(root.currentValue));
        if (root.settingType === "string" && controlLoader.item) {
            controlLoader.item.forceActiveFocus();
            return true;
        }
        root.openInSettings();
        return true;
    }

    function clicked(): bool {
        return root.activate();
    }

    function navigateLeft(): bool {
        return root.adjustBy(-1);
    }

    function navigateRight(): bool {
        return root.adjustBy(1);
    }

    function explain() {
        const description = String(root.setting?.description ?? "");
        const prompt = Translation.tr("Explain the setting %1 (%2). %3").arg(root.displayLabel).arg(root.key).arg(description);
        Ai.sendUserMessage(prompt);
    }

    Layout.fillWidth: true
    implicitHeight: cardColumn.implicitHeight + (root.compact ? Appearance.sizes.elevationMargin * 1.2 : Appearance.sizes.elevationMargin * 2)
    radius: root.expressiveStyle
        ? (root.isSelected ? Appearance.rounding.large : Appearance.rounding.normal)
        : Appearance.rounding.normal
    topLeftRadius: root.expressiveStyle ? root.radius : (root.launcherStyle
        ? (root.isFirst ? Appearance.rounding.large : (root.isSelected || root.isBelowSelected ? root.pillRadius : Appearance.rounding.small))
        : Appearance.rounding.normal)
    topRightRadius: root.topLeftRadius
    bottomLeftRadius: root.expressiveStyle ? root.radius : (root.launcherStyle
        ? (root.isLast ? Appearance.rounding.large : (root.isSelected || root.isAboveSelected ? root.pillRadius : Appearance.rounding.small))
        : Appearance.rounding.normal)
    bottomRightRadius: root.bottomLeftRadius
    color: root.expressiveStyle
        ? (root.isSelected
            ? root.selectedSurfaceColor
            : (root.isHovered ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHigh))
        : (root.launcherStyle
        ? (root.isSelected ? Appearance.colors.colPrimaryHover : (root.isHovered ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHigh))
        : Appearance.colors.colLayer2)

    // The full card gets a neutral surface hover. Its state must stay
    // separate from a checked switch, which uses the primary color.
    HoverHandler {
        id: cardHover
    }

    Behavior on topLeftRadius {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    Behavior on bottomLeftRadius {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: Appearance.animation.elementMoveFast.duration
        }
    }

    ColumnLayout {
        id: cardColumn
        anchors.fill: parent
        anchors.margins: root.compact ? Appearance.sizes.elevationMargin * 0.6 : Appearance.sizes.elevationMargin
        spacing: root.compact ? 4 : 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: root.expressiveStyle
                    ? Appearance.sizes.elevationMargin * 4
                    : Appearance.font.pixelSize.normal
                Layout.preferredHeight: Layout.preferredWidth

                MaterialShape {
                    anchors.fill: parent
                    visible: root.expressiveStyle
                    implicitSize: parent.width
                    shapeString: root.settingType === "bool" ? "Clover4Leaf"
                        : (root.settingType === "enum" ? "Cookie7Sided"
                        : (root.settingType === "string" ? "Arch" : "SoftBurst"))
                    color: root.isSelected
                        ? root.selectedAccentColor
                        : root.idleAccentColor
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.settingIcon
                    iconSize: Appearance.font.pixelSize.large
                    color: root.expressiveStyle
                        ? (root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer)
                        : root.foregroundColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.displayLabel
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.foregroundColor
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.sectionPath.length > 0
                    text: root.sectionPath
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.secondaryColor
                    opacity: root.launcherStyle && root.isSelected ? 0.78 : 1
                }
            }

            StyledSwitch {
                visible: root.expressiveStyle && root.canEditInline && root.settingType === "bool"
                sizeScale: 0.82
                checked: Boolean(root.currentValue)
                onToggled: {
                    if (checked !== Boolean(root.currentValue))
                        root.writeValue(checked);
                }
            }

            ConfiguredKeyHint {
                visible: root.expressiveStyle && root.isSelected && Config.options.search.appearance.showKeyHints
                actionId: "activate"
                fallbackKeys: ["↵"]
                surface: root.selectedSurfaceColor
                onSurface: Appearance.colors.colOnPrimaryContainer
            }

            RippleButton {
                id: openSettingsButton
                implicitWidth: openSettingsContent.implicitWidth + Appearance.sizes.elevationMargin * 1.4
                implicitHeight: Appearance.sizes.elevationMargin * 3.8
                buttonRadius: Appearance.rounding.full
                colBackground: root.isSelected ? root.selectedAccentColor : root.idleAccentColor
                colBackgroundHover: root.isSelected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                colRipple: root.isSelected ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
                onClicked: root.openInSettings()

                Accessible.name: Translation.tr("Open in Settings")

                contentItem: RowLayout {
                    id: openSettingsContent
                    spacing: Appearance.sizes.elevationMargin / 2

                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        text: Translation.tr("Open")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    }

                    ConfiguredKeyHint {
                        visible: Config.options.search.appearance.showKeyHints
                        actionId: "secondary"
                        fallbackKeys: ["Ctrl", "↵"]
                        surface: root.isSelected ? root.selectedAccentColor : root.idleAccentColor
                        onSurface: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    }
                }

                StyledToolTip { text: Translation.tr("Open in Settings") }
            }
        }

        Loader {
            id: controlLoader
            Layout.fillWidth: true
            sourceComponent: {
                // The Settings search panel is intentionally a compact command
                // surface. Expanding a slider, option flow or text field inside
                // one result made individual rows consume several list slots.
                // Numeric and enum values remain keyboard-adjustable through
                // Left/Right; text and composite controls open their full page.
                if (root.compact && root.expressiveStyle)
                    return null;
                if (!root.canEditInline || (root.expressiveStyle && root.settingType === "bool"))
                    return null;
                if (root.settingType === "bool")
                    return switchControl;
                if (root.settingType === "int")
                    return integerControl;
                if (root.settingType === "real" && root.hasRange)
                    return realControl;
                if (root.settingType === "enum" && root.enumOptions.length > 0)
                    return enumControl;
                if (root.settingType === "string")
                    return textControl;
                return null;
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.canEditInline && !(root.compact && root.expressiveStyle)
            text: root.enumOptions.length > 0
                ? Translation.tr("Composite control · open its page to choose safely")
                : Translation.tr("Open this setting to change its value.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.writeError.length > 0
            text: root.writeError
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.compact
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                text: root.key
                elide: Text.ElideRight
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                implicitHeight: 28
                leftPadding: 10
                rightPadding: 10
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.explain()

                contentItem: StyledText {
                    text: Translation.tr("Explain")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    Component {
        id: switchControl

        RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            StyledSwitch {
                checked: Boolean(root.currentValue)
                onToggled: root.writeValue(checked)
            }
        }
    }

    Component {
        id: integerControl

        RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            StyledSpinBox {
                id: numberBox
                from: root.hasRange ? Number(root.range.from) : -1000000
                to: root.hasRange ? Number(root.range.to) : 1000000
                stepSize: Number(root.numericStep())
                value: Number(root.currentValue ?? 0)
                // `valueModified` is the signal for "the user changed this",
                // but StyledSpinBox replaces the content item with a text
                // field that assigns `value` itself, and a plain assignment
                // emits no such thing. The plus and minus buttons therefore
                // moved the number on screen and wrote nothing. Every change
                // is committed instead, with the echo filtered out below.
                onValueChanged: root.commitNumber(value)

                Connections {
                    target: root
                    function onCurrentValueChanged() {
                        // Interacting with a SpinBox breaks the declarative
                        // binding above, so the control has to be told when
                        // the setting changes somewhere else.
                        const stored = Number(root.currentValue ?? 0);
                        if (Number(numberBox.value) !== stored)
                            numberBox.value = stored;
                    }
                }
            }
        }
    }

    Component {
        id: realControl

        StyledSlider {
            id: numberSlider
            Layout.fillWidth: true
            from: Number(root.range.from)
            to: Number(root.range.to)
            stepSize: Number(root.range?.step ?? 0)
            value: Number(root.currentValue ?? root.range.from)
            usePercentTooltip: false
            onMoved: root.commitNumber(value)

            Connections {
                target: root
                function onCurrentValueChanged() {
                    // Dragging breaks the binding above, same as the spin box.
                    const stored = Number(root.currentValue ?? numberSlider.from);
                    if (Number(numberSlider.value) !== stored)
                        numberSlider.value = stored;
                }
            }
        }
    }

    Component {
        id: enumControl

        ConfigSelectionArray {
            Layout.fillWidth: true
            // The control is a Flow and wraps onto new rows by itself; a
            // minimum width of zero keeps narrow launcher columns from
            // stretching the row to fit one long option line.
            Layout.minimumWidth: 0
            options: root.enumOptions
            currentValue: root.currentValue
            onSelected: value => root.writeValue(value)
        }
    }

    Component {
        id: textControl

        MaterialTextField {
            Layout.fillWidth: true
            // Single-line values only: the base field wraps while column
            // widths are still being resolved, which published huge
            // intermediate heights and broke the launcher row geometry.
            wrapMode: TextEdit.NoWrap
            Layout.minimumWidth: 80
            text: String(root.currentValue ?? "")
            onEditingFinished: {
                // Focus loss also fires editingFinished; committing that echo
                // would mark an untouched field as changed.
                if (text !== String(root.currentValue ?? ""))
                    root.writeValue(text);
            }
        }
    }
}
