import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One file `files_search` found, with the same "act on it directly, no model
 * required" affordance the Settings result card has: attach it to the next
 * message, or open the folder it lives in.
 */
Rectangle {
    id: root

    required property var file
    property bool compact: false

    readonly property string path: String(root.file?.path ?? "")
    readonly property string name: String(root.file?.name ?? root.path.split("/").pop())
    readonly property string kind: String(root.file?.kind ?? "")
    readonly property int bytes: Number(root.file?.bytes ?? 0)
    readonly property string humanSize: Ai.humanSize(root.bytes)

    readonly property string icon: {
        if (root.kind === "image") return "image";
        if (root.kind === "pdf") return "picture_as_pdf";
        if (root.kind === "document") return "description";
        if (root.kind === "text") return "article";
        return "insert_drive_file";
    }

    implicitHeight: rowLayout.implicitHeight + (root.compact ? 16 : 20)
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    RowLayout {
        id: rowLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.compact ? 8 : 12
        anchors.rightMargin: root.compact ? 8 : 12
        spacing: Appearance.rounding.unsharpenmore

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.icon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.name
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                text: root.humanSize
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        RippleButton {
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            topPadding: 0
            bottomPadding: 0
            leftPadding: 0
            rightPadding: 0
            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: {
                const lastSlash = root.path.lastIndexOf("/");
                Quickshell.execDetached(["xdg-open", lastSlash > 0 ? root.path.slice(0, lastSlash) : root.path]);
            }

            Accessible.name: Translation.tr("Open the folder this file is in")

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "folder_open"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
            }

            StyledToolTip {
                text: Translation.tr("Open containing folder")
            }
        }

        RippleButton {
            leftPadding: Appearance.rounding.small
            rightPadding: Appearance.rounding.small
            topPadding: 4
            bottomPadding: 4
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            // Queues it the same way the picker does: through the composer's
            // own probe → attachment pipeline, model-compat checks included.
            onClicked: Ai.attachFile(root.path)

            contentItem: StyledText {
                text: Translation.tr("Attach")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
