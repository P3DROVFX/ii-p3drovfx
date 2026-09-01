pragma ComponentBehavior: Bound

import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * What the assistant carries between conversations, in plain sight.
 *
 * Every line here goes into the system prompt of every chat, so every line
 * here can be read, rewritten and deleted. The model can add to this list
 * only through a tool that asks first, and the switch at the top takes the
 * whole thing out of the prompt without throwing anything away.
 */
Item {
    id: root

    signal closed

    readonly property real rowHeight: Math.round(Appearance.font.pixelSize.huge * 2)

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.unsharpenmore

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.rowHeight
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Appearance.rounding.small
                anchors.rightMargin: Appearance.rounding.unsharpenmore
                spacing: Appearance.rounding.unsharpenmore

                MaterialSymbol {
                    text: AiMemory.enabled ? "psychology" : "psychology_alt"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: AiMemory.enabled
                        ? Translation.tr("Used in every chat")
                        : Translation.tr("Kept, but not sent")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }

                StyledSwitch {
                    checked: AiMemory.enabled
                    onToggled: Config.options.ai.memory.enabled = checked
                }
            }
        }

        Rectangle {
            // Adding one by hand, which is the only way that does not need the
            // model to have thought of it first.
            Layout.fillWidth: true
            implicitHeight: root.rowHeight
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
                    text: "add"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }

                StyledTextInput {
                    id: newFactField
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnLayer2
                    onAccepted: {
                        if (AiMemory.remember(newFactField.text, "user"))
                            newFactField.clear();
                    }

                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: newFactField.text.length === 0
                        text: Translation.tr("Something it should always know")
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitHeight: Math.round(root.rowHeight * 0.72)
                    leftPadding: Appearance.rounding.small
                    rightPadding: Appearance.rounding.small
                    topPadding: 0
                    bottomPadding: 0
                    buttonRadius: Appearance.rounding.full
                    enabled: newFactField.text.trim().length > 0
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: {
                        if (AiMemory.remember(newFactField.text, "user"))
                            newFactField.clear();
                    }

                    contentItem: StyledText {
                        text: Translation.tr("Remember")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }

        StyledFlickable {
            id: factFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: factColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: factColumn
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Appearance.rounding.unsharpen

                Repeater {
                    model: ScriptModel {
                        values: Array.from(AiMemory.facts).reverse()
                    }

                    delegate: Rectangle {
                        id: factRow
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: Math.max(root.rowHeight, factText.implicitHeight + Appearance.rounding.small * 2)
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer2

                        StaggeredEntrance {
                            target: factRow
                            index: factRow.index
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Appearance.rounding.small
                            anchors.rightMargin: Appearance.rounding.unsharpen
                            spacing: Appearance.rounding.unsharpenmore

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: Appearance.rounding.unsharpen
                                text: factRow.modelData.source === "assistant" ? "smart_toy" : "person"
                                fill: 1
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext

                                StyledToolTip {
                                    text: factRow.modelData.source === "assistant"
                                        ? Translation.tr("The model asked to remember this")
                                        : Translation.tr("You wrote this")
                                }
                            }

                            StyledTextInput {
                                id: factText
                                Layout.fillWidth: true
                                text: factRow.modelData.text
                                color: Appearance.colors.colOnLayer2
                                onAccepted: AiMemory.edit(factRow.modelData.id, factText.text)
                                onActiveFocusChanged: {
                                    if (!activeFocus && factText.text !== factRow.modelData.text)
                                        AiMemory.edit(factRow.modelData.id, factText.text);
                                }
                            }

                            RippleButton {
                                implicitWidth: Math.round(root.rowHeight * 0.7)
                                implicitHeight: implicitWidth
                                buttonRadius: Appearance.rounding.full
                                topPadding: 0
                                bottomPadding: 0
                                leftPadding: 0
                                rightPadding: 0
                                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                                colBackgroundHover: Appearance.colors.colLayer3Hover
                                colRipple: Appearance.colors.colLayer3Active
                                onClicked: AiMemory.forget(factRow.modelData.id)

                                Accessible.name: Translation.tr("Forget this")

                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "delete"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer2
                                }

                                StyledToolTip {
                                    text: Translation.tr("Forget this")
                                }
                            }
                        }
                    }
                }
            }
        }

        PagePlaceholder {
            Layout.fillWidth: true
            Layout.fillHeight: true
            shown: AiMemory.facts.length === 0
            icon: "psychology"
            title: Translation.tr("Nothing remembered yet")
            description: Translation.tr("Write a line above, or let the model ask to keep one")
        }
    }
}
