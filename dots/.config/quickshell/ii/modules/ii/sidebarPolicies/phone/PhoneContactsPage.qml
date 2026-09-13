pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal

    property bool showBackButton: true
    signal goBack()

    property string selectedContactId: ""

    // Sub-page entrance animation
    opacity: 0
    transform: Translate { id: pageTranslate; y: 16 }

    Component.onCompleted: pageEntranceAnim.start()

    SequentialAnimation {
        id: pageEntranceAnim
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                from: 0
                to: 1
                duration: 280
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: pageTranslate
                property: "y"
                from: 16
                to: 0
                duration: 360
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // ─── Header Bar ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                id: backBtn
                visible: root.showBackButton
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer3
                }
                onClicked: root.goBack()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Contacts")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (!PhoneContactsService.ready) return Translation.tr("Connecting…")
                        const shown = String(PhoneContactsService.filteredContacts.length)
                        if (PhoneContactsService.hiddenCount <= 0) return Translation.tr("%1 found").arg(shown)
                        return Translation.tr("%1 found · %2 hidden")
                            .arg(shown).arg(String(PhoneContactsService.hiddenCount))
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                }
            }

            RippleButton {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer3
                }
                onClicked: PhoneContactsService.refresh()
                StyledToolTip {
                    text: Translation.tr("Refresh contacts")
                }
            }
        }

        // ─── Search Field ─────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialSymbol {
                    text: "search"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }

                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search contacts or numbers…")
                    placeholderTextColor: Appearance.colors.colSubtext
                    color: Appearance.colors.colOnLayer3
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    background: null
                    padding: 0
                    verticalAlignment: TextInput.AlignVCenter

                    onTextChanged: PhoneContactsService.setSearchQuery(text)

                    StyledTextContextMenu {
                        id: searchContextMenu
                        targetField: searchInput
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.RightButton
                        onPressed: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                searchInput.forceActiveFocus();
                                searchContextMenu.popup(mouse.x, mouse.y);
                            }
                        }
                    }
                }

                RippleButton {
                    visible: searchInput.text.length > 0
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 16
                        color: Appearance.colors.colSubtext
                    }
                    onClicked: {
                        searchInput.text = ""
                        PhoneContactsService.setSearchQuery("")
                    }
                }
            }
        }

        // ─── Favorites Section ──────────────────────────────────
        Item {
            id: favoritesRow
            Layout.fillWidth: true
            implicitHeight: favLayout.implicitHeight
            visible: favRepeater.count > 0

            ColumnLayout {
                id: favLayout
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                StyledText {
                    text: Translation.tr("Favorites")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                    opacity: 0.85
                }

                Flickable {
                    id: favFlickable
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    contentWidth: favRow.implicitWidth
                    contentHeight: height
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.DragOverBounds
                    maximumFlickVelocity: 3500

                    WheelHandler {
                        enabled: Config?.options.interactions.scrolling.fasterTouchpadScroll ?? false
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            // Mouse wheels emit multiples of ±120 on one axis; touchpads emit
                            // small continuous deltas, so each gets its own amplification factor.
                            const raw = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                            const threshold = Config.options.interactions.scrolling.mouseScrollDeltaThreshold;
                            const scrollFactor = Math.abs(raw) >= threshold ? Config.options.interactions.scrolling.mouseScrollFactor : Config.options.interactions.scrolling.touchpadScrollFactor;
                            const maxX = Math.max(0, favFlickable.contentWidth - favFlickable.width);
                            favFlickable.contentX = Math.max(0, Math.min(favFlickable.contentX - (raw / threshold) * scrollFactor, maxX));
                        }
                    }

                    Row {
                        id: favRow
                        spacing: 8

                        Repeater {
                            id: favRepeater
                            model: (PhoneContactsService.contacts || []).filter(c => PhoneContactsService.isFavorite(c.id))

                            delegate: RippleButton {
                                id: favChip
                                required property var modelData
                                width: 135
                                height: 56
                                buttonRadius: Appearance.rounding.normal
                                colBackground: Appearance.colors.colPrimaryContainer
                                colBackgroundHover: Appearance.colors.colPrimaryContainerHover

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // Circular Avatar
                                    Rectangle {
                                        id: favAvatarBox
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                        radius: 18
                                        color: Appearance.colors.colPrimary
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: modelData.avatarPath ? ("file://" + modelData.avatarPath) : ""
                                            visible: modelData.avatarPath !== ""
                                            fillMode: Image.PreserveAspectCrop

                                            layer.enabled: visible
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: favAvatarBox.width
                                                    height: favAvatarBox.height
                                                    radius: favAvatarBox.width / 2
                                                }
                                            }
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            visible: !modelData.avatarPath
                                            text: (modelData.displayName || "?").substring(0, 1).toUpperCase()
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: -2

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.displayName || Translation.tr("Unknown")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnPrimaryContainer
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: (modelData.phones && modelData.phones.length > 0) ? modelData.phones[0].value : ""
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnPrimaryContainer
                                            opacity: 0.8
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                onClicked: {
                                    root.selectedContactId = (root.selectedContactId === modelData.id ? "" : modelData.id)
                                    if (root.selectedContactId !== "") {
                                        const fc = PhoneContactsService.filteredContacts || []
                                        for (let i = 0; i < fc.length; i++) {
                                            if (fc[i] && fc[i].id === modelData.id) {
                                                contactsList.positionViewAtIndex(i, ListView.Beginning)
                                                break
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ─── Contacts List ────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: contactsList
                anchors.fill: parent
                model: PhoneContactsService.filteredContacts
                clip: true
                spacing: 6
                animateAppearance: false // Model is search-filtered: no pop-in on every keystroke

                delegate: Rectangle {
                    id: contactItem
                    required property var modelData
                    required property int index

                    width: contactsList.width
                    height: isExpanded ? expandedCol.implicitHeight + 16 : 60
                    radius: Appearance.rounding.normal
                    color: isExpanded ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2

                    readonly property bool isExpanded: root.selectedContactId === modelData.id

                    Behavior on height {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }

                    ColumnLayout {
                        id: expandedCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 8

                        // Collapsed row header
                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer3Hover

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                spacing: 10

                                // Circular Avatar
                                Rectangle {
                                    id: listAvatarBox
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 38
                                    radius: 19
                                    color: Appearance.colors.colPrimaryContainer
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.avatarPath ? ("file://" + modelData.avatarPath) : ""
                                        visible: modelData.avatarPath !== ""
                                        fillMode: Image.PreserveAspectCrop

                                        layer.enabled: visible
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: listAvatarBox.width
                                                height: listAvatarBox.height
                                                radius: listAvatarBox.width / 2
                                            }
                                        }
                                    }

                                    StyledText {
                                        anchors.centerIn: parent
                                        visible: !modelData.avatarPath
                                        text: (modelData.displayName || "?").substring(0, 1).toUpperCase()
                                        font.pixelSize: Appearance.font.pixelSize.medium
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: -2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.displayName || Translation.tr("Unknown Contact")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            if (modelData.organization) return modelData.organization
                                            if (modelData.phones && modelData.phones.length > 0) return modelData.phones[0].value
                                            if (modelData.emails && modelData.emails.length > 0) return modelData.emails[0].value
                                            return ""
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        opacity: 0.85
                                        elide: Text.ElideRight
                                    }
                                }

                                // Favorite Star Button
                                RippleButton {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer3Hover

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: PhoneContactsService.isFavorite(modelData.id) ? "star" : "star_outline"
                                        iconSize: 18
                                        fill: PhoneContactsService.isFavorite(modelData.id) ? 1.0 : 0.0
                                        color: PhoneContactsService.isFavorite(modelData.id)
                                               ? Appearance.colors.colPrimary
                                               : Appearance.colors.colSubtext
                                        animateChange: true
                                    }
                                    onClicked: PhoneContactsService.toggleFavorite(modelData.id)
                                    StyledToolTip {
                                        text: PhoneContactsService.isFavorite(modelData.id)
                                              ? Translation.tr("Remove from favorites")
                                              : Translation.tr("Add to favorites")
                                    }
                                }

                                // Chevron with smooth 180° rotation animation
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "expand_more"
                                    iconSize: 20
                                    color: Appearance.colors.colSubtext

                                    transform: Rotation {
                                        origin.x: 10
                                        origin.y: 10
                                        angle: contactItem.isExpanded ? 180 : 0
                                        Behavior on angle {
                                            NumberAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                        }
                                    }
                                }
                            }

                            onClicked: {
                                root.selectedContactId = (contactItem.isExpanded ? "" : modelData.id)
                            }
                        }

                        // Expanded Contact Details
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            visible: opacity > 0
                            opacity: contactItem.isExpanded ? 1.0 : 0.0
                            spacing: 8

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Appearance.colors.colOutlineVariant
                                opacity: 0.3
                            }

                            // Organization
                            StyledText {
                                Layout.fillWidth: true
                                visible: modelData.organization !== ""
                                text: Translation.tr("Org: %1").arg(modelData.organization)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colSubtext
                            }

                            // Phones Section
                            Repeater {
                                model: modelData.phones || []
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8

                                    MaterialSymbol {
                                        text: modelData.type === "mobile" ? "smartphone" : "phone"
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: -2
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.value
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer2
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.type || "phone"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            opacity: 0.8
                                        }
                                    }

                                    // Dial Button
                                    RippleButton {
                                        Layout.preferredHeight: 32
                                        Layout.preferredWidth: 32
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colPrimaryContainer
                                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "call"
                                            iconSize: 16
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                        onClicked: PhoneContactsService.openDialer(modelData.value)
                                        StyledToolTip {
                                            text: Translation.tr("Open dialer on phone")
                                        }
                                    }

                                    // SMS Button
                                    RippleButton {
                                        Layout.preferredHeight: 32
                                        Layout.preferredWidth: 32
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colSecondaryContainer
                                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "sms"
                                            iconSize: 16
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                        onClicked: PhoneContactsService.composeSms(modelData.value)
                                        StyledToolTip {
                                            text: Translation.tr("Compose SMS on phone")
                                        }
                                    }

                                    // Copy Button
                                    RippleButton {
                                        Layout.preferredHeight: 32
                                        Layout.preferredWidth: 32
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colLayer4
                                        colBackgroundHover: Appearance.colors.colLayer4Hover

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "content_copy"
                                            iconSize: 16
                                            color: Appearance.colors.colOnLayer4
                                        }
                                        onClicked: PhoneContactsService.copyPhone(modelData.value)
                                        StyledToolTip {
                                            text: Translation.tr("Copy number")
                                        }
                                    }
                                }
                            }

                            // Emails Section
                            Repeater {
                                model: modelData.emails || []
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "email"
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: -2
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.value
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer2
                                        }
                                    }

                                    RippleButton {
                                        Layout.preferredHeight: 32
                                        Layout.preferredWidth: 32
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colLayer4
                                        colBackgroundHover: Appearance.colors.colLayer4Hover

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "content_copy"
                                            iconSize: 16
                                            color: Appearance.colors.colOnLayer4
                                        }
                                        onClicked: Quickshell.clipboardText = modelData.value
                                        StyledToolTip {
                                            text: Translation.tr("Copy email")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty State overlay if list is empty
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                visible: PhoneContactsService.filteredContacts.length === 0

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: PhoneContactsService.ready ? "person_search" : "sync_problem"
                    iconSize: 48
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: PhoneContactsService.ready
                          ? (searchInput.text.length > 0 ? Translation.tr("No contacts matching search") : Translation.tr("No contacts found"))
                          : Translation.tr("Enable Contact Sync in KDE Connect on your phone")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
