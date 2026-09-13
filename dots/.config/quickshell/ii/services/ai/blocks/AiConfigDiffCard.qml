import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * What a settings change would do, before it does it.
 *
 * The assistant used to write the config the moment it decided to, and the
 * only record was a line of ticks after the fact — which is no help when the
 * key it guessed was the wrong one. Every proposed key is shown here against
 * the value it would replace, each one can be dropped on its own, and nothing
 * reaches the config until Apply.
 */
Rectangle {
    id: root

    property var messageData: null
    /** The card this is drawing, out of the turn's `toolCards`. */
    property var card: null
    readonly property var changes: Array.from(root.card?.data?.changes ?? [])

    /** Indexes the user unticked. Everything else is applied. */
    property var dropped: ({})

    readonly property int keptCount: root.keptChanges().length

    function toggle(index: int) {
        const next = {};
        for (const key in root.dropped) {
            next[key] = root.dropped[key];
        }
        next[index] = !next[index];
        root.dropped = next;
    }

    function keptChanges(): var {
        const result = [];
        for (let i = 0; i < root.changes.length; i++) {
            // A change the config would refuse is never kept, whatever the
            // ticks say: it cannot be applied, so offering it as applicable
            // would only produce a failure line after the fact.
            if (!root.dropped[i] && root.changes[i].valid !== false)
                result.push(root.changes[i]);
        }
        return result;
    }

    implicitHeight: cardColumnLayout.implicitHeight + 10 * 2
    radius: Appearance.rounding.small
    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
    border.width: 1
    border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)

    ColumnLayout {
        id: cardColumnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "tune"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                text: root.changes.length === 1 ? Translation.tr("It wants to change one setting") : Translation.tr("It wants to change %1 settings").arg(root.changes.length)
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer1
            }
        }

        Repeater {
            model: ScriptModel {
                values: root.changes
            }

            RippleButton {
                id: changeRow
                required property var modelData
                required property int index

                readonly property bool refused: changeRow.modelData.valid === false
                readonly property bool kept: !changeRow.refused && !root.dropped[changeRow.index]

                enabled: !changeRow.refused

                Layout.fillWidth: true
                leftPadding: 8
                rightPadding: 8
                topPadding: 6
                bottomPadding: 6
                buttonRadius: Appearance.rounding.verysmall
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.toggle(changeRow.index)

                contentItem: RowLayout {
                    spacing: 8

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        text: changeRow.refused ? "block" : (changeRow.kept ? "check_box" : "check_box_outline_blank")
                        iconSize: Appearance.font.pixelSize.larger
                        color: changeRow.refused ? Appearance.colors.colError : (changeRow.kept ? Appearance.colors.colPrimary : Appearance.colors.colSubtext)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: changeRow.kept ? 1 : 0.5

                        StyledText {
                            Layout.fillWidth: true
                            text: changeRow.modelData.key
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: changeRow.refused
                            text: changeRow.modelData.reason ?? ""
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colError
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: !changeRow.refused
                            spacing: 6

                            StyledText {
                                Layout.maximumWidth: parent.width * 0.45
                                text: changeRow.modelData.current
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            MaterialSymbol {
                                text: "arrow_right_alt"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: changeRow.modelData.proposed
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            spacing: 6

            StyledText {
                visible: root.keptCount !== root.changes.length
                text: Translation.tr("%1 of %2 kept").arg(root.keptCount).arg(root.changes.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            Item {
                Layout.fillWidth: true
            }

            RippleButton {
                leftPadding: 12
                rightPadding: 12
                topPadding: 5
                bottomPadding: 5
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: Ai.rejectConfigChanges(root.messageData)

                contentItem: StyledText {
                    text: Translation.tr("Discard")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }

            RippleButton {
                enabled: root.keptCount > 0
                opacity: enabled ? 1 : 0.5
                leftPadding: 12
                rightPadding: 12
                topPadding: 5
                bottomPadding: 5
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: root.card?.tool === "settings_propose_changes"
                    ? Ai.applySettingsChanges(root.messageData, root.keptChanges())
                    : Ai.applyConfigChanges(root.messageData, root.keptChanges())

                contentItem: StyledText {
                    text: root.keptCount === root.changes.length ? Translation.tr("Apply") : Translation.tr("Apply %1").arg(root.keptCount)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onPrimary
                }
            }
        }
    }
}
