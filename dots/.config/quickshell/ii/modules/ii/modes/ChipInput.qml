pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A list of short strings as removable chips, with a field to type another
 * and, when the caller can offer some, a menu of suggestions (running
 * windows, paired devices, known networks…) so the user rarely has to know
 * the exact spelling.
 */
ColumnLayout {
    id: root

    property var values: []
    property string placeholder: ""
    /// [{ label, value }] — shown under a "pick" button; empty hides it.
    property var suggestions: []
    /// Maps a stored value to what the chip shows.
    property var display: v => v

    signal changed(var list)

    spacing: 6

    function add(value) {
        const v = String(value ?? "").trim();
        if (!v.length)
            return;
        const list = Array.from(root.values);
        if (list.indexOf(v) !== -1)
            return;
        list.push(v);
        root.changed(list);
    }

    function removeAt(index) {
        const list = Array.from(root.values);
        list.splice(index, 1);
        root.changed(list);
    }

    Flow {
        Layout.fillWidth: true
        visible: root.values.length > 0
        spacing: 6

        Repeater {
            model: root.values

            delegate: Rectangle {
                id: chip
                required property string modelData
                required property int index

                implicitWidth: chipRow.implicitWidth + 20
                implicitHeight: 30
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4

                    StyledText {
                        text: root.display(chip.modelData)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    MouseArea {
                        implicitWidth: 18
                        implicitHeight: 18
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeAt(chip.index)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3
            border.width: entry.activeFocus ? 2 : 0
            border.color: Appearance.colors.colPrimary

            StyledTextInput {
                id: entry
                anchors {
                    fill: parent
                    leftMargin: 14
                    rightMargin: 14
                }
                verticalAlignment: TextInput.AlignVCenter
                color: Appearance.colors.colOnLayer3
                clip: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.add(entry.text);
                        entry.text = "";
                        event.accepted = true;
                    }
                }
                onEditingFinished: {
                    if (entry.text.trim().length) {
                        root.add(entry.text);
                        entry.text = "";
                    }
                }

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !entry.text.length
                    text: root.placeholder
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RippleButton {
            visible: root.suggestions.length > 0
            implicitHeight: 36
            implicitWidth: pickRow.implicitWidth + 24
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: suggestionMenu.open()

            contentItem: RowLayout {
                id: pickRow
                anchors.centerIn: parent
                spacing: 4

                StyledText {
                    text: Translation.tr("Pick")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer3
                }

                MaterialSymbol {
                    text: "expand_more"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer3
                }
            }

            Popup {
                id: suggestionMenu
                y: parent.height + 4
                x: parent.width - width
                width: 300
                height: Math.min(320, suggestionList.contentHeight + 16)
                padding: 8
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                background: Rectangle {
                    radius: Appearance.rounding.normal
                    color: Appearance.m3colors.m3surfaceContainerHigh
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }

                contentItem: StyledListView {
                    id: suggestionList
                    clip: true
                    spacing: 2
                    popin: false
                    animateAppearance: false
                    animatePopulate: false
                    model: root.suggestions

                    delegate: RippleButton {
                        id: suggestion
                        required property var modelData

                        width: suggestionList.width
                        implicitHeight: 38
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: {
                            root.add(suggestion.modelData.value);
                            suggestionMenu.close();
                        }

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 10
                            }
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: suggestion.modelData.label
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                visible: suggestion.modelData.label !== suggestion.modelData.value
                                text: suggestion.modelData.value
                                elide: Text.ElideMiddle
                                Layout.maximumWidth: 120
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
