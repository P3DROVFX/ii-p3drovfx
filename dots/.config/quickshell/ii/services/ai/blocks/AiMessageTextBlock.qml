pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: Config.options.sidebar.ai.renderMarkdown
    property bool latexEnabled: Config.options.sidebar.ai.renderLatex
    property bool enableMouseSelection: false
    property var segmentContent: ""
    property var messageData: null
    property bool done: true
    property bool forceDisableChunkSplitting: false

    property list<string> renderedLatexHashes: []
    property string renderedSegmentContent: typeof segmentContent === "string" ? segmentContent : ""
    property string shownText: renderedSegmentContent
    property bool fadeChunkSplitting: !forceDisableChunkSplitting && !editing && !/\n\|/.test(shownText) && Config.options.sidebar.ai.textFadeIn
    readonly property var displaySegments: root.splitDisplaySegments(root.shownText)

    Layout.fillWidth: true

    function localImageSource(rawSource): string {
        let source = String(rawSource ?? "").trim();
        if (source.startsWith("<") && source.endsWith(">"))
            source = source.slice(1, -1).trim();
        if (source.startsWith("file://"))
            return source;
        if (source.startsWith("/"))
            return `file://${source}`;
        return "";
    }

    function splitDisplaySegments(text): var {
        const content = String(text ?? "");
        if (root.editing || !root.renderMarkdown)
            return [{ type: "text", content: content }];

        const chunks = root.fadeChunkSplitting
            ? content.split(/\n\n(?= {0,2})|\n(?= {0,2}[-\*])/g).filter(line => line.trim() !== "")
            : [content];

        let segments = [];
        for (const chunk of chunks)
            segments = segments.concat(root.splitChunkDisplaySegments(String(chunk)));
        return segments;
    }

    function splitChunkDisplaySegments(content): var {
        const imagePattern = /!\[([^\]]*)\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g;
        const segments = [];
        let lastIndex = 0;
        let match;

        while ((match = imagePattern.exec(content)) !== null) {
            const source = root.localImageSource(match[2] ?? match[3] ?? "");
            if (source.length === 0)
                continue;

            if (match.index > lastIndex)
                segments.push({ type: "text", content: content.slice(lastIndex, match.index) });

            segments.push({
                type: "image",
                source: source,
                alt: String(match[1] ?? "")
            });
            lastIndex = imagePattern.lastIndex;
        }

        if (segments.length === 0 || lastIndex < content.length)
            segments.push({ type: "text", content: content.slice(lastIndex) });
        return segments.filter(segment => segment.type === "image" || segment.content.length > 0);
    }

    Timer {
        id: renderTimer
        interval: 1000
        repeat: false
        onTriggered: {
            renderLatex()
            for (const hash of renderedLatexHashes) {
                handleRenderedLatex(hash, true);
            }
        }
    }

    function renderLatex() {
        if (!root.latexEnabled || root.editing)
            return;
        // Regex for $...$, $$...$$, \[...\]
        // Note: This is a simple approach and may need refinement for edge cases
        let regex = /(\$\$([\s\S]+?)\$\$)|(\$([^\$]+?)\$)|(\\\[((?:.|\n)+?)\\\])|(\\\(([\s\S]+?)\\\))/g;
        let match;
        while ((match = regex.exec(segmentContent)) !== null) {
            let expression = match[1] || match[2] || match[3] || match[4] || match[5] || match[6] || match[7] || match[8];
            if (expression) {
                Qt.callLater(() => {
                    const [renderHash, isNew] = LatexRenderer.requestRender(expression.trim());
                    if (!renderedLatexHashes.includes(renderHash)) {
                        renderedLatexHashes.push(renderHash);
                    }
                });
            }
        }
    }

    function handleRenderedLatex(hash, force = false) {
        if (renderedLatexHashes.includes(hash) || force) {
            const imagePath = LatexRenderer.renderedImagePaths[hash];
            const markdownImage = `![latex](${imagePath})`;

            const expression = LatexRenderer.processedExpressions[hash];
            renderedSegmentContent = renderedSegmentContent.replace(expression, markdownImage);
        }
    }

    onDoneChanged: {
        if (root.latexEnabled)
            renderTimer.restart();
    }
    onEditingChanged: {
        if (!editing && root.latexEnabled) {
            renderLatex()
        } else {
            root.renderedSegmentContent = String(segmentContent ?? "");
        }
    }

    onLatexEnabledChanged: {
        root.renderedSegmentContent = String(segmentContent ?? "");
        if (root.latexEnabled && !root.editing)
            root.renderLatex();
    }

    onSegmentContentChanged: {
        renderedSegmentContent = String(segmentContent ?? "");
        if (!root.editing && root.latexEnabled && segmentContent) {
            root.renderLatex();
        }
    }

    // When something finishes rendering
    // 1. Check if the hash is in the list
    // 2. If it is, replace the expression with the image path
    Connections {
        target: LatexRenderer
        function onRenderFinished(hash, imagePath) {
            const expression = LatexRenderer.processedExpressions[hash];
            handleRenderedLatex(hash);
        }
    }

    spacing: 0
    Repeater {
        id: textLinesRepeater
        model: ScriptModel {
            values: root.displaySegments
        }
        delegate: Loader {
            id: segmentLoader
            required property int index
            required property var modelData

            Layout.fillWidth: true
            Layout.preferredHeight: item ? item.implicitHeight : 0
            sourceComponent: !root.editing && segmentLoader.modelData?.type === "image"
                ? imagePreviewComponent
                : textComponent

            Component {
                id: textComponent

                TextArea {
                    Layout.fillWidth: true
                    readOnly: !root.editing
                    selectByMouse: root.enableMouseSelection || root.editing
                    renderType: Text.NativeRendering
                    font.family: Appearance.font.family.reading
                    font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
                    font.pixelSize: Appearance.font.pixelSize.small
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    wrapMode: TextEdit.Wrap
                    color: root.messageData?.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                    textFormat: root.renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText
                    text: String(segmentLoader.modelData?.content ?? "")

                    onTextChanged: {
                        if (!root.editing) return;
                        root.segmentContent = text;
                    }

                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link);
                        GlobalStates.sidebarLeftOpen = false;
                    }

                    MouseArea { // Pointing hand for links
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton // Only for hover
                        hoverEnabled: true
                        cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor
                            : (root.enableMouseSelection || root.editing) ? Qt.IBeamCursor : Qt.ArrowCursor
                    }
                }
            }

            Component {
                id: imagePreviewComponent

                AiImagePreview {
                    source: segmentLoader.modelData?.source ?? ""
                    altText: segmentLoader.modelData?.alt ?? ""
                }
            }
        }
    }
}
