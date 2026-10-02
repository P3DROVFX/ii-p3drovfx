pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.easyEffects.components

/**
 * The preset in use as a hero, and every preset on the pipeline as a card beside it,
 * filtered by family ("A50 · Music" belongs to "A50"). A click loads a preset; the card's
 * own buttons edit it, make it the device's default, duplicate, rename or delete it.
 * Deleting keeps a copy in the preset folder's `.ii-backup/`.
 *
 * Wide, the hero stands in a column beside the grid; narrower it is a strip above it.
 * The columns of the grid are decided on the settled width, so opening a sheet never
 * re-deals the cards while it slides.
 */
Item {
    id: root

    required property var editor
    required property var panels
    property bool compact: false
    property bool wide: false
    /// The page's settled width and whether the hero fits beside the grid (see AppContent).
    property real layoutWidth: width
    property bool heroBeside: false

    signal editRequested()

    readonly property string pipeline: root.editor.pipeline
    readonly property var presets: root.pipeline === "input" ? EasyEffects.inputPresets : EasyEffects.outputPresets
    readonly property string current: root.pipeline === "input" ? EasyEffects.inputPreset : EasyEffects.outputPreset
    readonly property string deviceDefault: root.pipeline === "input" ? EasyEffects.inputDeviceDefault : EasyEffects.outputDeviceDefault
    readonly property var device: root.pipeline === "input" ? EasyEffects.inputDevice : EasyEffects.outputDevice
    /// Everything but a family the filter names is hidden; "*" shows all.
    property string filter: "*"
    readonly property var families: {
        const counts = {};
        const order = [];
        Array.from(root.presets).forEach(name => {
            const family = EasyEffects.familyOf(name);
            if (!(family in counts)) {
                counts[family] = 0;
                order.push(family);
            }
            counts[family]++;
        });
        // Named families in name order; the unfamilied ones last.
        order.sort((a, b) => (a === "") - (b === "") || a.localeCompare(b));
        return order.map(family => ({ family: family, count: counts[family] }));
    }
    readonly property bool filterable: root.families.length > 1
    readonly property string activeFilter: root.filterable && root.families.some(entry => entry.family === root.filter) ? root.filter : "*"
    readonly property var shown: {
        const order = root.families.map(entry => entry.family);
        return Array.from(root.presets)
            .filter(name => root.activeFilter === "*" || EasyEffects.familyOf(name) === root.activeFilter)
            .sort((a, b) => order.indexOf(EasyEffects.familyOf(a)) - order.indexOf(EasyEffects.familyOf(b)) || a.localeCompare(b));
    }

    PresetLibrary {
        id: library
        pipeline: root.pipeline
    }

    onPipelineChanged: root.filter = "*"

    /// What the hero shows (Settings > Preset card).
    readonly property var heroOptions: Config.options.easyEffects.hero

    property string notice: ""

    function say(text: string): void {
        root.notice = text;
        noticeTimer.restart();
    }

    Timer {
        id: noticeTimer
        interval: 3500
        onTriggered: root.notice = ""
    }

    function askName(title: string, initial: string, confirm: string, then: var): void {
        const sheet = root.panels.show(promptSheet, {
            title: title,
            caption: Translation.tr("Preset name"),
            initialText: initial,
            confirmLabel: confirm,
            symbol: "edit"
        });
        if (!sheet)
            return;
        sheet.submitted.connect(text => then(text.replace(/[\/\\]/g, " ").trim()));
    }

    function newPreset(): void {
        const family = EasyEffects.familyOf(root.current);
        root.askName(Translation.tr("New preset"), family.length > 0 ? `${family} · ` : "", Translation.tr("Create"), name => {
            if (name.length === 0 || root.presets.includes(name))
                return root.say(Translation.tr("A preset needs a new name"));
            const preset = {};
            preset[root.pipeline] = { blocklist: [], plugins_order: [] };
            EasyEffects.writePreset(root.pipeline, name, preset, ok => {
                root.say(ok ? Translation.tr("Created \"%1\"").arg(name) : Translation.tr("Couldn't create \"%1\"").arg(name));
                if (ok)
                    EasyEffects.refreshPresets();
            });
        });
    }

    function duplicate(name: string): void {
        root.askName(Translation.tr("Duplicate preset"), `${name} (copy)`, Translation.tr("Duplicate"), copy => {
            if (copy.length === 0 || root.presets.includes(copy))
                return root.say(Translation.tr("A preset needs a new name"));
            EasyEffects.duplicatePreset(root.pipeline, name, copy, ok => {
                root.say(ok ? Translation.tr("Duplicated as \"%1\"").arg(copy) : Translation.tr("Couldn't duplicate \"%1\"").arg(name));
                EasyEffects.refreshPresets();
            });
        });
    }

    function rename(name: string): void {
        root.askName(Translation.tr("Rename preset"), name, Translation.tr("Rename"), to => {
            if (to.length === 0 || to === name || root.presets.includes(to))
                return;
            EasyEffects.renamePreset(root.pipeline, name, to, ok => {
                root.say(ok ? Translation.tr("Renamed to \"%1\"").arg(to) : Translation.tr("Couldn't rename \"%1\"").arg(name));
                EasyEffects.refreshPresets();
                // A device default naming the old preset follows it.
                if (ok && root.deviceDefault === name)
                    EasyEffects.setDeviceDefault(root.pipeline, root.device, to);
            });
        });
    }

    function remove(name: string): void {
        const sheet = root.panels.show(confirmSheet, { presetName: name });
        if (!sheet)
            return;
        sheet.confirmed.connect(() => {
            EasyEffects.deletePreset(root.pipeline, name, ok => {
                root.say(ok ? Translation.tr("Deleted \"%1\"").arg(name) : Translation.tr("Couldn't delete \"%1\"").arg(name));
                EasyEffects.refreshPresets();
            });
        });
    }

    function toggleDefault(name: string): void {
        const clearing = root.deviceDefault === name;
        EasyEffects.setDeviceDefault(root.pipeline, root.device, clearing ? "" : name, ok => {
            if (!ok)
                return root.say(Translation.tr("Couldn't change the device default"));
            root.say(clearing ? Translation.tr("%1 has no default preset now").arg(Audio.friendlyDeviceName(root.device))
                : Translation.tr("%1 now starts with \"%2\"").arg(Audio.friendlyDeviceName(root.device)).arg(name));
        });
    }

    function importPreset(): void {
        EasyEffects.pickAndImport((ok, name, noPicker) => {
            if (noPicker)
                return root.say(Translation.tr("Install kdialog or zenity to pick a file"));
            if (name.length > 0 || ok)
                root.say(ok ? Translation.tr("Imported \"%1\"").arg(name) : Translation.tr("That file isn't an EasyEffects preset"));
            EasyEffects.refreshPresets();
        });
    }

    // ── Geometry ──────────────────────────────────────────────────────────
    readonly property real heroWidth: root.heroBeside
        ? Math.max(EasyEffectsStyle.heroWidthMin, Math.min(EasyEffectsStyle.heroWidth, root.layoutWidth * 0.34)) : 0
    readonly property real stripHeight: root.compact ? EasyEffectsStyle.fabSize : EasyEffectsStyle.fabSize + EasyEffectsStyle.gapLarge
    readonly property real contentX: root.heroBeside ? root.heroWidth + EasyEffectsStyle.gap : 0
    readonly property real contentY: root.heroBeside ? 0 : root.stripHeight + EasyEffectsStyle.gap
    /// The grid's width once the sheet and rail have settled.
    readonly property real gridLayoutWidth: Math.max(0, root.layoutWidth - root.contentX)
    readonly property int columns: Math.max(1, Math.floor((root.gridLayoutWidth + EasyEffectsStyle.gap) / (EasyEffectsStyle.presetCardMinWidth + EasyEffectsStyle.gap)))
    /// A grid too narrow for chips with glyphs and a labelled Import button.
    readonly property bool tight: root.gridLayoutWidth < EasyEffectsStyle.presetCardMinWidth * 2 + EasyEffectsStyle.gapHuge * 4
    readonly property real cardWidth: Math.floor((root.gridLayoutWidth - EasyEffectsStyle.gap * (root.columns - 1)) / root.columns)

    PresetHero {
        id: hero
        x: 0
        y: 0
        width: root.heroBeside ? root.heroWidth : root.width
        height: root.heroBeside ? root.height : root.stripHeight
        editor: root.editor
        strip: !root.heroBeside
        compact: root.compact
        showTopography: root.heroOptions.topography ?? true
        topographyReactive: root.heroOptions.topographyReactive ?? true
        topographyStrength: (root.heroOptions.topographyStrength ?? 100) / 100
        art: root.heroOptions.art ?? "shape"
        showDevice: root.heroOptions.showDevice ?? true
        showState: root.heroOptions.showState ?? true
        showDefault: root.heroOptions.showDefault ?? true
        showWave: root.heroOptions.showWave ?? true
        showCaption: root.heroOptions.showCaption ?? true
        showName: root.heroOptions.showName ?? true
        showEffects: root.heroOptions.showEffects ?? true
        showButtons: root.heroOptions.showButtons ?? true
        onEditRequested: root.editRequested()
    }

    Item {
        id: content
        x: root.contentX
        y: root.contentY
        width: root.width - root.contentX
        height: root.height - root.contentY

        ColumnLayout {
            anchors.fill: parent
            spacing: EasyEffectsStyle.gap

            // ── Filters (Import and the folder live in the app bar) ───────────
            Flow {
                Layout.fillWidth: true
                visible: root.filterable
                spacing: EasyEffectsStyle.gapSmall

                EasyEffectsFilterChip {
                    label: Translation.tr("All")
                    symbol: root.tight ? "" : "select_all"
                    count: root.presets.length
                    selected: root.activeFilter === "*"
                    onTriggered: root.filter = "*"
                }

                Repeater {
                    model: root.filterable ? root.families : []

                    EasyEffectsFilterChip {
                        required property var modelData
                        label: modelData.family.length > 0 ? modelData.family : Translation.tr("Other")
                        symbol: root.tight ? "" : (modelData.family.length > 0 ? EasyEffects.iconFor(modelData.family) : "more_horiz")
                        count: modelData.count
                        selected: root.activeFilter === modelData.family
                        onTriggered: root.filter = modelData.family
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledFlickable {
                    id: flick
                    anchors.fill: parent
                    clip: true
                    visible: root.presets.length > 0
                    contentWidth: width
                    contentHeight: grid.implicitHeight + EasyEffectsStyle.fabClearance

                    Flow {
                        id: grid
                        width: Math.max(flick.width, root.gridLayoutWidth)
                        spacing: EasyEffectsStyle.gap

                        move: Transition {
                            enabled: !EasyEffectsStyle.reducedMotion
                            NumberAnimation {
                                properties: "x,y"
                                duration: EasyEffectsStyle.motionDefault.duration
                                easing.type: Easing.OutCubic
                            }
                        }

                        Repeater {
                            model: root.shown

                            PresetCard {
                                id: card
                                required property string modelData
                                required property int index
                                name: modelData
                                info: library.infoOf(modelData)
                                inUse: modelData === root.current
                                isDefault: modelData === root.deviceDefault
                                deviceName: Audio.friendlyDeviceName(root.device)
                                width: root.cardWidth
                                onChosen: EasyEffects.loadPreset(card.modelData, root.pipeline, false)
                                onEditRequested: {
                                    if (!card.inUse)
                                        EasyEffects.loadPreset(card.modelData, root.pipeline, false);
                                    root.editRequested();
                                }
                                onDefaultToggled: root.toggleDefault(card.modelData)
                                onMoreRequested: root.panels.show(actionsSheet, { presetName: card.modelData })

                                Behavior on width {
                                    enabled: !EasyEffectsStyle.reducedMotion
                                    animation: EasyEffectsStyle.motionDefault.numberAnimation.createObject(card)
                                }

                                StaggeredEntrance {
                                    index: card.index
                                }
                            }
                        }
                    }
                }

                ClockEmptyState {
                    anchors.centerIn: parent
                    visible: root.presets.length === 0
                    symbol: "library_music"
                    title: Translation.tr("No presets yet")
                    subtitle: root.pipeline === "input"
                        ? Translation.tr("Input presets process your microphone. Create one here, or import a file.")
                        : Translation.tr("Create one here, import a file, or save one from EasyEffects' own window.")
                }
            }
        }

        FloatingActionButton {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: EasyEffectsStyle.gapTiny
            anchors.bottomMargin: EasyEffectsStyle.gapTiny
            baseSize: root.compact ? EasyEffectsStyle.fabSizeCompact : EasyEffectsStyle.fabSize
            iconSize: root.compact ? EasyEffectsStyle.iconLarge : EasyEffectsStyle.fabIcon
            buttonRadius: EasyEffectsStyle.radiusFab
            buttonRadiusPressed: EasyEffectsStyle.radiusFabPressed
            iconText: "add"
            buttonText: Translation.tr("New preset")
            expanded: hovered
            colBackground: EasyEffectsStyle.colPrimaryContainer
            colBackgroundHover: EasyEffectsStyle.colPrimaryContainerHover
            colBackgroundActive: EasyEffectsStyle.colPrimaryContainerActive
            colRipple: EasyEffectsStyle.colPrimaryContainerActive
            colOnBackground: EasyEffectsStyle.colOnPrimaryContainer
            onClicked: root.newPreset()
        }
    }

    // ── Notice ────────────────────────────────────────────────────────────
    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: EasyEffectsStyle.gapLarge
        }
        visible: opacity > 0
        opacity: root.notice.length > 0 ? 1 : 0
        width: Math.min(parent.width - EasyEffectsStyle.gapHuge * 2, noticeText.implicitWidth + EasyEffectsStyle.gapHuge * 2)
        height: 44
        radius: EasyEffectsStyle.pill(44)
        color: Appearance.m3colors.m3inverseSurface

        Behavior on opacity {
            animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
        }

        StyledText {
            id: noticeText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - EasyEffectsStyle.gapHuge * 2)
            elide: Text.ElideRight
            text: root.notice
            font.pixelSize: EasyEffectsStyle.textNormal
            color: Appearance.m3colors.m3inverseOnSurface
        }
    }

    Component {
        id: promptSheet
        EasyEffectsPromptSheet {}
    }

    // What a preset's "more" button offers. Each choice hands over to its own sheet.
    Component {
        id: actionsSheet

        EasyEffectsSheet {
            id: sheet
            property string presetName: ""

            title: EasyEffects.shortName(sheet.presetName)
            subtitle: sheet.presetName
            badge: EasyEffects.iconFor(sheet.presetName)

            ClockFormPicker {
                symbol: "content_copy"
                captionLeads: true
                caption: Translation.tr("Duplicate")
                value: Translation.tr("A copy to change without touching this one")
                onTriggered: {
                    const name = sheet.presetName;
                    sheet.close();
                    Qt.callLater(() => root.duplicate(name));
                }
            }

            ClockFormPicker {
                symbol: "edit"
                captionLeads: true
                caption: Translation.tr("Rename")
                value: Translation.tr("Device defaults follow the new name")
                onTriggered: {
                    const name = sheet.presetName;
                    sheet.close();
                    Qt.callLater(() => root.rename(name));
                }
            }

            ClockFormPicker {
                symbol: "delete"
                captionLeads: true
                caption: Translation.tr("Delete")
                value: Translation.tr("Kept in the backup folder")
                onTriggered: {
                    const name = sheet.presetName;
                    sheet.close();
                    Qt.callLater(() => root.remove(name));
                }
            }
        }
    }

    Component {
        id: confirmSheet

        EasyEffectsSheet {
            id: sheet
            property string presetName: ""
            signal confirmed()
            badge: "delete"

            title: Translation.tr("Delete preset")
            subtitle: sheet.presetName

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Translation.tr("\"%1\" goes to the backup folder beside your presets, so it can be put back by hand.").arg(sheet.presetName)
                font.pixelSize: EasyEffectsStyle.textNormal
                color: EasyEffectsStyle.colOnSurfaceVariant
            }

            actions: [
                ClockSheetAction {
                    label: Translation.tr("Cancel")
                    symbol: "close"
                    onClicked: sheet.close()
                },
                ClockSheetAction {
                    primary: true
                    danger: true
                    label: Translation.tr("Delete")
                    symbol: "delete"
                    onClicked: {
                        sheet.confirmed();
                        sheet.close();
                    }
                }
            ]
        }
    }
}
