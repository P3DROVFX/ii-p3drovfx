pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The dock's saved layouts (DockPresets): a slab with a header that names the one
 * the dock matches now, a field to save the current dock under a name, and the
 * presets as cards in balanced columns. The matching card fills with the
 * secondary container; clicking a card loads it, its corner button deletes it.
 */
Rectangle {
    id: root

    readonly property var presets: DockPresets.presetsList ?? []
    // Re-read when the dock's contents change, not only when the list does.
    readonly property int activeIndex: {
        Config.options.dock.pinnedApps;
        Config.options.dock.order;
        Config.options.dock.enableMediaWidget;
        Config.options.dock.enableWeatherWidget;
        Config.options.dock.enableSportsWidget;
        Config.options.dock.enableLivePreviewWidget;
        root.presets;
        return DockPresets.findMatchingPresetIndex();
    }

    function save() {
        const name = nameField.text.trim();
        if (name.length === 0)
            return;
        DockPresets.saveCurrentAsPreset(name);
        nameField.text = "";
    }

    implicitHeight: column.implicitHeight + 40
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                text: "bookmarks"
                iconSize: 24
                padding: 12
                fill: 1
                shape: MaterialShape.Shape.Cookie7Sided
                color: Appearance.colors.colTertiaryContainer
                colSymbol: Appearance.colors.colOnTertiaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Presets")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (root.presets.length === 0)
                            return Translation.tr("Save the apps, folders and widgets on the dock to come back to them");
                        const now = root.activeIndex >= 0 ? root.presets[root.activeIndex]?.name ?? "" : "";
                        const count = root.presets.length === 1 ? Translation.tr("1 saved") : Translation.tr("%1 saved").arg(root.presets.length);
                        return now.length > 0 ? Translation.tr("%1 · the dock matches “%2”").arg(count).arg(now) : count;
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Save the dock as it is now.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ToolbarTextField {
                id: nameField
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                placeholderText: Translation.tr("Name the current dock…")
                font.pixelSize: Appearance.font.pixelSize.normal
                onAccepted: root.save()
            }
            RippleButton {
                id: saveButton
                enabled: nameField.text.trim().length > 0
                implicitHeight: 48
                implicitWidth: saveRow.implicitWidth + 36
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.small
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: root.save()
                contentItem: Item {
                    RowLayout {
                        id: saveRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "bookmark_add"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Save")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }

        // The presets, in columns balanced over the rows they need.
        Flow {
            id: grid
            Layout.fillWidth: true
            visible: root.presets.length > 0
            spacing: 10
            readonly property int count: root.presets.length
            readonly property int maxCols: Math.max(1, Math.floor((width + spacing) / (148 + spacing)))
            readonly property int rows: Math.max(1, Math.ceil(grid.count / grid.maxCols))
            // Rows as even as the count allows: 5 over two rows is 3 + 2, never 4 + 1.
            function widthAt(index) {
                const base = Math.floor(grid.count / grid.rows);
                const extra = grid.count % grid.rows;
                let start = 0;
                for (let row = 0; row < grid.rows; row++) {
                    const inRow = base + (row < extra ? 1 : 0);
                    if (index < start + inRow)
                        return Math.floor((grid.width - grid.spacing * (inRow - 1)) / inRow);
                    start += inRow;
                }
                return grid.width;
            }

            Repeater {
                model: root.presets
                delegate: PresetCard {
                    required property var modelData
                    required property int index
                    preset: modelData
                    presetIndex: index
                    width: grid.widthAt(index)
                }
            }
        }
    }

    component PresetCard: RippleButton {
        id: card

        property var preset: ({})
        property int presetIndex: -1
        readonly property bool active: root.activeIndex === card.presetIndex
        readonly property color colContent: card.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        readonly property var glyphs: {
            const p = card.preset;
            const out = [];
            if (p.enableMediaWidget) out.push("play_circle");
            if (p.enableWeatherWidget) out.push("cloud");
            if (p.enableSportsWidget) out.push("sports_soccer");
            if (p.enableLivePreviewWidget) out.push("live_tv");
            if (p.showPhoneButton) out.push("smartphone");
            if (p.showOverviewButton) out.push("apps");
            if (p.showPinButton) out.push("keep");
            if (p.showTrashButton) out.push("delete");
            return out;
        }

        implicitHeight: 128
        buttonRadius: Appearance.rounding.large
        buttonRadiusPressed: Appearance.rounding.normal
        colBackground: card.active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: card.active ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
        colRipple: card.active ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active
        onClicked: DockPresets.applyPreset(card.preset)

        StyledToolTip {
            text: Translation.tr("Load this preset")
            extraVisibleCondition: !deleteButton.hovered
        }

        contentItem: Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                anchors.rightMargin: 12
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: card.preset.name ?? Translation.tr("Unnamed Preset")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: card.colContent
                        elide: Text.ElideRight
                    }
                    // Delete, in the card's own tint; error colours only under the pointer.
                    RippleButton {
                        id: deleteButton
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: height / 2
                        colBackground: ColorUtils.applyAlpha(card.colContent, 0.08)
                        colBackgroundHover: Appearance.colors.colErrorContainer
                        colRipple: Appearance.colors.colErrorContainerActive
                        onClicked: DockPresets.deletePreset(card.presetIndex)
                        contentItem: MaterialSymbol {
                            text: "delete"
                            iconSize: 17
                            horizontalAlignment: Text.AlignHCenter
                            color: deleteButton.hovered ? Appearance.colors.colOnErrorContainer : card.colContent
                        }
                        StyledToolTip {
                            text: Translation.tr("Delete preset")
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const apps = (card.preset.pinnedApps ?? []).length;
                        const files = (card.preset.pinnedFiles ?? []).length;
                        const a = apps === 1 ? Translation.tr("1 app") : Translation.tr("%1 apps").arg(apps);
                        const f = files === 1 ? Translation.tr("1 folder") : Translation.tr("%1 folders").arg(files);
                        return card.active ? a + " · " + f + " · " + Translation.tr("On the dock now") : a + " · " + f;
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: card.colContent
                    opacity: 0.8
                    elide: Text.ElideRight
                }

                Item {
                    Layout.fillHeight: true
                }

                Row {
                    spacing: 4
                    Repeater {
                        model: card.glyphs
                        delegate: Rectangle {
                            required property string modelData
                            width: 28
                            height: 28
                            radius: Appearance.rounding.full
                            color: ColorUtils.applyAlpha(card.colContent, 0.1)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: parent.modelData
                                iconSize: 15
                                fill: 1
                                color: card.colContent
                            }
                        }
                    }
                }
            }
        }
    }
}
