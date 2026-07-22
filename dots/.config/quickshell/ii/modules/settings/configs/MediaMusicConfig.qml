import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false

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
            buttonIcon: "palette"
            text: Translation.tr("Dynamic album art colors")
            checked: Config.options.media.dynamicAlbumColors
            onCheckedChanged: {
                Config.options.media.dynamicAlbumColors = checked;
            }
            StyledToolTip {
                text: Translation.tr("Extract dominant colors from album art to theme media controls (buttons, text, progress bar)")
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

        ConfigSwitch {
            enabled: Config.options.lyricsService.enable
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
        icon: "download"
        title: Translation.tr("Download")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "download"
                text: Translation.tr("Enable Media Downloader panel")
                checked: Config.options.mediaDownloader.enabled
                onCheckedChanged: Config.options.mediaDownloader.enabled = checked
                StyledToolTip {
                    text: Translation.tr("Enables the Media Downloader panel in search, accessible via the '!' prefix")
                }
            }

            ConfigTextField {
                icon: "folder"
                text: Translation.tr("Download path")
                inputText: Config.options.mediaDownloader.downloadPath
                textField.onTextChanged: Config.options.mediaDownloader.downloadPath = textField.text
            }

            ConfigSpinBox {
                icon: "multiple_stop"
                text: Translation.tr("Max concurrent downloads")
                value: Config.options.mediaDownloader.maxConcurrent
                from: 1
                to: 10
                stepSize: 1
                onValueChanged: Config.options.mediaDownloader.maxConcurrent = value
                StyledToolTip {
                    text: Translation.tr("Maximum number of simultaneous yt-dlp download processes")
                }
            }

            ContentSubsection {
                title: Translation.tr("Default format")
                icon: "tune"
                tooltip: Translation.tr("Default format selected when opening the Media Downloader panel")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.mediaDownloader.defaultFormat
                    onSelected: newValue => {
                        Config.options.mediaDownloader.defaultFormat = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Best"),        icon: "star",       value: "best" },
                        { displayName: Translation.tr("Video (MP4)"), icon: "movie",      value: "video-mp4" },
                        { displayName: Translation.tr("Audio (MP3)"), icon: "audiotrack", value: "audio-mp3" },
                        { displayName: Translation.tr("Audio (OGG)"), icon: "audiotrack", value: "audio-ogg" },
                        { displayName: Translation.tr("Audio (OPUS)"),icon: "audiotrack", value: "audio-opus" }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "data_object"
                text: Translation.tr("Embed metadata")
                checked: Config.options.mediaDownloader.embedMetadata
                onCheckedChanged: Config.options.mediaDownloader.embedMetadata = checked
                StyledToolTip {
                    text: Translation.tr("Embed title, artist, and other metadata into downloaded files")
                }
            }

            ConfigSwitch {
                buttonIcon: "image"
                text: Translation.tr("Write thumbnail")
                checked: Config.options.mediaDownloader.writeThumbnail
                onCheckedChanged: Config.options.mediaDownloader.writeThumbnail = checked
                StyledToolTip {
                    text: Translation.tr("Save thumbnail image alongside the downloaded media")
                }
            }

            ConfigSwitch {
                buttonIcon: "menu_book"
                text: Translation.tr("Add chapter markers")
                checked: Config.options.mediaDownloader.addChapters
                onCheckedChanged: Config.options.mediaDownloader.addChapters = checked
                StyledToolTip {
                    text: Translation.tr("Embed chapter markers in video files when available")
                }
            }
        }
    }

    ContentSection {
        icon: "network_check"
        title: Translation.tr("Network")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigTextField {
                icon: "vpn_key"
                text: Translation.tr("Proxy URL")
                inputText: Config.options.mediaDownloader.proxy
                textField.onTextChanged: Config.options.mediaDownloader.proxy = textField.text
            }

            ConfigSpinBox {
                icon: "speed"
                text: Translation.tr("Rate limit (KB/s)")
                value: Config.options.mediaDownloader.rateLimit
                from: 0
                to: 100000
                stepSize: 100
                onValueChanged: Config.options.mediaDownloader.rateLimit = value
                StyledToolTip {
                    text: Translation.tr("Maximum download speed in KB/s. Set to 0 for unlimited.")
                }
            }

            ConfigSwitch {
                buttonIcon: "timer_off"
                text: Translation.tr("Throttle detection bypass")
                checked: Config.options.mediaDownloader.throttleBypass
                onCheckedChanged: Config.options.mediaDownloader.throttleBypass = checked
                StyledToolTip {
                    text: Translation.tr("Work around server-side throttling by requesting at a minimum rate")
                }
            }
        }
    }

    ContentSection {
        icon: "build"
        title: Translation.tr("Advanced")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "rocket_launch"
                text: Translation.tr("Use aria2c (multi-thread)")
                checked: Config.options.mediaDownloader.useAria2c
                onCheckedChanged: Config.options.mediaDownloader.useAria2c = checked
                StyledToolTip {
                    text: Translation.tr("Use aria2c as downloader for faster parallel chunk downloads. Requires aria2c to be installed.")
                }
            }

            ConfigTextField {
                icon: "terminal"
                text: Translation.tr("Extra global args")
                inputText: Config.options.mediaDownloader.extraArgs
                textField.onTextChanged: Config.options.mediaDownloader.extraArgs = textField.text
            }

            ConfigSwitch {
                buttonIcon: "history"
                text: Translation.tr("Keep download history")
                checked: Config.options.mediaDownloader.keepHistory
                onCheckedChanged: Config.options.mediaDownloader.keepHistory = checked
                StyledToolTip {
                    text: Translation.tr("Keep a log of all downloaded URLs to avoid re-downloading")
                }
            }
        }
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "launcher"
                label: Translation.tr("Search prefixes")
                sectionHighlight: Translation.tr("Search Prefixes")
            }
        }
    }
}
