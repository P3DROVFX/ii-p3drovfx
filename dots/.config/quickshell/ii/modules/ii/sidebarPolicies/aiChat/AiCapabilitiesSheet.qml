pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Everything this chat's tools can do, with a prompt to try each one — the
 * manual for the harness, in the place the chat was.
 *
 * Same idea as `ChatShortcutSheet.qml` (a page in the same canvas, reachable
 * with one key and gone again with Escape), grouped the same way, but a row
 * here is a prompt rather than a keycap: tapping it drops the exact text
 * into the composer, the same way a finished dictation does — never sent on
 * its own, so it can be read and edited before it goes out.
 *
 * The list is a fixed reference, like the shortcuts page is: it does not
 * hide a group because the current model has no tool support or a policy
 * has switched something off. A prompt trying a capability that is not
 * available right now still teaches the reader what the shell *can* do and
 * what to change to get there; a blank page would teach nothing.
 */
Item {
    id: root

    signal promptChosen(string text)

    readonly property real groupGap: Appearance.rounding.small

    function navigateUp() {
        sheetFlickable.contentY = Math.max(0, sheetFlickable.contentY - sheetFlickable.height / 2);
    }

    function navigateDown() {
        sheetFlickable.contentY = Math.min(
            Math.max(0, sheetFlickable.contentHeight - sheetFlickable.height),
            sheetFlickable.contentY + sheetFlickable.height / 2);
    }

    readonly property var groups: [
        {
            title: Translation.tr("Settings"),
            icon: "settings",
            prompts: [
                Translation.tr("Turn up the animation speed"),
                Translation.tr("What's my current wallpaper cycling interval?"),
                Translation.tr("Turn on autohide for the bar")
            ]
        },
        {
            title: Translation.tr("Files"),
            icon: "folder_open",
            note: Translation.tr("Only looks inside the folders configured for it in Advanced settings."),
            prompts: [
                Translation.tr('Search for "wallpaper name" file'),
                Translation.tr("Find any PDF I downloaded this week"),
                Translation.tr("Show me the first few lines of notes.txt")
            ]
        },
        {
            title: Translation.tr("Images & OCR"),
            icon: "text_snippet",
            prompts: [
                Translation.tr("What does the text in this screenshot say?"),
                Translation.tr("Extract the text from this photo")
            ]
        },
        {
            title: Translation.tr("Web search"),
            icon: "search",
            note: Translation.tr("Uses the internet — off entirely under the Local policy."),
            prompts: [
                Translation.tr("Search the web for the latest Quickshell release notes"),
                Translation.tr("Read this article and summarize it for me")
            ]
        },
        {
            title: Translation.tr("Sports"),
            icon: "sports_score",
            prompts: [
                Translation.tr("Ask today's Premier League games"),
                Translation.tr("Did Real Madrid win their last match?")
            ]
        },
        {
            title: Translation.tr("Time, reminders & weather"),
            icon: "alarm",
            prompts: [
                Translation.tr("Remind me to drink water in 20 minutes"),
                Translation.tr("Set a recurring alarm for weekdays at 7:00"),
                Translation.tr("Start a Pomodoro timer"),
                Translation.tr("What's the status of my stopwatch?"),
                Translation.tr("What's on my calendar today?"),
                Translation.tr("What's my next calendar event?"),
                Translation.tr("What's the weather like right now?")
            ]
        },
        {
            title: Translation.tr("System & hardware"),
            icon: "monitor_heart",
            prompts: [
                Translation.tr("Why does my PC feel slow right now?"),
                Translation.tr("What's my battery percentage?"),
                Translation.tr("Turn on Do Not Disturb")
            ]
        },
        {
            title: Translation.tr("Keyboard shortcuts"),
            icon: "keyboard",
            prompts: [
                Translation.tr("How do I take a screenshot?"),
                Translation.tr("What's the shortcut to lock my screen?")
            ]
        },
        {
            title: Translation.tr("Windows & workspaces"),
            icon: "select_window",
            prompts: [
                Translation.tr("What windows are open right now?"),
                Translation.tr("Move Firefox to workspace 3")
            ]
        },
        {
            title: Translation.tr("Theme & wallpaper"),
            icon: "wallpaper",
            prompts: [
                Translation.tr("Switch to dark mode"),
                Translation.tr("Pick a random wallpaper from my folder")
            ]
        },
        {
            title: Translation.tr("Media"),
            icon: "music_note",
            prompts: [
                Translation.tr("What song is playing right now?"),
                Translation.tr("Skip to the next track"),
                Translation.tr("What are the lyrics to this song?")
            ]
        },
        {
            title: Translation.tr("Tasks & to-dos"),
            icon: "checklist",
            prompts: [
                Translation.tr("What's on my to-do list?"),
                Translation.tr("Add \u2018buy milk\u2019 to my tasks")
            ]
        },
        {
            title: Translation.tr("Gmail"),
            icon: "mail",
            note: Translation.tr("Read-only — nothing is ever sent, replied to, or deleted."),
            prompts: [
                Translation.tr("Do I have any unread emails from my boss?"),
                Translation.tr("Search my inbox for the flight confirmation")
            ]
        },
        {
            title: Translation.tr("Memory"),
            icon: "psychology",
            prompts: [
                Translation.tr("Remember that I prefer dark roast coffee"),
                Translation.tr("What do you remember about me?")
            ]
        },
        {
            title: Translation.tr("Notes"),
            icon: "note_add",
            prompts: [
                Translation.tr("Add this summary to my notes"),
                Translation.tr("Create a note from that last answer")
            ]
        },
        {
            title: Translation.tr("Run a command"),
            icon: "terminal",
            note: Translation.tr("Always shows the exact command and waits for you to approve it — never automatic, and off entirely under the Local policy unless allowed in Advanced settings."),
            prompts: [
                Translation.tr("Check how much disk space I have left"),
                Translation.tr("List the files in my Downloads folder")
            ]
        }
    ]

    StyledFlickable {
        id: sheetFlickable
        anchors.fill: parent
        contentHeight: sheetColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: sheetColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: root.groupGap

            Repeater {
                model: ScriptModel {
                    values: root.groups
                }

                delegate: ColumnLayout {
                    id: group
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: Appearance.rounding.unsharpenmore

                    StaggeredEntrance {
                        target: group
                        index: group.index
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Appearance.rounding.unsharpenmore
                        spacing: Appearance.rounding.unsharpenmore

                        MaterialSymbol {
                            text: group.modelData.icon
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: group.modelData.title
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: group.modelData.note ?? ""
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.75
                    }

                    Repeater {
                        model: ScriptModel {
                            values: group.modelData.prompts
                        }

                        delegate: RippleButton {
                            id: promptRow
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: promptRowLayout.implicitHeight + Appearance.rounding.small * 2
                            buttonRadius: Math.min(height / 2, Appearance.rounding.large)
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: root.promptChosen(promptRow.modelData)

                            Accessible.name: promptRow.modelData

                            contentItem: RowLayout {
                                id: promptRowLayout
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Appearance.rounding.small
                                spacing: Appearance.rounding.unsharpenmore

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignTop
                                    text: "format_quote"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: promptRow.modelData
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                }

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignTop
                                    text: "north_east"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
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
        color: Appearance.colors.colLayer1
    }
}
