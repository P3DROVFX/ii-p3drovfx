import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    readonly property real thumbnailDevicePixelRatio: (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(
        Math.max(1, Math.ceil(width * thumbnailDevicePixelRatio)),
        Math.max(1, Math.ceil(height * thumbnailDevicePixelRatio))
    )
    readonly property bool sourceIsVideo: /\.(mp4|mkv|webm|avi|mov|m4v|ogv|gif)$/i.test(sourcePath)
    property var thumbnailService: null
    readonly property bool thumbnailGenerationRunning: thumbnailGeneration.running
    property bool reloadRequested: false
    property string thumbnailPath: {
        if (sourcePath.length == 0)
            return "";
        const resolvedUrlWithoutFileProtocol = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encodedUrlWithoutFileProtocol = resolvedUrlWithoutFileProtocol.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedUrlWithoutFileProtocol}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    source: reloadRequested ? "" : thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    function startThumbnailGeneration() {
        if (!root.generateThumbnail)
            return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }

    onSourcePathChanged: root.startThumbnailGeneration()
    onGenerateThumbnailChanged: root.startThumbnailGeneration()
    onSourceSizeChanged: root.startThumbnailGeneration()

    function reloadThumbnail() {
        if (!root.thumbnailPath)
            return;

        root.cache = false;
        root.reloadRequested = true;
        Qt.callLater(function() {
            root.reloadRequested = false;
            root.cache = true;
        });
    }

    Connections {
        target: root.thumbnailService
        enabled: root.thumbnailService !== null
        ignoreUnknownSignals: true

        function onThumbnailGenerated(directory) {
            if (FileUtils.parentDirectory(root.sourcePath) === FileUtils.trimFileProtocol(directory))
                root.reloadThumbnail();
        }

        function onThumbnailGeneratedFile(filePath) {
            if (Qt.resolvedUrl(root.sourcePath) === Qt.resolvedUrl(filePath))
                root.reloadThumbnail();
        }
    }

    Process {
        id: thumbnailGeneration
        command: {
            if (!root.generateThumbnail || root.sourcePath.length === 0)
                return ["true"];

            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const sourcePath = StringUtils.shellSingleQuoteEscape(FileUtils.trimFileProtocol(root.sourcePath));
            const thumbnailPath = StringUtils.shellSingleQuoteEscape(FileUtils.trimFileProtocol(root.thumbnailPath));
            const thumbnailDirectory = StringUtils.shellSingleQuoteEscape(FileUtils.parentDirectory(FileUtils.trimFileProtocol(root.thumbnailPath)));

            if (root.sourceIsVideo) {
                return ["bash", "-c", `mkdir -p '${thumbnailDirectory}' && [ -f '${thumbnailPath}' ] && exit 0 || { command -v ffmpeg >/dev/null 2>&1 && ffmpeg -v error -y -i '${sourcePath}' -frames:v 1 -vf 'scale=${maxSize}:${maxSize}:force_original_aspect_ratio=decrease' '${thumbnailPath}' && exit 1; exit 2; }`];
            }

            return ["bash", "-c", `mkdir -p '${thumbnailDirectory}' && [ -f '${thumbnailPath}' ] && exit 0 || { magick '${sourcePath}' -resize ${maxSize}x${maxSize} '${thumbnailPath}' && exit 1; }`];
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) { // Force reload if thumbnail had to be generated
                root.reloadThumbnail();
            }
        }
    }
}
