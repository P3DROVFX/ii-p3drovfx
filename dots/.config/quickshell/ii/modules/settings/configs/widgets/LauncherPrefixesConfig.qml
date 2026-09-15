import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
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
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Search Prefixes")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "tune"
            title: Translation.tr("General Prefix Behavior")

            ConfigSwitch {
                buttonIcon: "list"
                text: Translation.tr("Show default actions without prefix")
                checked: Config.options.search.prefix.showDefaultActionsWithoutPrefix
                onCheckedChanged: {
                    Config.options.search.prefix.showDefaultActionsWithoutPrefix = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Always show Command, Math, and Web Search actions at the bottom of the result list")
                }
            }

            ContentSubsection {
                title: Translation.tr("Search engine base URL")
                icon: "public"
                Layout.fillWidth: true

                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.engineBaseUrl
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.engineBaseUrl = text
                }
            }
        }

        ContentSection {
            icon: "tag"
            title: Translation.tr("Prefix Triggers")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: [
                        {
                            "name": Translation.tr("Action"),
                            "icon": "bolt",
                            "prop": "action"
                        },
                        {
                            "name": Translation.tr("App"),
                            "icon": "apps",
                            "prop": "app"
                        },
                        {
                            "name": Translation.tr("Clipboard"),
                            "icon": "content_paste",
                            "prop": "clipboard"
                        },
                        {
                            "name": Translation.tr("Emojis"),
                            "icon": "mood",
                            "prop": "emojis"
                        },
                        {
                            "name": Translation.tr("Math"),
                            "icon": "calculate",
                            "prop": "math"
                        },
                        {
                            "name": Translation.tr("Shell command"),
                            "icon": "terminal",
                            "prop": "shellCommand"
                        },
                        {
                            "name": Translation.tr("Web search"),
                            "icon": "public",
                            "prop": "webSearch"
                        },
                        {
                            "name": Translation.tr("Window search"),
                            "icon": "layers",
                            "prop": "windowSearch"
                        },
                        {
                            "name": Translation.tr("File browser"),
                            "icon": "folder",
                            "prop": "fileBrowser"
                        },
                        {
                            "name": Translation.tr("File search"),
                            "icon": "search",
                            "prop": "fileSearch"
                        },
                        {
                            "name": Translation.tr("Bluetooth"),
                            "icon": "bluetooth",
                            "prop": "bluetooth"
                        },
                        {
                            "name": Translation.tr("Translator"),
                            "icon": "translate",
                            "prop": "translator"
                        },
                        {
                            "name": Translation.tr("Media Downloader"),
                            "icon": "download",
                            "prop": "mediaDownloader"
                        },
                        {
                            "name": Translation.tr("Material Symbols"),
                            "icon": "font_download",
                            "prop": "materialSymbols"
                        },
                        {
                            "name": Translation.tr("Typing test"),
                            "icon": "keyboard",
                            "prop": "typingTest"
                        },
                        {
                            "name": Translation.tr("AI Chat"),
                            "icon": "auto_awesome",
                            "prop": "ai"
                        }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 52
                        color: Appearance.colors.colSurfaceContainerLow
                        topLeftRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
                        topRightRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
                        bottomLeftRadius: index === 15 ? Appearance.rounding.small : Appearance.rounding.verysmall
                        bottomRightRadius: index === 15 ? Appearance.rounding.small : Appearance.rounding.verysmall

                        ScrollAnimate {}

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.bottomMargin: 2
                            anchors.topMargin: 2
                            spacing: 12

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: Appearance.colors.colSurfaceContainerHigh

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurface
                                }
                            }

                            StyledText {
                                text: modelData.name
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                                Layout.preferredWidth: 120
                            }

                            ToolbarTextField {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                text: Config.options.search.prefix[modelData.prop] || ""
                                onTextChanged: Config.options.search.prefix[modelData.prop] = text
                                colBackground: Appearance.colors.colSurfaceContainerHighest
                            }
                        }
                    }
                }
            }
        }
    }
}
