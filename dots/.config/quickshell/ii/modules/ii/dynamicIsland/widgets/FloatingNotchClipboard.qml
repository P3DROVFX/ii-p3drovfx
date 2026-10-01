import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

Item {
    id: root
    anchors.fill: parent

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.clipboard : null;
    }
    readonly property bool fromPhone: root.source ? root.source.fromPhone : false

    // Contracted view: simple "Copied" banner
    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.fromPhone ? "phonelink" : "assignment"
            iconSize: 16
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.bold: true
            color: Appearance.colors.colOnSurface
            text: root.fromPhone ? Translation.tr("Copied from phone") : Translation.tr("Copied!")
            elide: Text.ElideRight
            maximumLineCount: 1
            wrapMode: Text.NoWrap
        }

        // The copy is already in the clipboard: one press reads it aloud from
        // the island. Only for text the prompter can draw, and only while the
        // feature has an island to live in.
        RippleButton {
            id: prompterButton
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            buttonRadius: Appearance.rounding.full
            visible: Teleprompter.available && root.source && root.source.payload
                && !Cliphist.entryIsImage(root.source.payload)
            colBackground: prompterHover.hovered ? Appearance.colors.colSecondaryContainer : Qt.rgba(0, 0, 0, 0)
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colBackgroundActive: Appearance.colors.colSecondaryContainerActive
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: Teleprompter.startFromClipboard()

            HoverHandler {
                id: prompterHover
            }

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "subtitles"
                iconSize: 15
                fill: prompterHover.hovered ? 1 : 0
                color: Appearance.colors.colPrimary
            }

            StyledToolTip {
                text: Translation.tr("Read with Teleprompter")
                requireOverlay: false
            }
        }
    }
}
