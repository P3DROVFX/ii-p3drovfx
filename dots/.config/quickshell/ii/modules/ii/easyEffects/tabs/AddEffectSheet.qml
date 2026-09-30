pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * Picks an effect to add at the end of the chain. The new effect starts at EasyEffects'
 * own defaults, and the preset is saved and reloaded with it.
 */
ClockSheet {
    id: root

    required property var editor

    readonly property var entries: Object.keys(root.editor.table)
        .map(id => ({ id: id, name: root.editor.table[id].name }))
        .filter(entry => search.text.length === 0 || entry.name.toLowerCase().includes(search.text.trim().toLowerCase()))
        .sort((a, b) => a.name.localeCompare(b.name))

    title: Translation.tr("Add effect")
    subtitle: root.editor.presetName
    scrollable: true

    Component.onCompleted: Qt.callLater(search.focusInput)

    ClockFormField {
        id: search
        symbol: "search"
        caption: Translation.tr("Find an effect")
        placeholder: Translation.tr("Equalizer, compressor…")
        onAccepted: {
            if (root.entries.length > 0)
                root.pick(root.entries[0].id);
        }
    }

    function pick(plugin: string): void {
        root.editor.addEffect(plugin);
        root.close();
    }

    Repeater {
        model: root.entries

        RippleButton {
            id: entry
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 52
            buttonRadius: Appearance.rounding.small
            colBackground: ClockStyle.colField
            colBackgroundHover: ClockStyle.colFieldHover
            onClicked: root.pick(entry.modelData.id)

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                MaterialSymbol {
                    text: Logic.effectIcon(entry.modelData.id)
                    iconSize: ClockStyle.iconNormal
                    color: ClockStyle.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: entry.modelData.name
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal + 1
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    visible: root.editor.chain.some(id => Logic.instanceParts(id).plugin === entry.modelData.id)
                    text: Translation.tr("in chain")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }
        }
    }
}
