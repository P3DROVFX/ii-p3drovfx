pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../services/notes/NotesTemplates.js" as Templates

/**
 * Starting from something rather than from an empty page.
 *
 * A page in the note's own column, like the settings and the statistics: the rail still
 * says where you are and the list still shows the notes, so choosing a template is a step
 * on the way to writing rather than a door slammed in front of everything else.
 *
 * The catalogue on top, what the chosen one actually contains below it — a template's name
 * never says how much structure it brings, and the preview is instantiated, so the date it
 * would write is the date you see.
 */
Item {
    id: root

    signal templateChosen(string title, var tags, var blocks)

    clip: true

    /**
     * The page arrives rather than appearing.
     *
     * Nothing else in this app changes a whole column without saying so, and a third of
     * the window swapping its contents between two frames reads as a glitch. The column
     * fades and settles by a few pixels — the shell's own `elementMoveEnter` curve, the
     * one the lists use.
     */
    Component.onCompleted: entrance.restart()

    ParallelAnimation {
        id: entrance

        NumberAnimation {
            target: root
            property: "opacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: sections
            property: "y"
            from: NotesMetrics.readingPadding + 14
            to: NotesMetrics.readingPadding
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    readonly property var templates: Templates.getBuiltinTemplates()
    property int selectedIndex: 0
    readonly property var selected: root.templates[root.selectedIndex] ?? root.templates[0] ?? null
    readonly property var previewBlocks: root.selected ? Templates.instantiateBlocks(root.selected) : []

    function use(): void {
        if (!root.selected)
            return;
        const item = root.selected;
        root.templateChosen(item.name,
            Array.isArray(item.tags) ? item.tags.slice() : [],
            Templates.instantiateBlocks(item));
    }

    StyledFlickable {
        anchors.fill: parent
        contentHeight: sections.implicitHeight + NotesMetrics.readingPadding * 2
        clip: true

        ColumnLayout {
            id: sections
            width: Math.min(root.width - NotesMetrics.paneGap * 2, NotesMetrics.readingWidth)
            x: Math.round((root.width - width) / 2)
            y: NotesMetrics.readingPadding
            spacing: 18

            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Start from")

                Repeater {
                    model: root.templates

                    delegate: RippleButton {
                        id: row
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 68
                        buttonRadius: NotesMetrics.pillRadius(row.implicitHeight)
                        toggled: root.selectedIndex === row.index
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover

                        onClicked: root.selectedIndex = row.index
                        onDoubleClicked: {
                            root.selectedIndex = row.index;
                            root.use();
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: NotesMetrics.cardPadding
                            anchors.rightMargin: NotesMetrics.cardPadding
                            spacing: 14

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: row.modelData.icon
                                iconSize: 24
                                color: row.toggled
                                    ? Appearance.m3colors.m3onSecondaryContainer
                                    : Appearance.colors.colOnLayer1
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: row.toggled
                                        ? Appearance.m3colors.m3onSecondaryContainer
                                        : Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.description
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: row.toggled
                                        ? Appearance.m3colors.m3onSecondaryContainer
                                        : Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }

            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("What you get")
                visible: root.previewBlocks.length > 0

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: NotesMetrics.cardPadding
                    spacing: 6

                    Repeater {
                        model: root.previewBlocks

                        delegate: RowLayout {
                            id: line
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 10

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: {
                                    const type = line.modelData.type;
                                    if (type === "heading")
                                        return "title";
                                    if (type === "list")
                                        return line.modelData.style === "checkbox" ? "check_box_outline_blank"
                                            : (line.modelData.style === "number" ? "format_list_numbered" : "format_list_bulleted");
                                    if (type === "callout")
                                        return "info";
                                    if (type === "code")
                                        return "code";
                                    if (type === "quote")
                                        return "format_quote";
                                    return "short_text";
                                }
                                iconSize: 16
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                // A line the template leaves for you says so; printing the
                                // block's type name instead reads as content.
                                text: String(line.modelData.text ?? "").length > 0
                                    ? line.modelData.text
                                    : Translation.tr("for you to fill in")
                                opacity: String(line.modelData.text ?? "").length > 0 ? 1 : 0.55
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: line.modelData.type === "heading" ? Font.DemiBold : Font.Normal
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            RippleButton {
                id: useButton
                Layout.fillWidth: true
                implicitHeight: 52
                buttonRadius: NotesMetrics.pillRadius(useButton.implicitHeight)
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colBackgroundActive: Appearance.colors.colPrimaryActive
                enabled: root.selected !== null

                onClicked: root.use()

                // An `Item` that fills, and the row centred inside it. A `RowLayout` used
                // directly as a `contentItem` is positioned by the control instead, and
                // `anchors.centerIn` on it is ignored — which is how the icon and the
                // label ended up left of centre in a full-width pill.
                contentItem: Item {
                    anchors.fill: parent

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "note_add"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.selected
                            ? Translation.tr("New note from %1").arg(root.selected.name)
                            : Translation.tr("New note")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }
                }
            }
        }
    }
}
