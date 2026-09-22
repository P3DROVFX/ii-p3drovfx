pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.lock

/**
 * A password prompt, inside the island: sudo, polkit, ssh or git.
 *
 * Two layouts over one input. The card is the full question - who asked, what for, the
 * field, the fingerprint row and the buttons. The pill is the same field in one row,
 * for a sudo typed in a terminal, where the command is already on screen.
 *
 * The field is a hidden TextInput drawn as the lockscreen's shape characters, so the
 * secret never reaches a visible Text. Nothing here stores it: it is handed to
 * AskpassService on submit and the field is cleared.
 *
 * It never takes the keyboard on its own; the island decides that (see NotchIsland's
 * `askpassFocused`) and hands it over through `focused`. Asking for it - a click, or
 * the pointer resting on the prompt - is `focusRequested`.
 */
Item {
    id: root

    /** The island hands these over; see NotchContent. */
    property var request: null
    property bool shown: false
    property bool focused: false
    property string style: "card"
    /** The island's fingerprint listener. */
    property QtObject fingerprint: null

    signal focusRequested

    readonly property bool pill: root.style === "pill"
    readonly property bool hasRequest: root.request !== null && root.request !== undefined
    readonly property string kind: root.hasRequest ? root.request.kind : "sudo"
    readonly property bool confirmOnly: root.hasRequest && root.request.confirm === true
    readonly property bool infoOnly: root.hasRequest && root.request.info === true
    readonly property bool echo: root.hasRequest && root.request.echo === true
    readonly property int attempt: root.hasRequest ? root.request.attempt : 0
    readonly property bool pending: root.hasRequest && root.request.pending === true
    readonly property int waiting: AskpassService.waitingCount

    // ── What the island should be ────────────────────────────────────────────
    readonly property real padding: root.pill ? 8 : 16
    readonly property real cardWidth: 400
    readonly property real pillWidth: 460
    readonly property real pillHeight: 52
    readonly property real contentTargetWidth: root.pill ? root.pillWidth : root.cardWidth
    readonly property real contentTargetHeight: root.pill ? root.pillHeight
        : cardColumn.implicitHeight + 2 * root.padding

    // ── Text ─────────────────────────────────────────────────────────────────
    readonly property string title: {
        switch (root.kind) {
        case "polkit":
            return Translation.tr("Authentication required");
        case "ssh":
            return Translation.tr("SSH");
        case "git":
            return Translation.tr("Git credentials");
        default:
            return Translation.tr("Administrator password");
        }
    }
    // Polkit fills its message in after the request starts, so it is read live.
    readonly property string subject: !root.hasRequest ? ""
        : root.kind === "polkit" ? PolkitService.cleanMessage
        : (root.request.command || root.request.windowTitle || "")
    /** The prompt as asked, less its trailing colon and whitespace. */
    readonly property string promptText: {
        if (!root.hasRequest)
            return "";
        const text = String(root.request.prompt ?? "").trim().replace(/:$/, "");
        // sudo's own prompt ("[sudo] password for …", grosshack's "Enter Password or
        // Place finger…") says less than the card around it already does.
        if (root.kind === "sudo")
            return Translation.tr("Password");
        return text || (root.echo ? Translation.tr("Answer") : Translation.tr("Password"));
    }

    // ── Fingerprint ──────────────────────────────────────────────────────────
    // Only a prompt that says so races a finger (pam_fprintd_grosshack's). fprintd's
    // state is system-wide, so without that a scan for anything else - or a system with
    // no reader at all - never shows up on a plain password prompt.
    readonly property string fingerprintPhase: root.fingerprint ? root.fingerprint.phase : "idle"
    /** A finger can still answer this prompt. */
    readonly property bool fingerprintActive: root.hasRequest && root.request.racesFinger === true
        && root.request.fingerprintOver !== true
    /** It could, and no longer can: grosshack gave up on the finger, pam_unix asks. */
    readonly property bool fingerprintFailed: root.hasRequest && root.request.fingerprintOver === true
    readonly property bool fingerprintRetry: root.fingerprintActive && root.fingerprintPhase === "retry"

    readonly property string statusText: {
        if (root.pending)
            return Translation.tr("Checking…");
        if (root.attempt > 0)
            return Translation.tr("Incorrect password, try again");
        if (root.fingerprintRetry)
            return root.fingerprint.hint !== "" ? root.fingerprint.hint
                : Translation.tr("Not recognised · try again");
        if (root.fingerprintActive)
            return Translation.tr("Touch the sensor or type your password");
        if (root.fingerprintFailed)
            return Translation.tr("Fingerprint not accepted · type your password");
        if (!root.focused)
            return Translation.tr("Click to type");
        return "";
    }
    readonly property bool statusIsError: !root.pending
        && (root.attempt > 0 || root.fingerprintRetry || root.fingerprintFailed)

    // ── Input ────────────────────────────────────────────────────────────────
    property bool revealed: false
    property bool capsLock: false

    function submit() {
        if (!root.hasRequest || root.pending)
            return;
        if (root.confirmOnly) {
            AskpassService.submit("");
            return;
        }
        // Enter on an empty field sends nothing: an empty password is a wasted attempt,
        // one faillock counts.
        if (input.text.length === 0)
            return;
        if (AskpassService.submit(input.text))
            input.text = "";
    }

    function cancel() {
        input.text = "";
        AskpassService.cancel();
    }

    function takeFocus() {
        if (root.confirmOnly)
            root.forceActiveFocus();
        else
            input.forceActiveFocus();
    }

    onFocusedChanged: {
        if (root.focused && root.shown)
            Qt.callLater(root.takeFocus);
    }
    onShownChanged: {
        if (root.focused && root.shown)
            Qt.callLater(root.takeFocus);
    }

    // A new request, or the same one answered wrong: a clean field, and a shake for the
    // wrong answer.
    readonly property int requestId: root.hasRequest ? root.request.id : 0
    onRequestIdChanged: {
        input.text = "";
        root.revealed = false;
        if (root.request)
            capsProbe.running = true;
    }
    onAttemptChanged: {
        input.text = "";
        if (root.attempt > 0)
            shake.restart();
    }
    // The field is disabled while an answer is checked, which takes its focus away.
    onPendingChanged: {
        if (!root.pending && root.focused && root.shown)
            Qt.callLater(root.takeFocus);
    }
    Component.onCompleted: {
        if (root.request)
            capsProbe.running = true;
    }

    // Caps Lock: read once per prompt, then followed from the keys typed - never polled.
    Process {
        id: capsProbe
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            id: capsOut
            onStreamFinished: root.capsLock = String(capsOut.text ?? "").split("\n")
                .some(line => line.trim() !== "" && line.trim() !== "0")
        }
    }

    function noteKey(event) {
        if (event.key === Qt.Key_CapsLock) {
            root.capsLock = !root.capsLock;
            return;
        }
        const text = event.text;
        if (text.length !== 1 || text.toUpperCase() === text.toLowerCase())
            return;
        const upper = text === text.toUpperCase();
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        root.capsLock = upper !== shift;
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.cancel();
            event.accepted = true;
        } else if (root.confirmOnly && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.submit();
            event.accepted = true;
        }
    }

    // Asking for the keyboard: a click anywhere on the prompt, or the pointer resting on
    // it. Neither steals it back once the user has clicked away - they only ask.
    HoverHandler {
        id: hover
    }
    Timer {
        interval: 300
        running: hover.hovered && !root.focused && root.shown
        onTriggered: root.focusRequested()
    }
    TapHandler {
        onTapped: {
            root.focusRequested();
            root.takeFocus();
        }
    }

    TextInput {
        id: input
        // Off screen: the characters are drawn by PasswordChars, or by `echoText` when
        // the answer is not a secret or the user asked to see it.
        x: -10000
        width: 10
        enabled: root.hasRequest && !root.confirmOnly && !root.pending
        echoMode: TextInput.Password
        passwordMaskDelay: 0
        onAccepted: root.submit()
        Keys.onPressed: event => {
            root.noteKey(event);
            if (event.key === Qt.Key_Escape) {
                root.cancel();
                event.accepted = true;
            } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                input.text = "";
                event.accepted = true;
            }
        }
    }

    transform: Translate {
        id: shakeOffset
    }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeOffset; property: "x"; to: -8; duration: 50 }
        NumberAnimation { target: shakeOffset; property: "x"; to: 8; duration: 70 }
        NumberAnimation { target: shakeOffset; property: "x"; to: -5; duration: 60 }
        NumberAnimation { target: shakeOffset; property: "x"; to: 3; duration: 50 }
        NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 40 }
    }

    // ── Pieces ───────────────────────────────────────────────────────────────
    component RequesterIcon: Item {
        id: iconBox
        property real size: 32
        implicitWidth: iconBox.size
        implicitHeight: iconBox.size
        readonly property string windowClass: root.hasRequest ? root.request.windowClass : ""

        IconImage {
            anchors.fill: parent
            visible: iconBox.windowClass !== ""
            source: iconBox.windowClass !== ""
                ? Quickshell.iconPath(AppSearch.guessIcon(iconBox.windowClass), "utilities-terminal") : ""
            implicitSize: iconBox.size
        }

        Rectangle {
            anchors.fill: parent
            visible: iconBox.windowClass === ""
            radius: width / 2
            color: Appearance.colors.colPrimaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.kind === "polkit" ? "shield_lock"
                    : (root.kind === "sudo" ? "admin_panel_settings" : "key")
                fill: 1
                iconSize: Math.round(parent.width * 0.58)
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
    }

    component Field: Rectangle {
        id: field
        property real fieldHeight: 44
        implicitHeight: field.fieldHeight
        radius: height / 2
        color: Appearance.colors.colLayer2
        border.width: input.activeFocus ? 2 : 1
        border.color: root.statusIsError ? Appearance.colors.colError
            : (input.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant)

        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(field)
        }

        readonly property bool plain: root.echo || root.revealed

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: fieldTrailing.left
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0
            text: root.focused ? root.promptText : Translation.tr("Click to type")
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        PasswordChars {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: fieldTrailing.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - 8
            clip: true
            visible: !field.plain && input.text.length > 0
            length: input.text.length
            selectionStart: input.selectionStart
            selectionEnd: input.selectionEnd
            cursorPosition: input.cursorPosition
        }

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: fieldTrailing.left
            anchors.verticalCenter: parent.verticalCenter
            visible: field.plain && input.text.length > 0
            // Only while the user asked to see it, or it was never a secret.
            text: field.plain ? input.text : ""
            elide: Text.ElideLeft
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer2
        }

        Row {
            id: fieldTrailing
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.capsLock && !root.echo
                implicitWidth: capsLabel.implicitWidth + 12
                implicitHeight: 22
                radius: height / 2
                color: Appearance.colors.colTertiaryContainer

                StyledText {
                    id: capsLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Caps")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnTertiaryContainer
                }
            }

            RippleButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.echo
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: {
                    root.revealed = !root.revealed;
                    root.focusRequested();
                    root.takeFocus();
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.revealed ? "visibility_off" : "visibility"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Card ─────────────────────────────────────────────────────────────────
    ColumnLayout {
        id: cardColumn
        visible: !root.pill
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RequesterIcon {
                size: 36
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.variableAxes: Appearance.font.variableAxes.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subject !== ""
                    text: root.subject
                    elide: Text.ElideMiddle
                    maximumLineCount: root.kind === "polkit" ? 2 : 1
                    wrapMode: root.kind === "polkit" ? Text.Wrap : Text.NoWrap
                    font.family: root.kind === "polkit" ? Appearance.font.family.main
                        : Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignTop
                visible: root.waiting > 0
                implicitWidth: waitingLabel.implicitWidth + 14
                implicitHeight: 22
                radius: height / 2
                color: Appearance.colors.colSecondaryContainer

                StyledText {
                    id: waitingLabel
                    anchors.centerIn: parent
                    text: `+${root.waiting}`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.confirmOnly && root.promptText !== ""
            text: root.hasRequest ? String(root.request.prompt ?? "").trim() : ""
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
        }

        Field {
            Layout.fillWidth: true
            visible: !root.confirmOnly
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            visible: root.statusText !== ""
            spacing: 6

            MaterialSymbol {
                visible: root.fingerprintActive || root.fingerprintFailed
                text: root.fingerprintFailed ? "fingerprint_off" : "fingerprint"
                iconSize: 18
                fill: 1
                color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: root.statusText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.fillWidth: true
            }

            DialogButton {
                visible: !root.infoOnly
                buttonText: root.confirmOnly ? Translation.tr("No") : Translation.tr("Cancel")
                onClicked: root.cancel()
            }

            DialogButton {
                buttonText: root.infoOnly ? Translation.tr("OK")
                    : (root.confirmOnly ? Translation.tr("Yes") : Translation.tr("Unlock"))
                enabled: !root.pending && (root.confirmOnly || input.text.length > 0)
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: root.submit()
            }
        }
    }

    // ── Pill ─────────────────────────────────────────────────────────────────
    RowLayout {
        visible: root.pill
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: root.padding
        spacing: 10

        RequesterIcon {
            size: 28
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            Layout.preferredWidth: 120
            Layout.alignment: Qt.AlignVCenter
            // One short word for an error: the pill has no room for the card's sentence.
            text: root.pending ? Translation.tr("Checking…")
                : !root.statusIsError ? (root.subject || root.title)
                : root.attempt > 0 ? Translation.tr("Wrong password")
                : root.fingerprintFailed ? Translation.tr("Use password")
                : Translation.tr("Not recognised")
            // The command is code; a status is a sentence.
            readonly property bool showsStatus: root.pending || root.statusIsError
            elide: showsStatus ? Text.ElideRight : Text.ElideMiddle
            font.family: showsStatus ? Appearance.font.family.main : Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colSubtext
        }

        Field {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            fieldHeight: 36
            visible: !root.confirmOnly
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            visible: root.fingerprintActive
            text: "fingerprint"
            iconSize: 20
            fill: 1
            color: root.fingerprintRetry ? Appearance.colors.colError : Appearance.colors.colPrimary
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.waiting > 0
            text: `+${root.waiting}`
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }

        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            onClicked: root.cancel()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }
    }
}
