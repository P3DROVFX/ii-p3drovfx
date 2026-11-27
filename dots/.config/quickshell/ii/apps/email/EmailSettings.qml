import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQml.Models

Item {
    id: root

    property bool dragging: false

    component CustomSpinBoxRow: RowLayout {
        id: spinBoxRow
        property string labelText
        property string iconName
        property int value
        property int from
        property int to
        property int stepSize
        signal valueUpdateRequested(int newValue)

        spacing: 8

        // Left Label Box
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Appearance.colors.colSurfaceContainerHigh
            radius: Appearance.rounding.large

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                MaterialShape {
                    implicitWidth: 32
                    implicitHeight: 32
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: spinBoxRow.iconName
                        iconSize: 18
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                StyledText {
                    text: spinBoxRow.labelText
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurface
                }
            }
        }

        // Controls
        RowLayout {
            spacing: 4

            // Minus
            Rectangle {
                id: minusBtn
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                color: minusMouse.pressed ? Appearance.colors.colSurfaceContainerHighestActive : (minusMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHigh)
                topLeftRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.small
                bottomRightRadius: Appearance.rounding.small

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
                }

                scale: minusMouse.pressed ? 0.9 : 1.0
                Behavior on scale {
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(minusBtn)
                }

                StyledText {
                    anchors.centerIn: parent
                    text: "-"
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurface
                }
                MouseArea {
                    id: minusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (spinBoxRow.value - spinBoxRow.stepSize >= spinBoxRow.from)
                        spinBoxRow.valueUpdateRequested(spinBoxRow.value - spinBoxRow.stepSize)
                }
            }

            // Value
            Rectangle {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                color: Appearance.colors.colSurfaceContainerHigh
                radius: Appearance.rounding.small

                StyledText {
                    anchors.centerIn: parent
                    text: spinBoxRow.value.toString()
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurface
                }
            }

            // Plus
            Rectangle {
                id: plusBtn
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                color: plusMouse.pressed ? Appearance.colors.colSurfaceContainerHighestActive : (plusMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHigh)
                topLeftRadius: Appearance.rounding.small
                bottomLeftRadius: Appearance.rounding.small
                topRightRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
                }

                scale: plusMouse.pressed ? 0.9 : 1.0
                Behavior on scale {
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(plusBtn)
                }

                StyledText {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurface
                }
                MouseArea {
                    id: plusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (spinBoxRow.value + spinBoxRow.stepSize <= spinBoxRow.to)
                        spinBoxRow.valueUpdateRequested(spinBoxRow.value + spinBoxRow.stepSize)
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
        topLeftRadius: Appearance.rounding.small
        topRightRadius: Appearance.rounding.verylarge
        bottomLeftRadius: Appearance.rounding.small
        bottomRightRadius: Appearance.rounding.verylarge
    }

    StyledFlickable {
        anchors.fill: parent
        topMargin: 12
        bottomMargin: 12
        leftMargin: 12
        rightMargin: 12
        contentHeight: contentLayout.implicitHeight
        clip: true

        ColumnLayout {
            id: contentLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 48 // Gap between sections

            // 1. Account Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                StyledText {
                    Layout.bottomMargin: 8
                    text: Translation.tr("Accounts")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Repeater {
                    model: EmailService.accounts
                    delegate: Rectangle {
                        id: accCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: 88
                        color: EmailService.activeAccountIndex === index ? Appearance.colors.colSecondaryContainer : (accMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHigh)
                        radius: Appearance.rounding.large
                        border.width: EmailService.activeAccountIndex === index ? 2 : 0
                        border.color: Appearance.colors.colPrimary

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(accCard)
                        }

                        MouseArea {
                            id: accMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: EmailService.switchAccount(index)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16 + accCard.border.width
                            anchors.rightMargin: 16 + accCard.border.width
                            anchors.topMargin: 12 + accCard.border.width
                            anchors.bottomMargin: 12 + accCard.border.width
                            spacing: 12

                            Item {
                                Layout.preferredWidth: 56
                                Layout.preferredHeight: 56

                                // Circular User Avatar with proper masking
                                Rectangle {
                                    id: avatarContainer
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Appearance.colors.colSurfaceContainerHighest
                                    antialiasing: true

                                    Image {
                                        id: avatarImage
                                        anchors.fill: parent
                                        source: modelData.avatar || ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: false
                                        antialiasing: true
                                    }

                                    Rectangle {
                                        id: avatarMask
                                        anchors.fill: parent
                                        radius: width / 2
                                        visible: false
                                        antialiasing: true
                                    }

                                    OpacityMask {
                                        anchors.fill: parent
                                        source: avatarImage
                                        maskSource: avatarMask
                                        visible: avatarImage.status === Image.Ready
                                        antialiasing: true
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "account_circle"
                                        iconSize: 32
                                        color: Appearance.colors.colOnSurfaceVariant
                                        visible: !modelData.avatar || avatarImage.status !== Image.Ready
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                StyledText {
                                    text: modelData.email
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    font.weight: Font.DemiBold
                                    color: EmailService.activeAccountIndex === index ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    text: EmailService.activeAccountIndex === index ? Translation.tr("Active Account") : Translation.tr("Click to switch")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: EmailService.activeAccountIndex === index ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                    opacity: 0.7
                                }
                            }

                            MaterialSymbol {
                                visible: EmailService.activeAccountIndex === index
                                text: "check_circle"
                                iconSize: 24
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }

                // Add account button
                Rectangle {
                    id: addAccBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: Appearance.rounding.full
                    color: addAccMouse.pressed ? Appearance.colors.colSurfaceContainerHighestActive : (addAccMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHigh)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(addAccBtn)
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        MaterialSymbol {
                            text: "person_add"
                            iconSize: 20
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            text: Translation.tr("Add another account")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    MouseArea {
                        id: addAccMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: EmailService.startOAuth()
                    }

                    scale: addAccMouse.pressed ? 0.98 : 1.0
                    Behavior on scale {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(addAccBtn)
                    }
                }

                // Disconnect Button
                Rectangle {
                    id: disconnectBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: Appearance.rounding.full

                    property bool confirmMode: false

                    color: confirmMode ? Appearance.colors.colSecondary : Appearance.colors.colErrorContainer

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(disconnectBtn)
                    }

                    RowLayout {
                        id: disconnectBtnLayout
                        anchors.centerIn: parent
                        spacing: 12

                        StyledText {
                            text: disconnectBtn.confirmMode ? Translation.tr("Confirm") : Translation.tr("Disconnect current account")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: disconnectBtn.confirmMode ? Appearance.colors.colOnSecondary : Appearance.colors.colOnErrorContainer
                        }
                    }

                    MouseArea {
                        id: disconnectMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!disconnectBtn.confirmMode) {
                                disconnectBtn.confirmMode = true;
                                confirmTimer.restart();
                            } else {
                                disconnectBtn.confirmMode = false;
                                EmailService.removeAccount();
                            }
                        }
                    }

                    Timer {
                        id: confirmTimer
                        interval: 3000
                        repeat: false
                        onTriggered: disconnectBtn.confirmMode = false
                    }

                    scale: disconnectMouseArea.pressed ? 0.95 : disconnectMouseArea.containsMouse ? 1.02 : 1.0
                    Behavior on scale {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(disconnectBtn)
                    }
                }
            }

            // 2. Settings (SpinBoxes)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    CustomSpinBoxRow {
                        Layout.fillWidth: true
                        labelText: Translation.tr("Number of emails to load:")
                        iconName: "list"
                        from: 10
                        to: 50
                        stepSize: 10
                        value: EmailService.maxEmails
                        onValueUpdateRequested: function (newValue) {
                            EmailService.maxEmails = newValue;
                        }
                    }
                    StyledText {
                        Layout.leftMargin: 12
                        text: Translation.tr("Note: Higher values may decrease loading performance.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.7
                    }
                }

                CustomSpinBoxRow {
                    Layout.fillWidth: true
                    labelText: Translation.tr("Refresh interval (minutes)")
                    iconName: "timer"
                    from: 0
                    to: 120
                    stepSize: 1
                    value: EmailService.refreshIntervalMinutes
                    onValueUpdateRequested: function (newValue) {
                        EmailService.refreshIntervalMinutes = newValue;
                    }
                }
            }

            // 3. Display & Appearance
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.bottomMargin: 8
                    text: Translation.tr("Display & Appearance")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                // Compact Mode
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    topLeftRadius: Appearance.rounding.large
                    topRightRadius: Appearance.rounding.large
                    bottomLeftRadius: Appearance.rounding.small
                    bottomRightRadius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "compress"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Compact Mode")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.compactMode
                            onCheckedChanged: {
                                if (EmailService.compactMode !== checked) {
                                    EmailService.compactMode = checked;
                                }
                            }
                        }
                    }
                }

                // Show Snippets
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "short_text"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Show Snippets")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.showSnippets
                            onCheckedChanged: {
                                if (EmailService.showSnippets !== checked) {
                                    EmailService.showSnippets = checked;
                                }
                            }
                        }
                    }
                }

                // Show Avatars
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "face"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Show Avatars")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.showAvatars
                            onCheckedChanged: {
                                if (EmailService.showAvatars !== checked) {
                                    EmailService.showAvatars = checked;
                                }
                            }
                        }
                    }
                }

                // Body Font Size
                CustomSpinBoxRow {
                    Layout.fillWidth: true
                    labelText: Translation.tr("Body Font Size")
                    iconName: "format_size"
                    from: 10
                    to: 24
                    stepSize: 1
                    value: EmailService.bodyFontSize
                    onValueUpdateRequested: function (newValue) {
                        EmailService.bodyFontSize = newValue;
                    }
                }
            }

            // 4. Behavior
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.bottomMargin: 8
                    text: Translation.tr("Behavior")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                // Stay in settings
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    topLeftRadius: Appearance.rounding.large
                    topRightRadius: Appearance.rounding.large
                    bottomLeftRadius: Appearance.rounding.small
                    bottomRightRadius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "settings_applications"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Stay in settings after account switch")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.stayInSettingsAfterAccountSwitch
                            onCheckedChanged: {
                                if (EmailService.stayInSettingsAfterAccountSwitch !== checked) {
                                    EmailService.stayInSettingsAfterAccountSwitch = checked;
                                }
                            }
                        }
                    }
                }

                // Auto Mark as Read
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "visibility"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Auto Mark as Read")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.autoMarkAsRead
                            onCheckedChanged: {
                                if (EmailService.autoMarkAsRead !== checked) {
                                    EmailService.autoMarkAsRead = checked;
                                }
                            }
                        }
                    }
                }

                // Confirm Delete
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "warning"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Confirm Deletion")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.confirmDelete
                            onCheckedChanged: {
                                if (EmailService.confirmDelete !== checked) {
                                    EmailService.confirmDelete = checked;
                                }
                            }
                        }
                    }
                }

                // Email Stacking
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    topLeftRadius: Appearance.rounding.small
                    topRightRadius: Appearance.rounding.small
                    bottomLeftRadius: Appearance.rounding.large
                    bottomRightRadius: Appearance.rounding.large

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "layers"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Email Threading (beta)")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.stackingEnabled
                            onCheckedChanged: {
                                if (EmailService.stackingEnabled !== checked) {
                                    EmailService.stackingEnabled = checked;
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.large

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "schedule"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Semantic Timestamps")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.semanticTimestampsEnabled
                            onCheckedChanged: {
                                if (EmailService.semanticTimestampsEnabled !== checked) {
                                    EmailService.semanticTimestampsEnabled = checked;
                                }
                            }
                        }
                    }
                }
            }

            // 5. Mailboxes
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.bottomMargin: 8
                    text: Translation.tr("Mailboxes")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                // All Inboxes
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    topLeftRadius: Appearance.rounding.large
                    topRightRadius: Appearance.rounding.large
                    bottomLeftRadius: Appearance.rounding.small
                    bottomRightRadius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "all_inbox"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("All Inboxes")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enableAllInboxes
                            onCheckedChanged: {
                                if (EmailService.enableAllInboxes !== checked) {
                                    EmailService.enableAllInboxes = checked;
                                }
                            }
                        }
                    }
                }

                // Starred
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "star"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Starred")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enableStarred
                            onCheckedChanged: {
                                if (EmailService.enableStarred !== checked) {
                                    EmailService.enableStarred = checked;
                                }
                            }
                        }
                    }
                }

                // Spam
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "report"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Spam")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enableSpam
                            onCheckedChanged: {
                                if (EmailService.enableSpam !== checked) {
                                    EmailService.enableSpam = checked;
                                }
                            }
                        }
                    }
                }

                // Sent
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "send"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Sent")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enableSent
                            onCheckedChanged: {
                                if (EmailService.enableSent !== checked) {
                                    EmailService.enableSent = checked;
                                }
                            }
                        }
                    }
                }

                // Trash
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Trash")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enableTrash
                            onCheckedChanged: {
                                if (EmailService.enableTrash !== checked) {
                                    EmailService.enableTrash = checked;
                                }
                            }
                        }
                    }
                }

                // Important
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "label_important"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Important")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enableImportant
                            onCheckedChanged: {
                                if (EmailService.enableImportant !== checked) {
                                    EmailService.enableImportant = checked;
                                }
                            }
                        }
                    }
                }

                // Purchases
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    topLeftRadius: Appearance.rounding.small
                    topRightRadius: Appearance.rounding.small
                    bottomLeftRadius: Appearance.rounding.large
                    bottomRightRadius: Appearance.rounding.large

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "shopping_cart"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Purchases")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enablePurchases
                            onCheckedChanged: {
                                if (EmailService.enablePurchases !== checked) {
                                    EmailService.enablePurchases = checked;
                                }
                            }
                        }
                    }
                }
            }

            // 6. Categories
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.bottomMargin: 8
                    text: Translation.tr("Categories")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                // Category Updates
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    topLeftRadius: Appearance.rounding.large
                    topRightRadius: Appearance.rounding.large
                    bottomLeftRadius: Appearance.rounding.small
                    bottomRightRadius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "update"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Enable Updates")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enableUpdates
                            onCheckedChanged: {
                                if (EmailService.enableUpdates !== checked) {
                                    EmailService.enableUpdates = checked;
                                }
                            }
                        }
                    }
                }

                // Category Promotions
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "sell"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Enable Promotions")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enablePromotions
                            onCheckedChanged: {
                                if (EmailService.enablePromotions !== checked) {
                                    EmailService.enablePromotions = checked;
                                }
                            }
                        }
                    }
                }

                // Category Socials
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: Appearance.colors.colSurfaceContainerHigh
                    topLeftRadius: Appearance.rounding.small
                    topRightRadius: Appearance.rounding.small
                    bottomLeftRadius: Appearance.rounding.large
                    bottomRightRadius: Appearance.rounding.large

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24

                        MaterialShape {
                            implicitWidth: 32
                            implicitHeight: 32
                            shape: MaterialShape.Shape.Cookie12Sided
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "people"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Enable Socials")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledSwitch {
                            checked: EmailService.enableSocials
                            onCheckedChanged: {
                                if (EmailService.enableSocials !== checked) {
                                    EmailService.enableSocials = checked;
                                }
                            }
                        }
                    }
                }
            }

            // 4. Custom Tags (User Labels)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: EmailService.labels.count > 0

                StyledText {
                    Layout.bottomMargin: 8
                    text: Translation.tr("Custom Tags")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Repeater {
                    model: EmailService.labels
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        color: Appearance.colors.colSurfaceContainerHigh

                        topLeftRadius: index === 0 ? Appearance.rounding.large : Appearance.rounding.small
                        topRightRadius: index === 0 ? Appearance.rounding.large : Appearance.rounding.small
                        bottomLeftRadius: index === EmailService.labels.count - 1 ? Appearance.rounding.large : Appearance.rounding.small
                        bottomRightRadius: index === EmailService.labels.count - 1 ? Appearance.rounding.large : Appearance.rounding.small

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 24

                            MaterialShape {
                                implicitWidth: 32
                                implicitHeight: 32
                                shape: MaterialShape.Shape.Cookie12Sided
                                color: Appearance.colors.colSecondaryContainer
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "label"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: model.name
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSurface
                            }

                            StyledSwitch {
                                checked: EmailService.enabledLabels.includes(model.id)
                                onCheckedChanged: {
                                    var labels = [];
                                    for (var k = 0; k < EmailService.enabledLabels.length; k++) {
                                        labels.push(EmailService.enabledLabels[k]);
                                    }
                                    var idx = labels.indexOf(model.id);
                                    if (checked && idx === -1) {
                                        labels.push(model.id);
                                        EmailService.enabledLabels = labels;
                                    } else if (!checked && idx !== -1) {
                                        labels.splice(idx, 1);
                                        EmailService.enabledLabels = labels;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // 7. Sidebar Layout (Reordering)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.bottomMargin: 8
                    text: Translation.tr("Sidebar Layout")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: navOrderVisualModel.items.count * (56 + 4) + 16
                    color: "transparent"
                    radius: Appearance.rounding.large

                    DelegateModel {
                        id: navOrderVisualModel
                        model: EmailService.navOrder
                        delegate: EmailNavOrderEntry {}
                    }

                    StyledListView {
                        id: navOrderView
                        anchors.fill: parent
                        interactive: false
                        model: navOrderVisualModel
                        spacing: 4
                    }
                }
            }
        }
    }

    component EmailNavOrderEntry: Item {
        id: entryWrapper
        width: parent ? parent.width : 0
        height: 56

        required property var modelData
        property int visualIndex: DelegateModel.itemsIndex

        function getOrderedList() {
            var ordered = [];
            for (var i = 0; i < navOrderVisualModel.items.count; i++) {
                ordered.push(navOrderVisualModel.items.get(i).model.modelData);
            }
            return ordered;
        }

        Rectangle {
            id: entryContent
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            height: 48
            radius: Appearance.rounding.small
            color: dragArea.held ? Appearance.colors.colLayer2Active : (visualIndex % 2 == 0 ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2)

            opacity: dragArea.held ? 0.8 : 1
            scale: dragArea.held ? 1.02 : 1

            Behavior on y {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Drag.active: dragArea.held
            Drag.source: dragArea
            Drag.hotSpot.x: 24
            Drag.hotSpot.y: 24

            states: State {
                when: dragArea.held
                ParentChange {
                    target: entryContent
                    parent: root
                }
                AnchorChanges {
                    target: entryContent
                    anchors {
                        left: undefined
                        right: undefined
                        verticalCenter: undefined
                    }
                }
            }

            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 20
                    rightMargin: 20
                }
                spacing: 10

                MaterialSymbol {
                    id: dragIndicatorIcon
                    text: "drag_indicator"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOutline
                }

                MaterialSymbol {
                    text: modelData.icon
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                    fill: 1
                    Layout.leftMargin: 10
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr(modelData.label)
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurface
                    Layout.leftMargin: 10
                }
            }
        }

        DropArea {
            anchors.fill: parent
            onEntered: drag => {
                var fromIndex = drag.source.parent.visualIndex;
                var toIndex = entryWrapper.visualIndex;
                navOrderVisualModel.items.move(fromIndex, toIndex);
            }
        }

        MouseArea {
            id: dragArea

            property bool held: false
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: 60

            drag.target: held ? entryContent : undefined
            drag.axis: Drag.YAxis

            pressAndHoldInterval: 200

            onPressAndHold: {
                root.dragging = true;
                held = true;
            }
            onReleased: {
                EmailService.navOrder = entryWrapper.getOrderedList();
                held = false;
                root.dragging = false;
            }
        }
    }
}
