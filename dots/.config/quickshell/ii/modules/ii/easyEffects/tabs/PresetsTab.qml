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

/**
 * Every preset on the pipeline shown, grouped by family ("A50 · Music" sits with the
 * other "A50" presets). A click loads it; the card's own buttons edit it, make it the
 * output device's default, duplicate, rename or delete it. Deleting keeps a copy in the
 * preset folder's `.ii-backup/`.
 */
Item {
    id: root

    required property var editor
    required property var panels
    property bool compact: false
    property bool wide: false

    signal editRequested()

    readonly property string pipeline: root.editor.pipeline
    readonly property var presets: root.pipeline === "input" ? EasyEffects.inputPresets : EasyEffects.outputPresets
    readonly property string current: root.pipeline === "input" ? EasyEffects.inputPreset : EasyEffects.outputPreset
    readonly property string deviceDefault: root.pipeline === "input" ? EasyEffects.inputDeviceDefault : EasyEffects.outputDeviceDefault
    readonly property var device: root.pipeline === "input" ? EasyEffects.inputDevice : EasyEffects.outputDevice
    readonly property var groups: {
        const byFamily = {};
        const order = [];
        Array.from(root.presets).forEach(name => {
            const family = EasyEffects.familyOf(name);
            if (!(family in byFamily)) {
                byFamily[family] = [];
                order.push(family);
            }
            byFamily[family].push(name);
        });
        // Named families first, in name order; the unfamilied ones last.
        order.sort((a, b) => (a === "") - (b === "") || a.localeCompare(b));
        return order.map(family => ({ family: family, names: byFamily[family] }));
    }

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

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 2

        ColumnLayout {
            id: column
            x: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
            y: ClockStyle.gapSmall
            width: flick.width - x * 2
            spacing: ClockStyle.gapLarge

            // ── Now playing through ───────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: heroRow.implicitHeight + ClockStyle.cardPadding * 2
                radius: ClockStyle.radiusCard
                color: EasyEffects.active ? ClockStyle.colActiveCard : ClockStyle.colIdleCard

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: heroRow
                    anchors {
                        fill: parent
                        margins: ClockStyle.cardPadding
                    }
                    spacing: ClockStyle.gapLarge

                    MaterialShapeWrappedMaterialSymbol {
                        text: EasyEffects.iconFor(root.current)
                        iconSize: 30
                        padding: 16
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: EasyEffects.active ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                        colSymbol: EasyEffects.active ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.current.length > 0 ? root.current : Translation.tr("No preset loaded")
                            elide: Text.ElideRight
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            font.pixelSize: ClockStyle.textTitle
                            color: EasyEffects.active ? ClockStyle.colOnActiveCard : ClockStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: {
                                const device = Audio.friendlyDeviceName(root.device);
                                if (!EasyEffects.running)
                                    return Translation.tr("%1 · EasyEffects isn't running").arg(device);
                                if (EasyEffects.bypassed)
                                    return Translation.tr("%1 · effects bypassed").arg(device);
                                return root.deviceDefault.length > 0
                                    ? Translation.tr("%1 · default preset: %2").arg(device).arg(root.deviceDefault)
                                    : Translation.tr("%1 · no default preset").arg(device);
                            }
                            font.pixelSize: ClockStyle.textNormal
                            color: EasyEffects.active ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext
                        }
                    }

                    ClockButton {
                        visible: EasyEffects.running
                        variant: EasyEffects.bypassed ? "filled" : "tonal"
                        symbol: EasyEffects.bypassed ? "graphic_eq" : "do_not_disturb_on"
                        label: EasyEffects.bypassed ? Translation.tr("Turn on") : Translation.tr("Bypass")
                        iconOnly: root.compact
                        onClicked: EasyEffects.toggleBypass()
                    }
                }
            }

            // ── Actions ───────────────────────────────────────────────────
            Flow {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                ClockButton {
                    variant: "tonal"
                    symbol: "add"
                    label: Translation.tr("New preset")
                    onClicked: root.newPreset()
                }

                ClockButton {
                    variant: "tonal"
                    symbol: "file_open"
                    label: Translation.tr("Import")
                    onClicked: root.importPreset()
                }

                ClockButton {
                    variant: "text"
                    symbol: "folder_open"
                    label: Translation.tr("Open folder")
                    onClicked: Qt.openUrlExternally(`file://${EasyEffects.presetsDir}/${root.pipeline}`)
                }
            }

            ClockEmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: ClockStyle.gapHuge
                visible: root.presets.length === 0
                symbol: "library_music"
                title: Translation.tr("No presets yet")
                subtitle: root.pipeline === "input"
                    ? Translation.tr("Input presets process your microphone. Create one here, or import a file.")
                    : Translation.tr("Create one here, import a file, or save one from EasyEffects' own window.")
            }

            // ── Families ──────────────────────────────────────────────────
            Repeater {
                model: root.groups

                ColumnLayout {
                    id: group
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    StyledText {
                        Layout.leftMargin: ClockStyle.gapTiny
                        text: group.modelData.family.length > 0 ? group.modelData.family : Translation.tr("Other")
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: ClockStyle.colPrimary
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        Repeater {
                            model: group.modelData.names

                            PresetCard {
                                required property string modelData
                                width: root.compact ? column.width
                                    : Math.max(220, (column.width - ClockStyle.gapSmall * (cardsPerRow - 1)) / cardsPerRow)
                                readonly property int cardsPerRow: Math.max(1, Math.floor((column.width + ClockStyle.gapSmall) / (240 + ClockStyle.gapSmall)))
                                name: modelData
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Notice ────────────────────────────────────────────────────────────
    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: ClockStyle.gapLarge
        }
        visible: opacity > 0
        opacity: root.notice.length > 0 ? 1 : 0
        width: Math.min(parent.width - ClockStyle.gapHuge * 2, noticeText.implicitWidth + ClockStyle.gapHuge * 2)
        height: 44
        radius: ClockStyle.pill(44)
        color: Appearance.m3colors.m3inverseSurface

        Behavior on opacity {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        StyledText {
            id: noticeText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - ClockStyle.gapHuge * 2)
            elide: Text.ElideRight
            text: root.notice
            font.pixelSize: ClockStyle.textNormal
            color: Appearance.m3colors.m3inverseOnSurface
        }
    }

    // ── A preset ──────────────────────────────────────────────────────────
    component PresetCard: Rectangle {
        id: card
        required property string name
        readonly property bool inUse: card.name === root.current
        readonly property bool isDefault: card.name === root.deviceDefault

        implicitHeight: 96
        radius: ClockStyle.radiusLarge
        color: card.inUse ? ClockStyle.colActiveCard
            : cardHover.hovered ? ClockStyle.colIdleCardHover : ClockStyle.colIdleCard

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        HoverHandler {
            id: cardHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: EasyEffects.loadPreset(card.name, root.pipeline, false)
        }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: ClockStyle.gapLarge
                rightMargin: ClockStyle.gapSmall
            }
            spacing: ClockStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: EasyEffects.iconFor(card.name)
                iconSize: 22
                padding: 11
                shape: card.inUse ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: card.inUse ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                colSymbol: card.inUse ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: EasyEffects.shortName(card.name)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                    color: card.inUse ? ClockStyle.colOnActiveCard : ClockStyle.colOnSurface
                }

                RowLayout {
                    spacing: ClockStyle.gapTiny

                    MaterialSymbol {
                        visible: card.isDefault
                        text: "star"
                        fill: 1
                        iconSize: ClockStyle.iconSmall
                        color: card.inUse ? ClockStyle.colOnActiveCard : ClockStyle.colPrimary
                    }

                    StyledText {
                        text: card.inUse ? (card.isDefault ? Translation.tr("In use · device default") : Translation.tr("In use"))
                            : card.isDefault ? Translation.tr("Device default") : ""
                        font.pixelSize: ClockStyle.textSmall
                        color: card.inUse ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext
                    }
                }
            }

            // The card's own actions, shown while the pointer is on it.
            RowLayout {
                spacing: 0
                opacity: cardHover.hovered || root.compact ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                ClockIconButton {
                    size: 34
                    iconSize: ClockStyle.iconSmall + 2
                    symbol: "tune"
                    tooltip: Translation.tr("Edit effects")
                    onClicked: {
                        if (!card.inUse)
                            EasyEffects.loadPreset(card.name, root.pipeline, false);
                        root.editRequested();
                    }
                }

                ClockIconButton {
                    size: 34
                    iconSize: ClockStyle.iconSmall + 2
                    symbol: "star"
                    filled: card.isDefault
                    tooltip: card.isDefault ? Translation.tr("Stop being the default for %1").arg(Audio.friendlyDeviceName(root.device))
                        : Translation.tr("Make default for %1").arg(Audio.friendlyDeviceName(root.device))
                    onClicked: root.toggleDefault(card.name)
                }

                ClockIconButton {
                    size: 34
                    iconSize: ClockStyle.iconSmall + 2
                    symbol: "more_vert"
                    tooltip: Translation.tr("More")
                    onClicked: root.panels.show(actionsSheet, { presetName: card.name })
                }
            }
        }
    }

    Component {
        id: promptSheet
        ClockTextPromptSheet {}
    }

    // What a preset's "more" button offers. Each choice hands over to its own sheet.
    Component {
        id: actionsSheet

        ClockSheet {
            id: sheet
            property string presetName: ""

            title: EasyEffects.shortName(sheet.presetName)
            subtitle: sheet.presetName

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

        ClockSheet {
            id: sheet
            property string presetName: ""
            signal confirmed()

            title: Translation.tr("Delete preset")
            subtitle: sheet.presetName

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Translation.tr("\"%1\" goes to the backup folder beside your presets, so it can be put back by hand.").arg(sheet.presetName)
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnSurfaceVariant
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
