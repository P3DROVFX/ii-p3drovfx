pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets

/**
 * One page that tests what the chat depends on and says what is missing:
 * policy, current model, the Ollama daemon, tesseract, whisper, retrieval,
 * every provider key, and — live, not assumed — the search backend and the
 * agent's guarded page fetch. Reached from More controls; the audit called
 * this out as scattered across four places and answerable nowhere.
 *
 * Rows come from `AiDiagnosticsService`, which owns the probes and derives
 * the rest from the singletons that already detect them. Every line carries
 * its own retest, so a fix (a pulled model, an installed binary) can be
 * confirmed without leaving the conversation.
 */
Item {
    id: root

    Component.onCompleted: AiDiagnosticsService.open()

    readonly property real rowGap: Appearance.rounding.unsharpenmore
    readonly property real contentPadding: Appearance.rounding.large
    readonly property real controlExtent: Math.round(Appearance.font.pixelSize.huge * 2)

    readonly property var diag: AiDiagnosticsService

    /** Grouped rows in reading order; empty groups drop out entirely. */
    readonly property var groups: {
        const collected = {
            "chat": [],
            "providers": [],
            "local": [],
            "web": []
        };
        const staticChecks = Array.from(root.diag.staticChecks);
        for (let i = 0; i < staticChecks.length; i++)
            collected[staticChecks[i].group].push(staticChecks[i]);
        collected.providers = collected.providers.concat(Array.from(root.diag.keyChecks));
        const order = ["chat", "providers", "local", "web"];
        const result = [];
        for (let g = 0; g < order.length; g++) {
            if (collected[order[g]].length > 0)
                result.push({
                    "key": order[g],
                    "items": collected[order[g]]
                });
        }
        return result;
    }

    function stateGlyph(state: string): string {
        switch (state) {
        case "ok":
            return "check_circle";
        case "warn":
            return "warning";
        case "fail":
            return "error";
        case "running":
            return "progress_activity";
        default:
            return "radio_button_unchecked";
        }
    }

    function stateColor(state: string): color {
        switch (state) {
        case "ok":
            return Appearance.colors.colPrimary;
        case "fail":
            return Appearance.colors.colError;
        default:
            return Appearance.colors.colSubtext;
        }
    }

    implicitHeight: height

    StyledFlickable {
        id: sheetFlickable

        anchors.fill: parent
        contentHeight: pageColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: pageColumn

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: root.contentPadding

            // ── Header: the one-sentence verdict ──────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: root.rowGap * 2

                Rectangle {
                    Layout.preferredWidth: root.controlExtent
                    Layout.preferredHeight: root.controlExtent
                    radius: Appearance.rounding.large
                    color: {
                        if (!root.diag.anyRunning && root.diag.summary.failing === 0
                            && root.diag.summary.warning === 0 && root.diag.summary.total > 0)
                            return Appearance.colors.colPrimaryContainer;
                        if (!root.diag.anyRunning && root.diag.summary.failing > 0)
                            return Appearance.colors.colErrorContainer;
                        return Appearance.colors.colSecondaryContainer;
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: {
                            if (root.diag.anyRunning)
                                return "progress_activity";
                            if (root.diag.summary.failing > 0)
                                return "report";
                            if (root.diag.summary.total === 0)
                                return "quiz";
                            if (root.diag.summary.warning > 0)
                                return "warning";
                            return "check_circle";
                        }
                        fill: 1
                        iconSize: Appearance.font.pixelSize.huge
                        color: {
                            if (root.diag.anyRunning || root.diag.summary.failing === 0
                                && root.diag.summary.warning === 0 && root.diag.summary.total > 0) {
                                // Running reads neutral; a clean bill reads green-ish.
                                if (!root.diag.anyRunning)
                                    return Appearance.colors.colOnPrimaryContainer;
                                return Appearance.colors.colOnSecondaryContainer;
                            }
                            if (!root.diag.anyRunning && root.diag.summary.failing > 0)
                                return Appearance.colors.colOnErrorContainer;
                            return Appearance.colors.colOnSecondaryContainer;
                        }

                        RotationAnimation on rotation {
                            running: root.diag.anyRunning
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1400
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (root.diag.anyRunning)
                                return Translation.tr("Checking…");
                            if (root.diag.summary.total === 0)
                                return Translation.tr("Not tested yet");
                            if (root.diag.summary.failing > 0)
                                return root.diag.summary.failing === 1
                                    ? Translation.tr("One thing needs attention")
                                    : Translation.tr("%1 things need attention").arg(String(root.diag.summary.failing));
                            if (root.diag.summary.warning > 0)
                                return Translation.tr("Working, with %1 notes").arg(String(root.diag.summary.warning));
                            return Translation.tr("Everything checks out");
                        }
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.bold: true
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.diag.lastRunAt > 0
                            ? Translation.tr("Last run at %1").arg(Qt.formatDateTime(new Date(root.diag.lastRunAt), "HH:mm:ss"))
                            : Translation.tr("Quick local checks; nothing you said is sent anywhere.")
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    id: runAllButton

                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: root.controlExtent
                    implicitWidth: runAllRow.implicitWidth + Appearance.rounding.large * 2
                    enabled: !root.diag.anyRunning
                    opacity: enabled ? 1 : 0.55
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: root.diag.runAll()

                    Accessible.name: Translation.tr("Test everything")

                    contentItem: RowLayout {
                        id: runAllRow

                        spacing: 6

                        MaterialSymbol {
                            text: "bolt"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            text: root.diag.anyRunning ? Translation.tr("Testing…") : Translation.tr("Test everything")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            // ── Groups ─────────────────────────────────────────────────────
            Repeater {
                model: root.groups

                delegate: ColumnLayout {
                    id: groupColumn

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: root.rowGap

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.rowGap

                        MaterialSymbol {
                            text: "chevron_right"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.diag.groupTitles[groupColumn.modelData.key] ?? groupColumn.modelData.key
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Repeater {
                        model: groupColumn.modelData.items

                        delegate: DiagCheckRow {}
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: Appearance.rounding.large
            }
        }
    }

    ScrollEdgeFade {
        target: sheetFlickable
        vertical: true
    }

    /**
     * One check: status glyph, name, the sentence that says what is missing,
     * and its own way to be asked again. Same silhouette as the canvas rows
     * around the chat, but taller — the detail line is the point here.
     */
    component DiagCheckRow: Rectangle {
        id: rowRoot

        required property var modelData

        readonly property string checkId: rowRoot.modelData.id
        readonly property var result: root.diag.resultFor(checkId)
        readonly property bool running: root.diag.runningFor(checkId)
        readonly property string state: running ? "running" : (result.state ?? "idle")

        Layout.fillWidth: true
        implicitHeight: Math.max(rowBody.implicitHeight + root.rowGap * 2, root.controlExtent)
        radius: Appearance.rounding.large
        color: rowArea.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
            : rowArea.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.colors.colSurfaceContainerHighest

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        // Declared before the body so the pill takes the clicks its controls
        // do not: tapping anywhere else asks this one check again.
        MouseArea {
            id: rowArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.diag.retest(rowRoot.checkId)
        }

        RowLayout {
            id: rowBody

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.contentPadding
            spacing: root.rowGap * 2

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: root.stateGlyph(rowRoot.state)
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: root.stateColor(rowRoot.state)

                RotationAnimation on rotation {
                    running: rowRoot.running
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1400
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: rowRoot.modelData.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (rowRoot.running)
                            return Translation.tr("Running…");
                        return String(rowRoot.result.detail ?? "");
                    }
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButton {
                id: retestButton

                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.controlExtent
                Layout.preferredHeight: root.controlExtent
                enabled: !rowRoot.running
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: root.diag.retest(rowRoot.checkId)

                Accessible.name: Translation.tr("Test %1 again").arg(rowRoot.modelData.title)

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("Test again")
                }
            }
        }
    }
}
