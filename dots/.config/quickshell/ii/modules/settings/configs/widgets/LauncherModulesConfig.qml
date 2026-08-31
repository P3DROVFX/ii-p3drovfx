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
                MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnSecondaryContainer }
            }
            StyledText { text: Translation.tr("Search modules"); font.pixelSize: Appearance.font.pixelSize.large; font.family: Appearance.font.family.title; color: Appearance.colors.colOnLayer0 }
        }

        ContentSection {
            icon: "dashboard_customize"
            title: Translation.tr("Search panels")
            tooltip: Translation.tr("Each description lists the words that reveal the panel. A configured prefix opens it immediately.")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "content_paste"; text: Translation.tr("Clipboard"); description: Translation.tr("Search for ‘clipboard’, ‘clip’, ‘paste’, or type prefix ‘%1’.").arg(String(Config.options.search.prefix.clipboard)); checked: Config.options.search.modules.clipboard; onCheckedChanged: Config.options.search.modules.clipboard = checked }
                ConfigSwitch { buttonIcon: "bluetooth"; text: Translation.tr("Bluetooth"); description: Translation.tr("Search for ‘bluetooth’ or type prefix ‘%1’; device names also appear as results.").arg(String(Config.options.search.prefix.bluetooth)); checked: Config.options.search.modules.bluetooth; onCheckedChanged: Config.options.search.modules.bluetooth = checked }
                ConfigSwitch { buttonIcon: "translate"; text: Translation.tr("Translator"); description: Translation.tr("Search for ‘translator’, ‘translate’, ‘tradutor’, or type prefix ‘%1’.").arg(String(Config.options.search.prefix.translator)); checked: Config.options.search.modules.translator; onCheckedChanged: Config.options.search.modules.translator = checked }
                ConfigSwitch { buttonIcon: "download"; text: Translation.tr("Media downloader"); description: Translation.tr("Search for ‘download’, ‘video’, ‘media’, or type prefix ‘%1’. Requires Media Downloader to be enabled.").arg(String(Config.options.search.prefix.mediaDownloader)); checked: Config.options.search.modules.mediaDownloader; onCheckedChanged: Config.options.search.modules.mediaDownloader = checked }
                ConfigSwitch { buttonIcon: "font_download"; text: Translation.tr("Material Symbols"); description: Translation.tr("Search for ‘material’, ‘symbols’, ‘icons’, or type prefix ‘%1’.").arg(String(Config.options.search.prefix.materialSymbols)); checked: Config.options.search.modules.materialSymbols; onCheckedChanged: Config.options.search.modules.materialSymbols = checked }
                ConfigSwitch { buttonIcon: "keyboard"; text: Translation.tr("Typing test"); description: Translation.tr("Search for ‘typing’, ‘wpm’, ‘digitação’, or type prefix ‘%1’. The test runs entirely offline.").arg(String(Config.options.search.prefix.typingTest)); checked: Config.options.search.modules.typingTest.enable; onCheckedChanged: Config.options.search.modules.typingTest.enable = checked }
                ConfigSwitch { buttonIcon: "calendar_month"; text: Translation.tr("Calendar"); description: Translation.tr("Search for ‘calendar’, ‘agenda’, ‘event’, or ‘meeting’ to open it."); checked: Config.options.search.modules.calendar.enable; onCheckedChanged: Config.options.search.modules.calendar.enable = checked }
                ConfigSelectionArray {
                    visible: Config.options.search.modules.calendar.enable
                    Layout.fillWidth: true
                    currentValue: Config.options.search.modules.calendar.source
                    options: [{ displayName: Translation.tr("khal"), value: "khal" }, { displayName: Translation.tr("Google"), value: "google" }, { displayName: Translation.tr("Both"), value: "both" }]
                    onSelected: value => Config.options.search.modules.calendar.source = value
                }
                ConfigSwitch { buttonIcon: "task_alt"; text: Translation.tr("Tasks"); description: Translation.tr("Search for ‘tasks’, ‘task’, ‘tarefas’, or ‘todo’. Type a task and press Ctrl+N to create it."); checked: Config.options.search.modules.tasks.enable; onCheckedChanged: Config.options.search.modules.tasks.enable = checked }
                ConfigSwitch { buttonIcon: "timer"; text: Translation.tr("Timers"); description: Translation.tr("Search for ‘timer’, ‘timers’, ‘pomodoro’, or ‘alarm’. Use arrows and Enter inside the panel."); checked: Config.options.search.modules.timers.enable; onCheckedChanged: Config.options.search.modules.timers.enable = checked }
                ConfigSwitch { buttonIcon: "splitscreen"; text: Translation.tr("Window management"); description: Translation.tr("Search for ‘window’, ‘tiling’, ‘move’, ‘janela’, or ‘mover’ to act on the window that opened Search."); checked: Config.options.search.modules.windowManagement.enable; onCheckedChanged: Config.options.search.modules.windowManagement.enable = checked }
                ConfigSwitch { buttonIcon: "screenshot"; text: Translation.tr("Screenshots"); description: Translation.tr("Search for ‘screenshot’, ‘print’, ‘captura’, or ‘imagem’ to browse clipboard images."); checked: Config.options.search.modules.screenshots.enable; onCheckedChanged: Config.options.search.modules.screenshots.enable = checked }
                ConfigSwitch { buttonIcon: "mood"; text: Translation.tr("Emojis"); description: Translation.tr("Search for ‘emoji’ or type the configured emoji prefix to open the grid."); checked: Config.options.search.modules.emojis.enable; onCheckedChanged: Config.options.search.modules.emojis.enable = checked }
                ConfigSwitch { buttonIcon: "settings"; text: Translation.tr("Settings in Search"); description: Translation.tr("Type the name of a setting, such as ‘dark mode’, ‘night light’, or ‘Wi-Fi’, to change it from Search."); checked: Config.options.search.modules.settingsToggles.enable; onCheckedChanged: Config.options.search.modules.settingsToggles.enable = checked }
                ConfigSwitch { buttonIcon: "keyboard"; text: Translation.tr("Keybinds"); description: Translation.tr("Search for ‘keybind’, ‘shortcut’, ‘atalho’, or the action name."); checked: Config.options.search.modules.keybinds.enable; onCheckedChanged: Config.options.search.modules.keybinds.enable = checked }
                ConfigSwitch { buttonIcon: "toggle_on"; text: Translation.tr("Quick toggles"); description: Translation.tr("Shows matching system toggles directly among regular Search results."); checked: Config.options.search.modules.quickToggles.enable; onCheckedChanged: Config.options.search.modules.quickToggles.enable = checked }
            }
        }

        ContentSection {
            icon: "manage_search"
            title: Translation.tr("Search providers")
            tooltip: Translation.tr("Providers contribute results to normal Search; prefix providers run only when their prefix is typed.")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "select_window"; text: Translation.tr("Window search"); description: Translation.tr("Type prefix ‘%1’ followed by a window title or app class.").arg(String(Config.options.search.prefix.windowSearch)); checked: Config.options.search.modules.windowSearch; onCheckedChanged: Config.options.search.modules.windowSearch = checked }
                ConfigSwitch {
                    buttonIcon: "public"
                    text: Translation.tr("Browser sites")
                    description: Translation.tr("Match browser bookmarks and history in normal Search without typing a prefix.")
                    checked: Config.options.search.browserSites.enable
                    onCheckedChanged: Config.options.search.browserSites.enable = checked
                }
                ContentSubsection {
                    visible: Config.options.search.browserSites.enable
                    enabled: visible
                    Layout.fillWidth: true
                    title: Translation.tr("Browser sites index")
                    icon: "language"
                    tooltip: Translation.tr("The index is built outside the typing path and refreshed only after the browser database changes.")

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (BrowserSites.loading)
                                return Translation.tr("Loading browser sites…");
                            if (BrowserSites.error.length > 0)
                                return Translation.tr("Error: %1").arg(String(BrowserSites.error));
                            if (BrowserSites.ready)
                                return Translation.tr("Ready · %1 sites indexed").arg(String(BrowserSites.sites.length));
                            return Translation.tr("Waiting to index browser sites");
                        }
                        color: BrowserSites.error.length > 0
                            ? Appearance.colors.colError
                            : Appearance.colors.colOnLayer2
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: BrowserSites.profilePath.length > 0
                            ? Translation.tr("Profile: %1").arg(String(BrowserSites.profilePath))
                            : Translation.tr("Profile: auto-detect")
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WrapAnywhere
                    }

                    ConfigTextField {
                        Layout.fillWidth: true
                        text: Translation.tr("Profile override")
                        icon: "folder_open"
                        placeholderText: Translation.tr("Auto-detect browser profile")
                        tooltip: Translation.tr("Leave empty to detect the newest valid profile. An override must be a profile directory containing places.sqlite.")
                        inputText: Config.options.search.browserSites.profilePath
                        textField.onEditingFinished: Config.options.search.browserSites.profilePath = textField.text.trim()
                    }
                }

                ColumnLayout {
                    visible: Config.options.search.browserSites.enable
                    enabled: visible
                    Layout.fillWidth: true
                    spacing: Appearance.sizes.elevationMargin / 2

                    ConfigSwitch {
                        buttonIcon: "history"
                        text: Translation.tr("Include browsing history")
                        description: Translation.tr("Adds the highest-ranked history hosts. Bookmarks are always indexed.")
                        checked: Config.options.search.browserSites.includeHistory
                        onCheckedChanged: Config.options.search.browserSites.includeHistory = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "database"
                        text: Translation.tr("Use local favicons")
                        description: Translation.tr("Reads icons from the local browser database and cache without network access.")
                        checked: Config.options.search.browserSites.useLocalFavicons
                        onCheckedChanged: Config.options.search.browserSites.useLocalFavicons = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "cloud_download"
                        text: Translation.tr("Allow remote favicons")
                        description: Translation.tr("Allows a network request containing the site domain when no local icon is available. Keep off for maximum privacy.")
                        checked: Config.options.search.browserSites.allowRemoteFavicons
                        onCheckedChanged: Config.options.search.browserSites.allowRemoteFavicons = checked
                    }

                    ConfigSpinBox {
                        icon: "storage"
                        text: Translation.tr("History sites indexed")
                        value: Config.options.search.browserSites.maxIndexedSites
                        from: 0
                        to: 5000
                        stepSize: 50
                        onValueChanged: Config.options.search.browserSites.maxIndexedSites = value
                        StyledToolTip {
                            text: Translation.tr("Maximum history hosts kept in memory. Every bookmark remains included regardless of this limit.")
                        }
                    }

                    ConfigSpinBox {
                        icon: "format_list_numbered"
                        text: Translation.tr("Site results shown")
                        value: Config.options.search.browserSites.maxResults
                        from: 1
                        to: 20
                        stepSize: 1
                        onValueChanged: Config.options.search.browserSites.maxResults = value
                        StyledToolTip {
                            text: Translation.tr("Maximum browser-site rows contributed to one normal Search query.")
                        }
                    }

                    ConfigSpinBox {
                        icon: "refresh"
                        text: Translation.tr("Refresh interval (minutes)")
                        value: Config.options.search.browserSites.refreshMinutes
                        from: 1
                        to: 1440
                        stepSize: 1
                        onValueChanged: Config.options.search.browserSites.refreshMinutes = value
                        StyledToolTip {
                            text: Translation.tr("Minimum time between index rebuilds. A rebuild still waits until places.sqlite has changed.")
                        }
                    }
                }
                ConfigSwitch {
                    buttonIcon: "folder_data"
                    text: Translation.tr("File browser")
                    description: Translation.tr("Type ‘%1’ to open the full explorer. Navigate with arrows and Enter; press Ctrl+K for file operations and shortcuts.").arg(String(Config.options.search.prefix.fileBrowser))
                    checked: Config.options.search.modules.fileBrowser
                    onCheckedChanged: Config.options.search.modules.fileBrowser = checked
                }
                ContentSubsection {
                    visible: Config.options.search.modules.fileBrowser
                    enabled: visible
                    Layout.fillWidth: true
                    title: Translation.tr("File browser size")
                    icon: "aspect_ratio"
                    tooltip: Translation.tr("Changes only the full file browser panel; the size of other Search panels is unaffected.")

                    ConfigSlider {
                        buttonIcon: "width"
                        text: Translation.tr("Panel width (px)")
                        value: Config.options.search.fileBrowser.panelWidth
                        from: 860
                        to: 1600
                        stepSize: 20
                        usePercentTooltip: false
                        onValueChanged: Config.options.search.fileBrowser.panelWidth = value
                        StyledToolTip { text: Translation.tr("Controls the room shared by the file list and preview.") }
                    }

                    ConfigSlider {
                        buttonIcon: "height"
                        text: Translation.tr("Panel content height (px)")
                        value: Config.options.search.fileBrowser.panelBodyHeight
                        from: 420
                        to: 900
                        stepSize: 20
                        usePercentTooltip: false
                        onValueChanged: Config.options.search.fileBrowser.panelBodyHeight = value
                        StyledToolTip { text: Translation.tr("Controls how many files and metadata rows fit without scrolling.") }
                    }
                }
                ConfigSwitch { buttonIcon: "find_in_page"; text: Translation.tr("File search"); description: Translation.tr("Type prefix ‘%1’ followed by at least two characters to find files.").arg(String(Config.options.search.prefix.fileSearch)); checked: Config.options.search.modules.fileSearch; onCheckedChanged: Config.options.search.modules.fileSearch = checked }

                ContentSubsection {
                    title: Translation.tr("Indexed directory")
                    icon: "folder_open"
                    Layout.fillWidth: true
                    enabled: Config.options.search.modules.fileSearch

                    MaterialTextArea {
                        Layout.fillWidth: true
                        text: Config.options.search.fileSearchDirectory
                        wrapMode: TextEdit.NoWrap
                        onTextChanged: Config.options.search.fileSearchDirectory = text
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    enabled: Config.options.search.modules.fileSearch
                    spacing: Appearance.sizes.elevationMargin / 2

                    ConfigSwitch {
                        buttonIcon: "search"
                        text: Translation.tr("Show files and folders without a prefix")
                        description: Translation.tr("Adds a Files & folders group to ordinary results, alongside applications. The prefix keeps working either way.")
                        checked: Config.options.search.fileSearch.inlineResults
                        onCheckedChanged: Config.options.search.fileSearch.inlineResults = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "hide_image"
                        text: Translation.tr("Hide image thumbnails")
                        description: Translation.tr("Image and vector hits draw themselves in the row's icon slot. This leaves the file kind's symbol there instead.")
                        checked: Config.options.search.blurFileSearchResultPreviews
                        onCheckedChanged: Config.options.search.blurFileSearchResultPreviews = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "visibility"
                        text: Translation.tr("Include hidden files and folders")
                        description: Translation.tr("Covers dotfiles such as ~/.config, at the cost of walking every cache and state folder a home directory accumulates.")
                        checked: Config.options.search.fileSearch.includeHidden
                        enabled: Config.options.search.fileSearch.inlineResults
                        onCheckedChanged: Config.options.search.fileSearch.includeHidden = checked
                    }

                    ConfigSpinBox {
                        icon: "text_fields"
                        text: Translation.tr("Start searching files after (characters)")
                        value: Config.options.search.fileSearch.minimumQueryLength
                        from: 2
                        to: 8
                        stepSize: 1
                        enabled: Config.options.search.fileSearch.inlineResults
                        onValueChanged: Config.options.search.fileSearch.minimumQueryLength = value
                        StyledToolTip {
                            text: Translation.tr("One or two letters match a large share of a home directory. Raising this keeps the disk quiet until the query narrows.")
                        }
                    }

                    ConfigSpinBox {
                        icon: "format_list_numbered"
                        text: Translation.tr("File results shown")
                        value: Config.options.search.fileSearch.maxResults
                        from: 1
                        to: 20
                        stepSize: 1
                        enabled: Config.options.search.fileSearch.inlineResults
                        onValueChanged: Config.options.search.fileSearch.maxResults = value
                    }

                    ConfigSpinBox {
                        icon: "account_tree"
                        text: Translation.tr("Maximum folder depth (0 = unlimited)")
                        value: Config.options.search.fileSearch.maxDepth
                        from: 0
                        to: 20
                        stepSize: 1
                        enabled: Config.options.search.fileSearch.inlineResults
                        onValueChanged: Config.options.search.fileSearch.maxDepth = value
                        StyledToolTip {
                            text: Translation.tr("Capping depth shortens a complete filesystem search, at the cost of omitting files buried deeper. The file-search prefix always searches to full depth.")
                        }
                    }
                }
                ConfigSwitch { buttonIcon: "calculate"; text: Translation.tr("Calculator"); description: Translation.tr("Type an expression directly or use prefix ‘%1’.").arg(String(Config.options.search.prefix.math)); checked: Config.options.search.modules.math; onCheckedChanged: Config.options.search.modules.math = checked }
                ConfigSwitch { buttonIcon: "travel_explore"; text: Translation.tr("Web search"); description: Translation.tr("Type prefix ‘%1’ followed by the search terms, or use the fallback result.").arg(String(Config.options.search.prefix.webSearch)); checked: Config.options.search.modules.webSearch; onCheckedChanged: Config.options.search.modules.webSearch = checked }
                ConfigSwitch { buttonIcon: "terminal"; text: Translation.tr("Shell commands"); description: Translation.tr("Type prefix ‘%1’ followed by a command. Commands run only after pressing Enter.").arg(String(Config.options.search.prefix.shellCommand)); checked: Config.options.search.modules.shellCommand; onCheckedChanged: Config.options.search.modules.shellCommand = checked }
                ConfigSwitch { buttonIcon: "power_settings_new"; text: Translation.tr("System controls"); description: Translation.tr("Search for ‘lock’, ‘poweroff’, ‘reboot’, ‘suspend’, or ‘restart’; destructive controls require confirmation."); checked: Config.options.search.modules.systemControls; onCheckedChanged: Config.options.search.modules.systemControls = checked }
                ConfigSwitch { buttonIcon: "widgets"; text: Translation.tr("Shell actions"); description: Translation.tr("Makes shell tools such as color picker, wallpaper, OCR, recording, and overlays searchable by name."); checked: Config.options.search.modules.shellActions; onCheckedChanged: Config.options.search.modules.shellActions = checked }
            }
        }

        ContentSection {
            icon: "database"
            title: Translation.tr("Data-backed modules")
            tooltip: Translation.tr("These entries depend on local shell data or an account configured elsewhere in Settings or Cheat Sheet.")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "menu_book"; text: Translation.tr("Cheat Sheet shortcuts"); description: Translation.tr("Lets Search open Cheat Sheet pages such as timetable, elements, amino acids, workspaces, Gmail, and commands."); checked: Config.options.search.modules.cheatsheet.enable; onCheckedChanged: Config.options.search.modules.cheatsheet.enable = checked }
                ConfigSwitch { buttonIcon: "terminal"; text: Translation.tr("Commands"); description: Translation.tr("Search for ‘commands’, ‘command’, ‘comando’, ‘cmd’, or the command name. Super+Alt+C opens the panel directly."); checked: Config.options.search.modules.cheatsheet.commandsPanel; onCheckedChanged: Config.options.search.modules.cheatsheet.commandsPanel = checked }
                ConfigSwitch { buttonIcon: "mail"; text: Translation.tr("Gmail"); description: Translation.tr("Search for ‘gmail’, ‘email’, ‘mail’, ‘inbox’, or ‘unread’."); checked: Config.options.search.modules.cheatsheet.gmailPanel; onCheckedChanged: Config.options.search.modules.cheatsheet.gmailPanel = checked }
                ConfigSwitch { buttonIcon: "sports_soccer"; text: Translation.tr("Today’s games"); description: Translation.tr("Search for ‘sports’, ‘games’, ‘jogos’, ‘football’, or ‘futebol’ to see every monitored game today."); checked: Config.options.search.modules.sports.enable; onCheckedChanged: Config.options.search.modules.sports.enable = checked }
                ConfigSwitch { buttonIcon: "cancel"; text: Translation.tr("Quit process"); description: Translation.tr("Search for ‘process’, ‘kill’, ‘quit’, ‘fechar’, or a running process name. Enter requires confirmation."); checked: Config.options.search.modules.processes.enable; onCheckedChanged: Config.options.search.modules.processes.enable = checked }
                ConfigSwitch { buttonIcon: "routine"; text: Translation.tr("Modes & routines"); description: Translation.tr("Type a mode or routine name to activate or deactivate it."); checked: Config.options.modes.enable; onCheckedChanged: Config.options.modes.enable = checked }
                ConfigSwitch { buttonIcon: "wand_stars"; text: Translation.tr("Tools & Generators"); description: Translation.tr("Search for ‘tools’ or ‘generator’ to browse all, or type ‘uuid’, ‘password’, ‘lorem’, ‘base64’, ‘json’, etc. Enter executes and copies locally."); checked: Config.options.search.modules.tools.enable; onCheckedChanged: Config.options.search.modules.tools.enable = checked }
            }
        }
    }
}
