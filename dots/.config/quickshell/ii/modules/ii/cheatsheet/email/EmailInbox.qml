import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    signal composeRequested

    // Magnetic swipe tracking (Android 16 style)
    property int swipingIndex: -1
    property real activeSwipeX: 0

    property ListModel model: ListModel {}
    property bool loading: false
    property string activeTab: "inbox"
    property int pressedIndex: -1
    property bool isPullRefreshing: false
    property bool refreshing: isPullRefreshing && (root.loading || minRefreshTimer.running)

    property int currentPage: 0
    property bool hasNextPage: EmailService.hasNextPage(activeTab, currentPage)

    function refreshPagination() {
        hasNextPage = EmailService.hasNextPage(activeTab, currentPage);
    }

    Connections {
        target: root.model
        function onCountChanged() {
            root.refreshPagination();
        }
        function onDataChanged() {
            root.refreshPagination();
        }
    }

    onCurrentPageChanged: root.refreshPagination()
    onActiveTabChanged: {
        currentPage = 0;
        root.refreshPagination();
    }

    Timer {
        id: minRefreshTimer
        interval: 2000
        onTriggered: {
            if (!root.loading)
                root.isPullRefreshing = false;
        }
    }

    onLoadingChanged: {
        if (!loading && !minRefreshTimer.running)
            root.isPullRefreshing = false;
    }

    function getCustomLabels(labelsList) {
        if (!labelsList)
            return [];
        var systemLabels = ["INBOX", "UNREAD", "SPAM", "TRASH", "SENT", "STARRED", "IMPORTANT", "DRAFT", "CATEGORY_PERSONAL", "CATEGORY_SOCIAL", "CATEGORY_PROMOTIONS", "CATEGORY_UPDATES", "CATEGORY_FORUMS"];
        var result = [];
        var list = labelsList.toArray ? labelsList.toArray() : labelsList;
        for (var i = 0; i < list.length; i++) {
            var id = list[i];
            if (systemLabels.indexOf(id) === -1) {
                // Find label name in EmailService
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
                    result.push(id); // Fallback to ID
            }
        }
        return result;
    }

    signal emailSelected(string messageId, string threadId, bool isStack, real startX, real startY, real startWidth, real startHeight, real iconX, real iconY, real iconW, real iconH, real subjectX, real subjectY, real subjectW, real subjectH)

    Rectangle {
        anchors.fill: parent
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
        topLeftRadius: Appearance.rounding.verysmall
        topRightRadius: Appearance.rounding.windowRounding
        bottomLeftRadius: Appearance.rounding.verysmall
        bottomRightRadius: Appearance.rounding.windowRounding
        antialiasing: true
    }

    // Background Refresh Indicator (Linear Progress)
    Rectangle {
        id: backgroundSyncBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 0
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 2 // Thinner for a more subtle look
        radius: 1
        color: "transparent"
        visible: EmailService.loading && root.model.count > 0 && !root.isPullRefreshing && loadingDelayTimer.showBar
        clip: true
        z: 5

        Timer {
            id: loadingDelayTimer
            property bool showBar: false
            interval: 400 // Only show if sync takes more than 400ms
            running: EmailService.loading && root.model.count > 0 && !root.isPullRefreshing
            onTriggered: showBar = true
            onRunningChanged: if (!running)
                showBar = false
        }

        Rectangle {
            width: parent.width * 0.3
            height: parent.height
            radius: parent.radius
            color: Appearance.colors.colPrimary

            NumberAnimation on x {
                from: -parent.width * 0.3
                to: backgroundSyncBar.width
                duration: 1500
                loops: Animation.Infinite
                running: backgroundSyncBar.visible
            }
        }
    }

    StyledFlickable {
        id: flickable
        anchors.fill: parent
        topMargin: root.refreshing ? 80 : 12
        bottomMargin: 12
        leftMargin: 12
        rightMargin: 12
        contentHeight: contentLayout.implicitHeight
        clip: true

        Behavior on topMargin {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(flickable)
        }

        onDragEnded: {
            if (contentY < -140 && !root.isPullRefreshing) {
                root.isPullRefreshing = true;
                EmailService.syncLabel(root.activeTab, 0, true); // force = true

                minRefreshTimer.start();
            }
        }

        Item {
            width: flickable.width - 24
            height: 80
            y: -80

            Rectangle {
                anchors.centerIn: parent
                width: 56
                height: 56
                radius: Appearance.rounding.full
                antialiasing: true
                color: Appearance.colors.colSurfaceContainerHighest
                border.width: 0

                function getPullShape(yVal) {
                    var dist = Math.max(0, -yVal - 12);
                    if (dist < 20)
                        return MaterialShape.Shape.Circle;
                    if (dist < 40)
                        return MaterialShape.Shape.Cookie4Sided;
                    if (dist < 60)
                        return MaterialShape.Shape.Pentagon;
                    if (dist < 80)
                        return MaterialShape.Shape.Cookie6Sided;
                    if (dist < 100)
                        return MaterialShape.Shape.Cookie7Sided;
                    if (dist < 120)
                        return MaterialShape.Shape.Cookie9Sided;
                    return MaterialShape.Shape.Burst;
                }

                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: 36
                    visible: !root.refreshing
                    shape: parent.getPullShape(flickable.contentY)
                    color: flickable.contentY < -120 ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    rotation: flickable.contentY < -12 ? Math.max(0, -flickable.contentY - 20) * 2.5 : 0
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
                    }
                }
            }
        }

        ColumnLayout {
            id: contentLayout
            width: flickable.width - 24
            spacing: 4

            // Empty states
            Item {
                Layout.fillWidth: true
                implicitHeight: 450
                visible: root.model.count === 0 && !root.loading

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 24

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 180
                        implicitHeight: 180

                        MaterialShape {
                            id: emptyStateShape
                            anchors.fill: parent
                            shape: MaterialShape.Shape.Clover8Leaf
                            color: Appearance.colors.colSurfaceContainerHighest

                            RotationAnimator {
                                target: emptyStateShape
                                from: 0
                                to: 360
                                duration: 20000
                                loops: Animation.Infinite
                                running: root.model.count === 0 && !root.loading
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.activeTab === "spam" ? "report" : root.activeTab === "sent" ? "send" : root.activeTab === "search" ? "search" : root.activeTab.startsWith("label_") ? "label" : "inbox"
                            iconSize: 80
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 16

                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.activeTab === "spam" ? Translation.tr("No Spam Found") : root.activeTab === "sent" ? Translation.tr("No Sent Messages") : root.activeTab === "search" ? Translation.tr("No Results Found") : root.activeTab.startsWith("label_") ? Translation.tr("No Messages for this Label") : Translation.tr("Your Inbox is Clean")
                                font.pixelSize: 32
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.activeTab === "spam" ? Translation.tr("Looks like you're safe from junk for now.") : root.activeTab === "sent" ? Translation.tr("You haven't sent any emails from this account yet.") : root.activeTab === "search" ? Translation.tr("Try adjusting your filters or keywords.") : Translation.tr("You've cleared everything. Enjoy the peace!")
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: 0.8
                            }
                        }

                        // Contextual CTA
                        RippleButton {
                            Layout.alignment: Qt.AlignHCenter
                            implicitHeight: 40
                            implicitWidth: ctaLabel.implicitWidth + 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            visible: root.activeTab === "inbox" || root.activeTab === "spam"

                            onClicked: {
                                if (root.activeTab === "inbox") {
                                    root.composeRequested();
                                } else if (root.activeTab === "spam") {
                                    EmailService.syncLabel("spam", 0, true);
                                }
                            }

                            StyledText {
                                id: ctaLabel
                                anchors.centerIn: parent
                                text: root.activeTab === "spam" ? Translation.tr("Sync Spam") : Translation.tr("Compose Email")
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }

            // Loading state

            Repeater {
                id: emailRepeater
                model: root.model

                delegate: Item {
                    id: cardRoot
                    Layout.fillWidth: true
                    Layout.preferredHeight: EmailService.compactMode ? 64 : 96
                    Layout.bottomMargin: (model.isStack || false) ? (mouseArea.containsMouse ? 24 : 12) : 0
                    clip: false // Allow stack effect to overflow

                    Behavior on Layout.preferredHeight {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(cardRoot)
                    }
                    Behavior on Layout.bottomMargin {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(cardRoot)
                    }

                    // Staggered entrance animation
                    opacity: 0
                    transform: Translate {
                        id: enterTranslate
                        y: 20
                    }
                    Component.onCompleted: {
                        enterAnimTimer.interval = index * 30;
                        enterAnimTimer.start();
                    }
                    Timer {
                        id: enterAnimTimer
                        onTriggered: {
                            cardRoot.opacity = 1;
                            enterTranslate.y = 0;
                        }
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                    }

                    property bool visualPressed: false
                    Timer {
                        id: pressTimer
                        interval: 200
                        onTriggered: {
                            if (!mouseArea.pressed) {
                                visualPressed = false;
                                if (root.pressedIndex === index)
                                    root.pressedIndex = -1;
                            }
                        }
                    }

                    // Swipe-to-delete state
                    property real swipeX: 0
                    property bool swiping: false
                    property bool dismissed: false
                    readonly property real deleteWidth: 96
                    readonly property real deleteThreshold: -220
                    readonly property real starThreshold: 220
                    property bool confirmDeleteMode: false

                    // Magnetic neighbor effect
                    readonly property real magneticOffset: {
                        if (root.swipingIndex === -1 || root.swipingIndex === index)
                            return 0;
                            
                        let dist = Math.abs(root.swipingIndex - index);
                        if (dist === 1) {
                            // Pull immediate neighbors by 15% of the swipe distance, max 30px
                            let pull = root.activeSwipeX * 0.15;
                            return Math.max(-30, Math.min(30, pull));
                        } else if (dist === 2) {
                            // Pull secondary neighbors by 5% of the swipe distance, max 10px
                            let pull = root.activeSwipeX * 0.05;
                            return Math.max(-10, Math.min(10, pull));
                        }
                        return 0;
                    }

                    onSwipeXChanged: if (swiping)
                        root.activeSwipeX = swipeX

                    NumberAnimation {
                        id: snapAnim
                        target: cardRoot
                        property: "swipeX"
                        duration: 350
                        easing.type: Easing.OutCubic
                        onFinished: if (to === 0) {
                            root.swipingIndex = -1;
                            root.activeSwipeX = 0;
                        }
                    }

                    // Star Button (Dynamic background)
                    Rectangle {
                        id: starBtn
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, cardRoot.swipeX - 6)
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colTertiary
                        antialiasing: true
                        visible: cardRoot.swipeX > 4

                        MaterialSymbol {
                            id: starIconSymbol
                            anchors.centerIn: parent
                            text: root.activeTab === "trash" ? "restore" : "star"
                            fill: root.activeTab === "trash" ? 1 : ((model.starred || cardRoot.swipeX >= cardRoot.starThreshold) ? 1 : 0)
                            iconSize: cardRoot.swipeX >= cardRoot.starThreshold ? 42 : 32
                            color: Appearance.colors.colOnTertiary
                            Behavior on iconSize {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutBack
                                }
                            }
                        }
                    }

                    // Delete Button (Dynamic background)
                    Rectangle {
                        id: deleteBtn
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, -cardRoot.swipeX - 6)
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colError
                        antialiasing: true
                        visible: cardRoot.swipeX < -4

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: cardRoot.confirmDeleteMode ? "check" : (root.activeTab === "trash" ? "delete_forever" : "delete")
                            fill: (cardRoot.confirmDeleteMode || root.activeTab === "trash" || cardRoot.swipeX <= cardRoot.deleteThreshold) ? 1 : 0
                            iconSize: (cardRoot.swipeX <= cardRoot.deleteThreshold || cardRoot.confirmDeleteMode) ? 42 : 32
                            color: Appearance.colors.colOnError
                            Behavior on iconSize {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutBack
                                }
                            }
                        }

                        StyledText {
                            anchors.top: parent.top
                            anchors.topMargin: 64
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Translation.tr("Confirm")
                            color: Appearance.colors.colOnError
                            visible: cardRoot.confirmDeleteMode
                            font.weight: Font.Bold
                        }
                    }

                    // The actual card content container
                    Item {
                        id: swipeContainer
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width
                        x: cardRoot.swipeX + cardRoot.magneticOffset

                        transformOrigin: Item.Center
                        scale: visualPressed ? 0.96 : 1.0
                        Behavior on scale {
                            NumberAnimation {
                                duration: visualPressed ? 60 : 300
                                easing.type: visualPressed ? Easing.OutQuad : Easing.OutBack
                            }
                        }

                        Behavior on x {
                            enabled: !cardRoot.swiping
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Email Card Stacks (Thread indicators)
                        Rectangle {
                            id: stack2
                            anchors.fill: backgroundRect
                            anchors.topMargin: 12
                            anchors.bottomMargin: -12
                            anchors.leftMargin: 32
                            anchors.rightMargin: 32
                            z: -2
                            visible: (model.isStack || false) && !cardRoot.dismissed
                            color: backgroundRect.color
                            opacity: mouseArea.containsMouse ? 0.35 : 0.2
                            topLeftRadius: backgroundRect.topLeftRadius
                            topRightRadius: backgroundRect.topRightRadius
                            bottomLeftRadius: backgroundRect.bottomLeftRadius
                            bottomRightRadius: backgroundRect.bottomRightRadius

                            transform: Translate {
                                y: mouseArea.containsMouse ? 12 : 0
                                Behavior on y {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.OutBack
                                    }
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                }
                            }
                        }
                        Rectangle {
                            id: stack1
                            anchors.fill: backgroundRect
                            anchors.topMargin: 6
                            anchors.bottomMargin: -6
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            z: -1
                            visible: (model.isStack || false) && !cardRoot.dismissed
                            color: backgroundRect.color
                            opacity: mouseArea.containsMouse ? 0.7 : 0.4
                            topLeftRadius: backgroundRect.topLeftRadius
                            topRightRadius: backgroundRect.topRightRadius
                            bottomLeftRadius: backgroundRect.bottomLeftRadius
                            bottomRightRadius: backgroundRect.bottomRightRadius

                            transform: Translate {
                                y: mouseArea.containsMouse ? 6 : 0
                                Behavior on y {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.OutBack
                                    }
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                }
                            }
                        }

                        // Email Card
                        Rectangle {
                            id: backgroundRect
                            width: parent.width
                            height: parent.height
                            antialiasing: true
                            color: visualPressed ? Appearance.colors.colSecondaryContainerActive : (mouseArea.containsMouse ? Appearance.colors.colSecondaryContainerHover : (model.unread ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh))

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }

                            property bool isPressed: visualPressed
                            property bool isAbovePressed: root.pressedIndex === index + 1 && root.pressedIndex !== -1
                            property bool isBelowPressed: root.pressedIndex === index - 1 && root.pressedIndex !== -1

                            readonly property real swipeEffect: Math.min(height / 2, Math.abs(cardRoot.swipeX) * 0.5)

                            topLeftRadius: Math.max(swipeEffect, index === 0 ? Appearance.rounding.large : (isPressed || isBelowPressed ? height / 2 : Appearance.rounding.small))
                            topRightRadius: Math.max(swipeEffect, index === 0 ? Appearance.rounding.large : (isPressed || isBelowPressed ? height / 2 : Appearance.rounding.small))
                            bottomLeftRadius: Math.max(swipeEffect, index === root.model.count - 1 ? Appearance.rounding.large : (isPressed || isAbovePressed ? height / 2 : Appearance.rounding.small))
                            bottomRightRadius: Math.max(swipeEffect, index === root.model.count - 1 ? Appearance.rounding.large : (isPressed || isAbovePressed ? height / 2 : Appearance.rounding.small))

                            Behavior on topLeftRadius {
                                enabled: !cardRoot.swiping
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on topRightRadius {
                                enabled: !cardRoot.swiping
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on bottomLeftRadius {
                                enabled: !cardRoot.swiping
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on bottomRightRadius {
                                enabled: !cardRoot.swiping
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }

                            // Ripple
                            layer.enabled: true
                            layer.samples: 8
                            layer.smooth: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: backgroundRect.width
                                    height: backgroundRect.height
                                    topLeftRadius: backgroundRect.topLeftRadius
                                    topRightRadius: backgroundRect.topRightRadius
                                    bottomLeftRadius: backgroundRect.bottomLeftRadius
                                    bottomRightRadius: backgroundRect.bottomRightRadius
                                    antialiasing: true
                                }
                            }

                            Item {
                                id: ripple
                                width: ripple.implicitWidth
                                height: ripple.implicitHeight
                                opacity: 0
                                visible: width > 0 && height > 0
                                property real implicitWidth: 0
                                property real implicitHeight: 0
                                property color color: Appearance.colors.colPrimaryActive
                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(ripple)
                                }
                                RadialGradient {
                                    anchors.fill: parent
                                    gradient: Gradient {
                                        GradientStop {
                                            position: 0.0
                                            color: ripple.color
                                        }
                                        GradientStop {
                                            position: 0.4
                                            color: "transparent"
                                        }
                                    }
                                }
                                transform: Translate {
                                    x: -ripple.width / 2
                                    y: -ripple.height / 2
                                }
                            }

                            RippleAnim {
                                id: rippleFadeAnim
                                duration: 2400
                                target: ripple
                                property: "opacity"
                                to: 0
                            }

                            SequentialAnimation {
                                id: rippleAnim
                                property real x
                                property real y
                                property real radius
                                PropertyAction {
                                    target: ripple
                                    property: "x"
                                    value: rippleAnim.x
                                }
                                PropertyAction {
                                    target: ripple
                                    property: "y"
                                    value: rippleAnim.y
                                }
                                PropertyAction {
                                    target: ripple
                                    property: "opacity"
                                    value: 0.55
                                }
                                ParallelAnimation {
                                    RippleAnim {
                                        target: ripple
                                        properties: "implicitWidth,implicitHeight"
                                        from: 0
                                        to: rippleAnim.radius * 2
                                    }
                                }
                            }

                            // Email content
                            RowLayout {
                                anchors.fill: parent
                                spacing: 0

                                Item {
                                    Layout.preferredWidth: EmailService.compactMode ? 180 : 240
                                    Layout.fillHeight: true
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: EmailService.compactMode ? 8 : 12
                                        spacing: EmailService.compactMode ? 8 : 10

                                        Rectangle {
                                            id: iconRect
                                            Layout.preferredWidth: EmailService.compactMode ? 40 : 64
                                            Layout.preferredHeight: EmailService.compactMode ? 40 : 64
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: Appearance.rounding.full
                                            antialiasing: true
                                            visible: EmailService.showAvatars
                                            color: mouseArea.pressed ? Appearance.colors.colSurfaceContainerHigh : Appearance.colors.colSurfaceContainerHighest
                                            Behavior on color {
                                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                            }
                                            EmailIcon {
                                                id: avatarIcon
                                                anchors.centerIn: parent
                                                subject: model.subject
                                                sender: model.from
                                                snippet: model.snippet
                                                unread: model.unread
                                                iconSize: EmailService.compactMode ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.huge
                                                isPressed: mouseArea.pressed
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 8
                                            Layout.preferredHeight: 8
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: Appearance.rounding.full
                                            antialiasing: true
                                            color: Appearance.colors.colPrimary
                                            opacity: model.unread ? 1 : 0
                                            Behavior on opacity {
                                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: model.from.split("<")[0].trim() || model.from
                                            font.family: Appearance.font.family.main
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: model.unread ? Font.Bold : Font.Normal
                                            color: model.unread ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: EmailService.compactMode ? 8 : 16
                                        anchors.leftMargin: EmailService.compactMode ? 12 : 24
                                        spacing: EmailService.compactMode ? 2 : 4

                                        StyledText {
                                            visible: root.activeTab === "all_inboxes" && model.recipientAccount !== "" && !EmailService.compactMode
                                            text: model.recipientAccount
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colPrimary
                                            opacity: 0.6
                                            Layout.fillWidth: true
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            StyledText {
                                                id: cardSubjectText
                                                Layout.fillWidth: true
                                                text: model.subject
                                                font.family: Appearance.font.family.main
                                                font.pixelSize: Appearance.font.pixelSize.normal
                                                font.weight: Font.DemiBold
                                                color: Appearance.colors.colOnSurface
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }

                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "star"
                                                iconSize: Appearance.font.pixelSize.small
                                                color: Appearance.colors.colTertiary
                                                fill: 1
                                                visible: model.starred
                                            }

                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "delete"
                                                iconSize: Appearance.font.pixelSize.small
                                                color: Appearance.colors.colError
                                                fill: 1
                                                visible: model.labelsString.indexOf("TRASH") !== -1
                                            }

                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "layers"
                                                iconSize: 18
                                                color: Appearance.colors.colOnSurfaceVariant
                                                visible: (model.isStack || false)
                                                opacity: 0.6
                                            }

                                            // Total Count Badge for Stacks
                                            Rectangle {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredHeight: 20
                                                Layout.preferredWidth: Math.max(20, badgeText.implicitWidth + 8)
                                                radius: Appearance.rounding.full
                                                color: model.threadUnreadCount > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                                visible: (model.isStack || false)
                                                antialiasing: true
                                                border.width: model.threadUnreadCount > 0 ? 0 : 1
                                                border.color: Appearance.colors.colOutlineVariant

                                                StyledText {
                                                    id: badgeText
                                                    anchors.centerIn: parent
                                                    text: model.stackCount || ""
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    color: model.threadUnreadCount > 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                                }
                                            }

                                            Rectangle {
                                                id: dateChip
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredHeight: dateText.implicitHeight + 4
                                                Layout.preferredWidth: dateText.implicitWidth + 16
                                                radius: Appearance.rounding.full
                                                color: Appearance.colors.colTertiaryContainer
                                                antialiasing: true

                                                StyledText {
                                                    id: dateText
                                                    anchors.centerIn: parent
                                                    text: EmailService.formatRelativeDate(model.timestamp)
                                                    font.family: Appearance.font.family.main
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: model.unread ? Font.Bold : Font.Medium
                                                    color: Appearance.colors.colOnTertiaryContainer
                                                }
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: !EmailService.compactMode && EmailService.showSnippets
                                            text: model.snippet
                                            font.family: Appearance.font.family.main
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnSurfaceVariant
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            opacity: 0.7
                                        }
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: cardRoot.swiping

                        property real startX: 0
                        property real startY: 0
                        property real baseSwipeX: 0
                        property bool dragDecided: false
                        property bool isHorizontalDrag: false

                        onPressed: event => {
                            startX = event.x;
                            startY = event.y;
                            baseSwipeX = cardRoot.swipeX;
                            dragDecided = false;
                            isHorizontalDrag = false;

                            visualPressed = true;
                            root.pressedIndex = index;
                            root.swipingIndex = index; // Register magnetic focus
                            pressTimer.restart();

                            var dist = (ox, oy) => ox * ox + oy * oy;
                            rippleAnim.x = event.x;
                            rippleAnim.y = event.y;
                            ripple.color = Appearance.colors.colPrimaryActive;
                            rippleAnim.radius = Math.sqrt(Math.max(dist(0, 0), dist(width, 0), dist(0, height), dist(width, height)));
                            rippleFadeAnim.complete();
                            rippleAnim.restart();
                        }

                        onPositionChanged: event => {
                            if (!pressed)
                                return;

                            var dx = event.x - startX;
                            var dy = event.y - startY;

                            if (!dragDecided) {
                                if (Math.abs(dx) > 5) {
                                    dragDecided = true;
                                    isHorizontalDrag = Math.abs(dx) > Math.abs(dy) * 1.2 && !(model.isStack || false);
                                    if (isHorizontalDrag) {
                                        cardRoot.swiping = true;
                                        visualPressed = false;
                                        root.pressedIndex = -1;
                                    }
                                }
                            }

                            if (isHorizontalDrag && cardRoot.swiping) {
                                // If confirm mode is active, limit swipe until confirmed
                                if (cardRoot.confirmDeleteMode && (baseSwipeX + dx) < 0)
                                    cardRoot.swipeX = Math.max(-cardRoot.width, baseSwipeX + dx);
                                else
                                    cardRoot.swipeX = baseSwipeX + dx;
                            }
                        }

                        onReleased: event => {
                            if (cardRoot.swiping) {
                                cardRoot.swiping = false;
                                if (cardRoot.swipeX <= cardRoot.deleteThreshold) {
                                    if (EmailService.confirmDelete && !cardRoot.confirmDeleteMode) {
                                        cardRoot.confirmDeleteMode = true;
                                        snapAnim.to = -cardRoot.deleteWidth - 40;
                                        snapAnim.start();
                                    } else {
                                        cardRoot.dismissed = true;
                                        dismissAnim.start();
                                    }
                                } else if (cardRoot.swipeX >= cardRoot.starThreshold) {
                                    if (root.activeTab === "trash") {
                                        restoreAnim.start();
                                    } else {
                                        starAnim.start();
                                    }
                                } else {
                                    cardRoot.confirmDeleteMode = false;
                                    snapAnim.to = 0;
                                    snapAnim.start();
                                }
                            } else {
                                // Clique direto se o botão estiver visível
                                if (cardRoot.swipeX < -20 && event.x > (cardRoot.width + cardRoot.swipeX)) {
                                    cardRoot.dismissed = true;
                                    dismissAnim.start();
                                } else if (cardRoot.swipeX > 20 && event.x < cardRoot.swipeX) {
                                    if (root.activeTab === "trash") {
                                        restoreAnim.start();
                                    } else {
                                        starAnim.start();
                                    }
                                } else {
                                    if (!pressTimer.running) {
                                        visualPressed = false;
                                        root.pressedIndex = -1;
                                    }
                                    rippleFadeAnim.restart();
                                    triggerEmailSelection();
                                }
                            }
                        }

                        function triggerEmailSelection() {
                            if (model.unread && EmailService.autoMarkAsRead)
                                EmailService.markAsRead(model.id);
                            var rect = backgroundRect.mapToItem(root, 0, 0, backgroundRect.width, backgroundRect.height);
                            var iconR = iconRect.mapToItem(root, 0, 0, iconRect.width, iconRect.height);
                            var subjectR = cardSubjectText.mapToItem(root, 0, 0, cardSubjectText.width, cardSubjectText.height);
                            root.emailSelected(model.id, model.threadId, (model.isStack || false), rect.x, rect.y, rect.width, rect.height, iconR.x, iconR.y, iconR.width, iconR.height, subjectR.x, subjectR.y, subjectR.width, subjectR.height);
                        }

                        onCanceled: {
                            if (cardRoot.swiping) {
                                cardRoot.swiping = false;
                                cardRoot.swipeX = 0;
                            }
                            visualPressed = false;
                            root.pressedIndex = -1;
                            rippleFadeAnim.restart();
                        }
                    }

                    // Dismiss animation
                    SequentialAnimation {
                        id: dismissAnim
                        property string targetId: ""
                        onStarted: targetId = model.id

                        NumberAnimation {
                            target: cardRoot
                            property: "swipeX"
                            to: -cardRoot.width - 100
                            duration: 300
                            easing.type: Easing.InCubic
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: cardRoot
                                property: "opacity"
                                to: 0
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: cardRoot
                                property: "Layout.preferredHeight"
                                to: 0
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                        ScriptAction {
                            script: {
                                root.swipingIndex = -1;
                                root.activeSwipeX = 0;
                                if (root.activeTab === "trash") {
                                    EmailService.deleteMessagePermanent(dismissAnim.targetId);
                                } else {
                                    EmailService.trashMessage(dismissAnim.targetId);
                                }
                            }
                        }
                    }

                    // Restore animation
                    SequentialAnimation {
                        id: restoreAnim
                        property string targetId: ""
                        onStarted: targetId = model.id

                        NumberAnimation {
                            target: cardRoot
                            property: "swipeX"
                            to: cardRoot.width + 100
                            duration: 300
                            easing.type: Easing.InCubic
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: cardRoot
                                property: "opacity"
                                to: 0
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: cardRoot
                                property: "Layout.preferredHeight"
                                to: 0
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                        ScriptAction {
                            script: {
                                root.swipingIndex = -1;
                                root.activeSwipeX = 0;
                                EmailService.restoreMessage(restoreAnim.targetId);
                            }
                        }
                    }

                    // Star animation
                    SequentialAnimation {
                        id: starAnim
                        ScriptAction {
                            script: {
                                // Trigger ripple effect
                                rippleAnim.x = cardRoot.swipeX / 2;
                                rippleAnim.y = cardRoot.height / 2;
                                rippleAnim.radius = cardRoot.width * 1.5;
                                ripple.color = Appearance.colors.colTertiaryActive;
                                rippleFadeAnim.complete();
                                rippleAnim.restart();

                                // Toggle data
                                EmailService.toggleStarMessage(model.id, model.starred);
                            }
                        }

                        ParallelAnimation {
                            // Icon pop and bounce
                            SequentialAnimation {
                                NumberAnimation {
                                    target: starIconSymbol
                                    property: "scale"
                                    to: 2.2
                                    duration: 250
                                    easing.type: Easing.OutBack
                                }
                                NumberAnimation {
                                    target: starIconSymbol
                                    property: "scale"
                                    to: 1.3
                                    duration: 450
                                    easing.type: Easing.OutBounce
                                }
                            }

                            // Hold the swipe position
                            PauseAnimation {
                                duration: 600
                            }
                        }

                        NumberAnimation {
                            target: cardRoot
                            property: "swipeX"
                            to: 0
                            duration: 500
                            easing.type: Easing.OutExpo
                        }

                        ScriptAction {
                            script: {
                                cardRoot.swiping = false;
                                root.swipingIndex = -1;
                                root.activeSwipeX = 0;
                            }
                        }
                    }
                } // delegate end
            } // Repeater end

            // Premium Pager Controls - End of list
            RowLayout {
                id: pagerLayout
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 24
                Layout.bottomMargin: 32
                visible: root.currentPage > 0 || root.hasNextPage
                spacing: 4

                // Previous Page
                RippleButton {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    padding: 0
                    topLeftRadius: Appearance.rounding.large
                    bottomLeftRadius: Appearance.rounding.large
                    topRightRadius: 8
                    bottomRightRadius: 8
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    onClicked: {
                        if (root.currentPage > 0) {
                            root.currentPage -= 1;
                            flickable.contentY = 0;
                            EmailService.syncLabel(root.activeTab, root.currentPage);
                        }
                    }
                    contentItem: MaterialSymbol {
                        text: "chevron_left"
                        iconSize: 28
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.currentPage > 0 ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                        opacity: root.currentPage > 0 ? 1 : 0.4
                    }
                }

                // Current Page Indicator
                RippleButton {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    padding: 0
                    topLeftRadius: 8
                    bottomLeftRadius: 8
                    topRightRadius: 8
                    bottomRightRadius: 8
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    rippleEnabled: false
                    contentItem: StyledText {
                        text: (root.currentPage + 1).toString()
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                // Next Page
                RippleButton {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    padding: 0
                    topRightRadius: Appearance.rounding.large
                    bottomRightRadius: Appearance.rounding.large
                    topLeftRadius: 8
                    bottomLeftRadius: 8
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    onClicked: {
                        if (root.hasNextPage) {
                            root.currentPage += 1;
                            flickable.contentY = 0;
                            EmailService.syncLabel(root.activeTab, root.currentPage);
                        }
                    }
                    contentItem: MaterialSymbol {
                        text: "chevron_right"
                        iconSize: 28
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.hasNextPage ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                        opacity: root.hasNextPage ? 1 : 0.4
                    }
                }
            }
        }
    }

    component RippleAnim: NumberAnimation {
        duration: 1200
        easing.type: Easing.OutQuart
    }
}
