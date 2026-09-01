pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Review.
 *
 * What the hub owns on disk, and what it would write next. This used to be a dialog opened from
 * a permanently visible strip at the top of every tab; both are gone. The facts the strip was
 * spending four lines of prose on - how much is written, where, how old the backup is - are three
 * numbers, so they are three numbers, and the Lua itself gets the room a page can give it.
 */
HyprSubPage {
    id: page

    title: Translation.tr("Review")
    subtitle: Translation.tr("What this page has written, and what it would write next")

    readonly property var status: HyprlandGui.status

    /// [{ file, text, pending }] - pending ones are a diff of what has not been written yet,
    /// the rest are the block exactly as it sits on disk.
    property var blocks: []
    property int pending: 0
    /// A second read while the first is still in flight would let its answers land in the new
    /// list. They are stamped instead, and stale ones dropped.
    property int generation: 0

    property var _memo: ({})

    readonly property var staged: page.blocks.filter(block => block.pending)
    readonly property var onDisk: page.blocks.filter(block => !block.pending)

    readonly property string backupAge: {
        const at = page.status.backupAt;
        if (!at) return Translation.tr("none yet");
        const seconds = Math.max(0, Math.floor(Date.now() / 1000) - at);
        if (seconds < 90) return Translation.tr("just now");
        const minutes = Math.round(seconds / 60);
        if (minutes < 60) return Translation.tr("%1 min ago").arg(minutes);
        const hours = Math.round(minutes / 60);
        if (hours < 48) return Translation.tr("%1 h ago").arg(hours);
        return Translation.tr("%1 days ago").arg(Math.round(hours / 24));
    }

    function reload() {
        page.generation += 1;
        const generation = page.generation;
        const targets = Object.keys(HyprlandGui.targetFiles);
        page.blocks = [];
        page.pending = targets.length;
        for (const target of targets)
            HyprlandGui.previewDiff(target, (name, diff) => page.collect(generation, name, diff));
    }

    function collect(generation: int, target: string, diff: string) {
        if (generation !== page.generation) return;
        const blocks = Array.from(page.blocks);
        const file = String(HyprlandGui.targetFiles[target] ?? target).split("/").pop();
        const current = HyprlandGui.regionText(target);
        if (diff !== "") blocks.push({ "file": file, "text": diff, "pending": true });
        else if (current !== "") blocks.push({ "file": file, "text": current, "pending": false });
        page.blocks = blocks;
        page.pending -= 1;
    }

    Component.onCompleted: page.reload()

    Connections {
        target: HyprlandGui
        function onChanged() {
            reloadDebounce.restart();
        }
    }

    Timer {
        id: reloadDebounce
        // Five interpreter starts per refresh, so a burst of edits gets one answer, not one each.
        interval: 400
        onTriggered: page.reload()
    }

    /// One number and the word for it. Three of these say what the strip used to spend a
    /// paragraph on, and they are readable at a glance rather than at a sentence.
    component Stat: Rectangle {
        id: stat

        property string value: ""
        property string label: ""
        property string icon: ""
        property bool accent: false

        Layout.fillWidth: true
        implicitHeight: statColumn.implicitHeight + 32
        radius: Appearance.rounding.normal
        color: stat.accent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

        ColumnLayout {
            id: statColumn
            anchors.centerIn: parent
            spacing: 2

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: stat.icon
                iconSize: 20
                color: stat.accent ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colSubtext
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: stat.value
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: stat.accent ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: stat.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: stat.accent ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colSubtext
            }
        }
    }

    component Block: Rectangle {
        id: block

        required property var modelData

        Layout.fillWidth: true
        implicitHeight: blockColumn.implicitHeight + 28
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: blockColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 16
                rightMargin: 16
                topMargin: 14
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: block.modelData.pending ? "pending" : "description"
                    iconSize: 18
                    color: block.modelData.pending ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: block.modelData.file
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: blockText.implicitHeight + 24
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerHigh

                StyledText {
                    id: blockText
                    anchors.fill: parent
                    anchors.margins: 12
                    text: block.modelData.text
                    font.family: Appearance.font.family.monospace || "monospace"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurface
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("At a glance")
        icon: "insights"

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Stat {
                icon: "edit_document"
                value: String(page.status.managed)
                label: Translation.tr("settings written")
            }

            Stat {
                icon: "pending"
                accent: HyprlandGui.dirty
                value: String(HyprlandGui.pending.count)
                label: Translation.tr("not saved yet")
            }

            Stat {
                icon: "history"
                value: page.backupAge
                label: Translation.tr("last backup")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Not saved yet")
        icon: "pending"
        visible: page.staged.length > 0

        Repeater {
            model: page.staged

            delegate: Block {}
        }
    }

    ContentSection {
        title: Translation.tr("On disk")
        icon: "folder"

        StyledText {
            Layout.fillWidth: true
            visible: page.blocks.length === 0
            text: page.pending > 0 ? Translation.tr("Reading…")
                : Translation.tr("Nothing written yet.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: page.onDisk

            delegate: Block {}
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "shield"
                iconSize: 16
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Your own Lua above the markers is never touched. Every file is backed up first.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }
    }
}
