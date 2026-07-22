import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
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

            onClicked: page.goBack()
        }

        StyledText {
            text: Translation.tr("Media Downloader")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
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
}
