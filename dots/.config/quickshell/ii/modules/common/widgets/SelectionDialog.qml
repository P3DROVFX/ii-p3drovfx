import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real dialogPadding: 15
    property real dialogMargin: 30
    property string titleText: "Selection Dialog"
    property var items: []
    property bool enableSearch: false
    property string searchQuery: ""
    property int selectedId: choiceListView.currentIndex
    property var defaultChoice

    readonly property var filteredItems: {
        if (!root.enableSearch || root.searchQuery.trim() === "")
            return root.items;
        const query = root.searchQuery.trim().toLowerCase();
        return root.items.filter(item => item.toString().toLowerCase().includes(query));
    }

    readonly property var selectedItem: {
        if (root.selectedId >= 0 && root.selectedId < root.filteredItems.length)
            return root.filteredItems[root.selectedId];
        return null;
    }

    signal canceled
    signal selected(var result)

    Rectangle { // Scrim
        id: scrimOverlay
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colScrim
        MouseArea {
            hoverEnabled: true
            anchors.fill: parent
            preventStealing: true
            propagateComposedEvents: false
        }
    }

    Rectangle { // The dialog
        id: dialog
        color: Appearance.m3colors.m3surfaceContainerHighest
        radius: Appearance.rounding.normal
        anchors.fill: parent
        anchors.margins: dialogMargin
        implicitHeight: dialogColumnLayout.implicitHeight

        ColumnLayout {
            id: dialogColumnLayout
            anchors.fill: parent
            spacing: 12

            StyledText {
                id: dialogTitle
                Layout.topMargin: dialogPadding
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.alignment: Qt.AlignLeft
                color: Appearance.m3colors.m3onSurface
                font.pixelSize: Appearance.font.pixelSize.larger
                text: root.titleText
            }

            Rectangle {
                visible: root.enableSearch
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.preferredHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerLow

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 8

                    MaterialSymbol {
                        text: "search"
                        iconSize: Appearance.font.pixelSize.normal
                        color: searchField.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outline
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        placeholderText: Translation.tr("Search...")
                        placeholderTextColor: Appearance.m3colors.m3outline
                        color: Appearance.m3colors.m3onSurface
                        leftPadding: 0
                        rightPadding: 0
                        topPadding: 8
                        bottomPadding: 8
                        clip: true
                        wrapMode: TextEdit.NoWrap
                        background: Rectangle {
                            radius: 0
                            color: "transparent"
                        }

                        font {
                            family: Appearance.font.family.main
                            pixelSize: Appearance.font.pixelSize.small
                            hintingPreference: Font.PreferFullHinting
                            variableAxes: Appearance.font.variableAxes.main
                        }

                        text: root.searchQuery
                        onTextChanged: root.searchQuery = text

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            acceptedButtons: Qt.NoButton
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Down) {
                                if (choiceListView.currentIndex < choiceListView.count - 1) {
                                    choiceListView.currentIndex++;
                                    choiceListView.positionViewAtIndex(choiceListView.currentIndex, ListView.Contain);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                if (choiceListView.currentIndex > 0) {
                                    choiceListView.currentIndex--;
                                    choiceListView.positionViewAtIndex(choiceListView.currentIndex, ListView.Contain);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.selected(root.selectedItem);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                if (root.searchQuery !== "") {
                                    root.searchQuery = "";
                                    searchField.text = "";
                                } else {
                                    root.canceled();
                                }
                                event.accepted = true;
                            }
                        }

                        Component.onCompleted: {
                            if (root.enableSearch)
                                forceActiveFocus();
                        }
                    }

                    RippleButton {
                        implicitWidth: 28
                        implicitHeight: 28
                        visible: root.searchQuery !== ""
                        buttonRadius: Appearance.rounding.full
                        colBackground: pressed ? Appearance.colors.colSurfaceContainerHighestActive : (hovered ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHighest)

                        contentItem: Item {
                            anchors.fill: parent
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                color: Appearance.m3colors.m3onSurfaceVariant
                                font.pixelSize: 14
                            }
                        }

                        onClicked: {
                            root.searchQuery = "";
                            searchField.text = "";
                            searchField.forceActiveFocus();
                        }
                    }
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
            }

            StyledListView {
                id: choiceListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                currentIndex: {
                    const choice = root.defaultChoice;
                    if (choice === undefined)
                        return -1;
                    return root.filteredItems.indexOf(choice);
                }
                spacing: 6

                model: root.filteredItems

                delegate: StyledRadioButton {
                    id: radioButton
                    required property var modelData
                    required property int index
                    anchors {
                        left: parent?.left
                        right: parent?.right
                        leftMargin: root.dialogPadding
                        rightMargin: root.dialogPadding
                    }

                    description: modelData.toString()
                    checked: index === choiceListView.currentIndex

                    onCheckedChanged: {
                        if (checked) {
                            choiceListView.currentIndex = index;
                        }
                    }
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
            }

            RowLayout {
                id: dialogButtonsRowLayout
                Layout.bottomMargin: dialogPadding
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.alignment: Qt.AlignRight

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.canceled()
                }
                DialogButton {
                    buttonText: Translation.tr("OK")
                    onClicked: root.selected(root.selectedItem)
                }
            }
        }
    }
}
