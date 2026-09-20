import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

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

    /**
     * Files already decoded this session, by path; see Cliphist.decodedImages.
     *
     * Each thumbnail used to start a shell just to find out its file was already there,
     * a dozen of them on every open of the clipboard, on the frame the launcher starts
     * to grow.
     */
    readonly property var decoded: Cliphist.decodedImages

    /** The entry the running decode is for; "" once it has been superseded. */
    property string decodingPath: ""
    property bool retried: false

    function requestDecode() {
        root.source = "";
        root.failed = false;
        if (root.entryNumber <= 0 || root.imageDecodeFileName.length === 0)
            return;
        if (root.decoded[root.imageDecodeFilePath] === true) {
            root.source = "file://" + root.imageDecodeFilePath;
            return;
        }
        // One decode at a time, and never a kill: a decode cut short left half a file
        // behind, which the next open took for a finished one. The entry that is
        // wanted by the time this one ends is picked up in `onExited`.
        if (decodeImageProcess.running)
            return;
        root.decodingPath = root.imageDecodeFilePath;
        decodeImageProcess.command = ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(imageDecodePath)}' && { [ -s '${StringUtils.shellSingleQuoteEscape(imageDecodeFilePath)}' ] || { ${Cliphist.cliphistBinary} decode ${root.entryNumber} > '${StringUtils.shellSingleQuoteEscape(imageDecodeFilePath)}.part' && mv -f '${StringUtils.shellSingleQuoteEscape(imageDecodeFilePath)}.part' '${StringUtils.shellSingleQuoteEscape(imageDecodeFilePath)}'; }; }`];
        decodeImageProcess.running = true;
    }

    // Asking twice is free: the second finds the first still running, or its file.
    Component.onCompleted: root.requestDecode()
    onEntryChanged: root.requestDecode()

    Process {
        id: decodeImageProcess
        onExited: (exitCode, exitStatus) => {
            const finished = root.decodingPath;
            root.decodingPath = "";
            if (exitCode === 0)
                root.decoded[finished] = true;
            // The entry changed while this ran: what just finished is not what is shown.
            if (finished !== root.imageDecodeFilePath) {
                root.requestDecode();
                return;
            }
            if (exitCode === 0) {
                root.source = "file://" + root.imageDecodeFilePath;
            } else {
                console.error("[CliphistImage] Failed to decode image for entry:", root.entry);
                root.source = "";
                root.failed = true;
            }
        }
    }

    /**
     * The corners are rounded by a clipping rectangle, not a masked layer.
     *
     * The mask was a Qt5Compat effect - a QML component of its own, with a shader and
     * two texture sources - built once per picture. A clipboard full of screenshots
     * builds a dozen of those in the one frame the launcher opens on, which was most of
     * a quarter-second freeze.
     */
    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        StyledImage {
            id: image
            anchors.fill: parent

            source: root.source
            fillMode: Image.PreserveAspectFit
            antialiasing: true
            asynchronous: true

            onStatusChanged: {
                if (status !== Image.Error)
                    return;
                // A file that was there and no longer loads gets decoded again, once.
                if (root.decoded[root.imageDecodeFilePath] === true && !root.retried) {
                    root.retried = true;
                    delete root.decoded[root.imageDecodeFilePath];
                    root.requestDecode();
                    return;
                }
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
}
