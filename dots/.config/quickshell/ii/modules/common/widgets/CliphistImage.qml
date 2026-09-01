import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Io

Rectangle {
    id: root
    property string entry
    property real maxWidth
    property real maxHeight
    property bool blur: false
    property string blurText: "Image hidden"

    property string imageDecodePath: Directories.cliphistDecode
    property string imageDecodeFileName: root.entry.length > 0 ? Qt.md5(root.entry) + ".cliphist" : ""
    property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
    property string source
    readonly property bool loading: decodeImageProcess.running || (root.source.length > 0 && image.status === Image.Loading)
    readonly property bool ready: root.source.length > 0 && image.status === Image.Ready
    property bool failed: false

    property int entryNumber: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/^(\d+)\t/);
        return match ? parseInt(match[1]) : 0;
    }
    property int imageWidth: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/(\d+)x(\d+)/);
        return match ? parseInt(match[1]) : 0;
    }
    property int imageHeight: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/(\d+)x(\d+)/);
        return match ? parseInt(match[2]) : 0;
    }
    readonly property real fitScale: {
        if (imageWidth <= 0 || imageHeight <= 0)
            return 1;
        const w = root.maxWidth > 0 ? root.maxWidth : 300;
        const h = root.maxHeight > 0 ? root.maxHeight : 200;
        return Math.min(w / imageWidth, h / imageHeight, 1);
    }

    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.small
    implicitHeight: imageHeight * fitScale
    implicitWidth: imageWidth * fitScale

    function requestDecode() {
        decodeImageProcess.running = false;
        root.source = "";
        root.failed = false;
        if (root.entryNumber <= 0 || root.imageDecodeFileName.length === 0)
            return;
        decodeImageProcess.running = true;
    }

    Component.onCompleted: root.requestDecode()
    onEntryChanged: root.requestDecode()

    Process {
        id: decodeImageProcess
        command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(imageDecodePath)}' && { [ -s '${StringUtils.shellSingleQuoteEscape(imageDecodeFilePath)}' ] || ${Cliphist.cliphistBinary} decode ${root.entryNumber} > '${StringUtils.shellSingleQuoteEscape(imageDecodeFilePath)}'; }`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.source = "file://" + imageDecodeFilePath;
            } else {
                console.error("[CliphistImage] Failed to decode image for entry:", root.entry);
                root.source = "";
                root.failed = true;
            }
        }
    }

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: image.width
            height: image.height
            radius: root.radius
        }
    }

    StyledImage {
        id: image
        anchors.fill: parent

        source: root.source
        fillMode: Image.PreserveAspectFit
        antialiasing: true
        asynchronous: true

        onStatusChanged: {
            if (status === Image.Error)
                root.failed = true;
        }

        width: root.imageWidth * root.fitScale
        height: root.imageHeight * root.fitScale
    }

    Loader {
        id: blurLoader
        active: root.blur
        anchors.fill: image
        sourceComponent: GaussianBlur {
            source: image
            radius: 35
            samples: radius * 2 + 1

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.5)

                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    MaterialSymbol {
                        visible: width <= image.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "visibility_off"
                        font.pixelSize: 28
                    }
                    StyledText {
                        visible: width <= image.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.blurText
                        color: Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.smallie
                    }
                }
            }
        }
    }
}
