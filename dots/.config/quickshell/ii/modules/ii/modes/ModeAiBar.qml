pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.services.ai.blocks

/**
 * The assistant's seat in the Modes sidebar.
 *
 * One surface, five beats, and every verdict is said *inside* the element —
 * the Notes prompt bar's rule: no separate toast, no tooltip archaeology.
 * It opens as a search pill; while the agent works, the input gives its
 * place to the same typing shapes the chats use and the send toggle becomes
 * a stop button (cancelling is the same gesture that started it); when a
 * definition lands, the toggle morphs into a check, the pill names what was
 * created, and the row folds; when the model answers without writing —
 * a refusal, a question back — the pill says so and offers the hop to the
 * chat that holds its words; and a refusal shakes the pill, prints the
 * error on it, and keeps the sentence editable, because the fastest fix
 * for a refusal is editing the request that caused it.
 *
 * No leading icon: the header's button is the assistant's mark, and a
 * second one inside the field it opened is the same glyph twice.
 *
 * Stateless on purpose: `phase` is owned by the overlay (it owns the run)
 * and nothing here writes it. The animations key off its transitions, so
 * the bar can be destroyed by a tab switch mid-run and reappear showing
 * the right thing.
 */
Item {
    id: root

    /** "idle" | "running" | "success" | "answered" | "error". */
    property string phase: "idle"
    property bool expanded: false
    property string errorText: ""
    /// Name of the definition the run produced, shown on the success beat.
    property string createdName: ""

    signal submitted(string text)
    signal stopRequested()
    signal dismissed()
    signal successFinished()
    signal openChatRequested()

    readonly property bool running: phase === "running"
    readonly property bool settled: phase === "success"
    readonly property bool failed: phase === "error"
    readonly property bool answered: phase === "answered"
    /// The verdict lives where the sentence was typed; the pill hides the
    /// input for it.
    readonly property bool verdict: settled || failed || answered
    /// Refusal and answer point at the transcript; success does not need to.
    readonly property bool needsChat: failed || answered
    readonly property bool canSend: promptInput.text.trim().length > 0 && !running

    implicitWidth: 300
    implicitHeight: expanded ? (needsChat ? 98 : 54) : 0

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    onExpandedChanged: {
        if (expanded) {
            root.errorText = "";
            Qt.callLater(() => promptInput.forceActiveFocus());
        }
    }

    // The error beat: one shake, then settle; nothing loops.
    onPhaseChanged: {
        if (phase === "error")
            errorShake.restart();
        else if (phase === "success")
            successHoldTimer.restart();
    }

    Timer {
        id: successHoldTimer
        // Long enough to read the check and the name; the editor the agent
        // opened is already on screen while this holds.
        interval: 1800
        onTriggered: {
            root.successFinished();
            root.expanded = false;
        }
    }

    ErrorShakeAnimation {
        id: errorShake
        target: barColumn
        distance: 14
    }

    ColumnLayout {
        id: barColumn
        anchors.fill: parent
        spacing: 8
        visible: root.expanded || opacity > 0.01
        opacity: root.expanded ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            Rectangle {
                id: pill
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                Layout.alignment: Qt.AlignVCenter
                radius: Appearance.rounding.full
                // The surface carries the state: the container colour pair
                // of whichever beat is playing — neutral while listening or
                // answering, primary for a creation, the error pair for a
                // refusal.
                color: root.settled ? Appearance.colors.colPrimaryContainer
                    : (root.failed ? Appearance.colors.colErrorContainer : Appearance.m3colors.m3surfaceContainerHighest)
                clip: true

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                MouseArea {
                    // Typing stays typing: a press on the pill's empty area
                    // returns the caret instead of eating the click.
                    anchors.fill: parent
                    z: -1
                    onClicked: root.focusInput()
                }

                // Anchors, not Layout attached properties: the pill is a
                // Rectangle, so Layout.* here would be inert and the body
                // would collapse to 0×0 — the field would "leave" the pill.
                Item {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: 16
                        rightMargin: 14
                    }

                    StyledTextInput {
                        id: promptInput
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        enabled: !root.running
                        readOnly: root.settled
                        activeFocusOnTab: true
                        color: root.settled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.normal
                        clip: true
                        opacity: (!root.running && !root.verdict) ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasized
                            }
                        }

                        onAccepted: root.trySend()

                        Keys.onEscapePressed: event => {
                            event.accepted = true;
                            if (root.running)
                                root.stopRequested();
                            else
                                root.dismissed();
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.failed
                                ? Translation.tr("Ask again — or say it differently")
                                : Translation.tr("Describe a mode or routine…")
                            font: promptInput.font
                            color: root.failed
                                ? Appearance.colors.colOnErrorContainer
                                : Appearance.colors.colOnLayer1Inactive
                            visible: promptInput.text.length === 0 && !root.running && !root.verdict
                        }
                    }

                    AiTypingIndicator {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        active: root.running
                        opacity: root.running ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasized
                            }
                        }
                    }

                    // The verdict, printed on the pill itself: what was
                    // created, what the model said instead, or what broke.
                    StyledText {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        text: root.settled
                            ? (root.createdName.length > 0
                                ? Translation.tr("Created “%1”").arg(root.createdName)
                                : Translation.tr("Created"))
                            : (root.answered
                                ? Translation.tr("Answered in the chat — nothing was created")
                                : (root.errorText.length > 0
                                    ? root.errorText : Translation.tr("It did not work")))
                        color: root.settled ? Appearance.colors.colOnPrimaryContainer
                            : (root.failed ? Appearance.colors.colOnErrorContainer
                                : Appearance.m3colors.m3onSurface)
                        visible: root.verdict
                        animateChange: true
                    }
                }
            }

            // The send toggle — one gesture that starts, stops and retries.
            RippleButton {
                id: sendToggle
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: root.settled ? Appearance.colors.colPrimary
                    : (root.failed ? Appearance.colors.colErrorContainer
                        : (root.running ? Appearance.colors.colTertiaryContainer
                            : (root.canSend ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer)))
                colBackgroundHover: root.settled ? Appearance.colors.colPrimaryHover
                    : (root.failed ? Appearance.colors.colErrorContainerHover
                        : (root.running ? Appearance.colors.colTertiaryContainerHover
                            : (root.canSend ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover)))
                colRipple: root.settled ? Appearance.colors.colPrimaryActive
                    : (root.failed ? Appearance.colors.colErrorContainerActive
                        : (root.running ? Appearance.colors.colTertiaryContainerActive
                            : (root.canSend ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive)))
                enabled: root.running || root.failed || root.canSend
                onClicked: {
                    if (root.running)
                        root.stopRequested();
                    else
                        root.trySend();
                }

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.running ? "stop"
                        : (root.settled ? "check" : (root.failed ? "error" : "arrow_upward"))
                    iconSize: Appearance.font.pixelSize.large
                    fill: 1
                    color: root.settled ? Appearance.colors.colOnPrimary
                        : (root.failed ? Appearance.colors.colOnErrorContainer
                            : (root.running ? Appearance.colors.colOnTertiaryContainer
                                : (root.canSend ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer)))

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }

                // The morph reads as one object changing mind: the glyph
                // ducks and relands when the toggle changes what it is for.
                // Functional state feedback, one-shot.
                SequentialAnimation {
                    id: morphAnim
                    NumberAnimation {
                        target: sendToggle.contentItem
                        property: "scale"
                        to: 0.4
                        duration: 90
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                    }
                    NumberAnimation {
                        target: sendToggle.contentItem
                        property: "scale"
                        to: 1.15
                        duration: 160
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                    NumberAnimation {
                        target: sendToggle.contentItem
                        property: "scale"
                        to: 1.0
                        duration: 120
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                property string stateName: root.running ? "running"
                    : (root.settled ? "settled"
                        : (root.failed ? "failed"
                            : (root.answered ? "answered" : (root.canSend ? "ready" : "empty"))))
                onStateNameChanged: morphAnim.restart()

                StyledToolTip {
                    text: root.running ? Translation.tr("Stop the assistant")
                        : (root.failed && root.errorText.length > 0 ? root.errorText
                            : (root.settled ? Translation.tr("Done")
                                : Translation.tr("Send")))
                }
            }
        }

        // The hop the two quiet verdicts need: the model's own words (the
        // refusal, the answer, the error detail) live in the transcript, so
        // the bar points there instead of trying to paraphrase them.
        RippleButton {
            id: chatButton
            Layout.alignment: Qt.AlignHCenter
            visible: opacity > 0.01
            opacity: root.needsChat ? 1 : 0
            leftPadding: 12
            rightPadding: 12
            topPadding: 6
            bottomPadding: 6
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasized
                }
            }
            Layout.preferredHeight: root.needsChat ? implicitHeight : 0

            contentItem: RowLayout {
                spacing: 6
                MaterialSymbol {
                    text: "forum"
                    iconSize: 16
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    text: root.failed
                        ? Translation.tr("See what went wrong in the chat")
                        : Translation.tr("Read the answer in the chat")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            onClicked: root.openChatRequested()
        }
    }

    function trySend(): void {
        const text = promptInput.text.trim();
        if (text.length === 0 || root.running || root.settled)
            return;
        root.errorText = "";
        root.submitted(text);
    }

    function focusInput(): void {
        promptInput.forceActiveFocus();
        promptInput.cursorPosition = promptInput.text.length;
    }
}
