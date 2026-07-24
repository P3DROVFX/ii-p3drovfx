import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Media Integrations")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }
    ContentSection {
        icon: "album"
        title: Translation.tr("Media Integrations")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Prioritized player (e.g. spotify)")
            text: Config.options.media.priorityPlayer
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.media.priorityPlayer = text;
            }
        }

        ConfigSwitch {
            buttonIcon: "filter_list"
            text: Translation.tr("Filter duplicate players")
            checked: Config.options.media.filterDuplicatePlayers
            onCheckedChanged: {
                Config.options.media.filterDuplicatePlayers = checked;
            }
            StyledToolTip {
                text: Translation.tr("Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)")
            }
        }

        ConfigSwitch {
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Music Recognition") }

        ConfigSpinBox {
            icon: "timer_off"
            text: Translation.tr("Total duration timeout (s)")
            value: Config.options.musicRecognition.timeout
            from: 10
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.musicRecognition.timeout = value;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (s)")
            value: Config.options.musicRecognition.interval
            from: 2
            to: 10
            stepSize: 1
            onValueChanged: {
                Config.options.musicRecognition.interval = value;
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Lyrics services") }

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable lyrics service")
            checked: Config.options.lyricsService.enable
            onCheckedChanged: {
                Config.options.lyricsService.enable = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.lyricsService.enable
            buttonIcon: "mood"
            text: Translation.tr("Enable Genius lyrics service")
            checked: Config.options.lyricsService.enableGenius
            onCheckedChanged: {
                Config.options.lyricsService.enableGenius = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.lyricsService.enable
            buttonIcon: "library_books"
            text: Translation.tr("Enable LrcLib lyrics service")
            checked: Config.options.lyricsService.enableLrclib
            onCheckedChanged: {
                Config.options.lyricsService.enableLrclib = checked;
            }
        }
    }
}
