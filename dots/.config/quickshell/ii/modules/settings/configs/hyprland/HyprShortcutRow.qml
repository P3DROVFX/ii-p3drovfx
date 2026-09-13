pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One shortcut in the list: the keys on the left, what they do on the right.
 *
 * The same shape the cheatsheet uses, deliberately - it is the same information, and a shortcut
 * that looks like two different things in two places is two things to learn. What used to sit
 * under the name was "keybinds.lua:214", the file and line the bind was parsed from, on every
 * row: never something to act on, and it doubled the height of the list. Where a bind came from
 * is on the editor page, where changing it is the point.
 *
 * Nothing else is flagged here either. The stock config deliberately pairs most shell actions
 * with a fallback command on the same key, so a "something else is on this key" marker was on
 * every row in the list and therefore told nobody anything; the editor says it where it matters,
 * which is while you are about to take a key over.
 */
RippleButton {
    id: root

    required property var row

    signal openSubPage

    Layout.fillWidth: true
    implicitHeight: contentLayout.implicitHeight + 16
    useDynamicRadius: true

    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    onClicked: root.openSubPage()

    HighlightOverlay {
        anchors.fill: parent
        radius: root.buttonEffectiveRadius
        color: Appearance.colors.colSecondaryContainer
    }

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 12

            // A fixed width rather than a maximum: a Flow only knows to wrap once it has been
            // given one, and four modifiers plus a key is wider than a settings row.
            Flow {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 168
                spacing: 4

                Repeater {
                    model: HyprlandBinds.sortMods(root.row.mods ?? [])

                    delegate: HyprKeyChip {
                        required property var modelData

                        subdued: true
                        symbolKey: modelData
                        text: HyprlandBinds.modLabels[modelData] ?? modelData
                    }
                }

                HyprKeyChip {
                    symbolKey: root.row.resolved ? root.row.key : ""
                    text: root.row.resolved ? HyprlandBinds.keyLabel(root.row.key)
                        : Translation.tr("In a loop")
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: HyprlandBinds.titleOf(root.row)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.row.managed === true
                text: "edit"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "chevron_right"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }
        }
    }
}
