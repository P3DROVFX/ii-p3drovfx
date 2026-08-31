pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Everything the typing test can be tuned to, inside the panel itself.
 *
 * The launcher is keyboard-first and modal: sending someone to the Settings
 * window to change a caret style would end their session. These write the same
 * Config keys the Settings window would, so the two never diverge.
 */
Item {
    id: root

    readonly property var options: Config.options.search.typingTest

    /** QML's JS engine has no Object.fromEntries, so build the map by hand. */
    function packLabels(packs) {
        const labels = {};
        for (const pack of packs)
            labels[pack.id] = pack.label;
        return labels;
    }

    function packIds(packs) {
        return Array.from(packs).map(pack => pack.id);
    }

    signal requestClose

    component SectionTitle: StyledText {
        Layout.topMargin: Appearance.sizes.elevationMargin / 2
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        color: Appearance.colors.colPrimary
    }

    component OptionRow: Rectangle {
        id: optionRow
        property string label: ""
        property string description: ""
        default property alias controlSlot: controlHolder.data

        Layout.fillWidth: true
        implicitHeight: Math.max(44, rowLayout.implicitHeight + 16)
        radius: Appearance.rounding.small
        color: Appearance.colors.colSurfaceContainerLow

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: optionRow.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: optionRow.description.length > 0
                    text: optionRow.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            Item {
                id: controlHolder
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }

    component ChoiceChips: RowLayout {
        id: choiceChips
        property var values: []
        property var labels: null
        property string current: ""
        signal picked(string value)

        spacing: 4

        Repeater {
            model: choiceChips.values

            delegate: RippleButton {
                id: chip
                required property var modelData
                readonly property bool active: String(chip.modelData) === choiceChips.current

                implicitWidth: chipLabel.implicitWidth + 22
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: chip.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: chip.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                colRipple: chip.active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                onClicked: choiceChips.picked(String(chip.modelData))

                StyledText {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: choiceChips.labels ? (choiceChips.labels[chip.modelData] ?? chip.modelData) : chip.modelData
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: chip.active ? Font.DemiBold : Font.Normal
                    color: chip.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    StyledFlickable {
        id: scroller
        anchors.fill: parent
        contentHeight: settingsGrid.implicitHeight
        clip: true

        GridLayout {
            id: settingsGrid
            width: scroller.width
            columns: 2
            columnSpacing: Appearance.sizes.elevationMargin * 2
            rowSpacing: 6

            // ── Language ──────────────────────────────────────────────
            SectionTitle {
                Layout.columnSpan: 2
                text: Translation.tr("Language")
            }

            Flow {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: TypingLanguages.languages

                    delegate: RippleButton {
                        id: languageChip
                        required property var modelData
                        readonly property bool active: root.options.language === languageChip.modelData.id

                        implicitWidth: languageLabel.implicitWidth + 24
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: languageChip.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: languageChip.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: languageChip.active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: {
                            root.options.language = languageChip.modelData.id;
                            TypingLanguages.request(languageChip.modelData.id);
                        }

                        StyledText {
                            id: languageLabel
                            anchors.centerIn: parent
                            text: languageChip.modelData.label ?? languageChip.modelData.id
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: languageChip.active ? Font.DemiBold : Font.Normal
                            color: languageChip.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // ── Test length ───────────────────────────────────────────
            SectionTitle {
                Layout.columnSpan: 2
                text: Translation.tr("Test length")
            }

            // The toolbar carries the four presets; anything else belongs
            // here rather than as a text field wedged into that row.
            OptionRow {
                label: Translation.tr("Time")
                description: Translation.tr("%1 seconds").arg(String(root.options.time))

                StyledSlider {
                    implicitWidth: 170
                    from: 5
                    to: 300
                    stepSize: 5
                    value: root.options.time
                    onMoved: root.options.time = Math.round(value)
                }
            }

            OptionRow {
                label: Translation.tr("Words")
                description: Translation.tr("%1 words").arg(String(root.options.words))

                StyledSlider {
                    implicitWidth: 170
                    from: 5
                    to: 200
                    stepSize: 5
                    value: root.options.words
                    onMoved: root.options.words = Math.round(value)
                }
            }

            OptionRow {
                label: Translation.tr("Guided zen")
                description: Translation.tr("Zen types generated words instead of your own, with no limit")

                StyledSwitch {
                    checked: root.options.zenGuided
                    onToggled: root.options.zenGuided = checked
                }
            }

            // ── Typing surface ────────────────────────────────────────
            SectionTitle {
                Layout.columnSpan: 2
                text: Translation.tr("Typing surface")
            }

            OptionRow {
                label: Translation.tr("Text size")
                description: Translation.tr("%1 px").arg(String(root.options.fontSize))

                StyledSlider {
                    implicitWidth: 170
                    from: 16
                    to: 44
                    stepSize: 1
                    value: root.options.fontSize
                    onMoved: root.options.fontSize = Math.round(value)
                }
            }

            OptionRow {
                label: Translation.tr("Visible lines")
                description: Translation.tr("How much of the test stays on screen")

                ChoiceChips {
                    values: [2, 3, 4, 5]
                    current: String(root.options.visibleLines)
                    onPicked: value => root.options.visibleLines = Number(value)
                }
            }

            OptionRow {
                label: Translation.tr("Caret")

                ChoiceChips {
                    values: ["line", "block", "underline", "off"]
                    labels: ({
                        line: Translation.tr("line"),
                        block: Translation.tr("block"),
                        underline: Translation.tr("underline"),
                        off: Translation.tr("off")
                    })
                    current: root.options.caretStyle
                    onPicked: value => root.options.caretStyle = value
                }
            }

            OptionRow {
                label: Translation.tr("Smooth caret and line motion")

                StyledSwitch {
                    checked: root.options.smoothCaret
                    onToggled: root.options.smoothCaret = checked
                }
            }

            OptionRow {
                label: Translation.tr("Highlight the current word")
                description: Translation.tr("Dims every other word while you type")

                StyledSwitch {
                    checked: root.options.highlightCurrentWord
                    onToggled: root.options.highlightCurrentWord = checked
                }
            }

            OptionRow {
                label: Translation.tr("Blind mode")
                description: Translation.tr("Hides mistakes until the result")

                StyledSwitch {
                    checked: root.options.blindMode
                    onToggled: root.options.blindMode = checked
                }
            }

            // ── Live stats ────────────────────────────────────────────
            SectionTitle {
                Layout.columnSpan: 2
                text: Translation.tr("While typing")
            }

            OptionRow {
                label: Translation.tr("Live speed")

                StyledSwitch {
                    checked: root.options.showLiveWpm
                    onToggled: root.options.showLiveWpm = checked
                }
            }

            OptionRow {
                label: Translation.tr("Live accuracy")

                StyledSwitch {
                    checked: root.options.showLiveAccuracy
                    onToggled: root.options.showLiveAccuracy = checked
                }
            }

            OptionRow {
                label: Translation.tr("Finish on the last word")
                description: Translation.tr("No trailing space needed to end a words test")

                StyledSwitch {
                    checked: root.options.finishOnLastWord
                    onToggled: root.options.finishOnLastWord = checked
                }
            }

            OptionRow {
                label: Translation.tr("Tab restarts immediately")
                description: Translation.tr("Otherwise Tab points at restart and Enter presses it")

                StyledSwitch {
                    checked: root.options.quickRestart
                    onToggled: root.options.quickRestart = checked
                }
            }

            // ── Keyboard ──────────────────────────────────────────────
            SectionTitle {
                Layout.columnSpan: 2
                text: Translation.tr("Keyboard preview")
            }

            OptionRow {
                label: Translation.tr("Show the keyboard")

                StyledSwitch {
                    checked: root.options.keyboard.enable
                    onToggled: root.options.keyboard.enable = checked
                }
            }

            OptionRow {
                label: Translation.tr("Point at the next key")

                StyledSwitch {
                    checked: root.options.keyboard.highlightNextKey
                    onToggled: root.options.keyboard.highlightNextKey = checked
                }
            }

            OptionRow {
                Layout.columnSpan: 2
                label: Translation.tr("Layout")

                ChoiceChips {
                    values: ["qwerty", "qwertz", "azerty", "dvorak", "colemak"]
                    current: root.options.keyboard.layout
                    onPicked: value => root.options.keyboard.layout = value
                }
            }

            // ── Sound ─────────────────────────────────────────────────
            SectionTitle {
                Layout.columnSpan: 2
                text: Translation.tr("Sound")
            }

            OptionRow {
                label: Translation.tr("Key sounds")

                StyledSwitch {
                    checked: root.options.sounds.enable
                    onToggled: root.options.sounds.enable = checked
                }
            }

            OptionRow {
                label: Translation.tr("Sound on mistakes")
                enabled: root.options.sounds.enable
                opacity: enabled ? 1 : 0.5

                StyledSwitch {
                    checked: root.options.sounds.errorSound
                    onToggled: root.options.sounds.errorSound = checked
                }
            }

            OptionRow {
                Layout.columnSpan: 2
                label: Translation.tr("Key sound")
                enabled: root.options.sounds.enable
                opacity: enabled ? 1 : 0.5

                ChoiceChips {
                    values: root.packIds(TypingSoundPacks.clickPacks)
                    labels: root.packLabels(TypingSoundPacks.clickPacks)
                    current: root.options.sounds.theme
                    onPicked: value => root.options.sounds.theme = value
                }
            }

            OptionRow {
                Layout.columnSpan: 2
                label: Translation.tr("Mistake sound")
                enabled: root.options.sounds.enable && root.options.sounds.errorSound
                opacity: enabled ? 1 : 0.5

                ChoiceChips {
                    values: root.packIds(TypingSoundPacks.errorPacks)
                    labels: root.packLabels(TypingSoundPacks.errorPacks)
                    current: root.options.sounds.errorTheme
                    onPicked: value => root.options.sounds.errorTheme = value
                }
            }

            OptionRow {
                label: Translation.tr("Volume")
                description: Translation.tr("%1%").arg(String(root.options.sounds.volume))
                enabled: root.options.sounds.enable
                opacity: enabled ? 1 : 0.5

                StyledSlider {
                    implicitWidth: 170
                    from: 0
                    to: 100
                    stepSize: 5
                    value: root.options.sounds.volume
                    onMoved: root.options.sounds.volume = Math.round(value)
                }
            }

            // ── Shortcuts ─────────────────────────────────────────────
            SectionTitle {
                Layout.columnSpan: 2
                text: Translation.tr("Keyboard shortcuts")
            }

            // The bottom bar only has room for the common ones; the full set
            // lives here so nothing is discoverable by accident alone.
            Flow {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: [
                        { keys: ["Esc"], label: Translation.tr("Back, or leave this page") },
                        { keys: ["Ctrl", "R"], label: Translation.tr("Restart") },
                        { keys: ["Tab", "↵"], label: Translation.tr("Point at restart, then press it") },
                        { keys: ["Tab"], label: Translation.tr("Restart outright, when enabled above") },
                        { keys: ["Shift", "↵"], label: Translation.tr("Finish zen, or start the next test") },
                        { keys: ["Ctrl", "⌫"], label: Translation.tr("Erase the current word") },
                        { keys: ["Ctrl", "1-3"], label: Translation.tr("Time, words or zen") },
                        { keys: ["Ctrl", "G"], label: Translation.tr("Free or guided zen") },
                        { keys: ["Ctrl", "[", "]"], label: Translation.tr("Previous or next length") },
                        { keys: ["Ctrl", "P"], label: Translation.tr("Punctuation") },
                        { keys: ["Ctrl", "N"], label: Translation.tr("Numbers") },
                        { keys: ["Ctrl", "L"], label: Translation.tr("Next language") },
                        { keys: ["Ctrl", ","], label: Translation.tr("These settings") },
                        { keys: ["Ctrl", "H"], label: Translation.tr("Score history") },
                        { keys: ["Ctrl", "S"], label: Translation.tr("Statistics") }
                    ]

                    delegate: Rectangle {
                        id: shortcutRow
                        required property var modelData

                        implicitWidth: shortcutContent.implicitWidth + 24
                        implicitHeight: 34
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainerLow

                        RowLayout {
                            id: shortcutContent
                            anchors.centerIn: parent
                            spacing: 8

                            KeyHint {
                                keys: shortcutRow.modelData.keys
                                surface: Appearance.colors.colSurfaceContainerHigh
                                onSurface: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                text: shortcutRow.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }

            // ── History ───────────────────────────────────────────────
            SectionTitle {
                Layout.columnSpan: 2
                text: Translation.tr("Score history")
            }

            OptionRow {
                label: Translation.tr("Keep results on this machine")
                description: Translation.tr("Aggregate scores only — never the words or the keys")

                StyledSwitch {
                    checked: root.options.history.enable
                    onToggled: root.options.history.enable = checked
                }
            }

            OptionRow {
                label: Translation.tr("Results kept")
                description: Translation.tr("%1 most recent").arg(String(root.options.history.maxEntries))
                enabled: root.options.history.enable
                opacity: enabled ? 1 : 0.5

                StyledSlider {
                    implicitWidth: 170
                    from: 10
                    to: 500
                    stepSize: 10
                    value: root.options.history.maxEntries
                    onMoved: root.options.history.maxEntries = Math.round(value)
                }
            }

            OptionRow {
                Layout.columnSpan: 2
                label: Translation.tr("Clear every stored result")
                description: Translation.tr("%1 results, %2 personal bests and every lifetime total")
                    .arg(String(TypingHistory.results.length))
                    .arg(String(TypingHistory.personalBests.length))

                RippleButton {
                    implicitWidth: clearLabel.implicitWidth + 26
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colErrorContainer
                    colRipple: Appearance.colors.colErrorContainer
                    onClicked: TypingHistory.clear()

                    StyledText {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Clear")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }
    }

    TypingStageFade {
        target: scroller
        fadeSize: 36
    }
}
