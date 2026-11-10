pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.easyEffects.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * One setting of an effect, drawn from its entry in the generated table as a tile: a
 * badge with the glyph of what it sets, its name in small caps, the value in bold, and
 * under them a slider (logarithmic for frequencies), a switch, a choice, or a text field
 * for the few values with no range. A slider's value can be clicked to type an exact one,
 * and the arrow keys step a focused slider (ten steps with Shift).
 *
 * The row owns no state: it shows `value` and reports `edited(value)`. While a slider is
 * dragged it keeps its own position, so a value arriving back never fights the hand.
 */
Rectangle {
    id: root

    required property var control
    property var value
    property string labelOverride: ""

    signal edited(var value)

    readonly property string kind: root.control?.type ?? "double"
    readonly property bool ranged: root.control && root.control.min !== undefined && root.control.max !== undefined
    readonly property bool logScale: root.ranged && Logic.isLogControl(root.control)
    readonly property var shownValue: root.value === undefined ? root.control?.default : root.value

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + EasyEffectsStyle.gap * 2 - EasyEffectsStyle.gapTiny
    radius: EasyEffectsStyle.radiusField
    color: EasyEffectsStyle.colField

    function toSlider(v: real): real {
        if (!root.logScale)
            return v;
        const lo = Math.log(root.control.min), hi = Math.log(root.control.max);
        return (Math.log(Math.max(root.control.min, v)) - lo) / (hi - lo);
    }

    function fromSlider(p: real): real {
        if (!root.logScale)
            return p;
        const lo = Math.log(root.control.min), hi = Math.log(root.control.max);
        return Math.exp(lo + p * (hi - lo));
    }

    function stepAt(v: real): real {
        if (root.kind === "int")
            return 1;
        return root.logScale ? (v >= 1000 ? 10 : v >= 100 ? 1 : 0.1) : Logic.stepFor(root.control);
    }

    function tidy(v: real): real {
        const step = root.stepAt(v);
        return Number((Math.round(v / step) * step).toFixed(3));
    }

    function clamp(v: real): real {
        return Math.min(root.control.max, Math.max(root.control.min, v));
    }

    // A drag covers the whole range, too coarse for a fine value: the arrow keys and a
    // typed value reach any step.
    function nudge(steps: int): void {
        const v = Number(root.shownValue ?? 0);
        root.edited(root.tidy(root.clamp(v + steps * root.stepAt(v))));
    }

    function commitTyped(text: string): void {
        const match = String(text).replace(",", ".").match(/-?\d*\.?\d+/);
        if (!match)
            return;
        const number = Number(match[0]) * (/\d\s*k/i.test(text) ? 1000 : 1);
        root.edited(root.tidy(root.clamp(number)));
    }

    ColumnLayout {
        id: body
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: EasyEffectsStyle.gap
            rightMargin: EasyEffectsStyle.gapLarge
        }
        spacing: EasyEffectsStyle.gapSmall - 2

        RowLayout {
            Layout.fillWidth: true
            spacing: EasyEffectsStyle.gapSmall + 2

            EasyEffectsBadge {
                size: EasyEffectsStyle.controlBadge
                text: Logic.controlIcon(root.control?.key)
                shape: EasyEffectsStyle.shapeFor(root.control?.key)
                color: EasyEffectsStyle.colPrimaryContainer
                colSymbol: EasyEffectsStyle.colOnPrimaryContainer
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: (root.labelOverride.length > 0 ? root.labelOverride : Logic.labelFor(root.control?.key)).toUpperCase()
                elide: Text.ElideRight
                font.pixelSize: EasyEffectsStyle.textCaption
                font.variableAxes: EasyEffectsStyle.axesCaption
                font.letterSpacing: EasyEffectsStyle.letterSpacingCaption
                color: EasyEffectsStyle.colOnSurfaceVariant
            }

            StyledText {
                visible: (root.kind === "double" || root.kind === "int") && !valueField.visible
                text: Logic.formatValue(root.control, slider.pressed ? root.tidy(root.fromSlider(slider.value)) : root.shownValue)
                font.pixelSize: EasyEffectsStyle.textBody
                font.weight: Font.Bold
                color: valueArea.containsMouse ? EasyEffectsStyle.colPrimary : EasyEffectsStyle.colOnSurface

                MouseArea {
                    id: valueArea
                    anchors.fill: parent
                    anchors.margins: -6
                    enabled: root.ranged
                    hoverEnabled: true
                    cursorShape: Qt.IBeamCursor
                    onClicked: {
                        valueField.text = String(root.shownValue ?? "");
                        valueField.visible = true;
                        valueField.forceActiveFocus();
                        valueField.selectAll();
                    }
                }
            }

            StyledTextInput {
                id: valueField
                property bool cancelled: false
                visible: false
                Layout.preferredWidth: EasyEffectsStyle.valueFieldWidth
                horizontalAlignment: Text.AlignRight
                font.pixelSize: EasyEffectsStyle.textBody
                font.weight: Font.Bold
                color: EasyEffectsStyle.colPrimary
                Keys.onEscapePressed: {
                    valueField.cancelled = true;
                    valueField.focus = false;
                }
                onEditingFinished: {
                    if (!valueField.cancelled)
                        root.commitTyped(valueField.text);
                    valueField.cancelled = false;
                    valueField.visible = false;
                }
                onActiveFocusChanged: {
                    if (!valueField.activeFocus)
                        valueField.visible = false;
                }
            }

            StyledSwitch {
                visible: root.kind === "bool"
                checked: root.shownValue === true
                checkable: false
                onClicked: root.edited(!(root.shownValue === true))
            }
        }

        StyledSlider {
            id: slider
            Layout.fillWidth: true
            visible: (root.kind === "double" || root.kind === "int") && root.ranged
            configuration: StyledSlider.Configuration.M
            from: root.logScale ? 0 : (root.control?.min ?? 0)
            to: root.logScale ? 1 : (root.control?.max ?? 1)
            stepSize: 0
            usePercentTooltip: false
            tooltipContent: Logic.formatValue(root.control, root.tidy(root.fromSlider(slider.value)))
            onMoved: root.edited(root.tidy(root.fromSlider(slider.value)))
            Keys.onPressed: event => {
                const up = event.key === Qt.Key_Right || event.key === Qt.Key_Up;
                if (!up && event.key !== Qt.Key_Left && event.key !== Qt.Key_Down)
                    return;
                event.accepted = true;
                root.nudge((up ? 1 : -1) * (event.modifiers & Qt.ShiftModifier ? 10 : 1));
            }

            // Follows the preset except while held.
            Binding {
                target: slider
                property: "value"
                value: root.toSlider(Number(root.shownValue ?? 0))
                when: !slider.pressed
                restoreMode: Binding.RestoreNone
            }
        }

        StyledComboBox {
            Layout.fillWidth: true
            visible: root.kind === "enum"
            implicitHeight: EasyEffectsStyle.fieldBadge
            model: root.kind === "enum" ? root.control.options : []
            currentIndex: root.kind === "enum" ? Math.max(0, root.control.options.indexOf(root.shownValue)) : -1
            onActivated: index => root.edited(root.control.options[index])
        }

        // No range to slide over (a few convolver angles), or a name.
        StyledTextInput {
            Layout.fillWidth: true
            visible: root.kind === "string" || ((root.kind === "double" || root.kind === "int") && !root.ranged)
            text: String(root.shownValue ?? "")
            font.pixelSize: EasyEffectsStyle.textNormal
            color: EasyEffectsStyle.colOnSurface
            onEditingFinished: {
                if (root.kind === "string") {
                    root.edited(text);
                    return;
                }
                const number = Number(text);
                if (!isNaN(number))
                    root.edited(root.kind === "int" ? Math.round(number) : number);
            }
        }
    }
}
