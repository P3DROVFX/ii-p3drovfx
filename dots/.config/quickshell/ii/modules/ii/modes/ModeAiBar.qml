pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services.ai.blocks

/**
 * The assistant's seat above the Modes and Routines grids.
 *
 * One surface, five beats, and every verdict is said *inside* the element — the Notes
 * prompt bar's rule: no separate toast, no tooltip archaeology. It opens as a filled
 * search pill; while the agent works, the input gives its place to the same typing
 * shapes the chats use and the send toggle becomes a stop button (cancelling is the
 * same gesture that started it); when a definition lands, the toggle morphs into a
 * check, the pill names what was created, and the row folds; when the model answers
 * without writing — a refusal, a question back — the pill says so and offers the hop to
 * the chat that holds its words; and a refusal shakes the pill, prints the error on it,
 * and keeps the sentence editable, because the fastest fix for a refusal is editing the
 * request that caused it.
 *
 * Stateless on purpose: `phase` is owned by the app shell (it owns the run) and nothing
 * here writes it, nor `expanded` — the page binds that from the phase, so a success
 * folds the bar by the phase going back to idle. The animations key off the phase's
 * transitions, so the bar can be destroyed by a tab switch mid-run and reappear showing
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
    /// What the empty field invites ("Describe a mode…").
    property string placeholder: Translation.tr("Describe a mode or routine…")

    signal submitted(string text)
    signal stopRequested()
    signal dismissed()
    signal successFinished()
    signal openChatRequested()

    readonly property bool running: phase === "running"
    readonly property bool settled: phase === "success"
    readonly property bool failed: phase === "error"
    readonly property bool answered: phase === "answered"
    /// The verdict lives where the sentence was typed; the pill hides the input for it.
    readonly property bool verdict: settled || failed || answered
    /// Refusal and answer point at the transcript; success does not need to.
    readonly property bool needsChat: failed || answered
    readonly property bool canSend: promptInput.text.trim().length > 0 && !running

    implicitWidth: 300
    implicitHeight: expanded ? (needsChat ? 104 : 58) : 0

    Behavior on implicitHeight {
        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
    }

    onExpandedChanged: {
        if (expanded) {
            root.errorText = "";
            Qt.callLater(() => promptInput.forceActiveFocus());
        }
    }

    // A bar built mid-beat (a tab switch to the page that holds what was created) still
    // has to end the success beat, or the page would wait on it forever.
    Component.onCompleted: {
        if (phase === "success")
            successHoldTimer.restart();
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
        // Long enough to read the check and the name before the page moves on to what
        // the run created.
        interval: 1800
        onTriggered: root.successFinished()
    }

    ErrorShakeAnimation {
        id: errorShake
        target: barColumn
        distance: 14
    }

    ColumnLayout {
        id: barColumn
        anchors.fill: parent
        spacing: ClockStyle.gapSmall
        visible: root.expanded || opacity > 0.01
        opacity: root.expanded ? 1 : 0

        Behavior on opacity {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: ClockStyle.gapTiny
            spacing: ClockStyle.gapSmall

            Rectangle {
                id: pill
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                Layout.alignment: Qt.AlignVCenter
                radius: ClockStyle.pill(52)
                // The surface carries the state: the container pair of whichever beat
                // is playing — the field while listening or answering, primary for a
                // creation, the error pair for a refusal.
                color: root.settled ? ClockStyle.colPrimaryContainer
                    : root.failed ? ClockStyle.colErrorContainer
                    : promptInput.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField
                clip: true

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                MouseArea {
                    // Typing stays typing: a press on the pill's empty area returns the
                    // caret instead of eating the click.
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.IBeamCursor
                    onClicked: root.focusInput()
                }

                // Anchors, not Layout attached properties: the pill is a Rectangle, so
                // Layout.* here would be inert and the body would collapse to 0×0.
                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: ClockStyle.gapSmall
                        rightMargin: ClockStyle.gapLarge + 2
                    }
                    spacing: ClockStyle.gap

                    MaterialShapeWrappedMaterialSymbol {
                        text: root.settled ? "check" : root.failed ? "error" : "auto_awesome"
                        iconSize: 18
                        padding: 9
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: root.settled ? ClockStyle.colPrimary
                            : root.failed ? ClockStyle.colError : ClockStyle.colTertiaryContainer
                        colSymbol: root.settled ? ClockStyle.colOnPrimary
                            : root.failed ? ClockStyle.colOnError : ClockStyle.colOnTertiaryContainer
                        fill: 1
                        rotation: root.running ? 45 : 0
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

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
                            color: root.settled ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                            font.pixelSize: ClockStyle.textNormal + 1
                            clip: true
                            opacity: (!root.running && !root.verdict) ? 1 : 0

                            Behavior on opacity {
                                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
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
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.failed ? Translation.tr("Ask again — or say it differently") : root.placeholder
                                elide: Text.ElideRight
                                font: promptInput.font
                                color: root.failed ? ClockStyle.colOnErrorContainer : Appearance.colors.colOnLayer1Inactive
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
                                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                            }
                        }

                        // The verdict, printed on the pill itself: what was created,
                        // what the model said instead, or what broke.
                        StyledText {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal + 1
                            font.weight: Font.DemiBold
                            text: root.settled
                                ? (root.createdName.length > 0
                                    ? Translation.tr("Created “%1”").arg(root.createdName)
                                    : Translation.tr("Created"))
                                : (root.answered
                                    ? Translation.tr("Answered in the chat — nothing was created")
                                    : (root.errorText.length > 0
                                        ? root.errorText : Translation.tr("It did not work")))
                            color: root.settled ? ClockStyle.colOnPrimaryContainer
                                : root.failed ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSurface
                            visible: root.verdict
                            animateChange: true
                        }
                    }
                }
            }

            // The send toggle — one gesture that starts, stops and retries.
            RippleButton {
                id: sendToggle
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: root.running ? ClockStyle.radiusLarge : ClockStyle.pill(52)
                buttonRadiusPressed: ClockStyle.radiusSmall
                colBackground: root.settled ? ClockStyle.colPrimary
                    : (root.failed ? ClockStyle.colErrorContainer
                        : (root.running ? ClockStyle.colTertiaryContainer
                            : (root.canSend ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer)))
                colBackgroundHover: root.settled ? ClockStyle.colPrimaryHover
                    : (root.failed ? ClockStyle.colErrorContainerHover
                        : (root.running ? ClockStyle.colTertiaryContainerHover
                            : (root.canSend ? ClockStyle.colPrimaryHover : ClockStyle.colSecondaryContainerHover)))
                colRipple: root.settled ? ClockStyle.colPrimaryActive
                    : (root.failed ? Appearance.colors.colErrorContainerActive
                        : (root.running ? ClockStyle.colTertiaryContainerActive
                            : (root.canSend ? ClockStyle.colPrimaryActive : ClockStyle.colSecondaryContainerActive)))
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
                        : (root.settled ? "check" : (root.failed ? "refresh" : "arrow_upward"))
                    iconSize: ClockStyle.iconNormal
                    fill: 1
                    color: root.settled ? ClockStyle.colOnPrimary
                        : (root.failed ? ClockStyle.colOnErrorContainer
                            : (root.running ? ClockStyle.colOnTertiaryContainer
                                : (root.canSend ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer)))

                    Behavior on color {
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }
                }

                // The morph reads as one object changing mind: the glyph ducks and
                // relands when the toggle changes what it is for. One-shot.
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
                onStateNameChanged: {
                    if (!ClockStyle.reducedMotion)
                        morphAnim.restart();
                }

                StyledToolTip {
                    text: root.running ? Translation.tr("Stop the assistant")
                        : (root.failed && root.errorText.length > 0 ? root.errorText
                            : (root.settled ? Translation.tr("Done")
                                : Translation.tr("Send")))
                }
            }
        }

        // The hop the two quiet verdicts need: the model's own words (the refusal, the
        // answer, the error detail) live in the transcript, so the bar points there
        // instead of trying to paraphrase them.
        ClockChip {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: root.needsChat ? implicitHeight : 0
            visible: opacity > 0.01
            opacity: root.needsChat ? 1 : 0
            height_: 34
            symbol: "forum"
            label: root.failed
                ? Translation.tr("See what went wrong in the chat")
                : Translation.tr("Read the answer in the chat")
            selected: true
            onClicked: root.openChatRequested()

            Behavior on opacity {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }
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
