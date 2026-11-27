import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions

Item {
    id: root

    // Input properties
    property string subject: ""
    property string senderFull: ""
    property string icon: "person"
    property string date: ""
    property string body: ""
    property bool loadingBody: false
    property string htmlPath: ""
    property var attachments: null
    property string messageId: ""
    property string threadId: ""
    property string labelsString: ""
    property var detectedMeetings: []
    property var detectedPhones: []
    property var detectedCodes: []

    property string displayBody: ""
    property string quotedBody: ""
    property bool hasQuotedBody: false
    property bool showQuoted: false

    function processBody(rawBody) {
        if (!rawBody) {
            root.displayBody = "";
            root.quotedBody = "";
            root.hasQuotedBody = false;
            return;
        }

        var patterns = [/--- .* wrote ---/i, /Em .* escreveu:/i, /On .* wrote:/i, /<div class="gmail_quote"/i, /<blockquote>/i];

        var splitIndex = -1;
        for (var i = 0; i < patterns.length; i++) {
            var match = rawBody.match(patterns[i]);
            if (match) {
                if (splitIndex === -1 || match.index < splitIndex) {
                    splitIndex = match.index;
                }
            }
        }

        var emailRegex = /([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(?![^<]*>|[^<>]*<\/a>)/g;

        if (splitIndex !== -1) {
            var main = rawBody.substring(0, splitIndex).trim();
            var quoted = rawBody.substring(splitIndex).trim();
            root.displayBody = main.replace(emailRegex, '<a href="copy:$1">$1</a>');
            root.quotedBody = quoted.replace(emailRegex, '<a href="copy:$1">$1</a>');
            root.hasQuotedBody = true;
        } else {
            root.displayBody = rawBody.replace(emailRegex, '<a href="copy:$1">$1</a>');
            root.quotedBody = "";
            root.hasQuotedBody = false;
        }
    }

    onBodyChanged: {
        processBody(root.body);
        updateDetections();
    }

    readonly property string processedBody: root.displayBody

    // Read by the cheatsheet: no tab swipe while the pointer is in the email
    // body or a text selection drag is running.
    readonly property bool locksHorizontalSwipe: readingPaneHover.hovered || bodyText.interacting || quotedText.interacting

    function updateDetections() {
        var res = EmailDetections.detectAll(root.body, root.subject);
        root.detectedMeetings = res.meetings;
        root.detectedPhones = res.phones;
        root.detectedCodes = res.codes;
    }

    function getCustomLabels(str) {
        if (!str || str === "")
            return [];
        var systemLabels = ["UNREAD", "SPAM", "TRASH", "SENT", "STARRED", "IMPORTANT", "DRAFT", "CATEGORY_PERSONAL", "CATEGORY_SOCIAL", "CATEGORY_PROMOTIONS", "CATEGORY_UPDATES", "CATEGORY_FORUMS"];
        var result = [];

        var list = str.split(",");

        for (var i = 0; i < list.length; i++) {
            var id = list[i].trim();
            if (!id || id === "INBOX")
                continue;

            if (systemLabels.indexOf(id) === -1) {
                var found = false;
                for (var j = 0; j < EmailService.labels.count; j++) {
                    var l = EmailService.labels.get(j);
                    if (l.id === id) {
                        result.push(l.name);
                        found = true;
                        break;
                    }
                }
                if (!found)
                    result.push(id);
            }
        }
        return result;
    }

    signal closeStarted
    signal closeRequested
    signal replyRequested(string to, string subject, string body, string threadId, string inReplyTo)

    property real startX: 0
    property real startY: 0
    property real startWidth: 0
    property real startHeight: 0
    property bool isAnimating: false
    property bool isClosing: false

    // Ghost element positions (for return animation)
    property real cardIconX: 0
    property real cardIconY: 0
    property real cardIconW: 0
    property real cardIconH: 0
    property real cardSubjectX: 0
    property real cardSubjectY: 0
    property real cardSubjectW: 0
    property real cardSubjectH: 0

    opacity: 0

    // Block ALL mouse events from passing through to inbox below
    MouseArea {
        anchors.fill: parent
        z: 0
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
    }

    onVisibleChanged: {
        if (visible) {
            updateDetections();
            isAnimating = true;
            isClosing = false;
            background.x = startX;
            background.y = startY;
            background.width = startWidth;
            background.height = startHeight;
            root.opacity = 1;
            contentCol.opacity = 0;
            fabContainer.opacity = 0;
            // Init ghosts at card positions, hidden
            ghostIcon.x = cardIconX;
            ghostIcon.y = cardIconY;
            ghostIcon.width = cardIconW;
            ghostIcon.height = cardIconH;
            openAnim.start();
        }
    }

    SequentialAnimation {
        id: openAnim
        ParallelAnimation {
            NumberAnimation {
                target: background
                properties: "x,y"
                to: 0
                duration: 450
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: background
                property: "width"
                to: root.width
                duration: 450
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: background
                property: "height"
                to: root.height
                duration: 450
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: contentCol
                property: "opacity"
                to: 1
                duration: 400
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: fabContainer
                property: "opacity"
                to: 1
                duration: 400
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction {
            script: {
                isAnimating = false;
            }
        }
    }

    function startClose() {
        root.closeStarted();
        isClosing = true;

        if (contentAvatarRect) {
            var avatarPos = contentAvatarRect.mapToItem(root, 0, 0);
            ghostIcon.x = avatarPos.x;
            ghostIcon.y = avatarPos.y;
            ghostIcon.width = contentAvatarRect.width;
            ghostIcon.height = contentAvatarRect.height;
            ghostIcon.opacity = 1;
        }

        if (contentSubjectText) {
            var subjectPos = contentSubjectText.mapToItem(root, 0, 0);
            ghostSubject.x = subjectPos.x;
            ghostSubject.y = subjectPos.y;
            ghostSubject.width = contentSubjectText.width;
            ghostSubject.height = subjectPos.height;
            ghostSubject.opacity = 1;
        }

        closeAnim.start();
    }

    SequentialAnimation {
        id: closeAnim
        ScriptAction {
            script: isAnimating = true
        }
        ParallelAnimation {
            // Background geometry contraction (Reversed Open)
            NumberAnimation {
                target: background
                properties: "x,y"
                to: startX
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: background
                property: "width"
                to: startWidth
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: background
                property: "height"
                to: startHeight
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            // Content fade out
            NumberAnimation {
                target: contentCol
                property: "opacity"
                to: 0
                duration: 250
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: fabContainer
                property: "opacity"
                to: 0
                duration: 250
                easing.type: Easing.OutCubic
            }
            // Global root fade out
            NumberAnimation {
                target: root
                property: "opacity"
                to: 0
                duration: 400
                easing.type: Easing.InOutQuad
            }

            // Ghost icon animates from content position to card position
            NumberAnimation {
                target: ghostIcon
                property: "x"
                to: cardIconX
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: ghostIcon
                property: "y"
                to: cardIconY
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: ghostIcon
                property: "width"
                to: cardIconW
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: ghostIcon
                property: "height"
                to: cardIconH
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: ghostIcon
                property: "opacity"
                to: 0
                duration: 400
                easing.type: Easing.InCubic
            }

            // Ghost subject animates from content position to card position
            NumberAnimation {
                target: ghostSubject
                property: "x"
                to: cardSubjectX
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: ghostSubject
                property: "y"
                to: cardSubjectY
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: ghostSubject
                property: "width"
                to: cardSubjectW
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: ghostSubject
                property: "height"
                to: cardSubjectH
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: ghostSubject
                property: "opacity"
                to: 0
                duration: 400
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

    // Derived properties
    readonly property string senderName: {
        var parts = senderFull.split("<");
        return parts.length > 1 ? parts[0].trim() : senderFull;
    }
    readonly property string senderEmail: {
        var match = senderFull.match(/<(.+?)>/);
        return match ? match[1] : senderFull;
    }

    Rectangle {
        id: background
        x: isAnimating ? undefined : 0
        y: isAnimating ? undefined : 0
        width: isAnimating ? undefined : root.width
        height: isAnimating ? undefined : root.height

        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
        topLeftRadius: Appearance.rounding.verysmall
        topRightRadius: Appearance.rounding.windowRounding
        bottomLeftRadius: Appearance.rounding.verysmall
        bottomRightRadius: Appearance.rounding.windowRounding
        antialiasing: true
        clip: true

        Item {
            id: contentCol
            width: root.width
            height: root.height

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                // ── Header row: subject + reply + close ──────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        StyledText {
                            id: contentSubjectText
                            Layout.fillWidth: false
                            Layout.maximumWidth: parent.width * 0.7
                            text: root.subject
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            font.family: Appearance.font.family.main
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        // Label Chips side-by-side with subject
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4
                            visible: customLabelRepeater.count > 0
                            Repeater {
                                id: customLabelRepeater
                                model: root.getCustomLabels(root.labelsString)
                                delegate: Rectangle {
                                    height: 24
                                    width: contentLabelText.implicitWidth + 16
                                    radius: Appearance.rounding.verysmall
                                    color: Appearance.colors.colTertiaryContainer
                                    StyledText {
                                        id: contentLabelText
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.pixelSize: 11
                                        font.weight: Font.Black
                                        color: Appearance.colors.colOnTertiaryContainer
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        } // Spacer
                    }

                    // Reply button
                    RippleButton {
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: 130
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.m3colors.m3primaryContainer
                        onClicked: {
                            var cleanBody = root.body.replace(/<[^>]*>?/gm, ''); // Basic HTML strip
                            // Format reply as Gmail-style quote
                            var replyBody = "<br><br><div class=\"gmail_quote\">" + "<div dir=\"ltr\" class=\"gmail_attr\">Em " + root.date + ", " + root.senderFull + " escreveu:<br></div>" + "<blockquote class=\"gmail_quote\" style=\"margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex\">" + root.body + "</blockquote></div>";

                            var replySubject = root.subject.toLowerCase().startsWith("re:") ? root.subject : "Re: " + root.subject;
                            root.replyRequested(root.senderFull, replySubject, replyBody, root.threadId, root.messageId);
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "reply"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: "Reply"
                                color: Appearance.colors.colOnPrimary
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                        }
                    }

                    // Close button
                    RippleButton {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
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

                // ── Sender row: avatar + name/email chips ────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    spacing: 4

                    // Avatar circle
                    Rectangle {
                        id: contentAvatarRect
                        width: 64
                        height: 64
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer4Base
                        antialiasing: true

                        EmailIcon {
                            anchors.centerIn: parent
                            icon: root.icon || "person"
                            iconSize: 24
                        }
                    }

                    // Name chip
                    Rectangle {
                        Layout.preferredWidth: nameText.implicitWidth + 48
                        Layout.preferredHeight: 64
                        color: Appearance.colors.colLayer4Base
                        topLeftRadius: Appearance.rounding.verylarge
                        bottomLeftRadius: Appearance.rounding.verylarge
                        topRightRadius: Appearance.rounding.small
                        bottomRightRadius: Appearance.rounding.small
                        antialiasing: true

                        StyledText {
                            id: nameText
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            text: root.senderName
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    // Email chip
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        color: Appearance.colors.colLayer4Base
                        topLeftRadius: Appearance.rounding.small
                        bottomLeftRadius: Appearance.rounding.small
                        topRightRadius: Appearance.rounding.verylarge
                        bottomRightRadius: Appearance.rounding.verylarge
                        antialiasing: true

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            text: root.senderEmail
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }

                // ── Body area ────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer4Base
                    clip: true

                    // Inside the reading pane a horizontal drag selects text:
                    // the cheatsheet's tab swipe must not take it.
                    HoverHandler {
                        id: readingPaneHover
                    }

                    StyledFlickable {
                        anchors.fill: parent
                        anchors.margins: 20
                        contentWidth: width
                        contentHeight: contentColInsideFlickable.implicitHeight
                        clip: true
                        // A mouse drag over the text is a selection, not a
                        // flick; the wheel and touchpad still scroll.
                        acceptedButtons: (bodyText.interacting || quotedText.interacting) ? Qt.NoButton : Qt.LeftButton

                        ColumnLayout {
                            id: contentColInsideFlickable
                            width: parent.width
                            spacing: 16

                            // Skeleton loading screen
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.loadingBody
                                spacing: 12

                                Repeater {
                                    model: [0.9, 0.8, 0.95, 0.7, 0.5]
                                    delegate: Rectangle {
                                        Layout.preferredWidth: parent.width * modelData
                                        Layout.preferredHeight: 16
                                        radius: Appearance.rounding.small
                                        color: Appearance.colors.colSurfaceContainerHighest

                                        SequentialAnimation on opacity {
                                            loops: Animation.Infinite
                                            running: root.loadingBody
                                            NumberAnimation { from: 0.3; to: 0.7; duration: 800; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.7; to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                            }

                            SelectableEmailText {
                                id: bodyText
                                Layout.fillWidth: true
                                visible: !root.loadingBody
                                html: root.loadingBody ? "" : root.processedBody
                                font.family: Appearance.font.family.reading
                                font.pixelSize: EmailService.bodyFontSize
                                font.weight: Font.Normal
                                color: Appearance.colors.colOnSurface
                            }

                            // Quoted text section
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.hasQuotedBody && !root.loadingBody
                                spacing: 8

                                RippleButton {
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: 48
                                    buttonRadius: Appearance.rounding.small
                                    colBackground: Appearance.colors.colSurfaceContainerHighest
                                    onClicked: root.showQuoted = !root.showQuoted

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "more_horiz"
                                        iconSize: 20
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                }

                                Item {
                                    id: quotedTextContainer
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.showQuoted ? quotedText.implicitHeight : 0
                                    clip: true
                                    Behavior on Layout.preferredHeight {
                                        NumberAnimation {
                                            duration: 350
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                                        }
                                    }

                                    SelectableEmailText {
                                        id: quotedText
                                        width: parent.width
                                        enabled: root.showQuoted
                                        html: root.quotedBody
                                        font.family: Appearance.font.family.reading
                                        font.pixelSize: EmailService.bodyFontSize - 1
                                        font.weight: Font.Normal
                                        color: Appearance.colors.colOnSurfaceVariant
                                        opacity: root.showQuoted ? 0.7 : 0
                                        Behavior on opacity {
                                            NumberAnimation { duration: 250 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Generic loading indicator hidden since we use a pulsing skeleton now
                }
            }
        }

        // ── Floating Action Buttons (Inside Background) ───────────────────
        RowLayout {
            id: fabContainer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            spacing: 4
            z: 20

            property bool showBrowser: root.htmlPath !== ""
            property int attachmentCount: root.attachments ? root.attachments.count : 0
            visible: showBrowser || attachmentCount > 0 || root.detectedMeetings.length > 0 || root.detectedCodes.length > 0 || root.detectedPhones.length > 0

            RippleButton {
                id: openInBrowserFab
                visible: fabContainer.showBrowser

                implicitHeight: 48
                implicitWidth: browserFabRow.implicitWidth + 40

                buttonRadius: Appearance.rounding.full
                topRightRadius: (root.detectedMeetings.length > 0 || root.detectedCodes.length > 0 || root.detectedPhones.length > 0 || fabContainer.attachmentCount > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                bottomRightRadius: (root.detectedMeetings.length > 0 || root.detectedCodes.length > 0 || root.detectedPhones.length > 0 || fabContainer.attachmentCount > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full

                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.m3colors.m3primaryContainer
                onClicked: Qt.openUrlExternally("file://" + root.htmlPath)

                RowLayout {
                    id: browserFabRow
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: "open_in_browser"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: qsTr("Open in Browser")
                        color: Appearance.colors.colOnPrimary
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
            }

            Repeater {
                model: root.detectedMeetings
                delegate: RippleButton {
                    implicitHeight: 48
                    implicitWidth: meetingFabRow.implicitWidth + 32
                    buttonRadius: Appearance.rounding.full

                    topLeftRadius: (fabContainer.showBrowser || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    bottomLeftRadius: (fabContainer.showBrowser || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    topRightRadius: (index < root.detectedMeetings.length - 1 || root.detectedCodes.length > 0 || root.detectedPhones.length > 0 || fabContainer.attachmentCount > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    bottomRightRadius: (index < root.detectedMeetings.length - 1 || root.detectedCodes.length > 0 || root.detectedPhones.length > 0 || fabContainer.attachmentCount > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full

                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.m3colors.m3primaryContainer

                    onClicked: Qt.openUrlExternally(modelData.url)
                    altAction: () => Quickshell.clipboardText = modelData.url

                    RowLayout {
                        id: meetingFabRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: 20
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: modelData.type
                            color: Appearance.colors.colOnSecondaryContainer
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }

                    StyledToolTip {
                        text: modelData.url
                    }
                }
            }
            Repeater {
                model: root.detectedCodes
                delegate: RippleButton {
                    property bool copied: false
                    implicitHeight: 48
                    implicitWidth: codeFabRow.implicitWidth + 32
                    buttonRadius: Appearance.rounding.full

                    topLeftRadius: (fabContainer.showBrowser || root.detectedMeetings.length > 0 || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    bottomLeftRadius: (fabContainer.showBrowser || root.detectedMeetings.length > 0 || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    topRightRadius: (index < root.detectedCodes.length - 1 || root.detectedPhones.length > 0 || fabContainer.attachmentCount > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    bottomRightRadius: (index < root.detectedCodes.length - 1 || root.detectedPhones.length > 0 || fabContainer.attachmentCount > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full

                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.m3colors.m3primaryContainer

                    onClicked: {
                        Quickshell.clipboardText = modelData;
                        copied = true;
                        copyTimer.restart();
                    }

                    Timer {
                        id: copyTimer
                        interval: 2000
                        onTriggered: copied = false
                    }

                    RowLayout {
                        id: codeFabRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: copied ? "check" : "key"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        StyledText {
                            text: modelData
                            color: Appearance.colors.colOnPrimaryContainer
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }
                }
            }

            Repeater {
                model: root.detectedPhones
                delegate: RippleButton {
                    implicitHeight: 48
                    implicitWidth: phoneFabRow.implicitWidth + 32
                    buttonRadius: Appearance.rounding.full

                    topLeftRadius: (fabContainer.showBrowser || root.detectedMeetings.length > 0 || root.detectedCodes.length > 0 || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    bottomLeftRadius: (fabContainer.showBrowser || root.detectedMeetings.length > 0 || root.detectedCodes.length > 0 || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    topRightRadius: (index < root.detectedPhones.length - 1 || fabContainer.attachmentCount > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                    bottomRightRadius: (index < root.detectedPhones.length - 1 || fabContainer.attachmentCount > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full

                    colBackground: Appearance.colors.colTertiaryContainer
                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                    colRipple: Appearance.m3colors.m3primaryContainer

                    onClicked: Quickshell.clipboardText = modelData
                    altAction: () => Quickshell.clipboardText = modelData

                    RowLayout {
                        id: phoneFabRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: "call"
                            iconSize: 20
                            color: Appearance.colors.colOnTertiaryContainer
                        }
                        StyledText {
                            text: modelData
                            color: Appearance.colors.colOnTertiaryContainer
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }

                    StyledToolTip {
                        text: qsTr("Copy Number")
                    }
                }
            }

            Repeater {
                model: root.attachments
                delegate: RowLayout {
                    spacing: 4
                    property bool isIcs: model.name.toLowerCase().endsWith(".ics") || model.mimeType === "text/calendar"

                    // Extra button for ICS files
                    RippleButton {
                        id: icsActionBtn
                        visible: isIcs
                        implicitHeight: 48
                        implicitWidth: icsInfoText.implicitWidth + 64
                        buttonRadius: Appearance.rounding.full

                        topLeftRadius: (fabContainer.showBrowser || root.detectedMeetings.length > 0 || root.detectedPhones.length > 0 || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                        bottomLeftRadius: (fabContainer.showBrowser || root.detectedMeetings.length > 0 || root.detectedPhones.length > 0 || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                        topRightRadius: Appearance.rounding.verysmall
                        bottomRightRadius: Appearance.rounding.verysmall

                        colBackground: imported ? Appearance.m3colors.m3successContainer : (icsInfo ? Appearance.m3colors.m3tertiaryContainer : Appearance.m3colors.m3surfaceVariant)
                        colBackgroundHover: imported ? Appearance.m3colors.m3successContainer : (icsInfo ? Appearance.colors.colTertiaryContainerHover : Appearance.m3colors.m3surfaceVariant)
                        colRipple: Appearance.m3colors.m3primaryContainer

                        property bool imported: false
                        property string status: "idle"
                        property var icsInfo: model.eventInfo

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            MaterialSymbol {
                                id: calIcon
                                anchors.verticalCenter: parent.verticalCenter
                                text: icsActionBtn.imported ? "event_available" : (icsActionBtn.status === "downloading" ? "sync" : "calendar_add_on")
                                iconSize: 22
                                color: icsActionBtn.imported ? Appearance.m3colors.m3onSuccessContainer : (icsActionBtn.icsInfo ? Appearance.m3colors.m3onTertiaryContainer : Appearance.m3colors.m3onSurfaceVariant)

                                RotationAnimation on rotation {
                                    running: icsActionBtn.status === "downloading"
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running)
                                        calIcon.rotation = 0
                                }
                            }

                            StyledText {
                                id: icsInfoText
                                anchors.verticalCenter: parent.verticalCenter
                                text: icsActionBtn.icsInfo ? (icsActionBtn.icsInfo.startTime + " • " + icsActionBtn.icsInfo.date.replace(/-/g, "/")) : (icsActionBtn.imported ? qsTr("Imported") : qsTr("Add to Calendar"))
                                color: icsActionBtn.imported ? Appearance.m3colors.m3onSuccessContainer : (icsActionBtn.icsInfo ? Appearance.m3colors.m3onTertiaryContainer : Appearance.m3colors.m3onSurfaceVariant)
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.smallie
                            }
                        }

                        onClicked: {
                            if (icsActionBtn.imported)
                                return;

                            if (downloadFab.status === "done" && downloadFab.lastPath.startsWith("/tmp")) {
                                icsActionBtn.status = "downloading";
                                CalendarService.importFromIcs(downloadFab.lastPath, true);
                                icsActionBtn.imported = true;
                                icsActionBtn.status = "done";
                            } else {
                                icsActionBtn.status = "downloading";
                                // Download to /tmp for calendar import
                                EmailService.downloadAttachment(root.messageId, model.attachmentId, model.name, "/tmp");

                                var onDownload;
                                onDownload = function (id, success, path) {
                                    if (id === model.attachmentId) {
                                        if (success) {
                                            CalendarService.importFromIcs(path, true);
                                            icsActionBtn.imported = true;
                                            icsActionBtn.status = "done";
                                        } else {
                                            icsActionBtn.status = "idle";
                                        }
                                        EmailService.attachmentDownloadFinished.disconnect(onDownload);
                                    }
                                };
                                EmailService.attachmentDownloadFinished.connect(onDownload);
                            }
                        }

                        StyledToolTip {
                            text: qsTr("Add to Calendar")
                        }
                    }

                    RippleButton {
                        id: downloadFab
                        implicitHeight: 48
                        implicitWidth: Math.min(200, downloadContent.implicitWidth + 40)

                        property string status: "idle"
                        property string lastPath: ""
                        buttonRadius: Appearance.rounding.full

                        topLeftRadius: (isIcs || fabContainer.showBrowser || root.detectedMeetings.length > 0 || root.detectedPhones.length > 0 || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                        bottomLeftRadius: (isIcs || fabContainer.showBrowser || root.detectedMeetings.length > 0 || root.detectedPhones.length > 0 || index > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                        topRightRadius: (index === fabContainer.attachmentCount - 1) ? Appearance.rounding.full : Appearance.rounding.verysmall
                        bottomRightRadius: (index === fabContainer.attachmentCount - 1) ? Appearance.rounding.full : Appearance.rounding.verysmall

                        colBackground: status === "done" ? Appearance.m3colors.m3successContainer : Appearance.colors.colSecondaryContainer
                        colBackgroundHover: status === "done" ? Appearance.m3colors.m3successContainer : Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.m3colors.m3primaryContainer

                        onClicked: {
                            if (status === "idle") {
                                status = "downloading";
                                EmailService.downloadAttachment(root.messageId, model.attachmentId, model.name);
                            } else if (status === "done" && lastPath !== "") {
                                Qt.openUrlExternally("file://" + lastPath);
                            }
                        }

                        Connections {
                            target: EmailService
                            function onAttachmentDownloadFinished(id, success, path) {
                                // Ignore downloads to /tmp (they are for calendar import only)
                                if (id === model.attachmentId && !path.startsWith("/tmp")) {
                                    if (success) {
                                        downloadFab.status = "done";
                                        downloadFab.lastPath = path;
                                    } else {
                                        downloadFab.status = "idle";
                                    }
                                }
                            }
                        }

                        RowLayout {
                            id: downloadContent
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                id: dlIcon
                                text: downloadFab.status === "done" ? "check" : (downloadFab.status === "downloading" ? "sync" : "download")
                                iconSize: 22
                                color: downloadFab.status === "done" ? Appearance.m3colors.m3onSuccessContainer : Appearance.colors.colOnSecondaryContainer

                                RotationAnimation on rotation {
                                    running: downloadFab.status === "downloading"
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running)
                                        dlIcon.rotation = 0
                                }
                            }

                            ColumnLayout {
                                spacing: 0
                                StyledText {
                                    text: downloadFab.status === "downloading" ? qsTr("Downloading...") : model.name
                                    color: downloadFab.status === "done" ? Appearance.m3colors.m3onSuccessContainer : Appearance.colors.colOnSecondaryContainer
                                    font.weight: Font.Bold
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 120
                                }
                            }
                        }

                        StyledToolTip {
                            text: model.name
                        }
                    }
                }
            }
        }
    }

    // ── Ghost elements for shared element return animation ─────────────────
    Rectangle {
        id: ghostIcon
        opacity: 0
        radius: Appearance.rounding.full
        antialiasing: true
        color: Appearance.colors.colSurfaceContainerHighest
        z: 30
        visible: (root.isClosing || root.isAnimating) && opacity > 0.01

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    StyledText {
        id: ghostSubject
        opacity: 0
        z: 30
        visible: (root.isClosing || root.isAnimating) && opacity > 0.01
        text: root.subject
        font.pixelSize: Appearance.font.pixelSize.large
        font.weight: Font.Bold
        font.family: Appearance.font.family.main
        color: Appearance.colors.colOnSurface
        elide: Text.ElideRight
        maximumLineCount: 1
    }
}
