pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Ready-made routines under the list (Samsung's Discover tab). Collapsed
 * by default; clicking a row previews it in the right pane, Add copies it
 * into the list, where it is an ordinary routine from then on. The rows
 * scroll in their own strip, so the block shares the column with the list
 * instead of pushing the New button off the card.
 */
ColumnLayout {
    id: root

    property bool expanded: false
    /// Header plus a couple of rows: the least the block is worth showing at.
    // Expanded, it wants every template on screen; the routine list is
    // what scrolls.
    readonly property real minimumHeight: implicitHeight
    /// Template shown in the right pane, "" for none.
    property string previewKey: ""

    signal added(string id)
    signal previewRequested(string key)

    readonly property var templates: ModeSchema.routineTemplates()

    function hasCopy(key) {
        return Modes.routines.some(r => r.template === key);
    }

    spacing: 4

    RippleButton {
        Layout.fillWidth: true
        implicitHeight: 40
        buttonRadius: Appearance.rounding.normal
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: root.expanded = !root.expanded

        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 6
            }
            spacing: 8

            MaterialSymbol {
                text: "auto_awesome"
                iconSize: 20
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Templates")
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text: String(root.templates.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            MaterialSymbol {
                text: root.expanded ? "expand_less" : "expand_more"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }
    }

    StyledFlickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.expanded
        implicitHeight: contentHeight
        contentHeight: rows.implicitHeight
        contentWidth: width
        clip: true

        ColumnLayout {
            id: rows
            width: parent.width
            spacing: 2

            Repeater {
                model: root.templates

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool copied: root.hasCopy(row.modelData.template)
                    readonly property bool previewing: root.previewKey === row.modelData.template
                    readonly property string description: ModeUi.templateDescription(row.modelData.template)

                    Layout.fillWidth: true
                    implicitHeight: 56
                    radius: Appearance.rounding.normal
                    color: {
                        if (row.previewing)
                            return Appearance.colors.colSecondaryContainer;
                        return rowArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent";
                    }

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.previewRequested(row.modelData.template)
                    }

                    // The full wording when the row had to cut it short.
                    // Hung on the row, so it sits above it like any other
                    // tooltip rather than across the row's own title.
                    StyledToolTip {
                        extraVisibleCondition: rowArea.containsMouse && (nameText.truncated || descText.truncated)
                        text: nameText.truncated ? row.modelData.name + "\n" + row.description : row.description
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 8
                        }
                        spacing: 10

                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: Appearance.rounding.full
                            color: ModeUi.container(row.modelData.color ?? "")

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: row.modelData.icon
                                iconSize: 20
                                color: ModeUi.onContainer(row.modelData.color ?? "")
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                id: nameText
                                Layout.fillWidth: true
                                text: row.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: row.previewing ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                id: descText
                                Layout.fillWidth: true
                                text: row.description
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: row.previewing ? ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.3)
                                    : Appearance.colors.colSubtext
                            }
                        }

                        RippleButton {
                            implicitHeight: 30
                            implicitWidth: addRow.implicitWidth + 20
                            buttonRadius: Appearance.rounding.full
                            colBackground: row.copied ? Appearance.colors.colLayer2 : Appearance.colors.colSecondaryContainer
                            colBackgroundHover: row.copied ? Appearance.colors.colLayer2Hover : Appearance.colors.colSecondaryContainerHover
                            colRipple: row.copied ? Appearance.colors.colLayer2Active : Appearance.colors.colSecondaryContainerActive
                            onClicked: root.added(Modes.addRoutineFromTemplate(row.modelData.template))

                            StyledToolTip {
                                text: row.copied ? Translation.tr("Already in the list — add another copy") : Translation.tr("Add to the list")
                            }

                            contentItem: RowLayout {
                                id: addRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    text: row.copied ? "check" : "add"
                                    iconSize: 16
                                    color: row.copied ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnSecondaryContainer
                                }

                                StyledText {
                                    text: row.copied ? Translation.tr("Added") : Translation.tr("Add")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: row.copied ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
