import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Frame of an app's own settings page (Cheatsheet tabs, Usage, Modes), shown by
 * an AppSettingsHost over the app's page. Drawn in the Clock/Phone settings
 * vocabulary (docs/design/material3-expressive.md): titled sections of rows
 * sharing one surface. Two columns of sections on a wide sheet, one below ~900 px.
 */
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    default property alias primary: primaryColumn.data
    property alias secondary: secondaryColumn.data
    readonly property bool twoColumns: flick.width >= 900 && secondaryColumn.children.length > 0

    signal goBack()

    /** Scrolls the body so `item` sits at the top. */
    function scrollTo(item) {
        const y = item.mapToItem(body, 0, 0).y;
        flick.contentY = Math.max(0, Math.min(y - 8, flick.contentHeight - flick.height));
    }

    RowLayout {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 12

        RippleButton {
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledToolTip {
                text: Translation.tr("Back") + " (Esc)"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.huge
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }

    StyledFlickable {
        id: flick
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            bottom: parent.bottom
            topMargin: 16
        }
        clip: true
        contentHeight: body.implicitHeight + 24
        boundsBehavior: Flickable.StopAtBounds

        GridLayout {
            id: body
            width: Math.min(flick.width - 16, 1280)
            x: Math.round((flick.width - width) / 2)
            columns: root.twoColumns ? 2 : 1
            columnSpacing: 20
            rowSpacing: 20

            ColumnLayout {
                id: primaryColumn
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: 20
            }

            ColumnLayout {
                id: secondaryColumn
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                visible: children.length > 0
                spacing: 20
            }
        }
    }
}
