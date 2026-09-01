pragma ComponentBehavior: Bound

import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * What can be done with an answer, under the answer.
 *
 * It used to sit above the message, in a header that also carried the
 * model's name and the user's — which put six controls between the question
 * and its answer. Here it is a single pill beneath the bubble: which model
 * wrote this, and the five things worth doing about it. Editing and reading
 * the raw markdown are gone; neither belonged on a finished answer.
 */
Rectangle {
    id: root

    required property string messageId
    required property var messageData

    /** Asks the control bar for another model to redo this answer with. */
    signal regenerateRequested(string messageId)
    /** Asks the control bar to show the model picker. */
    signal modelPickerRequested

    /**
     * The short bar: which model answered, ask again, copy. The Search panel
     * is for quick questions in a strip that is mostly composer, so branching,
     * swapping models and deleting are left to the sidebar rather than
     * crowding four more circles into it.
     */
    property bool minimal: false

    /** The bar shares the answer's own tone, and its controls the question's. */
    property color surfaceColor: Appearance.colors.colLayer0Base
    property color buttonColor: Appearance.colors.colLayer2
    property color buttonInk: Appearance.colors.colOnLayer2

    readonly property var modelEntry: Ai.models[root.messageData?.model] ?? null
    readonly property string modelTitle: root.modelEntry?.title ?? root.modelEntry?.name ?? String(root.messageData?.model ?? "")

    /**
     * A bar narrow enough that the five actions and the model's name cannot
     * both be comfortable. The actions give way first: they are round and
     * recognisable at any size, while a name cut to "Gemini 2.5 Fla…" tells
     * nobody which model answered.
     */
    readonly property bool compact: root.width < Appearance.font.pixelSize.huge * 19
    readonly property real controlExtent: Math.round(Appearance.font.pixelSize.huge * (root.compact ? 1.95 : 2.15))
    /**
     * The glyph follows the circle rather than a fixed step of the type
     * scale, so growing the bar grows what is drawn on it instead of leaving
     * the same small icon adrift in a wider button.
     */
    readonly property real symbolSize: Math.round(root.controlExtent * 0.48)
    // Both measures follow the control, so a taller bar is a tighter one
    // rather than a taller one with the same holes in it.
    readonly property real controlGap: Math.max(2, Math.round(root.controlExtent * 0.12))
    readonly property real inset: Math.max(2, Math.round(root.controlExtent * 0.14))
    /** The pill's own inset, counted once on each side of its content. */
    readonly property real pillPadding: Math.round(root.controlExtent * 0.28)
    /** How many round controls sit to the right of the model's name. */
    readonly property int actionCount: root.minimal ? 2 : 5
    /**
     * Everything the actions leave over, which is what the name may use.
     *
     * The row is: pill, the gap that separates the two groups, then one gap
     * per action. Counting it exactly is what keeps a long model name from
     * ever growing into the first circle — the name is cut instead.
     */
    readonly property real modelPillLimit: Math.max(root.controlExtent,
        root.width - root.inset * 2 - (root.controlExtent + root.controlGap) * root.actionCount - root.controlGap)
    /**
     * Below this the name has room for two or three characters, which says
     * less than the logo already does — so the pill becomes the logo.
     */
    readonly property bool showModelName: root.modelPillLimit >= root.controlExtent * 2

    implicitHeight: root.controlExtent + root.inset * 2
    radius: Appearance.rounding.full
    color: root.surfaceColor

    RowLayout {
        id: actionsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        spacing: root.controlGap

        RippleButton {
            // Which model wrote this, and a way to answer with another one
            // next time without leaving the transcript.
            id: modelPill
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: root.modelPillLimit
            // A layout may shrink an item below its implicit width; saying so
            // explicitly is what stops the pill and the first circle from
            // ever being asked to share the same pixels.
            Layout.minimumWidth: root.controlExtent
            implicitHeight: root.controlExtent
            // Measured off its parts, not off the row inside it: a filling
            // child in a Control's content item feeds the Control's width
            // back into itself and Layouts abort the pass.
            readonly property real leadWidth: modelIconLoader.active ? modelIconLoader.implicitWidth : modelGlyph.implicitWidth
            implicitWidth: root.showModelName
                ? Math.min(modelPill.Layout.maximumWidth,
                    modelLabel.implicitWidth + modelPill.leadWidth + modelPillRow.spacing + root.pillPadding * 2 + 1)
                : root.controlExtent
            buttonRadius: Appearance.rounding.full
            topPadding: 0
            bottomPadding: 0
            leftPadding: root.showModelName ? root.pillPadding : 0
            rightPadding: root.showModelName ? root.pillPadding : 0
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: root.modelPickerRequested()

            contentItem: RowLayout {
                id: modelPillRow
                spacing: Appearance.rounding.unsharpenmore

                Loader {
                    // A provider that ships a logo gets its logo; everything
                    // else gets the glyph the catalogue chose for it.
                    id: modelIconLoader
                    Layout.alignment: Qt.AlignVCenter
                    active: (root.modelEntry?.icon ?? "").length > 0
                    visible: active

                    sourceComponent: CustomIcon {
                        implicitWidth: root.symbolSize
                        implicitHeight: root.symbolSize
                        width: implicitWidth
                        height: implicitHeight
                        source: root.modelEntry?.icon ?? ""
                        colorize: true
                        color: Appearance.colors.colOnPrimary
                    }
                }

                MaterialSymbol {
                    id: modelGlyph
                    Layout.alignment: Qt.AlignVCenter
                    visible: (root.modelEntry?.icon ?? "").length === 0
                    text: (root.modelEntry?.materialIcon ?? "").length > 0 ? root.modelEntry.materialIcon : "auto_awesome"
                    fill: 1
                    iconSize: root.symbolSize
                    color: Appearance.colors.colOnPrimary
                }

                StyledText {
                    id: modelLabel
                    // Whatever the actions left, minus what the logo and the
                    // padding take: past that the name is cut, never the bar.
                    Layout.maximumWidth: Math.max(0, modelPill.Layout.maximumWidth - modelPill.leadWidth
                        - modelPillRow.spacing - root.pillPadding * 2)
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.showModelName
                    text: root.modelTitle
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.bold: true
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnPrimary
                }
            }

            StyledToolTip {
                text: Translation.tr("Answered by %1\nClick to change the model").arg(root.modelTitle)
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
        }

        ActionButton {
            visible: !root.minimal
            symbol: "swap_horiz"
            tooltipText: Translation.tr("Ask again with another model")
            onTriggered: root.regenerateRequested(root.messageId)
        }

        ActionButton {
            visible: !root.minimal
            symbol: "alt_route"
            tooltipText: Translation.tr("Branch off here into a new chat")
            onTriggered: Ai.forkFrom(root.messageId)
        }

        ActionButton {
            symbol: "refresh"
            tooltipText: Translation.tr("Ask again. The answer being replaced stays in its own chat")
            onTriggered: Ai.regenerate(root.messageId)
        }

        ActionButton {
            visible: !root.minimal
            symbol: "delete"
            tooltipText: Translation.tr("Delete this answer")
            onTriggered: Ai.removeMessage(root.messageId)
        }

        ActionButton {
            // The one thing here that is done *to* the answer rather than to
            // the chat, so it is the one that carries the accent.
            id: copyAction
            property bool copied: false

            symbol: copyAction.copied ? "inventory" : "content_copy"
            accented: true
            tooltipText: copyAction.copied ? Translation.tr("Copied") : Translation.tr("Copy the answer")
            onTriggered: {
                // The reasoning is never part of what gets copied. Chats saved
                // before it had a field of its own still carry it inline, so
                // it is stripped here too.
                AiOutputController.copyText(String(root.messageData?.content ?? "").replace(/<think>[\s\S]*?<\/think>/g, "").trim());
                copyAction.copied = true;
                copyResetTimer.restart();
            }

            Timer {
                // Long enough to be read as confirmation, short enough that
                // the button is itself again before it is needed twice.
                id: copyResetTimer
                interval: Appearance.animation.elementMoveSlow.duration * 3
                onTriggered: copyAction.copied = false
            }
        }
    }

    /** One round control on the answer's own bar. */
    component ActionButton: RippleButton {
        id: actionButton

        property string symbol: ""
        property string tooltipText: ""
        /** Set on the one action that is not about the chat but about the text. */
        property bool accented: false

        signal triggered

        Layout.alignment: Qt.AlignVCenter
        Layout.minimumWidth: root.controlExtent
        implicitWidth: root.controlExtent
        implicitHeight: root.controlExtent
        buttonRadius: Appearance.rounding.full
        // Pressing it rounds the corners in, the way every other pill in the
        // sidebar answers a press.
        buttonRadiusPressed: Appearance.rounding.normal
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        colBackground: actionButton.accented ? Appearance.colors.colPrimary : root.buttonColor
        colBackgroundHover: actionButton.accented ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
        colRipple: actionButton.accented ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
        onClicked: actionButton.triggered()

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: actionButton.symbol
            fill: 1
            iconSize: root.symbolSize
            color: actionButton.accented ? Appearance.colors.colOnPrimary : root.buttonInk
            // The glyph itself answers the press, so a control that swaps its
            // icon (copy → copied) does not simply cut from one to the other.
            scale: actionButton.down ? 0.86 : 1

            Behavior on scale {
                animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
            }
        }

        StyledToolTip {
            text: actionButton.tooltipText
        }
    }
}
