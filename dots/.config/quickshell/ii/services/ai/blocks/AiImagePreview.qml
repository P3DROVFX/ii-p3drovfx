import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A bounded preview for a local image referenced by an assistant message.
 *
 * Markdown's native image item uses the file's intrinsic dimensions. That is
 * useful in a document editor, but unsafe in a narrow chat transcript: a
 * high-resolution wallpaper can make the message several thousand pixels
 * tall before the viewport reaches the visible part of the image.
 */
Item {
    id: root

    property string source: ""
    property string altText: ""

    readonly property real previewAspectRatio: 16 / 9
    readonly property real previewMinimumHeight: Appearance.font.pixelSize.huge * 4
    readonly property real previewMaxHeight: Appearance.font.pixelSize.huge * 12

    Layout.fillWidth: true
    implicitHeight: Math.min(
        root.previewMaxHeight,
        Math.max(root.previewMinimumHeight, root.width / root.previewAspectRatio)
    )
    clip: true

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        Image {
            id: previewImage
            anchors.fill: parent
            anchors.margins: Appearance.rounding.unsharpenmore
            fillMode: Image.PreserveAspectFit
            source: root.source
            asynchronous: true
            smooth: true
            sourceSize.width: Math.max(1, Math.round(root.width * 2))
            sourceSize.height: Math.max(1, Math.round(root.width * 2 / root.previewAspectRatio))
        }

        StyledText {
            anchors.centerIn: parent
            visible: previewImage.status === Image.Error
            text: root.altText.length > 0
                ? Translation.tr("Preview unavailable: %1").arg(root.altText)
                : Translation.tr("Preview unavailable")
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
