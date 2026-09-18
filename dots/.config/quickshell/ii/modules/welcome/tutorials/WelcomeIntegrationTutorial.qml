import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.welcome
import qs.modules.welcome.tutorials
import qs.services
import "."

Item {
    id: root
    anchors.fill: parent

    property string title: ""
    property string subtitle: ""
    property string materialIcon: ""
    property string statusText: ""
    property string statusKind: "neutral"
    property var usedInChips: []

    signal backRequested()
    default property alias tutorialContent: contentContainer.data

    readonly property color statusBgColor: {
        if (root.statusKind === "ready")
            return Appearance.colors.colPrimaryContainer;
        if (root.statusKind === "attention")
            return Appearance.colors.colErrorContainer;
        if (root.statusKind === "configured")
            return Appearance.colors.colSecondaryContainer;
        return Appearance.colors.colLayer2;
    }

    readonly property color statusFgColor: {
        if (root.statusKind === "ready")
            return Appearance.colors.colOnPrimaryContainer;
        if (root.statusKind === "attention")
            return Appearance.colors.colOnErrorContainer;
        if (root.statusKind === "configured")
            return Appearance.colors.colOnSecondaryContainer;
        return Appearance.colors.colOnLayer2;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // Top Navigation Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButtonWithIcon {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                centerContent: true
                materialIcon: "arrow_back"
                iconPixelSize: Appearance.font.pixelSize.larger
                mainText: ""
                colText: Appearance.colors.colOnSecondaryContainer
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Status Pill
            Rectangle {
                visible: root.statusText.length > 0
                radius: Appearance.rounding.full
                implicitHeight: 28
                implicitWidth: statusLabel.implicitWidth + 18
                color: root.statusBgColor

                StyledText {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: root.statusText
                    color: root.statusFgColor
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                }
            }
        }

        // Subpage Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                implicitWidth: 44
                implicitHeight: 44

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.materialIcon
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // Used In Tag Chips
        RowLayout {
            Layout.topMargin: 2
            spacing: 6
            visible: root.usedInChips && root.usedInChips.length > 0

            StyledText {
                text: Translation.tr("Used in:")
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            Repeater {
                model: root.usedInChips
                delegate: Rectangle {
                    required property string modelData
                    radius: Appearance.rounding.small
                    implicitHeight: 20
                    implicitWidth: chipText.implicitWidth + 10
                    color: Appearance.colors.colLayer1

                    StyledText {
                        id: chipText
                        anchors.centerIn: parent
                        text: Translation.tr(modelData)
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    }
                }
            }
        }

        // Scrollable Tutorial Content Area
        Flickable {
            id: flickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6
            contentWidth: width
            contentHeight: contentContainer.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: contentContainer
                width: flickable.width - 12
                spacing: 16
            }

            TouchpadScrollHandler {
                flickable: flickable
            }
        }
    }
}
