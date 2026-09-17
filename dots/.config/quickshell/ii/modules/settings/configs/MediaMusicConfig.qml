import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: mediaMusicRoot
    anchors.fill: parent

    property alias contentY: root.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: root
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

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

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Album art blur animations")
                checked: Config.options.media.albumArtBlurAnimations
                onCheckedChanged: Config.options.media.albumArtBlurAnimations = checked
                StyledToolTip {
                    text: Translation.tr("Animate album art blur when pausing and blur/zoom when changing tracks in quick toggles, Android media popups and the Android desktop media widget.")
                }
            }

            ConfigSwitch {
                buttonIcon: "graphic_eq"
                text: Translation.tr("Music Recognition")
                checked: true
                configPage: Qt.resolvedUrl("widgets/MusicRecognitionConfig.qml")
                StyledToolTip {
                    text: Translation.tr("Click button text to configure music recognition timeout and polling interval.")
                }
            }

            ConfigSwitch {
                buttonIcon: "lyrics"
                text: Translation.tr("Enable lyrics service")
                checked: Config.options.lyricsService.enable
                configPage: Qt.resolvedUrl("widgets/LyricsConfig.qml")
                onCheckedChanged: {
                    Config.options.lyricsService.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Toggle lyrics service. Click button text to configure Genius, LrcLib, and YouTube Music providers.")
                }
            }
        }

        ContentSection {
            icon: "download"
            title: Translation.tr("Media Downloader")

            ConfigSwitch {
                buttonIcon: "download"
                text: Translation.tr("Enable Media Downloader panel")
                checked: Config.options.mediaDownloader.enabled
                configPage: Qt.resolvedUrl("widgets/MediaDownloaderConfig.qml")
                onCheckedChanged: Config.options.mediaDownloader.enabled = checked
                StyledToolTip {
                    text: Translation.tr("Enables the Media Downloader panel in search ('!' prefix). Click button text for download paths, formats, network proxies, and aria2c settings.")
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

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
