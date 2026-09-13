import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Search matching")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "travel_explore"
            title: Translation.tr("Typo & keyboard layout matching")
            tooltip: Translation.tr("Tune how typos, keyboard layout mismatches and relevance thresholds are handled during search.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "trending_up"
                    text: Translation.tr("Frequency-based ranking")
                    description: Translation.tr("Learns from launches and moves frequently used results closer to the top. Data stays on this device.")
                    checked: Config.options.search.frecency
                    onCheckedChanged: Config.options.search.frecency = checked
                }

                ConfigSwitch {
                    buttonIcon: "keyboard_alt"
                    text: Translation.tr("Correct wrong keyboard layout")
                    description: Translation.tr("Maps a query typed with another layout active back through the physical keys, so ‘ашкуащч’ still finds Firefox. Cyrillic is transliterated as well.")
                    checked: Config.options.search.typoTolerance.keyboardLayouts
                    onCheckedChanged: Config.options.search.typoTolerance.keyboardLayouts = checked
                }

                ConfigSwitch {
                    buttonIcon: "spellcheck"
                    text: Translation.tr("Typo-tolerant matching (Myers)")
                    description: Translation.tr("When nothing matches exactly, a bit-parallel edit-distance pass finds the app you meant — ‘disccord’, ‘telgeram’, ‘vscdoe’. It runs only on an otherwise empty result, so it never crowds a query that already worked.")
                    checked: Config.options.search.typoTolerance.enable
                    onCheckedChanged: Config.options.search.typoTolerance.enable = checked
                }

                ConfigSlider {
                    buttonIcon: "tune"
                    text: Translation.tr("Typo tolerance strictness")
                    value: Config.options.search.typoTolerance.threshold
                    from: 0.15
                    to: 0.6
                    stepSize: 0.05
                    enabled: Config.options.search.typoTolerance.enable
                    onValueChanged: Config.options.search.typoTolerance.threshold = value
                    StyledToolTip {
                        text: Translation.tr("How close a name has to be before the typo pass offers it. Lower catches more mangled queries and lets more unrelated names through.")
                    }
                }

                ConfigSlider {
                    buttonIcon: "filter_alt"
                    text: Translation.tr("Result relevance floor")
                    value: Config.options.search.fuzzyThreshold
                    from: 0.0
                    to: 0.7
                    stepSize: 0.05
                    onValueChanged: Config.options.search.fuzzyThreshold = value
                    StyledToolTip {
                        text: Translation.tr("Fuzzy matching accepts any scattered subsequence, so without a floor ‘file’ reaches names that merely contain those letters somewhere. Raise it for a shorter, stricter list.")
                    }
                }
            }
        }
    }
}
