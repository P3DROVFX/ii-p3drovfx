import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Widgets
import qs.modules.waffle.looks




ContentPage {
    id: page
    readonly property int index: 9
    property bool register: parent.register ?? false
    forceWidth: true

    ContentSection {
        icon: "tune"
        title: Translation.tr("General")

        ConfigSwitch {
            buttonIcon: "trending_up"
            text: Translation.tr("Frecency-based ranking")
            checked: Config.options.search.frecency
            onCheckedChanged: {
                Config.options.search.frecency = checked;
            }
            StyledToolTip {
                text: Translation.tr("Sort apps by usage frequency and recency")
            }
        }

        ConfigSwitch {
            buttonIcon: "list"
            text: Translation.tr("Show default actions without prefix")
            checked: Config.options.search.prefix.showDefaultActionsWithoutPrefix
            onCheckedChanged: {
                Config.options.search.prefix.showDefaultActionsWithoutPrefix = checked;
            }
            StyledToolTip {
                text: Translation.tr("Always show Command, Math, and Web Search at the bottom")
            }
        }

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Non-app result delay (ms)")
            value: Config.options.search.nonAppResultDelay
            from: 0
            to: 500
            stepSize: 10
            onValueChanged: {
                Config.options.search.nonAppResultDelay = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Blur file search result previews")
            checked: Config.options.search.blurFileSearchResultPreviews
            onCheckedChanged: {
                Config.options.search.blurFileSearchResultPreviews = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Enable built-in system controls (:lock, :reboot...)")
            checked: Config.options.search.enableSystemControls
            onCheckedChanged: {
                Config.options.search.enableSystemControls = checked;
            }
            StyledToolTip {
                text: Translation.tr("Allows running commands like :lock, :reboot, :poweroff, :suspend, and :restart directly from search")
            }
        }

        ConfigSwitch {
            buttonIcon: "calculate"
            text: Translation.tr("Enable integrated math & unit converter previews")
            checked: Config.options.search.enableMathPreview
            onCheckedChanged: {
                Config.options.search.enableMathPreview = checked;
            }
            StyledToolTip {
                text: Translation.tr("Displays real-time answers for math expressions and unit conversions in the result list")
            }
        }

        ConfigSwitch {
            buttonIcon: "apps"
            text: Translation.tr("Always list apps on empty query")
            checked: Config.options.search.alwaysListApps
            onCheckedChanged: {
                Config.options.search.alwaysListApps = checked;
            }
            StyledToolTip {
                text: Translation.tr("Opens the app list immediately when search is opened with no query, bypassing the workspace overview")
            }
        }
    }

    ContentSection {
        icon: "tag"
        title: Translation.tr("Prefixes")

        ContentSubsection {
            title: Translation.tr("Search prefixes")
            tooltip: Translation.tr("Characters that activate special search modes")

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 8

                StyledText { text: Translation.tr("Action"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.action
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.action = text;
                }

                StyledText { text: Translation.tr("App"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.app
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.app = text;
                }

                StyledText { text: Translation.tr("Clipboard"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.clipboard
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.clipboard = text;
                }

                StyledText { text: Translation.tr("Emojis"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.emojis
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.emojis = text;
                }

                StyledText { text: Translation.tr("Math"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.math
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.math = text;
                }

                StyledText { text: Translation.tr("Shell command"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.shellCommand
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.shellCommand = text;
                }

                StyledText { text: Translation.tr("Web search"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.webSearch
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.webSearch = text;
                }

                StyledText { text: Translation.tr("Window search"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.windowSearch
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.windowSearch = text;
                }

                StyledText { text: Translation.tr("File browser"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.fileBrowser
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.fileBrowser = text;
                }

                StyledText { text: Translation.tr("File search"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.fileSearch
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.fileSearch = text;
                }

                StyledText { text: Translation.tr("Bluetooth"); color: Appearance.colors.colOnSurface }
                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.prefix.bluetooth
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.prefix.bluetooth = text;
                }
            }
        }
    }

    ContentSection {
        icon: "label"
        title: Translation.tr("App Aliases")
        tooltip: Translation.tr("Define shortcuts for apps, folders, and commands")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            // Custom Aliases List
            Repeater {
                model: Config.options.search.aliases || []
                delegate: Rectangle {
                    id: aliasTile
                    Layout.fillWidth: true
                    height: 56
                    color: Appearance.colors.colSurfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    radius: Appearance.rounding.small

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // Type Icon Badge
                        Rectangle {
                            width: 32
                            height: 32
                            radius: Appearance.rounding.verysmall
                            color: modelData.type === "app" ? Appearance.colors.colPrimaryContainer : 
                                   modelData.type === "folder" ? Appearance.colors.colSecondaryContainer : 
                                   Appearance.colors.colTertiaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: modelData.type === "app" ? "apps" : 
                                      modelData.type === "folder" ? "folder" : "terminal"
                                color: modelData.type === "app" ? Appearance.colors.colOnPrimaryContainer : 
                                       modelData.type === "folder" ? Appearance.colors.colOnSecondaryContainer : 
                                       Appearance.colors.colOnTertiaryContainer
                            }
                        }

                        // Alias Tag
                        Rectangle {
                            color: Appearance.colors.colSurfaceContainerHigh
                            radius: Appearance.rounding.verysmall
                            implicitWidth: Math.max(48, aliasText.implicitWidth + 12)
                            implicitHeight: 28
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant

                            StyledText {
                                id: aliasText
                                anchors.centerIn: parent
                                text: modelData.alias
                                font.bold: true
                                color: Appearance.colors.colPrimary
                            }
                        }

                        // Target Path or command
                        StyledText {
                            text: modelData.target
                            color: Appearance.colors.colOnSurface
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                        // Expressive Delete Button
                        IconToolbarButton {
                            text: "delete"
                            colText: Appearance.colors.colError
                            onClicked: {
                                let newAliases = Array.from(Config.options.search.aliases || []);
                                newAliases.splice(index, 1);
                                Config.options.search.aliases = newAliases;
                            }
                        }
                    }
                }
            }

            Item { height: 4; Layout.fillWidth: true } // Spacer

            // The Adding panel
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: addLayout.implicitHeight + 24
                color: Appearance.colors.colSurfaceContainerLow
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                radius: Appearance.rounding.small

                ColumnLayout {
                    id: addLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    ColumnLayout {
                        id: addAliasArea
                        Layout.fillWidth: true
                        spacing: 12

                        property string selectedType: "app"
                        property string appFilter: ""

                        readonly property var sortedApps: {
                            let list = Array.from(AppSearch.list || []);
                            list.sort((a, b) => {
                                let scoreA = AppUsage.getScore(a.id);
                                let scoreB = AppUsage.getScore(b.id);
                                if (scoreA !== scoreB) {
                                    return scoreB - scoreA;
                                }
                                return a.name.localeCompare(b.name);
                            });
                            return list;
                        }

                        readonly property var filteredApps: {
                            let list = sortedApps;
                            if (appFilter.trim() !== "") {
                                let f = appFilter.toLowerCase();
                                return list.filter(app => app.name.toLowerCase().includes(f) || app.id.toLowerCase().includes(f));
                            }
                            return list.slice(0, 6); // Limit frequent apps to exactly 6!
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            ConfigSelectionArray {
                                currentValue: addAliasArea.selectedType
                                onSelected: newValue => { addAliasArea.selectedType = newValue; }
                                options: [
                                    { displayName: Translation.tr("App"), icon: "apps", value: "app" },
                                    { displayName: Translation.tr("Folder"), icon: "folder", value: "folder" },
                                    { displayName: Translation.tr("Command"), icon: "terminal", value: "command" }
                                ]
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            MaterialTextField {
                                id: newAliasInput
                                Layout.preferredWidth: 140
                                placeholderText: Translation.tr("Alias (e.g. i)")
                            }

                            MaterialTextField {
                                id: newTargetInput
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Target (e.g. Downloads/ii-vynx or app-id)")
                            }

                            RippleButtonWithIcon {
                                mainText: Translation.tr("Add")
                                materialIcon: "add"
                                colBackground: Appearance.colors.colSecondaryContainer
                                onClicked: {
                                    if (newAliasInput.text.trim() === "" || newTargetInput.text.trim() === "") return;
                                    let newAliases = Array.from(Config.options.search.aliases || []);
                                    newAliases.push({
                                        alias: newAliasInput.text.trim(),
                                        type: addAliasArea.selectedType,
                                        target: newTargetInput.text.trim()
                                    });
                                    Config.options.search.aliases = newAliases;
                                    newAliasInput.text = "";
                                    newTargetInput.text = "";
                                }
                            }
                        }

                        // App Selection Panel
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: addAliasArea.selectedType === "app"

                            Item { height: 2; Layout.fillWidth: true } // spacer

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                StyledText {
                                    text: addAliasArea.appFilter.trim() === "" ? Translation.tr("Frequent Apps") : Translation.tr("Matches")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: true
                                    color: Appearance.colors.colOnSurface
                                    Layout.preferredWidth: 110
                                }

                                // Expressive pill-shaped search input
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 38
                                    color: Appearance.colors.colSurfaceContainerHigh
                                    radius: Appearance.rounding.full
                                    border.width: 1
                                    border.color: appFilterInput.focus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        MaterialSymbol {
                                            text: "search"
                                            iconSize: 18
                                            color: appFilterInput.focus ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                        }

                                        TextField {
                                            id: appFilterInput
                                            Layout.fillWidth: true
                                            placeholderText: Translation.tr("Type application name...")
                                            placeholderTextColor: Appearance.colors.colOnSurfaceVariant
                                            color: Appearance.colors.colOnSurface
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            background: null // Transparent
                                            clip: true
                                            onTextChanged: addAliasArea.appFilter = text
                                        }

                                        IconToolbarButton {
                                            visible: appFilterInput.text !== ""
                                            text: "close"
                                            implicitHeight: 28
                                            implicitWidth: 28
                                            colText: Appearance.colors.colOnSurfaceVariant
                                            onClicked: {
                                                appFilterInput.text = "";
                                            }
                                        }
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 8

                                Repeater {
                                    model: addAliasArea.filteredApps
                                    delegate: Rectangle {
                                        id: chip
                                        color: chipMouse.hovered ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                                        border.width: 1
                                        border.color: chipMouse.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                        radius: Appearance.rounding.full
                                        width: appLayout.implicitWidth + 24
                                        height: 34

                                        Behavior on color {
                                            ColorAnimation { duration: 120 }
                                        }
                                        Behavior on border.color {
                                            ColorAnimation { duration: 120 }
                                        }

                                        RowLayout {
                                            id: appLayout
                                            anchors.centerIn: parent
                                            spacing: 8

                                            WAppIcon {
                                                iconName: modelData.icon
                                                implicitSize: 18
                                                tryCustomIcon: false
                                            }

                                            StyledText {
                                                text: modelData.name
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.bold: chipMouse.hovered
                                                color: chipMouse.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                            }
                                        }

                                        MouseArea {
                                            id: chipMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                newTargetInput.text = modelData.id;
                                                addAliasArea.selectedType = "app";
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "content_paste"
        title: Translation.tr("Clipboard Detectors")

        ConfigSwitch {
            buttonIcon: "palette"
            text: Translation.tr("Hex color")
            checked: Config.options.search.clipboard.detectors.hexColor
            onCheckedChanged: Config.options.search.clipboard.detectors.hexColor = checked;
            StyledToolTip { text: Translation.tr("Detects hex colors (#fff, #rrggbb). Shows full-color preview in detail panel.") }
        }
        ConfigSwitch {
            buttonIcon: "link"
            text: Translation.tr("URL")
            checked: Config.options.search.clipboard.detectors.url
            onCheckedChanged: Config.options.search.clipboard.detectors.url = checked;
            StyledToolTip { text: Translation.tr("Detects URLs. Smart action: Open Link in browser.") }
        }
        ConfigSwitch {
            buttonIcon: "alternate_email"
            text: Translation.tr("Email")
            checked: Config.options.search.clipboard.detectors.email
            onCheckedChanged: Config.options.search.clipboard.detectors.email = checked;
            StyledToolTip { text: Translation.tr("Detects email addresses. Smart action: Open in mail client.") }
        }
        ConfigSwitch {
            buttonIcon: "phone"
            text: Translation.tr("Phone")
            checked: Config.options.search.clipboard.detectors.phone
            onCheckedChanged: Config.options.search.clipboard.detectors.phone = checked;
            StyledToolTip { text: Translation.tr("Detects phone numbers. Smart action: Open in dialer via tel: URI.") }
        }
        ConfigSwitch {
            buttonIcon: "data_object"
            text: Translation.tr("JSON")
            checked: Config.options.search.clipboard.detectors.json
            onCheckedChanged: Config.options.search.clipboard.detectors.json = checked;
            StyledToolTip { text: Translation.tr("Detects JSON objects/arrays. Smart action: Format JSON and copy to clipboard.") }
        }
        ConfigSwitch {
            buttonIcon: "notes"
            text: Translation.tr("Multiline")
            checked: Config.options.search.clipboard.detectors.multiline
            onCheckedChanged: Config.options.search.clipboard.detectors.multiline = checked;
            StyledToolTip { text: Translation.tr("Detects text with 2+ lines. Shows line count badge in the list.") }
        }
        ConfigSwitch {
            buttonIcon: "tag"
            text: Translation.tr("Number")
            checked: Config.options.search.clipboard.detectors.number
            onCheckedChanged: Config.options.search.clipboard.detectors.number = checked;
            StyledToolTip { text: Translation.tr("Detects numbers (including formatted with spaces/commas). Smart action: Copy stripped of separators.") }
        }
        ConfigSwitch {
            buttonIcon: "markdown"
            text: Translation.tr("Markdown")
            checked: Config.options.search.clipboard.detectors.markdown
            onCheckedChanged: Config.options.search.clipboard.detectors.markdown = checked;
            StyledToolTip { text: Translation.tr("Detects Markdown text. Smart action: Copy plain text with markup stripped.") }
        }
        ConfigSwitch {
            buttonIcon: "folder_open"
            text: Translation.tr("File path")
            checked: Config.options.search.clipboard.detectors.filePath
            onCheckedChanged: Config.options.search.clipboard.detectors.filePath = checked;
            StyledToolTip { text: Translation.tr("Detects absolute file/folder paths. Smart action: Open with default file manager.") }
        }
    }

    ContentSection {
        icon: "settings_suggest"
        title: Translation.tr("Clipboard Customization")

        ConfigSlider {
            buttonIcon: "width"
            text: Translation.tr("Panel width (px)")
            value: Config.options.search.clipboard.panelWidth
            from: 600
            to: 1200
            stepSize: 10
            usePercentTooltip: false
            onValueChanged: Config.options.search.clipboard.panelWidth = value
        }

        ConfigSlider {
            buttonIcon: "vertical_split"
            text: Translation.tr("List column ratio")
            value: Config.options.search.clipboard.listColumnRatio * 100
            from: 25
            to: 60
            stepSize: 5
            usePercentTooltip: true
            onValueChanged: Config.options.search.clipboard.listColumnRatio = value / 100
        }

        ConfigSlider {
            buttonIcon: "image_aspect_ratio"
            text: Translation.tr("Image preview height (px)")
            value: Config.options.search.clipboard.imageHeight
            from: 100
            to: 400
            stepSize: 10
            usePercentTooltip: false
            onValueChanged: Config.options.search.clipboard.imageHeight = value
        }

        ConfigSlider {
            buttonIcon: "format_size"
            text: Translation.tr("Text preview font size (pt)")
            value: Config.options.search.clipboard.previewFontSize
            from: 9
            to: 20
            stepSize: 1
            usePercentTooltip: false
            onValueChanged: Config.options.search.clipboard.previewFontSize = value
        }

        ConfigSwitch {
            buttonIcon: "info"
            text: Translation.tr("Show metadata panel")
            checked: Config.options.search.clipboard.showMetadata
            onCheckedChanged: Config.options.search.clipboard.showMetadata = checked
        }

        ConfigSwitch {
            buttonIcon: "travel_explore"
            text: Translation.tr("Fuzzy search for clipboard")
            checked: Config.options.search.clipboard.enableSloppySearch
            onCheckedChanged: Config.options.search.clipboard.enableSloppySearch = checked
        }
    }

    ContentSection {
        icon: "travel_explore"
        title: Translation.tr("Web Search")

        ContentSubsection {
            title: Translation.tr("Search engine base URL")
            MaterialTextArea {
                Layout.fillWidth: true
                text: Config.options.search.engineBaseUrl
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.search.engineBaseUrl = text;
            }
        }

        ContentSubsection {
            title: Translation.tr("File search directory")
            MaterialTextArea {
                Layout.fillWidth: true
                text: Config.options.search.fileSearchDirectory
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.search.fileSearchDirectory = text;
            }
        }
    }
}
