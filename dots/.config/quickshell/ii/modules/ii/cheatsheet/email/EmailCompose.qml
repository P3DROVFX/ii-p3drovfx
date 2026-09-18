import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.modules.common.models

Item {
    id: root

    property bool isOpen: false
    property bool isAnimating: false
    signal closeRequested

    property var imageFilters: ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.svg"]
    property bool imageOnlyMode: false
    property bool linkDialogVisible: false
    property string linkTextVal: ""
    property string linkUrlVal: ""

    // Draft persistence - load on start
    Component.onCompleted: {
        toInput.text = EmailService.composeDraftTo || "";
        subjectInput.text = EmailService.composeDraftSubject;
        bodyInput.text = EmailService.composeDraftBody;
        root.attachments = EmailService.composeDraftAttachments || [];
    }

    // Save drafts on change
    Connections {
        target: toInput
        function onTextChanged() {
            EmailService.composeDraftTo = toInput.text;
        }
    }
    Connections {
        target: subjectInput
        function onTextChanged() {
            EmailService.composeDraftSubject = subjectInput.text;
        }
    }
    Connections {
        target: bodyInput
        function onTextChanged() {
            EmailService.composeDraftBody = bodyInput.text;
        }
    }
    onAttachmentsChanged: {
        EmailService.composeDraftAttachments = root.attachments;
    }

    // Alias to inputs
    property alias toText: toInput.text
    property alias subjectText: subjectInput.text
    property string lastError: ""
    property var attachments: []
    property string threadId: ""
    property string inReplyTo: ""

    // Send availability
    readonly property bool canSend: toInput.text.trim().length > 0 && subjectInput.text.trim().length > 0 && bodyInput.text.trim().length > 0 && !EmailService.sendingEmail

    function setReplyMode(to, subject, body, threadId = "", inReplyTo = "") {
        toInput.text = to;
        subjectInput.text = subject;
        bodyInput.text = body;
        root.threadId = threadId;
        root.inReplyTo = inReplyTo;
        root.attachments = [];
        bodyInput.cursorPosition = 0;
        bodyInput.forceActiveFocus();
    }

    // Block ALL mouse events from passing through to inbox below
    MouseArea {
        anchors.fill: parent
        z: 0
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
    }

    onIsOpenChanged: {
        if (isOpen) {
            isAnimating = true;
            background.x = root.width / 2;
            background.width = root.width / 2;
            background.y = 0;
            background.height = root.height;
            contentItem.opacity = 0;
            openAnim.start();
        }
    }

    SequentialAnimation {
        id: openAnim
        ParallelAnimation {
            NumberAnimation {
                target: background
                property: "x"
                to: 0
                duration: 380
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: background
                property: "width"
                to: root.width
                duration: 380
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: contentItem
                property: "opacity"
                to: 1
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction {
            script: isAnimating = false
        }
    }

    function startClose() {
        closeAnim.start();
    }

    SequentialAnimation {
        id: closeAnim
        ScriptAction {
            script: isAnimating = true
        }
        ParallelAnimation {
            NumberAnimation {
                target: background
                property: "x"
                to: root.width / 2
                duration: 300
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: background
                property: "width"
                to: root.width / 2
                duration: 300
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: contentItem
                property: "opacity"
                to: 0
                duration: 200
                easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: {
                isAnimating = false;
                root.closeRequested();
            }
        }
    }

    // ── Rich-text formatting on selection ────────────────────────────────────
    function applyFormat(fmt) {
        var edit = bodyInput;
        if (edit.selectionStart === edit.selectionEnd) {
            // No selection: toggle global font property as convenience
            if (fmt === "bold")
                edit.font.bold = !edit.font.bold;
            else if (fmt === "italic")
                edit.font.italic = !edit.font.italic;
            else if (fmt === "under")
                edit.font.underline = !edit.font.underline;
            else if (fmt === "strike")
                edit.font.strikeout = !edit.font.strikeout;
            return;
        }

        var start = edit.selectionStart;
        var end = edit.selectionEnd;
        var selectedText = edit.getText(start, end);

        var tag = "b";
        if (fmt === "italic")
            tag = "i";
        else if (fmt === "under")
            tag = "u";
        else if (fmt === "strike")
            tag = "s";

        // Remove and replace selected text with tags
        edit.remove(start, end);
        edit.insert(start, "<" + tag + ">" + selectedText + "</" + tag + ">");
        edit.select(start, start + selectedText.length);
        edit.forceActiveFocus();
    }

    // Alignment helpers (applied globally to the document)
    function setAlign(a) {
        bodyInput.horizontalAlignment = a;
    }

    // ── Send ─────────────────────────────────────────────────────────────────
    function doSend() {
        if (!canSend)
            return;
        root.lastError = "";
        // bodyInput.text is already HTML because textFormat is RichText
        EmailService.sendEmail(toInput.text.trim(), subjectInput.text.trim(), bodyInput.text, root.attachments, root.threadId, root.inReplyTo);
    }

    Connections {
        target: EmailService
        function onEmailSent(success, errorMsg) {
            if (success) {
                // Clear inputs and persistent draft
                toInput.text = "";
                subjectInput.text = "";
                bodyInput.text = "";
                root.attachments = [];
                EmailService.composeDraftTo = "";
                EmailService.composeDraftSubject = "";
                EmailService.composeDraftBody = "";
                EmailService.composeDraftAttachments = [];

                root.lastError = "";
                toastText.text = qsTr("Email sent successfully!");
                toastIcon.text = "check_circle";
                toastIcon.color = Appearance.m3colors.m3success;
                toastAnim.restart();
                closeDelayTimer.start();
            } else {
                root.lastError = errorMsg;
                toastText.text = errorMsg;
                toastIcon.text = "error";
                toastIcon.color = Appearance.m3colors.m3error;
                toastAnim.restart();
            }
        }
    }

    Timer {
        id: closeDelayTimer
        interval: 1500
        onTriggered: root.startClose()
    }

    // ── Internal QML File Picker Logic ──────────────────────────────────────
    property url currentFolder: Directories.home
    function toggleFilePicker(imageOnly) {
        root.imageOnlyMode = !!imageOnly;
        qmlFilePicker.visible = !qmlFilePicker.visible;
    }

    // ── Background + content ────────────────────────────────────────────────
    Rectangle {
        id: background
        anchors.fill: parent
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
        visible: root.isOpen || root.isAnimating
        opacity: root.isOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }

        topLeftRadius: Appearance.rounding.small
        topRightRadius: Appearance.rounding.verylarge
        bottomLeftRadius: Appearance.rounding.small
        bottomRightRadius: Appearance.rounding.large
        antialiasing: true
        clip: true

        Item {
            id: contentItem
            anchors.fill: parent
            anchors.margins: 12
            opacity: 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                // ── Header ───────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 12

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("New Draft")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    // Send button — disabled when fields empty or sending
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: 48
                        implicitWidth: sendRowLayout.implicitWidth + 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.canSend ? Appearance.colors.colPrimary : Appearance.colors.colLayer2Base
                        colBackgroundHover: root.canSend ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                        colRipple: Appearance.m3colors.m3primaryContainer
                        enabled: root.canSend
                        onClicked: root.doSend()

                        RowLayout {
                            id: sendRowLayout
                            anchors.centerIn: parent
                            spacing: 8

                            // Fix: use plain MaterialSymbol directly, no wrapper Item
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "send"
                                iconSize: 16
                                color: root.canSend ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                visible: !EmailService.sendingEmail
                            }

                            MaterialLoadingIndicator {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 16
                                implicitHeight: 16
                                color: Appearance.colors.colOnPrimary
                                loading: EmailService.sendingEmail
                                visible: EmailService.sendingEmail
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: qsTr("Send")
                                color: root.canSend ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                        }
                    }

                    RippleButton {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer4Base
                        colBackgroundHover: Appearance.colors.colLayer4Hover
                        colRipple: Appearance.colors.colLayer4Active
                        onClicked: root.startClose()

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 20
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                // ── To field ─────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    spacing: 4

                    Rectangle {
                        Layout.preferredWidth: toLabelText.implicitWidth + 48
                        Layout.preferredHeight: 64
                        color: Appearance.colors.colLayer2Base
                        topLeftRadius: Appearance.rounding.verylarge
                        bottomLeftRadius: Appearance.rounding.verylarge
                        topRightRadius: Appearance.rounding.small
                        bottomRightRadius: Appearance.rounding.small
                        antialiasing: true
                        StyledText {
                            id: toLabelText
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            text: qsTr("To")
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        color: Appearance.colors.colLayer2Base
                        topLeftRadius: Appearance.rounding.small
                        bottomLeftRadius: Appearance.rounding.small
                        topRightRadius: Appearance.rounding.verylarge
                        bottomRightRadius: Appearance.rounding.verylarge
                        antialiasing: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.IBeamCursor
                            onClicked: toInput.forceActiveFocus()
                        }

                        TextInput {
                            id: toInput
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                            clip: true

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Add recipients")
                                color: Appearance.colors.colOnSurfaceVariant
                                visible: toInput.text.length === 0 && !toInput.activeFocus
                            }
                        }
                    }
                }

                // ── Subject field ─────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    spacing: 4

                    Rectangle {
                        Layout.preferredWidth: subjectLabelText.implicitWidth + 48
                        Layout.preferredHeight: 64
                        color: Appearance.colors.colLayer2Base
                        topLeftRadius: Appearance.rounding.verylarge
                        bottomLeftRadius: Appearance.rounding.verylarge
                        topRightRadius: Appearance.rounding.small
                        bottomRightRadius: Appearance.rounding.small
                        antialiasing: true
                        StyledText {
                            id: subjectLabelText
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            text: qsTr("Subject")
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        color: Appearance.colors.colLayer2Base
                        topLeftRadius: Appearance.rounding.small
                        bottomLeftRadius: Appearance.rounding.small
                        topRightRadius: Appearance.rounding.verylarge
                        bottomRightRadius: Appearance.rounding.verylarge
                        antialiasing: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.IBeamCursor
                            onClicked: subjectInput.forceActiveFocus()
                        }

                        TextInput {
                            id: subjectInput
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                            clip: true

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Subject...")
                                color: Appearance.colors.colOnSurfaceVariant
                                visible: subjectInput.text.length === 0 && !subjectInput.activeFocus
                            }
                        }
                    }
                }

                // ── Body area ─────────────────────────────────────────────────
                Rectangle {
                    id: bodyRect
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.verylarge
                    color: Appearance.colors.colLayer2Base
                    clip: true

                    // Full-area mouse handler: clicking ANYWHERE in the rectangle
                    // focuses the editor — even in padding areas above the text.
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.IBeamCursor
                        // Only forward clicks that land outside the TextEdit itself
                        onClicked: bodyInput.forceActiveFocus()
                        // Don't steal events from the TextEdit's own mouse handling
                        propagateComposedEvents: true
                    }

                    // Placeholder — shown over the whole rect until user starts typing
                    StyledText {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.topMargin: 20
                        anchors.leftMargin: 20
                        text: qsTr("Write your message here...")
                        color: Appearance.colors.colOnSurfaceVariant
                        visible: bodyInput.text.length === 0 && !bodyInput.activeFocus
                        // z above flickable so it's never clipped
                        z: 2
                    }

                    Flickable {
                        id: bodyFlickable
                        anchors.fill: parent
                        anchors.margins: 20
                        anchors.bottomMargin: 88  // space for toolbar
                        contentWidth: width
                        contentHeight: Math.max(height, bodyInput.implicitHeight)
                        clip: false  // var placeholder show through

                        TextEdit {
                            id: bodyInput
                            width: parent.width
                            height: Math.max(parent.height, implicitHeight)
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.RichText
                            persistentSelection: true
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                            selectedTextColor: Appearance.colors.colOnPrimary
                            selectionColor: Appearance.colors.colPrimary

                            // HoverHandler to set correct cursor inside the TextEdit
                            HoverHandler {
                                cursorShape: Qt.IBeamCursor
                            }
                        }

                        TouchpadScrollHandler {
                            flickable: bodyFlickable
                        }
                    }

                    // Attachments preview chips
                    RowLayout {
                        id: attachmentsRow
                        anchors.bottom: toolbar.top
                        anchors.bottomMargin: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Repeater {
                            model: root.attachments
                            delegate: MouseArea {
                                id: attChip
                                width: chipContent.implicitWidth + 24
                                height: 36
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                // Hover/Active background
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.full
                                    color: attChip.pressed ? Appearance.colors.colSecondaryActive : attChip.containsMouse ? Appearance.colors.colSecondaryHover : Appearance.colors.colSecondaryContainer
                                    border.width: 1
                                    border.color: Appearance.colors.colOutlineVariant

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 150
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                RowLayout {
                                    id: chipContent
                                    anchors.centerIn: parent
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "attach_file"
                                        iconSize: 16
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }

                                    StyledText {
                                        text: modelData.substring(modelData.lastIndexOf('/') + 1)
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnSecondaryContainer
                                        Layout.maximumWidth: 150
                                        elide: Text.ElideRight
                                    }

                                    // Remove button
                                    MouseArea {
                                        id: removeBtn
                                        width: 24
                                        height: 24
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var newAtts = root.attachments.slice();
                                            newAtts.splice(index, 1);
                                            root.attachments = newAtts;
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Appearance.rounding.full
                                            color: removeBtn.pressed ? Appearance.colors.colLayer4Active : removeBtn.containsMouse ? Appearance.colors.colLayer4Hover : "transparent"

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "close"
                                                iconSize: 14
                                                color: Appearance.colors.colOnSecondaryContainer
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Floating Toolbar ──────────────────────────────────────
                    Rectangle {
                        id: toolbar
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        height: 64
                        width: toolbarRow.implicitWidth + 48
                        radius: Appearance.rounding.full
                        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
                        z: 3

                        // Catch mouse events on the toolbar background so they don't
                        // propagate to the bodyRect focus MouseArea.
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                            onClicked: mouse => mouse.accepted = true
                            onPressed: mouse => mouse.accepted = true
                        }

                        RowLayout {
                            id: toolbarRow
                            anchors.centerIn: parent
                            spacing: 8

                            // Group 1 — text style (act on selection if any, else toggle global)
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.applyFormat("bold")
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "format_bold"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.applyFormat("italic")
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "format_italic"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.applyFormat("under")
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "format_underlined"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.applyFormat("strike")
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "strikethrough_s"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            Rectangle {
                                width: 1
                                height: 32
                                color: Appearance.colors.colOutlineVariant
                            }

                            // Group 2 — alignment
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                toggled: bodyInput.horizontalAlignment === TextEdit.AlignLeft
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                onClicked: root.setAlign(TextEdit.AlignLeft)
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "format_align_left"
                                    iconSize: 18
                                    color: parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                toggled: bodyInput.horizontalAlignment === TextEdit.AlignHCenter
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                onClicked: root.setAlign(TextEdit.AlignHCenter)
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "format_align_center"
                                    iconSize: 18
                                    color: parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                toggled: bodyInput.horizontalAlignment === TextEdit.AlignRight
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                onClicked: root.setAlign(TextEdit.AlignRight)
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "format_align_right"
                                    iconSize: 18
                                    color: parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            Rectangle {
                                width: 1
                                height: 32
                                color: Appearance.colors.colOutlineVariant
                            }

                            // Group 3 — attach / image
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.toggleFilePicker(false)
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "attach_file"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.toggleFilePicker(true)
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "image"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            Rectangle {
                                width: 1
                                height: 32
                                color: Appearance.colors.colOutlineVariant
                            }

                            // Group 4 — link (placeholder)
                            RippleButton {
                                implicitHeight: 36
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: {
                                    var edit = bodyInput;
                                    var selected = edit.getText(edit.selectionStart, edit.selectionEnd);
                                    root.linkTextVal = selected;
                                    root.linkUrlVal = "https://";
                                    root.linkDialogVisible = true;
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "link"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Feedback Toast ───────────────────────────────────────────────────────
    Rectangle {
        id: feedbackToast
        width: toastContent.implicitWidth + 32
        height: 48
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer4Base
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: yOffset
        property int yOffset: -60
        opacity: 0
        z: 99

        RowLayout {
            id: toastContent
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                id: toastIcon
                iconSize: 20
            }
            StyledText {
                id: toastText
                color: Appearance.colors.colOnSurface
            }
        }

        SequentialAnimation {
            id: toastAnim
            ParallelAnimation {
                NumberAnimation {
                    target: feedbackToast
                    property: "yOffset"
                    to: 20
                    duration: 300
                    easing.type: Easing.OutBack
                }
                NumberAnimation {
                    target: feedbackToast
                    property: "opacity"
                    to: 1
                    duration: 200
                }
            }
            PauseAnimation {
                duration: 3000
            }
            ParallelAnimation {
                NumberAnimation {
                    target: feedbackToast
                    property: "yOffset"
                    to: -60
                    duration: 300
                    easing.type: Easing.InBack
                }
                NumberAnimation {
                    target: feedbackToast
                    property: "opacity"
                    to: 0
                    duration: 200
                }
            }
        }
    }

    // ── Internal File Picker Overlay ──────────────────────────────────────────
    Rectangle {
        id: qmlFilePicker
        anchors.fill: parent
        color: Appearance.m3colors.m3surfaceContainerHigh
        visible: false
        z: 100
        topLeftRadius: Appearance.rounding.small
        topRightRadius: Appearance.rounding.verylarge
        bottomLeftRadius: Appearance.rounding.small
        bottomRightRadius: Appearance.rounding.large
        antialiasing: true
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ── Header ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                spacing: 12

                Rectangle {
                    width: 36
                    height: 36
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.imageOnlyMode ? "image" : "attach_file"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                StyledText {
                    text: root.imageOnlyMode ? qsTr("Select Image") : qsTr("Select Attachment")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    Layout.fillWidth: true
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer4Base
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: qmlFilePicker.visible = false

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            // ── Quick Access Buttons ─────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        {
                            icon: "home",
                            label: qsTr("Home"),
                            path: Directories.home
                        },
                        {
                            icon: "description",
                            label: qsTr("Documents"),
                            path: Directories.documents
                        },
                        {
                            icon: "download",
                            label: qsTr("Downloads"),
                            path: Directories.downloads
                        },
                        {
                            icon: "image",
                            label: qsTr("Pictures"),
                            path: Directories.pictures
                        }
                    ]
                    delegate: RippleButton {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: {
                            var currentPath = FileUtils.trimFileProtocol(localFolderModel.folder.toString());
                            var btnPath = FileUtils.trimFileProtocol(modelData.path);
                            return currentPath === btnPath ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2Base;
                        }
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active

                        onClicked: {
                            localFolderModel.folder = Qt.resolvedUrl("file://" + FileUtils.trimFileProtocol(modelData.path));
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: 14
                                color: {
                                    var currentPath = FileUtils.trimFileProtocol(localFolderModel.folder.toString());
                                    var btnPath = FileUtils.trimFileProtocol(modelData.path);
                                    return currentPath === btnPath ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant;
                                }
                            }

                            StyledText {
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: {
                                    var currentPath = FileUtils.trimFileProtocol(localFolderModel.folder.toString());
                                    var btnPath = FileUtils.trimFileProtocol(modelData.path);
                                    return currentPath === btnPath ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant;
                                }
                            }
                        }
                    }
                }
            }

            // ── Address Bar ──────────────────────────────────────────────────
            AddressBar {
                id: pickerAddressBar
                Layout.fillWidth: true
                directory: FileUtils.trimFileProtocol(localFolderModel.folder)
                onNavigateToDirectory: path => {
                    localFolderModel.folder = Qt.resolvedUrl(path.startsWith("/") ? "file://" + path : path);
                }
                radius: Appearance.rounding.normal
            }

            // ── File List ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.large
                color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1 : Appearance.m3colors.m3surfaceContainerLow
                clip: true

                ListView {
                    id: localFileView
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 2
                    interactive: contentHeight > height
                    model: FolderListModelWithHistory {
                        id: localFolderModel
                        folder: "file://" + FileUtils.trimFileProtocol(Directories.home)
                        showDirs: true
                        showDotAndDotDot: false
                        sortField: FolderListModel.Name
                        nameFilters: root.imageOnlyMode ? root.imageFilters : []
                    }

                    // Empty state
                    StyledText {
                        anchors.centerIn: parent
                        text: qsTr("This folder is empty")
                        color: Appearance.colors.colOnSurfaceVariant
                        visible: localFileView.count === 0
                    }

                    delegate: MouseArea {
                        id: fileDelegate
                        width: localFileView.width
                        height: 48
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        // Capture FolderListModel context properties into local
                        // properties — context props work in QML bindings but
                        // are inaccessible inside imperative JS signal handlers.
                        // Use filePath (plain string) to avoid QUrl normalization
                        // issues; mirrors the working quick-access button pattern.
                        property bool capturedIsDir: fileIsDir
                        property string capturedPath: filePath  // absolute path, no file://
                        property string capturedName: fileName

                        onClicked: {
                            if (fileDelegate.capturedIsDir) {
                                localFolderModel.folder = "file://" + fileDelegate.capturedPath;
                            } else {
                                var path = fileDelegate.capturedPath;
                                if (!root.attachments.includes(path)) {
                                    var newAtts = root.attachments.slice();
                                    newAtts.push(path);
                                    root.attachments = newAtts;
                                }
                                qmlFilePicker.visible = false;
                            }
                        }

                        // ── Hover/Press background ──
                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: fileDelegate.pressed ? Appearance.colors.colLayer2Active : fileDelegate.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // ── Content row ──
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            // Modern folder/file icon container
                            Rectangle {
                                width: 34
                                height: 34
                                radius: Appearance.rounding.small
                                color: fileDelegate.capturedIsDir ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: fileDelegate.capturedIsDir ? "folder" : getFileIcon(fileDelegate.capturedName)
                                    iconSize: 18
                                    color: fileDelegate.capturedIsDir ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary

                                    function getFileIcon(name) {
                                        var ext = name.split('.').pop().toLowerCase();
                                        if (["jpg", "jpeg", "png", "gif", "svg", "webp", "bmp"].includes(ext))
                                            return "image";
                                        if (["mp4", "mkv", "avi", "mov", "webm"].includes(ext))
                                            return "movie";
                                        if (["mp3", "flac", "ogg", "wav", "aac", "m4a"].includes(ext))
                                            return "audio_file";
                                        if (["pdf"].includes(ext))
                                            return "picture_as_pdf";
                                        if (["zip", "tar", "gz", "7z", "rar", "xz"].includes(ext))
                                            return "folder_zip";
                                        if (["doc", "docx", "odt", "txt", "md", "rtf"].includes(ext))
                                            return "article";
                                        if (["xls", "xlsx", "csv", "ods"].includes(ext))
                                            return "table_chart";
                                        if (["ppt", "pptx", "odp"].includes(ext))
                                            return "slideshow";
                                        if (["py", "js", "qml", "sh", "html", "css", "json", "xml"].includes(ext))
                                            return "code";
                                        return "description";
                                    }
                                }
                            }

                            // File name
                            StyledText {
                                text: fileDelegate.capturedName
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }

                            // File size for files
                            StyledText {
                                visible: !fileDelegate.capturedIsDir
                                text: {
                                    if (typeof fileSize !== "undefined" && fileSize >= 0) {
                                        var s = fileSize;
                                        if (s < 1024)
                                            return s + " B";
                                        if (s < 1048576)
                                            return (s / 1024).toFixed(1) + " KB";
                                        if (s < 1073741824)
                                            return (s / 1048576).toFixed(1) + " MB";
                                        return (s / 1073741824).toFixed(1) + " GB";
                                    }
                                    return "";
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            // Chevron for directories
                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: 16
                                color: Appearance.colors.colOnSurfaceVariant
                                visible: fileDelegate.capturedIsDir
                            }
                        }
                    }
                    ScrollBar.vertical: StyledScrollBar {}

                    TouchpadScrollHandler {
                        flickable: localFileView
                    }
                }
            }

            // ── Footer tip ───────────────────────────────────────────────────
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                MaterialSymbol {
                    text: "info"
                    iconSize: 14
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: qsTr("Click a folder to enter, or a file to attach it")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    // ── Link Insertion Dialog ────────────────────────────────────────────────
    Rectangle {
        id: linkDialogOverlay
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        visible: root.linkDialogVisible
        z: 200

        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 400)
            height: linkCol.implicitHeight + 32
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.color: Appearance.colors.colOutlineVariant
            border.width: 1

            ColumnLayout {
                id: linkCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                StyledText {
                    text: qsTr("Insert Link")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true
                    StyledText {
                        text: qsTr("Text to display")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1Base
                        border.color: textInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                        border.width: textInput.activeFocus ? 2 : 1
                        TextInput {
                            id: textInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: Appearance.colors.colOnSurface
                            text: root.linkTextVal
                            onTextChanged: root.linkTextVal = text
                        }
                    }
                }

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true
                    StyledText {
                        text: qsTr("To what URL should this link go?")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1Base
                        border.color: urlInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                        border.width: urlInput.activeFocus ? 2 : 1
                        TextInput {
                            id: urlInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: Appearance.colors.colOnSurface
                            text: root.linkUrlVal
                            onTextChanged: root.linkUrlVal = text
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 12
                    Item { Layout.fillWidth: true }

                    RippleButton {
                        implicitWidth: 80
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.linkDialogVisible = false
                        StyledText {
                            anchors.centerIn: parent
                            text: qsTr("Cancel")
                            color: Appearance.colors.colPrimary
                            font.weight: Font.Bold
                        }
                    }

                    RippleButton {
                        implicitWidth: 80
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: {
                            root.linkDialogVisible = false;
                            var edit = bodyInput;
                            var start = edit.selectionStart;
                            var end = edit.selectionEnd;
                            var txt = root.linkTextVal || root.linkUrlVal;
                            var url = root.linkUrlVal;
                            var htmlLink = "<a href=\"" + url + "\">" + txt + "</a>";
                            edit.remove(start, end);
                            edit.insert(start, htmlLink);
                            edit.forceActiveFocus();
                        }
                        StyledText {
                            anchors.centerIn: parent
                            text: qsTr("OK")
                            color: Appearance.colors.colOnPrimary
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }
    }
}
