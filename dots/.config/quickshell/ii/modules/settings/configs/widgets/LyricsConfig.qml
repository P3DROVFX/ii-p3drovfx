import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    RowLayout {
        visible: root.showBackButton
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
            text: Translation.tr("Lyrics Providers")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Provider Services")
        icon: "lyrics"

        ConfigSwitch {
            buttonIcon: "mood"
            text: Translation.tr("Enable Genius lyrics service")
            checked: Config.options.lyricsService.enableGenius
            onCheckedChanged: {
                Config.options.lyricsService.enableGenius = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "library_books"
            text: Translation.tr("Enable LrcLib lyrics service")
            checked: Config.options.lyricsService.enableLrclib
            onCheckedChanged: {
                Config.options.lyricsService.enableLrclib = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "subtitles"
            text: Translation.tr("Enable BetterLyrics service (cached TTML)")
            checked: Config.options.lyricsService.enableBetterlyrics
            onCheckedChanged: {
                Config.options.lyricsService.enableBetterlyrics = checked;
            }
            StyledToolTip {
                text: Translation.tr("Fetches syllable-synced TTML lyrics from BetterLyrics cache without needing an API key.")
            }
        }

        ConfigSwitch {
            buttonIcon: "smart_display"
            text: Translation.tr("Enable YouTube Music lyrics")
            checked: Config.options.lyricsService.enableYtmusic
            onCheckedChanged: {
                Config.options.lyricsService.enableYtmusic = checked;
            }
            StyledToolTip {
                text: Translation.tr("Requires ytmusicapi installed in the venv (see ii-vynx setup). Fetches plain lyrics from YouTube Music.")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Lyrics Provider")
        icon: "tune"

        ConfigSelectionArray {
            currentValue: Config.options.lyricsService.lyricsProvider ?? "auto"
            options: [
                {
                    displayName: Translation.tr("Auto (BetterLyrics → LRCLib → YTMusic → Genius)"),
                    icon: "auto_awesome",
                    value: "auto"
                },
                {
                    displayName: Translation.tr("BetterLyrics (cached TTML)"),
                    icon: "subtitles",
                    value: "betterlyrics"
                },
                {
                    displayName: Translation.tr("LRCLib (synced/plain)"),
                    icon: "timer",
                    value: "lrclib"
                },
                {
                    displayName: Translation.tr("YouTube Music"),
                    icon: "smart_display",
                    value: "ytmusic"
                },
                {
                    displayName: Translation.tr("Genius (plain)"),
                    icon: "music_note",
                    value: "genius"
                }
            ]
            onSelected: newValue => {
                Config.options.lyricsService.lyricsProvider = newValue;
                LyricsService.initiliazeLyrics();
            }
        }
    }
}
