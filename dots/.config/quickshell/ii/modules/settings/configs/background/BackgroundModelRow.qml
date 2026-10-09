pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A cut-out model of the depth effect: what it is, what it costs, and the one action that
 * fits its state (download, cancel while it downloads, remove once installed). Rows share a
 * group shape through GroupPosition, so hiding one keeps the corners right.
 */
Rectangle {
    id: root

    readonly property real padding: 16
    readonly property real contentSpacing: 14
    readonly property real textSpacing: 4
    readonly property real iconSize: 20
    readonly property real iconPadding: 8
    readonly property real bytesPerGB: 1e9
    readonly property real bytesPerMB: 1e6
    readonly property real mbPerGB: 1000

    required property var modelData
    readonly property string modelId: root.modelData.id
    readonly property bool installed: DepthEffect.installed.includes(root.modelId)
    readonly property bool downloading: DepthEffect.downloadingModel === root.modelId
    readonly property bool failed: DepthEffect.errorModel === root.modelId && DepthEffect.errorMessage !== ""
    readonly property GroupPosition groupPosition: GroupPosition {
        item: root
    }

    function sizeText(bytes) {
        return bytes >= root.bytesPerGB ? (bytes / root.bytesPerGB).toFixed(1) + " GB" : Math.round(bytes / root.bytesPerMB) + " MB";
    }

    function memoryText(mb) {
        return mb >= root.mbPerGB ? Translation.tr("~%1 GB").arg((mb / root.mbPerGB).toFixed(mb % root.mbPerGB === 0 ? 0 : 1)) : Translation.tr("~%1 MB").arg(mb);
    }

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + root.padding * 2
    color: Appearance.colors.colLayer2
    topLeftRadius: root.groupPosition.isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
    topRightRadius: root.groupPosition.isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
    bottomLeftRadius: root.groupPosition.isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
    bottomRightRadius: root.groupPosition.isLast ? Appearance.rounding.large : Appearance.rounding.verysmall

    RowLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: root.padding
        }
        spacing: root.contentSpacing

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: root.installed ? "check" : root.modelData.icon
            shape: root.installed ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
            iconSize: root.iconSize
            padding: root.iconPadding
            color: root.installed ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            colSymbol: root.installed ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.textSpacing

            StyledText {
                Layout.fillWidth: true
                text: root.modelData.name
                color: Appearance.colors.colOnLayer2
                font {
                    family: Appearance.font.family.title
                    variableAxes: Appearance.font.variableAxes.titleRounded
                    pixelSize: Appearance.font.pixelSize.normal
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: root.modelData.description
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("%1 · %2 of RAM for ~%3 s per wallpaper · %4 · %5")
                    .arg(root.sizeText(root.modelData.bytes))
                    .arg(root.memoryText(root.modelData.peakMemoryMB))
                    .arg(root.modelData.seconds)
                    .arg(root.modelData.architecture)
                    .arg(root.modelData.license)
            }
            StyledProgressBar {
                visible: root.downloading
                Layout.fillWidth: true
                Layout.topMargin: root.textSpacing
                value: DepthEffect.downloadProgress
            }
            StyledText {
                visible: root.downloading || root.failed
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: root.failed ? DepthEffect.errorMessage
                    : DepthEffect.cancelling ? Translation.tr("Cancelling…")
                    : (DepthEffect.downloadPhase === "runtime" ? Translation.tr("Installing the ONNX runtime… %1%")
                        : Translation.tr("Downloading… %1%")).arg(Math.round(DepthEffect.downloadProgress * 100))
            }
        }

        AppRowButton {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.installed && !root.downloading
            enabled: DepthEffect.downloadingModel === "" && DepthEffect.statusKnown
            symbol: "download"
            label: Translation.tr("Download")
            onClicked: DepthEffect.download(root.modelId)
        }
        AppRowButton {
            Layout.alignment: Qt.AlignVCenter
            visible: root.downloading
            enabled: !DepthEffect.cancelling
            symbol: "close"
            label: Translation.tr("Cancel")
            onClicked: DepthEffect.cancelDownload()
        }
        AppRowButton {
            Layout.alignment: Qt.AlignVCenter
            visible: root.installed
            danger: true
            symbol: "delete"
            label: Translation.tr("Remove")
            onClicked: DepthEffect.remove(root.modelId)
        }
    }
}
