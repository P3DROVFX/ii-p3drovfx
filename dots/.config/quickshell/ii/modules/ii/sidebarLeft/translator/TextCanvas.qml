import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property bool isInput: true
    property string placeholderText
    property string text: ""
    property real minHeight: 150
    property real maxTextHeight: Appearance.font.pixelSize.small * 14
    property var inputTextArea: isInput ? inputLoader.item?.textArea : undefined
    readonly property string displayedText: isInput
        ? (root.inputTextArea?.text ?? "")
        : (root.text.length > 0 ? root.text : "")
    default property alias actionButtons: actions.data
    Layout.fillWidth: true
    implicitHeight: Math.max(root.minHeight, inputColumn.implicitHeight)
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal

    signal inputTextChanged();

    TapHandler {
        enabled: root.isInput
        onTapped: {
            if (!root.inputTextArea)
                return;
            root.inputTextArea.forceActiveFocus();
            root.inputTextArea.cursorPosition = root.inputTextArea.length;
        }
    }

    ColumnLayout {
        id: inputColumn
        anchors.fill: parent
        spacing: 0

        Loader {
            id: inputLoader
            active: root.isInput
            visible: root.isInput
            Layout.fillWidth: true
            sourceComponent: StyledFlickable {
                id: inputFlickable
                property alias textArea: inputTextArea
                implicitHeight: Math.min(root.maxTextHeight, inputTextArea.implicitHeight)
                contentWidth: width
                contentHeight: inputTextArea.implicitHeight
                clip: true

                TextArea.flickable: StyledTextArea {
                    id: inputTextArea
                    placeholderText: root.placeholderText
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    padding: 15
                    background: null
                    onTextChanged: root.inputTextChanged()
                }
            }
        }

        Loader {
            id: outputLoader
            active: !root.isInput
            visible: !root.isInput
            Layout.fillWidth: true
            sourceComponent: StyledFlickable {
                id: outputFlickable
                implicitHeight: Math.min(root.maxTextHeight, contentHeight)
                contentWidth: width
                contentHeight: outputTextArea.implicitHeight
                clip: true

                StyledText {
                    id: outputTextArea
                    width: outputFlickable.width
                    padding: 15
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.text.length > 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                    text: root.text.length > 0 ? root.text : root.placeholderText
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 10

            Loader {
                active: root.isInput
                visible: root.isInput
                Layout.leftMargin: 10
                sourceComponent: Text {
                    text: Translation.tr("%1 characters").arg(root.displayedText.length)
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            Item { Layout.fillWidth: true }
            ButtonGroup {
                id: actions
            }
        }
    }
}
