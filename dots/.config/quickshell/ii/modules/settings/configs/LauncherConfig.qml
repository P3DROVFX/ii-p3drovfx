import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.services

ContentPage {
    id: page

    forceWidth: false

    ContentSection {
        icon: "tune"
        title: Translation.tr("Search Behavior")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "trending_up"
                text: Translation.tr("Frequency-based ranking")
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

            ConfigSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Show now playing media bubble")
                checked: Config.options.search.showNowPlayingBubble
                onCheckedChanged: {
                    Config.options.search.showNowPlayingBubble = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Shows a floating media player bubble in the search launcher when media is playing")
                }

            }

            ConfigSlider {
                buttonIcon: "search"
                text: Translation.tr("Search base width (px)")
                value: Config.options.search.baseWidth
                from: 360
                to: 1000
                stepSize: 10
                usePercentTooltip: false
                onValueChanged: Config.options.search.baseWidth = value
            }

        }

    }

    ContentSection {
        icon: "tag"
        title: Translation.tr("Search Prefixes")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: [{
                    "name": Translation.tr("Action"),
                    "icon": "bolt",
                    "prop": "action"
                }, {
                    "name": Translation.tr("App"),
                    "icon": "apps",
                    "prop": "app"
                }, {
                    "name": Translation.tr("Clipboard"),
                    "icon": "content_paste",
                    "prop": "clipboard"
                }, {
                    "name": Translation.tr("Emojis"),
                    "icon": "mood",
                    "prop": "emojis"
                }, {
                    "name": Translation.tr("Math"),
                    "icon": "calculate",
                    "prop": "math"
                }, {
                    "name": Translation.tr("Shell command"),
                    "icon": "terminal",
                    "prop": "shellCommand"
                }, {
                    "name": Translation.tr("Web search"),
                    "icon": "public",
                    "prop": "webSearch"
                }, {
                    "name": Translation.tr("Window search"),
                    "icon": "layers",
                    "prop": "windowSearch"
                }, {
                    "name": Translation.tr("File browser"),
                    "icon": "folder",
                    "prop": "fileBrowser"
                }, {
                    "name": Translation.tr("File search"),
                    "icon": "search",
                    "prop": "fileSearch"
                }, {
                    "name": Translation.tr("Bluetooth"),
                    "icon": "bluetooth",
                    "prop": "bluetooth"
                }, {
                    "name": Translation.tr("Translator"),
                    "icon": "translate",
                    "prop": "translator"
                }, {
                    "name": Translation.tr("Media Downloader"),
                    "icon": "download",
                    "prop": "mediaDownloader"
                }, {
                    "name": Translation.tr("Material Symbols"),
                    "icon": "font_download",
                    "prop": "materialSymbols"
                }]

                delegate: Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    color: Appearance.colors.colSurfaceContainerLow
                    topLeftRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
                    topRightRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
                    bottomLeftRadius: index === 13 ? Appearance.rounding.small : Appearance.rounding.verysmall
                    bottomRightRadius: index === 13 ? Appearance.rounding.small : Appearance.rounding.verysmall

                    ScrollAnimate {
                    }

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

                        TextField {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            text: Config.options.search.prefix[modelData.prop]
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.small
                            onTextChanged: Config.options.search.prefix[modelData.prop] = text

                            background: Rectangle {
                                color: Appearance.colors.colSurfaceContainerHighest
                                radius: Appearance.rounding.full
                            }

                        }

                    }

                }

            }

        }

    }

    ContentSection {
        icon: "label"
        title: Translation.tr("App Aliases")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: Config.options.search.aliases || []

                delegate: Rectangle {
                    id: aliasDelegate

                    property bool isEditing: false

                    Layout.fillWidth: true
                    height: 60
                    color: Appearance.colors.colSurfaceContainerLow
                    topLeftRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
                    topRightRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
                    bottomLeftRadius: index === (Config.options.search.aliases.length - 1) ? Appearance.rounding.small : Appearance.rounding.verysmall
                    bottomRightRadius: index === (Config.options.search.aliases.length - 1) ? Appearance.rounding.small : Appearance.rounding.verysmall

                    ScrollAnimate {
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: modelData.type === "app" ? Appearance.colors.colPrimaryContainer : modelData.type === "folder" ? Appearance.colors.colSecondaryContainer : Appearance.colors.colTertiaryContainer

                            Loader {
                                anchors.centerIn: parent
                                sourceComponent: modelData.type === "app" ? appIconComp : fallbackIconComp
                            }

                            Component {
                                id: appIconComp

                                WAppIcon {
                                    iconName: modelData.target.replace(".desktop", "")
                                    implicitSize: 20
                                    tryCustomIcon: false
                                }

                            }

                            Component {
                                id: fallbackIconComp

                                MaterialSymbol {
                                    iconSize: 20
                                    text: modelData.type === "folder" ? "folder" : modelData.type === "builtin" ? "explore" : "terminal"
                                    color: modelData.type === "folder" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnTertiaryContainer
                                }

                            }

                        }

                        Rectangle {
                            color: Appearance.colors.colSurfaceContainerHigh
                            radius: Appearance.rounding.verysmall
                            implicitWidth: Math.max(40, aliasDelegate.isEditing ? aliasEditInput.implicitWidth + 16 : aliasText.implicitWidth + 16)
                            implicitHeight: 26

                            StyledText {
                                id: aliasText

                                visible: !aliasDelegate.isEditing
                                anchors.centerIn: parent
                                text: modelData.alias
                                font.bold: true
                                color: Appearance.colors.colPrimary
                            }

                            TextField {
                                id: aliasEditInput

                                visible: aliasDelegate.isEditing
                                anchors.fill: parent
                                text: modelData.alias
                                color: Appearance.colors.colPrimary
                                font.bold: true
                                background: null
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                        }

                        StyledText {
                            text: modelData.target
                            color: Appearance.colors.colOnSurface
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: 18
                            colBackground: Appearance.colors.colSurfaceContainerHigh
                            colBackgroundHover: aliasDelegate.isEditing ? Appearance.colors.colSuccessContainer : Appearance.colors.colPrimaryContainer
                            onClicked: {
                                if (aliasDelegate.isEditing) {
                                    let newAlias = aliasEditInput.text.trim();
                                    if (newAlias === "") {
                                        aliasDelegate.isEditing = false;
                                        return ;
                                    }
                                    let newAliases = Array.from(Config.options.search.aliases || []);
                                    let exists = newAliases.some((a, idx) => {
                                        return a.alias === newAlias && idx !== index;
                                    });
                                    if (!exists) {
                                        newAliases[index].alias = newAlias;
                                        Config.options.search.aliases = newAliases;
                                    }
                                    aliasDelegate.isEditing = false;
                                } else {
                                    aliasDelegate.isEditing = true;
                                    aliasEditInput.forceActiveFocus();
                                }
                            }

                            contentItem: Item {
                                anchors.fill: parent

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 18
                                    text: aliasDelegate.isEditing ? "check" : "edit"
                                    color: parent.parent.parent.hovered ? (aliasDelegate.isEditing ? Appearance.colors.colOnSuccessContainer : Appearance.colors.colOnPrimaryContainer) : (aliasDelegate.isEditing ? Appearance.colors.colSuccess : Appearance.colors.colPrimary)
                                }

                            }

                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: 18
                            colBackground: Appearance.colors.colSurfaceContainerHigh
                            colBackgroundHover: Appearance.colors.colErrorContainer
                            onClicked: {
                                let newAliases = Array.from(Config.options.search.aliases || []);
                                newAliases.splice(index, 1);
                                Config.options.search.aliases = newAliases;
                            }

                            contentItem: Item {
                                anchors.fill: parent

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 18
                                    text: "delete"
                                    color: parent.parent.parent.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colError
                                }

                            }

                        }

                    }

                }

            }

        }

    }

    ContentSection {
        icon: "add_circle"
        title: Translation.tr("Add New Alias")

        ColumnLayout {
            id: addAliasArea

            property string selectedType: "app"
            property string appFilter: ""
            property var sortedApps: AppSearch.list.length > 0 ? AppSearch.frecencyQuery("") : []
            readonly property var filteredApps: {
                let list = sortedApps;
                if (appFilter.trim() !== "") {
                    let f = appFilter.toLowerCase();
                    let res = list.filter((app) => {
                        return app.name.toLowerCase().includes(f) || app.id.toLowerCase().includes(f);
                    });
                    return res.slice(0, 12);
                }
                return list.slice(0, 8);
            }

            Layout.fillWidth: true
            spacing: 12

            Item {
                Layout.fillWidth: true
                implicitHeight: typeSection.implicitHeight

                ContentSubsection {
                    id: typeSection

                    title: Translation.tr("Alias Target Type")
                    icon: "my_location"
                    anchors.fill: parent

                    ConfigSelectionArray {
                        currentValue: addAliasArea.selectedType
                        onSelected: (newValue) => {
                            addAliasArea.selectedType = newValue;
                        }
                        options: [{
                            "displayName": Translation.tr("App"),
                            "icon": "apps",
                            "value": "app"
                        }, {
                            "displayName": Translation.tr("Folder"),
                            "icon": "folder",
                            "value": "folder"
                        }, {
                            "displayName": Translation.tr("Command"),
                            "icon": "terminal",
                            "value": "command"
                        }, {
                            "displayName": Translation.tr("Built-in"),
                            "icon": "explore",
                            "value": "builtin"
                        }]
                    }

                }

            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    color: Appearance.colors.colSecondaryContainer
                    topLeftRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.verysmall
                    bottomRightRadius: Appearance.rounding.verysmall

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 12

                        TextField {
                            id: newAliasInput

                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Alias (e.g. i)")
                            placeholderTextColor: Qt.rgba(Appearance.colors.colOnSecondaryContainer.r, Appearance.colors.colOnSecondaryContainer.g, Appearance.colors.colOnSecondaryContainer.b, 0.5)
                            color: Appearance.colors.colOnSecondaryContainer
                            background: null
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    color: Appearance.colors.colSecondaryContainer
                    radius: Appearance.rounding.verysmall

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16

                        TextField {
                            id: newTargetInput

                            Layout.fillWidth: true
                            placeholderText: addAliasArea.selectedType === "builtin" ? Translation.tr("Select target below...") : Translation.tr("Target (e.g. app-id, path)")
                            enabled: addAliasArea.selectedType !== "builtin"
                            placeholderTextColor: Qt.rgba(Appearance.colors.colOnSecondaryContainer.r, Appearance.colors.colOnSecondaryContainer.g, Appearance.colors.colOnSecondaryContainer.b, 0.5)
                            color: Appearance.colors.colOnSecondaryContainer
                            background: null
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                    }

                }

                RippleButton {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 48
                    topLeftRadius: Appearance.rounding.verysmall
                    bottomLeftRadius: Appearance.rounding.verysmall
                    topRightRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    rippleColor: Appearance.colors.colSecondaryContainerActive
                    onClicked: {
                        if (newAliasInput.text.trim() === "" || newTargetInput.text.trim() === "")
                            return ;

                        let newAliases = Array.from(Config.options.search.aliases || []);
                        // Duplicate alias check
                        let exists = newAliases.some((a) => {
                            return a.alias === newAliasInput.text.trim();
                        });
                        if (exists)
                            return ;

                        newAliases.push({
                            "alias": newAliasInput.text.trim(),
                            "type": addAliasArea.selectedType,
                            "target": newTargetInput.text.trim()
                        });
                        Config.options.search.aliases = newAliases;
                        newAliasInput.text = "";
                        newTargetInput.text = "";
                    }

                    contentItem: Item {
                        anchors.fill: parent

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "add"
                            iconSize: 24
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                    }

                }

            }

            Item {
                Layout.fillWidth: true
                implicitHeight: appsSection.implicitHeight

                ContentSubsection {
                    id: appsSection

                    title: addAliasArea.selectedType === "app" ? Translation.tr("Search frequent apps for alias target") : (addAliasArea.selectedType === "builtin" ? Translation.tr("Select available built-in target") : Translation.tr("Enter path or command directly above"))
                    icon: "search"
                    anchors.fill: parent

                    // App suggestion area
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: addAliasArea.selectedType === "app"

                        Rectangle {
                            Layout.fillWidth: true
                            height: 44
                            color: Appearance.colors.colSurfaceContainerHigh
                            radius: 22

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 8
                                spacing: 8

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
                                    background: null
                                    clip: true
                                    onTextChanged: addAliasArea.appFilter = text
                                }

                                IconToolbarButton {
                                    visible: appFilterInput.text !== ""
                                    text: "close"
                                    implicitHeight: 28
                                    implicitWidth: 28
                                    colText: Appearance.colors.colOnSurfaceVariant
                                    onClicked: appFilterInput.text = ""
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

                                    color: chipMouse.containsMouse ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                                    radius: 18
                                    width: appLayout.implicitWidth + 24
                                    height: 36

                                    RowLayout {
                                        id: appLayout

                                        anchors.centerIn: parent
                                        spacing: 6

                                        WAppIcon {
                                            iconName: modelData.icon
                                            implicitSize: 16
                                            tryCustomIcon: false
                                        }

                                        StyledText {
                                            text: modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.bold: chipMouse.containsMouse
                                            color: chipMouse.containsMouse ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
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

                    // Builtin suggestion area
                    Flow {
                        property var builtins: [{
                            "id": "clipboard",
                            "name": Translation.tr("Clipboard"),
                            "icon": "content_paste"
                        }, {
                            "id": "emojis",
                            "name": Translation.tr("Emoji Picker"),
                            "icon": "mood"
                        }, {
                            "id": "math",
                            "name": Translation.tr("Calculator Mode"),
                            "icon": "calculate"
                        }, {
                            "id": "bluetooth",
                            "name": Translation.tr("Bluetooth Manager"),
                            "icon": "bluetooth"
                        }, {
                            "id": "translator",
                            "name": Translation.tr("Translator"),
                            "icon": "translate"
                        }, {
                            "id": "settings",
                            "name": Translation.tr("Settings"),
                            "icon": "settings"
                        }]

                        Layout.fillWidth: true
                        spacing: 8
                        visible: addAliasArea.selectedType === "builtin"

                        Repeater {
                            model: parent.builtins

                            delegate: Rectangle {
                                id: builtinChip

                                property bool selected: newTargetInput.text === modelData.id

                                color: selected ? Appearance.colors.colPrimaryContainer : (builtinMouse.containsMouse ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh)
                                radius: 18
                                width: builtinLayout.implicitWidth + 24
                                height: 36

                                RowLayout {
                                    id: builtinLayout

                                    anchors.centerIn: parent
                                    spacing: 6

                                    MaterialSymbol {
                                        text: modelData.icon
                                        iconSize: 16
                                        color: builtinChip.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                    }

                                    StyledText {
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: builtinChip.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                        font.bold: builtinChip.selected
                                    }

                                }

                                MouseArea {
                                    id: builtinMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        newTargetInput.text = modelData.id;
                                        newAliasInput.forceActiveFocus();
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
        icon: "folder"
        title: Translation.tr("Directories & Targets")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

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

            ContentSubsection {
                title: Translation.tr("File search directory")
                icon: "folder_open"
                Layout.fillWidth: true

                MaterialTextArea {
                    Layout.fillWidth: true
                    text: Config.options.search.fileSearchDirectory
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: Config.options.search.fileSearchDirectory = text
                }

            }

        }

    }

}
