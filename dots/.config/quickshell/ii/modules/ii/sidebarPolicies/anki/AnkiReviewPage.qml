pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A study session: app bar (back, deck, card actions), the three queue counts with the
 * current card's queue lifted, the question pane, the answer pane under it once shown,
 * and the rating slot. Anki's scheduler decides everything; this only draws the card
 * the daemon hands over and sends back the rating.
 *
 * Keys: Space/Enter shows the answer, then rates Good; 1–4 rate; Z/Ctrl+Z undoes;
 * R replays audio; M marks; Esc goes back.
 */
Item {
    id: root

    readonly property var card: Anki.card
    readonly property bool revealed: Anki.revealed
    readonly property bool finished: !Anki.cardBusy && Anki.card === null
    readonly property bool hasTypeIn: !!root.card?.typeIn
    /// Cloze answers repeat the whole text, revealed: they replace the question.
    readonly property bool answerReplacesQuestion: root.revealed && !(root.card?.answerSplit ?? true)

    property bool showMore: false

    signal backRequested()

    function revealOrGood() {
        if (!root.card)
            return;
        if (!root.revealed)
            Anki.reveal(typeField.text);
        else
            Anki.answer(3);
    }

    Keys.onPressed: event => {
        if (typeField.input.activeFocus && event.key !== Qt.Key_Escape)
            return;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (event.key === Qt.Key_Escape) {
            root.backRequested();
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.revealOrGood();
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4 && !ctrl) {
            if (root.revealed)
                Anki.answer(event.key - Qt.Key_1 + 1);
        } else if (event.key === Qt.Key_Z) {
            Anki.undo();
        } else if (event.key === Qt.Key_R) {
            Anki.playSide(root.revealed);
        } else if (event.key === Qt.Key_M) {
            Anki.cardAction("mark", {});
        } else {
            return;
        }
        event.accepted = true;
    }

    Connections {
        target: Anki
        function onCardSerialChanged() {
            typeField.text = "";
            cardFlick.contentY = 0;
            if (root.hasTypeIn)
                Qt.callLater(() => typeField.input.forceActiveFocus());
            else
                root.forceActiveFocus();
            if (!ClockStyle.reducedMotion)
                cardEntrance.restart();
        }
        function onRevealedChanged() {
            if (Anki.revealed) {
                root.forceActiveFocus();
                Qt.callLater(() => {
                    if (answerPane.visible && !root.answerReplacesQuestion)
                        cardFlick.contentY = Math.max(0, Math.min(answerPane.y - ClockStyle.gap, cardFlick.contentHeight - cardFlick.height));
                });
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: ClockStyle.gapSmall

        // ── App bar ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapTiny

            AnkiIconButton {
                symbol: "arrow_back"
                tooltip: Translation.tr("Decks (Esc)")
                onClicked: root.backRequested()
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: ClockStyle.gapTiny
                spacing: -2
                StyledText {
                    Layout.fillWidth: true
                    text: (root.card?.deck ?? Anki.studyDeck?.fullName ?? "").split("::").pop()
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.card ? root.card.model : ""
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }

            AnkiIconButton {
                symbol: "undo"
                tooltip: Translation.tr("Undo (Z)")
                onClicked: Anki.undo()
            }
            AnkiIconButton {
                visible: !!root.card
                symbol: "flag"
                toggled: (root.card?.flag ?? 0) !== 0
                tooltip: Translation.tr("Flag")
                onClicked: Anki.cardAction("flag", { "flag": (root.card?.flag ?? 0) === 0 ? 1 : 0 })
            }
            AnkiIconButton {
                visible: !!root.card
                symbol: "more_vert"
                toggled: root.showMore
                tooltip: Translation.tr("More")
                onClicked: root.showMore = !root.showMore
            }
        }

        // Card actions, folded under "more" so the bar stays quiet.
        Item {
            id: moreSlot
            readonly property bool open: root.showMore && !!root.card
            Layout.fillWidth: true
            Layout.preferredHeight: moreSlot.open ? moreFlow.implicitHeight : 0
            visible: Layout.preferredHeight > 0.5
            clip: true
            Behavior on Layout.preferredHeight {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }
            Flow {
                id: moreFlow
                width: parent.width
                opacity: moreSlot.open ? 1 : 0
                Behavior on opacity {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
                spacing: ClockStyle.gapTiny
                Repeater {
                    model: [
                        { "symbol": "star", "label": root.card?.marked ? Translation.tr("Unmark") : Translation.tr("Mark"), "cmd": "mark", "args": {} },
                        { "symbol": "visibility_off", "label": Translation.tr("Bury card"), "cmd": "bury", "args": {} },
                        { "symbol": "hide_source", "label": Translation.tr("Bury note"), "cmd": "bury", "args": { "note": true } },
                        { "symbol": "pause_circle", "label": Translation.tr("Suspend"), "cmd": "suspend", "args": {} }
                    ]
                    AnkiChip {
                        required property var modelData
                        symbol: modelData.symbol
                        label: modelData.label
                        onClicked: {
                            if (modelData.cmd !== "mark")
                                root.showMore = false;
                            Anki.cardAction(modelData.cmd, modelData.args);
                        }
                    }
                }
            }
        }

        // ── Queue counts ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: !root.finished
            spacing: ClockStyle.gapTiny

            Repeater {
                model: [
                    { "key": "new", "label": Translation.tr("New"), "col": ClockStyle.colPrimaryContainer, "on": ClockStyle.colOnPrimaryContainer },
                    { "key": "learn", "label": Translation.tr("Learning"), "col": ClockStyle.colTertiaryContainer, "on": ClockStyle.colOnTertiaryContainer },
                    { "key": "review", "label": Translation.tr("Review"), "col": ClockStyle.colSecondaryContainer, "on": ClockStyle.colOnSecondaryContainer }
                ]

                AnkiCountPill {
                    required property var modelData
                    Layout.fillWidth: true
                    label: modelData.label
                    value: root.card?.counts?.[modelData.key] ?? 0
                    current: root.card?.queue === modelData.key
                    colActive: modelData.col
                    colOnActive: modelData.on
                }
            }
        }

        // ── Card ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.finished

            StyledFlickable {
                id: cardFlick
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: cardColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: cardColumn
                    width: cardFlick.width
                    spacing: ClockStyle.gapSmall

                    opacity: 1
                    transform: Translate {
                        id: cardRise
                    }

                    // Question (or the revealed cloze, which repeats it)
                    Rectangle {
                        id: questionPane
                        Layout.fillWidth: true
                        // Short cards sit in a pane that fills the view; long ones grow.
                        Layout.preferredHeight: Math.max(questionColumn.implicitHeight + ClockStyle.cardPadding * 2,
                            root.revealed && !root.answerReplacesQuestion ? 0 : cardFlick.height - (typePane.visible ? typePane.height + ClockStyle.gapSmall : 0))
                        radius: ClockStyle.radiusCard
                        color: ClockStyle.colPane

                        ColumnLayout {
                            id: questionColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: ClockStyle.cardPadding
                            }
                            spacing: ClockStyle.gapSmall

                            AnkiCardText {
                                id: questionText
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: questionText.fitWidth(questionColumn.width)
                                body: root.answerReplacesQuestion ? (root.card?.answer ?? "") : (root.card?.question ?? "")
                                css: root.card?.css ?? ""
                            }

                            AnkiAudioRow {
                                Layout.alignment: Qt.AlignHCenter
                                clips: root.card?.audioQ ?? []
                            }
                        }
                    }

                    // Answer
                    Rectangle {
                        id: answerPane
                        Layout.fillWidth: true
                        visible: root.revealed && !root.answerReplacesQuestion
                        implicitHeight: answerColumn.implicitHeight + ClockStyle.cardPadding * 2
                        radius: ClockStyle.radiusCard
                        color: ClockStyle.colSurfaceHigh

                        ColumnLayout {
                            id: answerColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: ClockStyle.cardPadding
                            }
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                text: Translation.tr("Answer")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: ClockStyle.colOnSurfaceVariant
                            }

                            AnkiCardText {
                                id: answerText
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: answerText.fitWidth(answerColumn.width)
                                body: root.card?.answer ?? ""
                                css: root.card?.css ?? ""
                            }

                            AnkiAudioRow {
                                Layout.alignment: Qt.AlignHCenter
                                clips: root.card?.audioA ?? []
                            }
                        }
                    }

                    // Type-in answer
                    ClockFormField {
                        id: typePane
                        Layout.fillWidth: true
                        visible: root.hasTypeIn && !root.revealed
                        symbol: "keyboard"
                        shapeKind: MaterialShape.Shape.Cookie7Sided
                        caption: Translation.tr("Type the answer")
                        placeholder: Translation.tr("Enter to check")
                        onAccepted: Anki.reveal(typePane.text)
                    }
                }
            }

        }

        // ── Finished ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.finished

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                spacing: ClockStyle.gapLarge

                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: "celebration"
                    shape: "Sunny"
                    shapeSize: ClockStyle.emptyShapeSmall
                    colShape: ClockStyle.colPrimaryContainer
                    colIcon: ClockStyle.colOnPrimaryContainer
                    title: Translation.tr("All done for now")
                    subtitle: Translation.tr("This deck has nothing else due today. Come back later for the cards in learning.")
                }

                ClockSheetAction {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: false
                    Layout.preferredWidth: 220
                    primary: true
                    label: Translation.tr("Back to decks")
                    symbol: "arrow_back"
                    onClicked: root.backRequested()
                }
            }
        }

        AnkiRatingBar {
            Layout.fillWidth: true
            visible: !root.finished
            revealed: root.revealed
            busy: Anki.cardBusy
            labels: root.card?.labels ?? ["", "", "", ""]
            onRevealRequested: Anki.reveal(typePane.text)
            onRated: ease => Anki.answer(ease)
        }
    }

    property alias typeField: typePane

    ParallelAnimation {
        id: cardEntrance
        NumberAnimation {
            target: cardColumn
            property: "opacity"
            from: 0
            to: 1
            duration: ClockStyle.motionEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        NumberAnimation {
            target: cardRise
            property: "y"
            from: ClockStyle.enterOffset
            to: 0
            duration: ClockStyle.motionEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
}
