pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * The AI summary of the commits behind the remote, with the controls to run
 * or redo it. Draws nothing when there is neither a summary nor a model that
 * could write one, unless `showUnavailable` asks for the hint.
 */
ColumnLayout {
    id: root

    property bool compact: false
    // Explain why no summary can be made (Settings wants that; the bar popup
    // would rather stay quiet).
    property bool showUnavailable: false
    // The box behind the summary. Settings puts the card on a layer-2 surface,
    // so it wants something darker or the box only shows on hover.
    property color boxColor: Appearance.colors.colLayer2

    // The answer, one entry per line. Qt's Markdown list renderer indents
    // bullets by a fixed 40 px that QML cannot shrink, so the bullets are laid
    // out by hand from the raw lines instead.
    readonly property var lines: {
        const out = [];
        for (const raw of String(ShellUpdateSummary.text ?? "").split("\n")) {
            const match = raw.match(/^(\s*)(?:[-*•]|\d+[.)])\s+(.*)$/);
            if (match) {
                out.push({ bullet: true, level: Math.min(2, Math.floor(match[1].length / 2)), text: match[2].trim() });
                continue;
            }
            const text = raw.trim();
            if (text !== "") out.push({ bullet: false, level: 0, text: text });
        }
        return out;
    }

    readonly property bool hasSummary: ShellUpdateSummary.current
    readonly property bool canRun: ShellUpdateSummary.available && !ShellUpdateSummary.generating
    readonly property bool active: root.hasSummary || ShellUpdateSummary.generating || ShellUpdateSummary.error !== "" || ShellUpdateSummary.available || root.showUnavailable

    visible: root.active
    spacing: root.compact ? 6 : 8

    function unavailableText() {
        switch (ShellUpdateSummary.unavailableReason) {
        case "disabled":
            return Translation.tr("AI is turned off in Policies, so no summary can be written.");
        case "missing-key":
            return Translation.tr("The current AI model needs an API key before it can summarise.");
        case "model-unavailable":
            return Translation.tr("Pick a model in the AI tab to summarise new commits.");
        case "remote-model-blocked":
            return Translation.tr("Local-only AI mode blocks the current model; pick a local one to summarise.");
        case "keyring-loading":
            return Translation.tr("Loading API keys…");
        default:
            return "";
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            text: "auto_awesome"
            iconSize: root.compact ? 16 : 18
            color: Appearance.colors.colPrimary
        }

        StyledText {
            text: Translation.tr("AI summary")
            font.pixelSize: root.compact ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            visible: root.hasSummary
            text: ShellUpdateSummary.modelTitle
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            Layout.maximumWidth: 140
        }

        Item {
            Layout.fillWidth: true
        }

        MaterialLoadingIndicator {
            visible: ShellUpdateSummary.generating
            implicitSize: 18
        }

        RippleButtonWithIcon {
            visible: ShellUpdateSummary.available
            enabled: root.canRun
            materialIcon: root.hasSummary ? "refresh" : "auto_awesome"
            mainText: ShellUpdateSummary.generating ? Translation.tr("Summarising…") : (root.hasSummary ? Translation.tr("Redo") : Translation.tr("Summarize"))
            onClicked: ShellUpdateSummary.summarize(true)

            StyledToolTip {
                text: root.hasSummary ? Translation.tr("Ask %1 again").arg(ShellUpdateSummary.modelTitle) : Translation.tr("Ask %1 to summarise these commits").arg(ShellUpdateSummary.modelTitle)
            }
        }
    }

    Rectangle {
        visible: root.hasSummary
        Layout.fillWidth: true
        implicitHeight: summaryColumn.implicitHeight + (root.compact ? 16 : 24)
        radius: Appearance.rounding.normal
        color: root.boxColor

        ColumnLayout {
            id: summaryColumn
            anchors {
                fill: parent
                margins: root.compact ? 8 : 12
            }
            spacing: root.compact ? 4 : 6

            Repeater {
                model: root.lines

                RowLayout {
                    id: line
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.leftMargin: line.modelData.level * (root.compact ? 12 : 16)
                    spacing: 6

                    StyledText {
                        visible: line.modelData.bullet
                        Layout.alignment: Qt.AlignTop
                        text: "•"
                        font.pixelSize: lineText.font.pixelSize
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        id: lineText
                        Layout.fillWidth: true
                        text: line.modelData.text
                        textFormat: Text.MarkdownText
                        wrapMode: Text.Wrap
                        font.pixelSize: root.compact ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }
        }
    }

    StyledText {
        visible: ShellUpdateSummary.error !== "" && !ShellUpdateSummary.generating
        Layout.fillWidth: true
        text: Translation.tr("The summary failed: %1").arg(ShellUpdateSummary.error)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
        wrapMode: Text.Wrap
    }

    StyledText {
        visible: root.showUnavailable && !ShellUpdateSummary.available && ShellUpdates.hasUpdate && root.unavailableText() !== ""
        Layout.fillWidth: true
        text: root.unavailableText()
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
    }

    StyledText {
        visible: root.hasSummary
        Layout.fillWidth: true
        text: root.compact ? Translation.tr("Written from the commit messages, not the code — the full list is in Settings › About.") : Translation.tr("Written from the commit messages, not the code — check the list below when it matters.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
    }
}
