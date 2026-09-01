pragma ComponentBehavior: Bound

import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Projects: a folder with an opinion.
 *
 * Chats filed under one share a prompt, so "the shell" and "the thesis" stop
 * needing the same paragraph typed into every conversation. Filing is a
 * choice made here, on the chat that is open; nothing is moved automatically,
 * and a chat with no project behaves exactly as it did before projects
 * existed.
 */
Item {
    id: root

    signal closed

    readonly property real rowHeight: Math.round(Appearance.font.pixelSize.huge * 2.2)
    readonly property var projects: Ai.projects
    property string editingId: ""

    function persist(list) {
        Config.options.ai.projects = list;
    }

    function addProject(name: string) {
        const trimmed = String(name ?? "").trim();
        if (trimmed.length === 0)
            return;
        const project = {
            id: `p${Date.now().toString(36)}`,
            name: trimmed,
            icon: "folder_special",
            prompt: ""
        };
        root.persist([...root.projects, project]);
        Ai.setProject(project.id);
        root.editingId = project.id;
    }

    function updateProject(projectId: string, changes: var) {
        root.persist(root.projects.map(project => String(project.id) === String(projectId)
            ? Object.assign({}, project, changes)
            : project));
    }

    function removeProject(projectId: string) {
        root.persist(root.projects.filter(project => String(project.id) !== String(projectId)));
        if (Ai.sessionProjectId === projectId)
            Ai.setProject("");
    }

    /** One project, and what can be done with it. */
    component ProjectRow: Rectangle {
        id: projectRow

        property string name: ""
        property string detail: ""
        property string icon: "folder_special"
        property bool selected: false
        property bool expanded: false
        property bool removable: true

        signal chosen
        signal toggledEditor
        signal removed

        implicitHeight: root.rowHeight
        radius: Appearance.rounding.large
        color: projectRow.selected
            ? Appearance.colors.colPrimaryContainer
            : (projectMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            id: projectMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: projectRow.chosen()
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Appearance.rounding.small
            anchors.rightMargin: Appearance.rounding.unsharpen
            spacing: Appearance.rounding.unsharpenmore

            MaterialSymbol {
                text: projectRow.icon
                fill: 1
                iconSize: Appearance.font.pixelSize.huge
                color: projectRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: projectRow.name
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: projectRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: projectRow.detail
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: projectRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                }
            }

            RippleButton {
                visible: projectRow.removable
                implicitWidth: Math.round(root.rowHeight * 0.62)
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                topPadding: 0
                bottomPadding: 0
                leftPadding: 0
                rightPadding: 0
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: projectRow.toggledEditor()

                Accessible.name: Translation.tr("Edit this project's prompt")

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: projectRow.expanded ? "keyboard_arrow_up" : "edit_note"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: projectRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("The prompt every chat here starts with")
                }
            }

            RippleButton {
                visible: projectRow.removable
                implicitWidth: Math.round(root.rowHeight * 0.62)
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                topPadding: 0
                bottomPadding: 0
                leftPadding: 0
                rightPadding: 0
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: projectRow.removed()

                Accessible.name: Translation.tr("Delete this project")

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "delete"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: projectRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("Delete the project. The chats in it stay.")
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.unsharpenmore

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.round(root.rowHeight * 0.9)
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Appearance.rounding.small
                anchors.rightMargin: Appearance.rounding.unsharpen
                spacing: Appearance.rounding.unsharpenmore

                MaterialSymbol {
                    text: "create_new_folder"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }

                StyledTextInput {
                    id: newProjectField
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnLayer2
                    onAccepted: {
                        root.addProject(newProjectField.text);
                        newProjectField.clear();
                    }

                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: newProjectField.text.length === 0
                        text: Translation.tr("Name a new project")
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitHeight: Math.round(root.rowHeight * 0.6)
                    leftPadding: Appearance.rounding.small
                    rightPadding: Appearance.rounding.small
                    topPadding: 0
                    bottomPadding: 0
                    buttonRadius: Appearance.rounding.full
                    enabled: newProjectField.text.trim().length > 0
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: {
                        root.addProject(newProjectField.text);
                        newProjectField.clear();
                    }

                    contentItem: StyledText {
                        text: Translation.tr("Create")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }

        StyledFlickable {
            id: projectFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: projectColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: projectColumn
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Appearance.rounding.unsharpen

                ProjectRow {
                    Layout.fillWidth: true
                    name: Translation.tr("No project")
                    detail: Translation.tr("This chat stands on its own")
                    icon: "block"
                    selected: Ai.sessionProjectId.length === 0
                    removable: false
                    onChosen: Ai.setProject("")
                }

                Repeater {
                    model: ScriptModel {
                        values: root.projects
                    }

                    delegate: ColumnLayout {
                        id: projectEntry
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 0

                        ProjectRow {
                            Layout.fillWidth: true
                            name: projectEntry.modelData.name ?? ""
                            detail: String(projectEntry.modelData.prompt ?? "").length > 0
                                ? Translation.tr("Has its own prompt")
                                : Translation.tr("No prompt yet")
                            icon: projectEntry.modelData.icon ?? "folder_special"
                            selected: Ai.sessionProjectId === projectEntry.modelData.id
                            expanded: root.editingId === projectEntry.modelData.id
                            onChosen: Ai.setProject(projectEntry.modelData.id)
                            onToggledEditor: root.editingId = root.editingId === projectEntry.modelData.id ? "" : projectEntry.modelData.id
                            onRemoved: root.removeProject(projectEntry.modelData.id)
                        }

                        Item {
                            // The project's own prompt, folded away until it is
                            // being written.
                            Layout.fillWidth: true
                            Layout.leftMargin: Appearance.rounding.small
                            Layout.rightMargin: Appearance.rounding.small
                            Layout.topMargin: implicitHeight > 0 ? Appearance.rounding.unsharpen : 0
                            implicitHeight: root.editingId === projectEntry.modelData.id ? Math.round(Appearance.font.pixelSize.huge * 7) : 0
                            visible: root.editingId === projectEntry.modelData.id || implicitHeight > 0.5
                            clip: true

                            Behavior on implicitHeight {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.large
                                color: Appearance.colors.colLayer2

                                StyledTextArea {
                                    id: promptArea
                                    anchors.fill: parent
                                    anchors.margins: Appearance.rounding.unsharpenmore
                                    wrapMode: TextArea.Wrap
                                    text: projectEntry.modelData.prompt ?? ""
                                    color: Appearance.colors.colOnLayer2
                                    background: null
                                    placeholderText: Translation.tr("What every chat in this project should know")
                                    onActiveFocusChanged: {
                                        if (!activeFocus && promptArea.text !== (projectEntry.modelData.prompt ?? ""))
                                            root.updateProject(projectEntry.modelData.id, {
                                                prompt: promptArea.text
                                            });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}
