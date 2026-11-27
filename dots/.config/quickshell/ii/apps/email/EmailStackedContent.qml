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
    property string threadId: ""

    // Animation properties (mirrored from EmailContent for transition)
    property real startX: 0
    property real startY: 0
    property real startWidth: 0
    property real startHeight: 0
    property bool isAnimating: false
    property bool isClosing: false

    // Message bodies under the pointer or in a selection drag. Counted, since
    // each expanded message has its own text.
    property int interactingBodies: 0
    // Read by the cheatsheet: no tab swipe while the pointer is over the
    // thread or a text selection drag is running.
    readonly property bool locksHorizontalSwipe: threadHover.hovered || root.interactingBodies > 0

    signal closeStarted
    signal closeRequested
    signal replyRequested(string to, string subject, string body, string threadId, string inReplyTo)

    property int newestIndex: {
        var count = EmailService.currentThreadMessages.count;
        if (count === 0) return -1;
        var maxTs = -1;
        var maxIdx = -1;
        for (var i = 0; i < count; i++) {
            var item = EmailService.currentThreadMessages.get(i);
            if (item && item.timestamp > maxTs) {
                maxTs = item.timestamp;
                maxIdx = i;
            }
        }
        return maxIdx;
    }

    opacity: 0

    onVisibleChanged: {
        if (visible) {
            isAnimating = true;
            isClosing = false;
            background.x = startX;
            background.y = startY;
            background.width = startWidth;
            background.height = startHeight;
            root.opacity = 1;
            contentArea.opacity = 0;

            // Fetch the thread
            EmailService.fetchThread(root.threadId);

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
                target: contentArea
                property: "opacity"
                to: 1
                duration: 400
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction {
            script: isAnimating = false
        }
    }

    function startClose() {
        root.closeStarted();
        isClosing = true;
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
            NumberAnimation {
                target: contentArea
                property: "opacity"
                to: 0
                duration: 250
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "opacity"
                to: 0
                duration: 400
                easing.type: Easing.InOutQuad
            }
        }
        ScriptAction {
            script: {
                isAnimating = false;
                root.closeRequested();
            }
        }
    }

    // Block mouse events
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
    }

    Rectangle {
        id: background
        x: isAnimating ? undefined : 0
        y: isAnimating ? undefined : 0
        width: isAnimating ? undefined : root.width
        height: isAnimating ? undefined : root.height
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
        topLeftRadius: Appearance.rounding.small
        topRightRadius: Appearance.rounding.verylarge
        bottomLeftRadius: Appearance.rounding.small
        bottomRightRadius: Appearance.rounding.large
        clip: true

        Item {
            id: contentArea
            anchors.fill: parent
            opacity: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    StyledText {
                        Layout.fillWidth: true
                        text: root.subject
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }

                    RippleButton {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer4Base
                        onClicked: root.startClose()
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 20
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                // Stacked Emails List
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"
                    clip: true

                    HoverHandler {
                        id: threadHover
                    }

                    StyledFlickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: stackCol.implicitHeight
                        // A mouse drag over a body is a selection, not a
                        // flick; the wheel and touchpad still scroll.
                        acceptedButtons: root.interactingBodies > 0 ? Qt.NoButton : Qt.LeftButton

                        ColumnLayout {
                            id: stackCol
                            width: parent.width
                            spacing: 8
                            visible: !EmailService.loadingEmailBody

                            Repeater {
                                model: EmailService.currentThreadMessages
                                delegate: Item {
                                    id: msgRoot
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: isExpanded ? (contentCol.implicitHeight + 32) : 64

                                    property bool isExpanded: index === root.newestIndex // Newest email expanded by default
                                    property var detectedMeetings: []
                                    property var detectedPhones: []
                                    property var detectedCodes: []
                                    property bool confirmDeleteMode: false

                                    Timer {
                                        id: confirmTimer
                                        interval: 3000
                                        repeat: false
                                        onTriggered: msgRoot.confirmDeleteMode = false
                                    }

                                    onIsExpandedChanged: {
                                        if (isExpanded && model.unread) {
                                            EmailService.markAsRead(model.id);
                                            EmailService.currentThreadMessages.setProperty(index, "unread", false);
                                        }
                                        confirmDeleteMode = false;
                                        confirmTimer.stop();
                                    }

                                    function toggleExpand() {
                                        isExpanded = !isExpanded;
                                    }

                                    function updateDetections() {
                                        var res = EmailDetections.detectAll(model.body, model.subject);
                                        detectedMeetings = res.meetings;
                                        detectedPhones = res.phones;
                                        detectedCodes = res.codes;
                                    }

                                    Component.onCompleted: updateDetections()

                                    // Connection line segments
                                    Rectangle {
                                        x: 28 // 8 (contentCol margin) + 20 (half avatar)
                                        width: 2
                                        height: 28
                                        anchors.top: parent.top
                                        color: Appearance.colors.colOutlineVariant
                                        opacity: 0.4
                                        visible: index > 0
                                        z: -1
                                    }
                                    Rectangle {
                                        x: 28
                                        width: 2
                                        anchors.top: parent.top
                                        anchors.topMargin: 28
                                        anchors.bottom: parent.bottom
                                        color: Appearance.colors.colOutlineVariant
                                        opacity: 0.4
                                        visible: index < EmailService.currentThreadMessages.count - 1
                                        z: -1
                                    }

                                    Rectangle {
                                        id: backgroundRect
                                        anchors.fill: parent
                                        radius: Appearance.rounding.large
                                        color: isExpanded ? (Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1 : Appearance.m3colors.m3surfaceContainerLow) : (msgMouse.pressed ? Appearance.colors.colSurfaceContainerHighestActive : (msgMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover : (model.unread ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh)))
                                        border.width: model.unread ? 2 : 0
                                        border.color: Appearance.colors.colPrimary
                                        clip: true

                                        scale: msgMouse.pressed ? 0.985 : 1.0
                                        Behavior on scale {
                                            NumberAnimation {
                                                duration: 150
                                                easing.type: Easing.OutQuint
                                            }
                                        }
                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 250
                                            }
                                        }
                                        Behavior on border.width {
                                            NumberAnimation {
                                                duration: 350
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        Behavior on border.color {
                                            ColorAnimation {
                                                duration: 350
                                            }
                                        }

                                        MouseArea {
                                            id: msgMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: msgRoot.toggleExpand()
                                        }

                                        ColumnLayout {
                                            id: contentCol
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 12

                                            // Card Header
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 12

                                                Rectangle {
                                                    width: 40
                                                    height: 40
                                                    radius: Appearance.rounding.full
                                                    color: Appearance.colors.colSurfaceContainerHighest
                                                    EmailIcon {
                                                        id: avatarIcon
                                                        anchors.centerIn: parent
                                                        iconSize: 20
                                                        subject: model.subject
                                                        sender: model.from
                                                        snippet: model.snippet
                                                        unread: model.unread
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: model.from.split("<")[0].trim() || model.from
                                                        font.weight: model.unread ? Font.Bold : Font.DemiBold
                                                        font.pixelSize: Appearance.font.pixelSize.normal
                                                        color: Appearance.colors.colOnSurface
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        visible: !isExpanded
                                                        text: model.subject
                                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                                        color: Appearance.colors.colOnSurfaceVariant
                                                        elide: Text.ElideRight
                                                        maximumLineCount: 1
                                                        opacity: 0.7
                                                    }
                                                }

                                                RowLayout {
                                                    spacing: 8

                                                    // Individual Actions
                                                    // Header actions removed as per request (they now appear as FABs when expanded)
                                                    Item {
                                                        width: 1
                                                    }

                                                    // Date Pill
                                                    Rectangle {
                                                        Layout.preferredHeight: dateText.implicitHeight + 4
                                                        Layout.preferredWidth: dateText.implicitWidth + 16
                                                        radius: Appearance.rounding.full
                                                        color: Appearance.colors.colTertiaryContainer
                                                        antialiasing: true

                                                        StyledText {
                                                            id: dateText
                                                            anchors.centerIn: parent
                                                            text: EmailService.formatRelativeDate(model.timestamp)
                                                            font.pixelSize: Appearance.font.pixelSize.small
                                                            font.weight: model.unread ? Font.Bold : Font.Medium
                                                            color: model.unread ? Appearance.colors.colPrimary : Appearance.colors.colOnTertiaryContainer
                                                        }
                                                    }

                                                    MaterialSymbol {
                                                        text: isExpanded ? "expand_less" : "expand_more"
                                                        iconSize: 22
                                                        color: Appearance.colors.colOnSurfaceVariant
                                                    }
                                                }
                                            }

                                            // Body (if expanded)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: bodyText.implicitHeight
                                                visible: isExpanded
                                                color: "transparent"
                                                clip: true

                                                SelectableEmailText {
                                                    id: bodyText
                                                    width: parent.width
                                                    enabled: isExpanded
                                                    html: model.body
                                                    font.family: Appearance.font.family.reading
                                                    font.pixelSize: EmailService.bodyFontSize
                                                    color: Appearance.colors.colOnSurface

                                                    property bool counted: false
                                                    function syncCount() {
                                                        const want = interacting;
                                                        if (want === counted)
                                                            return;
                                                        counted = want;
                                                        root.interactingBodies += want ? 1 : -1;
                                                    }
                                                    onInteractingChanged: syncCount()
                                                    Component.onDestruction: {
                                                        if (counted)
                                                            root.interactingBodies -= 1;
                                                    }
                                                }
                                            }
                                            // Action FABs (Expanded only)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 8
                                                visible: isExpanded && model.body !== ""
                                                spacing: 8

                                                // LEFT SIDE: Detections + Open in Browser
                                                RowLayout {
                                                    spacing: 4

                                                    // Open in Browser FAB
                                                    RippleButton {
                                                        implicitHeight: 40
                                                        implicitWidth: browserRow.implicitWidth + 24
                                                        buttonRadius: Appearance.rounding.full

                                                        topRightRadius: (msgRoot.detectedMeetings.length > 0 || msgRoot.detectedCodes.length > 0 || msgRoot.detectedPhones.length > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                                                        bottomRightRadius: (msgRoot.detectedMeetings.length > 0 || msgRoot.detectedCodes.length > 0 || msgRoot.detectedPhones.length > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full

                                                        colBackground: Appearance.colors.colSurfaceContainerHigh
                                                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                                                        onClicked: Qt.openUrlExternally("https://mail.google.com/mail/u/0/#inbox/" + model.id)
                                                        RowLayout {
                                                            id: browserRow
                                                            anchors.centerIn: parent
                                                            spacing: 6
                                                            MaterialSymbol {
                                                                text: "open_in_browser"
                                                                iconSize: 18
                                                                color: Appearance.colors.colOnSurface
                                                            }
                                                            StyledText {
                                                                text: Translation.tr("Open")
                                                                font.weight: Font.Bold
                                                                font.pixelSize: Appearance.font.pixelSize.smallie
                                                                color: Appearance.colors.colOnSurface
                                                            }
                                                        }
                                                    }

                                                    // Meetings
                                                    Repeater {
                                                        model: msgRoot.detectedMeetings
                                                        delegate: RippleButton {
                                                            implicitHeight: 40
                                                            implicitWidth: meetingRow.implicitWidth + 24
                                                            buttonRadius: Appearance.rounding.full

                                                            topLeftRadius: Appearance.rounding.verysmall
                                                            bottomLeftRadius: Appearance.rounding.verysmall
                                                            topRightRadius: (index < msgRoot.detectedMeetings.length - 1 || msgRoot.detectedCodes.length > 0 || msgRoot.detectedPhones.length > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                                                            bottomRightRadius: (index < msgRoot.detectedMeetings.length - 1 || msgRoot.detectedCodes.length > 0 || msgRoot.detectedPhones.length > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full

                                                            colBackground: Appearance.colors.colSecondaryContainer
                                                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                                            onClicked: Qt.openUrlExternally(modelData.url)
                                                            RowLayout {
                                                                id: meetingRow
                                                                anchors.centerIn: parent
                                                                spacing: 6
                                                                MaterialSymbol {
                                                                    text: modelData.icon
                                                                    iconSize: 18
                                                                    color: Appearance.colors.colOnSecondaryContainer
                                                                }
                                                                StyledText {
                                                                    text: modelData.type
                                                                    font.weight: Font.Bold
                                                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                                                    color: Appearance.colors.colOnSecondaryContainer
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // OTP Codes
                                                    Repeater {
                                                        model: msgRoot.detectedCodes
                                                        delegate: RippleButton {
                                                            property bool copied: false
                                                            implicitHeight: 40
                                                            implicitWidth: codeRow.implicitWidth + 24
                                                            buttonRadius: Appearance.rounding.full

                                                            topLeftRadius: Appearance.rounding.verysmall
                                                            bottomLeftRadius: Appearance.rounding.verysmall
                                                            topRightRadius: (index < msgRoot.detectedCodes.length - 1 || msgRoot.detectedPhones.length > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full
                                                            bottomRightRadius: (index < msgRoot.detectedCodes.length - 1 || msgRoot.detectedPhones.length > 0) ? Appearance.rounding.verysmall : Appearance.rounding.full

                                                            colBackground: Appearance.colors.colPrimaryContainer
                                                            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
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
                                                                id: codeRow
                                                                anchors.centerIn: parent
                                                                spacing: 6
                                                                MaterialSymbol {
                                                                    text: copied ? "check" : "key"
                                                                    iconSize: 18
                                                                    color: Appearance.colors.colOnPrimaryContainer
                                                                }
                                                                StyledText {
                                                                    text: modelData
                                                                    font.weight: Font.Bold
                                                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                                                    color: Appearance.colors.colOnPrimaryContainer
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Phones
                                                    Repeater {
                                                        model: msgRoot.detectedPhones
                                                        delegate: RippleButton {
                                                            implicitHeight: 40
                                                            implicitWidth: phoneRow.implicitWidth + 24
                                                            buttonRadius: Appearance.rounding.full

                                                            topLeftRadius: Appearance.rounding.verysmall
                                                            bottomLeftRadius: Appearance.rounding.verysmall
                                                            topRightRadius: (index < msgRoot.detectedPhones.length - 1) ? Appearance.rounding.verysmall : Appearance.rounding.full
                                                            bottomRightRadius: (index < msgRoot.detectedPhones.length - 1) ? Appearance.rounding.verysmall : Appearance.rounding.full

                                                            colBackground: Appearance.colors.colTertiaryContainer
                                                            colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                                                            onClicked: Quickshell.clipboardText = modelData
                                                            RowLayout {
                                                                id: phoneRow
                                                                anchors.centerIn: parent
                                                                spacing: 6
                                                                MaterialSymbol {
                                                                    text: "call"
                                                                    iconSize: 18
                                                                    color: Appearance.colors.colOnTertiaryContainer
                                                                }
                                                                StyledText {
                                                                    text: modelData
                                                                    font.weight: Font.Bold
                                                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                                                    color: Appearance.colors.colOnTertiaryContainer
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                } // MIDDLE SPACER

                                                // RIGHT SIDE: Email Actions
                                                RowLayout {
                                                    spacing: 4

                                                    // Star FAB
                                                    RippleButton {
                                                        implicitHeight: 40
                                                        implicitWidth: starRow.implicitWidth + 24
                                                        buttonRadius: Appearance.rounding.full

                                                        topRightRadius: Appearance.rounding.verysmall
                                                        bottomRightRadius: Appearance.rounding.verysmall

                                                        colBackground: Appearance.colors.colSecondaryContainer
                                                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                                        onClicked: EmailService.toggleStarMessage(model.id, model.starred)
                                                        RowLayout {
                                                            id: starRow
                                                            anchors.centerIn: parent
                                                            spacing: 6
                                                            MaterialSymbol {
                                                                text: model.starred ? "star" : "star_outline"
                                                                iconSize: 18
                                                                fill: model.starred ? 1 : 0
                                                                color: model.starred ? Appearance.colors.colTertiary : Appearance.colors.colOnSecondaryContainer
                                                            }
                                                            StyledText {
                                                                text: model.starred ? Translation.tr("Starred") : Translation.tr("Star")
                                                                font.weight: Font.Bold
                                                                font.pixelSize: Appearance.font.pixelSize.smallie
                                                                color: Appearance.colors.colOnSecondaryContainer
                                                            }
                                                        }
                                                    }

                                                    // Reply FAB
                                                    RippleButton {
                                                        implicitHeight: 40
                                                        implicitWidth: replyRow.implicitWidth + 24
                                                        buttonRadius: Appearance.rounding.full

                                                        topLeftRadius: Appearance.rounding.verysmall
                                                        bottomLeftRadius: Appearance.rounding.verysmall
                                                        topRightRadius: Appearance.rounding.verysmall
                                                        bottomRightRadius: Appearance.rounding.verysmall

                                                        colBackground: Appearance.colors.colPrimary
                                                        colBackgroundHover: Appearance.colors.colPrimaryHover
                                                        onClicked: {
                                                            var replySubject = root.subject.toLowerCase().indexOf("re:") === 0 ? root.subject : "Re: " + root.subject;
                                                            var replyBody = "<br><br><div class=\"gmail_quote\">Em " + model.date + ", " + model.from + " escreveu:<br></div><blockquote class=\"gmail_quote\" style=\"margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex\">" + model.body + "</blockquote>";
                                                            root.replyRequested(model.from, replySubject, replyBody, model.threadId, model.id);
                                                        }
                                                        RowLayout {
                                                            id: replyRow
                                                            anchors.centerIn: parent
                                                            spacing: 6
                                                            MaterialSymbol {
                                                                text: "reply"
                                                                iconSize: 18
                                                                color: Appearance.colors.colOnPrimary
                                                            }
                                                            StyledText {
                                                                text: Translation.tr("Reply")
                                                                font.weight: Font.Bold
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                color: Appearance.colors.colOnPrimary
                                                            }
                                                        }
                                                    }

                                                    // Delete FAB
                                                    RippleButton {
                                                        implicitHeight: 40
                                                        implicitWidth: deleteRow.implicitWidth + 24
                                                        buttonRadius: Appearance.rounding.full

                                                        topLeftRadius: Appearance.rounding.verysmall
                                                        bottomLeftRadius: Appearance.rounding.verysmall

                                                        colBackground: msgRoot.confirmDeleteMode ? Appearance.colors.colError : Appearance.colors.colErrorContainer
                                                        colBackgroundHover: msgRoot.confirmDeleteMode ? Appearance.colors.colErrorHover : Appearance.colors.colErrorContainerHover
                                                        onClicked: {
                                                            if (EmailService.confirmDelete && !msgRoot.confirmDeleteMode) {
                                                                msgRoot.confirmDeleteMode = true;
                                                                confirmTimer.start();
                                                            } else {
                                                                confirmTimer.stop();
                                                                msgRoot.confirmDeleteMode = false;
                                                                EmailService.trashMessage(model.id);
                                                            }
                                                        }
                                                        RowLayout {
                                                            id: deleteRow
                                                            anchors.centerIn: parent
                                                            spacing: 6
                                                            MaterialSymbol {
                                                                text: msgRoot.confirmDeleteMode ? "check" : "delete"
                                                                iconSize: 18
                                                                color: msgRoot.confirmDeleteMode ? Appearance.colors.colOnError : Appearance.colors.colOnErrorContainer
                                                            }
                                                            StyledText {
                                                                text: msgRoot.confirmDeleteMode ? Translation.tr("Confirm?") : Translation.tr("Delete")
                                                                font.weight: Font.Bold
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                color: msgRoot.confirmDeleteMode ? Appearance.colors.colOnError : Appearance.colors.colOnErrorContainer
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Behavior on Layout.preferredHeight {
                                        NumberAnimation {
                                            duration: 400
                                            easing.type: Easing.OutQuint
                                        }
                                    }
                                }
                            }
                        }
                    }

                    MaterialLoadingIndicator {
                        anchors.centerIn: parent
                        visible: EmailService.loadingEmailBody
                        loading: EmailService.loadingEmailBody
                    }
                }
            }
        }
    }
}
