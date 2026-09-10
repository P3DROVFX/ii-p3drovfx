pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * The commits the fork's remote is ahead by, grouped by what kind of change
 * they are (from the "type(scope): summary" subject convention). Shared by the
 * bar indicator's popup, which caps the rows, and the About page, which does
 * not. Clicking a row opens the commit on GitHub.
 */
ColumnLayout {
    id: root

    // 0 lists everything; otherwise the first N rows in group order and a
    // trailing "and N more".
    property int maxRows: 0
    property bool compact: false
    property real rowSpacing: 4
    // Row colours; Settings sits on a layer-2 surface and overrides them one
    // layer down so the rows stay visible without hover.
    property color rowColor: Appearance.colors.colLayer2
    property color rowHoverColor: Appearance.colors.colLayer2Hover

    readonly property var groupDefs: [
        { id: "feat", title: Translation.tr("New"), icon: "auto_awesome", types: ["feat", "feature", "add"] },
        { id: "fix", title: Translation.tr("Fixes"), icon: "build", types: ["fix", "bugfix", "hotfix"] },
        { id: "perf", title: Translation.tr("Performance"), icon: "speed", types: ["perf"] },
        { id: "style", title: Translation.tr("Look"), icon: "palette", types: ["style", "ui"] },
        { id: "internal", title: Translation.tr("Internals"), icon: "construction", types: ["refactor", "chore", "build", "ci", "test", "docs", "revert"] },
        { id: "other", title: Translation.tr("Other"), icon: "commit", types: [] }
    ]

    readonly property var groups: {
        const commits = Array.from(ShellUpdates.commits ?? []);
        const buckets = root.groupDefs.map(def => ({ def: def, commits: [] }));
        const other = buckets[buckets.length - 1];
        for (const commit of commits) {
            const bucket = buckets.find(entry => entry.def.types.indexOf(commit.type) >= 0) ?? other;
            bucket.commits.push(commit);
        }
        let budget = root.maxRows > 0 ? root.maxRows : Number.MAX_SAFE_INTEGER;
        const shown = [];
        for (const bucket of buckets) {
            if (bucket.commits.length === 0 || budget <= 0) continue;
            const slice = bucket.commits.slice(0, budget);
            budget -= slice.length;
            shown.push({ id: bucket.def.id, title: bucket.def.title, icon: bucket.def.icon, total: bucket.commits.length, commits: slice });
        }
        return shown;
    }
    readonly property int shownCount: root.groups.reduce((sum, group) => sum + group.commits.length, 0)
    readonly property int hiddenCount: Math.max(0, (ShellUpdates.commits?.length ?? 0) - root.shownCount)

    function groupColor(id) {
        if (id === "feat") return Appearance.colors.colPrimaryContainer;
        if (id === "fix") return Appearance.colors.colErrorContainer;
        if (id === "perf" || id === "style") return Appearance.colors.colTertiaryContainer;
        return Appearance.colors.colSecondaryContainer;
    }

    function groupTextColor(id) {
        if (id === "feat") return Appearance.colors.colOnPrimaryContainer;
        if (id === "fix") return Appearance.colors.colOnErrorContainer;
        if (id === "perf" || id === "style") return Appearance.colors.colOnTertiaryContainer;
        return Appearance.colors.colOnSecondaryContainer;
    }

    spacing: root.compact ? 6 : 10

    Repeater {
        model: root.groups

        delegate: ColumnLayout {
            id: groupItem
            required property var modelData

            Layout.fillWidth: true
            spacing: root.rowSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: groupItem.modelData.icon
                    iconSize: root.compact ? 14 : 16
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: groupItem.modelData.title
                    font.pixelSize: root.compact ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: groupItem.modelData.total
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            Repeater {
                model: groupItem.modelData.commits

                delegate: Rectangle {
                    id: row
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: rowLayout.implicitHeight + (root.compact ? 8 : 12)
                    radius: Appearance.rounding.small
                    color: rowMouse.containsMouse ? root.rowHoverColor : root.rowColor

                    Behavior on color {
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }

                    RowLayout {
                        id: rowLayout
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: root.compact ? 8 : 10
                            rightMargin: root.compact ? 8 : 10
                        }
                        spacing: 8

                        Rectangle {
                            visible: row.modelData.scope !== "" || row.modelData.breaking
                            radius: Appearance.rounding.verysmall
                            color: row.modelData.breaking ? Appearance.colors.colError : root.groupColor(groupItem.modelData.id)
                            implicitWidth: scopeText.implicitWidth + 12
                            implicitHeight: scopeText.implicitHeight + 4

                            StyledText {
                                id: scopeText
                                anchors.centerIn: parent
                                text: row.modelData.breaking ? Translation.tr("breaking") : row.modelData.scope
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: row.modelData.breaking ? Appearance.colors.colOnError : root.groupTextColor(groupItem.modelData.id)
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.summary
                            font.pixelSize: root.compact ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                            wrapMode: root.compact ? Text.NoWrap : Text.Wrap
                            maximumLineCount: root.compact ? 1 : 3
                        }

                        StyledText {
                            visible: !root.compact
                            text: String(row.modelData.sha ?? "").substring(0, 7)
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const url = ShellUpdates.commitUrl(row.modelData.sha);
                            if (url !== "") Qt.openUrlExternally(url);
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: rowMouse.containsMouse && String(row.modelData.body ?? "").trim() !== ""
                        requireOverlay: false
                        text: String(row.modelData.body ?? "").trim()
                    }
                }
            }
        }
    }

    StyledText {
        visible: root.hiddenCount > 0 || ShellUpdates.commitsTruncated
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: {
            if (root.hiddenCount > 0) return Translation.tr("and %1 more").arg(root.hiddenCount);
            return Translation.tr("Only the newest commits are listed");
        }
    }
}
