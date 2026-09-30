pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * One effect's settings, in the side sheet beside the chain.
 *
 * Every control comes from the generated table, so any effect EasyEffects ships can be
 * edited without a hand-written form. Equalizers get their curve and a band list (one
 * band open at a time); multiband effects a band picker. Edits are heard at once when
 * live apply is on and saved with "Save to preset" on the Effects page.
 */
ClockSheet {
    id: root

    required property var editor
    required property string instance

    readonly property var spec: root.editor.specOf(root.instance)
    readonly property var block: root.editor.blockOf(root.instance)
    readonly property var bands: root.spec?.bands ?? null
    readonly property var channels: root.spec?.channels ?? []
    readonly property bool isEqualizer: root.channels.length > 0
    readonly property bool split: root.block?.["split-channels"] === true
    readonly property int bandCount: root.isEqualizer ? Number(root.block?.["num-bands"] ?? 0) : (root.bands?.count ?? 0)
    readonly property var topControls: (root.spec?.controls ?? []).filter(control => control.key !== "bypass")
    readonly property var sections: {
        const order = [];
        root.topControls.forEach(control => {
            const section = control.section ?? "";
            if (!order.includes(section))
                order.push(section);
        });
        return order;
    }

    property string channel: root.channels[0] ?? ""
    property int openBand: -1
    property int multibandBand: 0

    // An equalizer band opens on what gets tuned most; the table keeps EasyEffects' order.
    readonly property var bandLead: ["frequency", "gain", "q", "type"]
    readonly property var bandControls: {
        const controls = (root.bands?.controls ?? []).filter(control => control.key !== "width");
        const rank = control => {
            const lead = root.bandLead.indexOf(control.key);
            return lead >= 0 ? lead : root.bandLead.length + controls.indexOf(control);
        };
        return controls.slice().sort((a, b) => rank(a) - rank(b));
    }

    title: root.editor.nameOf(root.instance)
    subtitle: root.editor.presetName

    function bandValue(control: var, band: int): var {
        const section = root.isEqualizer ? `${root.channel}/band${band}` : `band${band}`;
        const value = root.editor.value(root.instance, section, control.key);
        return value === undefined ? (control.defaults ?? [])[band] : value;
    }

    function setBand(control: var, band: int, value: var): void {
        // Unsplit, one curve drives both channels: write it to both.
        const targets = root.isEqualizer ? (root.split ? [root.channel] : root.channels) : [""];
        targets.forEach(channel => root.editor.setValue(root.instance, control, value, band, channel));
    }

    function setTop(control: var, value: var): void {
        if (root.isEqualizer && control.key === root.bands?.countKey) {
            root.growBands(Math.round(value));
            return;
        }
        root.editor.setValue(root.instance, control, value, 0, "");
    }

    // EasyEffects reads every band below the count and fails on a missing one, so a
    // larger count brings its bands along, and the chain is saved at once.
    function growBands(count: int): void {
        let data = root.editor.data;
        root.channels.forEach(channel => {
            for (let n = 0; n < count; n++) {
                if (Logic.valueAt(data, root.editor.pipeline, root.instance, `${channel}/band${n}`, "type") !== undefined)
                    continue;
                root.bands.controls.forEach(control => {
                    data = Logic.setValue(data, root.editor.pipeline, root.instance, `${channel}/band${n}`, control.key,
                        (control.defaults ?? [])[n]);
                });
            }
        });
        data = Logic.setValue(data, root.editor.pipeline, root.instance, "", root.bands.countKey, count);
        root.editor.data = data;
        root.editor.save();
    }

    function bandSummary(band: int): string {
        const controls = root.bands?.controls ?? [];
        const find = key => controls.find(control => control.key === key);
        const type = root.bandValue(find("type"), band);
        const parts = [String(type), Logic.formatValue(find("frequency"), root.bandValue(find("frequency"), band))];
        if (/Bell|shelf/i.test(String(type)))
            parts.push(Logic.formatValue(find("gain"), root.bandValue(find("gain"), band)));
        parts.push("Q " + Number(root.bandValue(find("q"), band)).toFixed(2));
        return parts.join(" · ");
    }

    // ── Enabled ──────────────────────────────────────────────────────────
    ClockFormToggle {
        symbol: "power_settings_new"
        label: Translation.tr("Enabled")
        description: root.block?.bypass === true ? Translation.tr("Bypassed: the sound passes through untouched")
            : Translation.tr("Processing the sound")
        checked: root.block?.bypass !== true
        onToggled: checked => root.editor.setBypass(root.instance, !checked)
    }

    // An effect this build of the table doesn't know: EasyEffects' window can edit it.
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.spec === null
        spacing: ClockStyle.gapSmall

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Translation.tr("This effect is newer than the shell's editor. Its settings are edited in EasyEffects' own window.")
            font.pixelSize: ClockStyle.textNormal
            color: ClockStyle.colOnSurfaceVariant
        }

        ClockButton {
            variant: "tonal"
            symbol: "open_in_new"
            label: Translation.tr("Open EasyEffects")
            onClicked: EasyEffects.openNativeWindow()
        }
    }

    // ── Equalizer curve ──────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: root.isEqualizer
        implicitHeight: curve.implicitHeight + 16
        radius: Appearance.rounding.small
        color: ClockStyle.colField

        EqualizerCurve {
            id: curve
            anchors {
                fill: parent
                margins: 8
            }
            block: root.isEqualizer ? root.block : null
            channels: root.channels
            highlightBand: root.openBand
            highlightChannel: root.channel
        }
    }

    // ── The effect's own settings, by section ────────────────────────────
    Repeater {
        model: root.sections

        ColumnLayout {
            id: sectionColumn
            required property string modelData
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                visible: sectionColumn.modelData.length > 0
                Layout.topMargin: ClockStyle.gapSmall
                text: Logic.labelFor(sectionColumn.modelData)
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
                color: ClockStyle.colPrimary
            }

            Repeater {
                model: root.topControls.filter(control => (control.section ?? "") === sectionColumn.modelData)

                EffectControl {
                    required property var modelData
                    control: modelData
                    value: root.editor.value(root.instance, modelData.section ?? "", modelData.key)
                    onEdited: value => root.setTop(modelData, value)
                }
            }
        }
    }

    // ── Equalizer bands ──────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: ClockStyle.gapSmall
        visible: root.isEqualizer
        spacing: ClockStyle.gapSmall

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Bands")
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.DemiBold
            color: ClockStyle.colPrimary
        }

        Repeater {
            model: root.split ? root.channels : []

            ClockChip {
                required property string modelData
                height_: 30
                label: Logic.labelFor(modelData)
                selected: root.channel === modelData
                onClicked: root.channel = modelData
            }
        }
    }

    Repeater {
        model: root.isEqualizer ? root.bandCount : 0

        Rectangle {
            id: bandRow
            required property int index
            readonly property bool open: root.openBand === bandRow.index

            Layout.fillWidth: true
            implicitHeight: bandColumn.implicitHeight + 16
            radius: Appearance.rounding.small
            color: bandRow.open ? ClockStyle.colSecondaryContainer : ClockStyle.colField

            ColumnLayout {
                id: bandColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 8
                }
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    StyledText {
                        Layout.preferredWidth: 22
                        horizontalAlignment: Text.AlignHCenter
                        text: String(bandRow.index + 1)
                        font.family: ClockStyle.fontNumbers
                        font.weight: Font.Bold
                        color: ClockStyle.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.bandSummary(bandRow.index)
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: bandRow.open ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                    }

                    MaterialSymbol {
                        text: "expand_more"
                        rotation: bandRow.open ? 180 : 0
                        iconSize: ClockStyle.iconSmall + 2
                        color: ClockStyle.colOnSurfaceVariant
                    }
                }

                // Only the open band builds its controls.
                Loader {
                    Layout.fillWidth: true
                    active: bandRow.open
                    visible: active
                    sourceComponent: ColumnLayout {
                        spacing: 4

                        Repeater {
                            model: root.bandControls

                            EffectControl {
                                required property var modelData
                                control: modelData
                                value: root.bandValue(modelData, bandRow.index)
                                onEdited: value => root.setBand(modelData, bandRow.index, value)
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: 36
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openBand = bandRow.open ? -1 : bandRow.index
            }
        }
    }

    // ── Multiband bands ──────────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        Layout.topMargin: ClockStyle.gapSmall
        visible: !root.isEqualizer && root.bands !== null
        spacing: 4

        Repeater {
            model: !root.isEqualizer && root.bands ? root.bands.count : 0

            ClockChip {
                required property int index
                height_: 30
                label: Translation.tr("Band %1").arg(index + 1)
                selected: root.multibandBand === index
                opacity: index === 0 || root.editor.value(root.instance, `band${index}`, "enable-band") === true ? 1 : 0.55
                onClicked: root.multibandBand = index
            }
        }
    }

    Repeater {
        model: !root.isEqualizer && root.bands
            ? root.bands.controls.filter(control => root.multibandBand >= (control.fromBand ?? 0)) : []

        EffectControl {
            required property var modelData
            control: modelData
            value: root.bandValue(modelData, root.multibandBand)
            onEdited: value => root.setBand(modelData, root.multibandBand, value)
        }
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Reset to defaults")
            symbol: "restart_alt"
            danger: true
            visible: root.spec !== null
            onClicked: root.editor.resetEffect(root.instance)
        },
        ClockSheetAction {
            primary: true
            label: Translation.tr("Done")
            symbol: "check"
            onClicked: root.close()
        }
    ]
}
