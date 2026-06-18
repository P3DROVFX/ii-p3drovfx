import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title
    property string icon: ""
    property string tooltip: ""
    property var customBackgroundColor: undefined
    property list<string> stringMap: []
    default property alias contentData: sectionContent.data

    Layout.fillWidth: true
    spacing: 12

    Component.onCompleted: {
        if (page?.register == false)
            return;
        if (!page?.index)
            return;
        SearchRegistry.registerSection({
            pageIndex: page?.index,
            title: root.title,
            searchStrings: root.stringMap.slice(),
            yPos: root.y
        });
    }

    function addKeyword(word) {
        if (!word)
            return;
        stringMap.push(word);
    }

    ScrollAnimate {}

    Rectangle {
        id: cardContainer
        Layout.fillWidth: true
        implicitHeight: cardInnerLayout.implicitHeight + 32
        radius: Appearance.rounding.normal
        color: root.customBackgroundColor !== undefined ? root.customBackgroundColor : Appearance.colors.colLayer0
        border.width: root.customBackgroundColor !== undefined ? 0 : 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: cardInnerLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
            }
            spacing: 12

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: 8

                Loader {
                    id: iconLoader
                    active: root.icon && root.icon.length > 0
                    visible: active
                    Layout.alignment: Qt.AlignVCenter
                    opacity: 1 - highlightOverlay.opacity

                    sourceComponent: MaterialSymbol {
                        text: root.icon
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledText {
                    opacity: 1 - highlightOverlay.opacity
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    color: Appearance.colors.colOnLayer1
                    Layout.fillWidth: true
                }

                MaterialSymbol {
                    opacity: 1 - highlightOverlay.opacity
                    visible: root.tooltip && root.tooltip.length > 0
                    text: "info"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1

                    MouseArea {
                        id: infoMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.WhatsThisCursor
                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: infoMouseArea.containsMouse
                            text: root.tooltip
                        }
                    }
                }
            }

            ColumnLayout {
                id: sectionContent
                Layout.fillWidth: true
                spacing: 4
            }
        }

        HighlightOverlay {
            id: highlightOverlay
            anchors.fill: parent
            radius: cardContainer.radius
            visible: opacity > 0
        }
    }
}
