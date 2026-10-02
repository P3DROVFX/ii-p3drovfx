pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.easyEffects.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * Picks an effect to add at the end of the chain. The new effect starts at EasyEffects'
 * own defaults, and the preset is saved and reloaded with it.
 */
EasyEffectsSheet {
    id: root

    required property var editor

    readonly property var entries: Object.keys(root.editor.table)
        .map(id => ({ id: id, name: root.editor.table[id].name }))
        .filter(entry => search.text.length === 0 || entry.name.toLowerCase().includes(search.text.trim().toLowerCase()))
        .sort((a, b) => a.name.localeCompare(b.name))

    title: Translation.tr("Add effect")
    subtitle: root.editor.presetName
    badge: "add"
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
            readonly property bool inChain: root.editor.chain.some(id => Logic.instanceParts(id).plugin === entry.modelData.id)
            Layout.fillWidth: true
            implicitHeight: EasyEffectsStyle.railRowHeight
            buttonRadius: EasyEffectsStyle.radiusField
            colBackground: EasyEffectsStyle.colField
            colBackgroundHover: EasyEffectsStyle.colFieldHover
            colRipple: EasyEffectsStyle.colFieldHover
            onClicked: root.pick(entry.modelData.id)

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: EasyEffectsStyle.gapSmall + 2
                anchors.rightMargin: EasyEffectsStyle.gapLarge
                spacing: EasyEffectsStyle.gap

                EasyEffectsBadge {
                    size: EasyEffectsStyle.fieldBadge
                    text: Logic.effectIcon(entry.modelData.id)
                    shape: EasyEffectsStyle.shapeFor(entry.modelData.id)
                    color: EasyEffectsStyle.colPrimaryContainer
                    colSymbol: EasyEffectsStyle.colOnPrimaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: entry.modelData.name
                    elide: Text.ElideRight
                    font.variableAxes: EasyEffectsStyle.axesName
                    font.pixelSize: EasyEffectsStyle.textBody
                    color: EasyEffectsStyle.colOnSurface
                }

                EasyEffectsPill {
                    visible: entry.inChain
                    label: Translation.tr("in chain")
                    pillHeight: EasyEffectsStyle.pillHeight - EasyEffectsStyle.gapTiny
                    labelSize: EasyEffectsStyle.textCaption
                    colContent: EasyEffectsStyle.colOnSecondaryContainer
                    colFill: EasyEffectsStyle.colSecondaryContainer
                }
            }
        }
    }
}
