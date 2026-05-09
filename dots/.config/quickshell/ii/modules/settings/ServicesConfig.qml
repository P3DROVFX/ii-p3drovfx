import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Io

ContentPage {
    id: page
    readonly property int index: 5
    property bool register: parent.register ?? false
    forceWidth: true

    ContentSection {
        icon: "neurology"
        title: Translation.tr("AI")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("System prompt")
            text: Config.options.ai.systemPrompt
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.ai.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        icon: "album"
        title: Translation.tr("Media")

        ContentSubsection {
            title: Translation.tr("Prioritized player")
            tooltip: Translation.tr("Automatically sets the active player to a newly detected player if its identifier matches the value specified in the priority player property so you dont have to manually set the active player")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Desktop entry name (e.g. spotify, google-chrome)")
                text: Config.options.media.priorityPlayer
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.media.priorityPlayer = text;
                }
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

    }

    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Music Recognition")

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
    }

    ContentSection {
        icon: "cell_tower"
        title: Translation.tr("Networking")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("User agent (for services that require it)")
            text: Config.options.networking.userAgent
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.networking.userAgent = text;
            }
        }
    }

    ContentSection {
        icon: "memory"
        title: Translation.tr("Resources")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
        
    }


    ContentSection {
        icon: "lyrics"
        title: Translation.tr("Lyrics")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable lyrics service")
            checked: Config.options.lyricsService.enable
            onCheckedChanged: {
                Config.options.lyricsService.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Disabling this will prevent the API from being called, but already cached lyrics will still be available.")
            }
        }


        ConfigRow {
            uniform: true

            ConfigSwitch {
                enabled: Config.options.lyricsService.enable
                buttonIcon: "mood"
                text: Translation.tr("Enable genius lyrics service")
                checked: Config.options.lyricsService.enableGenius
                onCheckedChanged: {
                    Config.options.lyricsService.enableGenius = checked;
                }
            }
            ConfigSwitch {
                enabled: Config.options.lyricsService.enable
                buttonIcon: "library_books"
                text: Translation.tr("Enable lrclib lyrics service")
                checked: Config.options.lyricsService.enableLrclib
                onCheckedChanged: {
                    Config.options.lyricsService.enableLrclib = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "file_open"
        title: Translation.tr("Save paths")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Video Recording Path")
            text: Config.options.screenRecord.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenRecord.savePath = text;
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Screenshot Path (leave empty to just copy)")
            text: Config.options.screenSnip.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenSnip.savePath = text;
            }
        }
    }

    ContentSection {
        icon: "search"
        title: Translation.tr("Search")

        ContentSubsection {
            title: Translation.tr("Prefixes")
            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Action")
                    text: Config.options.search.prefix.action
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.action = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Clipboard")
                    text: Config.options.search.prefix.clipboard
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.clipboard = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Emojis")
                    text: Config.options.search.prefix.emojis
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.emojis = text;
                    }
                }
            }

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Math")
                    text: Config.options.search.prefix.math
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.math = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Shell command")
                    text: Config.options.search.prefix.shellCommand
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.shellCommand = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Web search")
                    text: Config.options.search.prefix.webSearch
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.webSearch = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("File search")
                    text: Config.options.search.prefix.fileSearch
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.fileSearch = text;
                    }
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Web search")
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Base URL")
                text: Config.options.search.engineBaseUrl
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.engineBaseUrl = text;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("File search")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search directory")
                text: Config.options.search.fileSearchDirectory
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.fileSearchDirectory = text;
                }
            }

            ConfigSwitch {
                buttonIcon: "hide_image"
                text: Translation.tr("Blur file search result previews")
                checked: Config.options.search.blurFileSearchResultPreviews
                onCheckedChanged: {
                    Config.options.search.blurFileSearchResultPreviews = checked;
                }
            }

        }
    }

    ContentSection {
        icon: "file_open"
        title: Translation.tr("Wallpaper Browser")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Download path")
            text: Config.options.wallpapers.paths.download
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.wallpapers.paths.download = text;
            }
        }
    }

    // There's no update indicator in ii for now so we shouldn't show this yet
    // ContentSection {
    //     icon: "deployed_code_update"
    //     title: Translation.tr("System updates (Arch only)")

    //     ConfigSwitch {
    //         text: Translation.tr("Enable update checks")
    //         checked: Config.options.updates.enableCheck
    //         onCheckedChanged: {
    //             Config.options.updates.enableCheck = checked;
    //         }
    //     }

    //     ConfigSpinBox {
    //         icon: "av_timer"
    //         text: Translation.tr("Check interval (mins)")
    //         value: Config.options.updates.checkInterval
    //         from: 60
    //         to: 1440
    //         stepSize: 60
    //         onValueChanged: {
    //             Config.options.updates.checkInterval = value;
    //         }
    //     }
    // }

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Weather")
        ConfigRow {
            ConfigSwitch {
                buttonIcon: "assistant_navigation"
                text: Translation.tr("Enable GPS based location")
                checked: Config.options.bar.weather.enableGPS
                onCheckedChanged: {
                    Config.options.bar.weather.enableGPS = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "thermometer"
                text: Translation.tr("Fahrenheit unit")
                checked: Config.options.bar.weather.useUSCS
                onCheckedChanged: {
                    Config.options.bar.weather.useUSCS = checked;
                }
                StyledToolTip {
                    text: Translation.tr("It may take a few seconds to update")
                }
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("City name")
            text: Config.options.bar.weather.city
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.bar.weather.city = text;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (m)")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: {
                Config.options.bar.weather.fetchInterval = value;
            }
        }
    }

    ContentSection {
        id: btImagesSection
        icon: "bluetooth"
        title: Translation.tr("Bluetooth Device Images")

        // Processing Logic
        property string pendingMac: ""
        readonly property string manageScript: Quickshell.shellPath("scripts/services/manage_device_image.sh")

        function getDeviceImages() {
            let images = (Config.options.apps && Config.options.apps.bluetoothDeviceImages) ? Config.options.apps.bluetoothDeviceImages : [];
            // Convert to real JS array if it isn't already (though it should be now)
            return Array.from(images);
        }

        function getAvailableDevices() {
            let all = BluetoothStatus.friendlyDeviceList;
            let managed = getDeviceImages();
            let available = [];
            for (let i = 0; i < all.length; i++) {
                let isManaged = false;
                for (let j = 0; j < managed.length; j++) {
                    if (all[i].address === managed[j].mac) {
                        isManaged = true;
                        break;
                    }
                }
                if (!isManaged) {
                    available.push(all[i]);
                }
            }
            return available;
        }

        function getDeviceName(mac) {
            let all = BluetoothStatus.friendlyDeviceList;
            for (let i = 0; i < all.length; i++) {
                if (all[i].address === mac) {
                    return all[i].name || "Unknown Device";
                }
            }
            return "Unknown Device";
        }

        Process {
            id: pickerProc
            stdout: StdioCollector {
                onStreamFinished: {
                    let path = text.trim();
                    if (path.length > 0 && btImagesSection.pendingMac !== "") {
                        copyProc.exec([btImagesSection.manageScript, "copy", path, btImagesSection.pendingMac]);
                    }
                }
            }
        }

        Process {
            id: copyProc
            stdout: StdioCollector {
                onStreamFinished: {
                    let filename = text.trim();
                    if (filename.length > 0) {
                        let list = btImagesSection.getDeviceImages();
                        let idx = -1;
                        for (let i = 0; i < list.length; i++) {
                            if (list[i].mac === btImagesSection.pendingMac) {
                                idx = i;
                                break;
                            }
                        }
                        if (idx !== -1) {
                            list[idx] = { "mac": btImagesSection.pendingMac, "image": filename };
                        } else {
                            list.push({ "mac": btImagesSection.pendingMac, "image": filename });
                        }
                        Config.options.apps.bluetoothDeviceImages = list;
                        btImagesSection.pendingMac = ""; 
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("1. Select a Device")
            visible: btImagesSection.getAvailableDevices().length > 0
            
            Flow {
                Layout.fillWidth: true
                spacing: 12
                
                Repeater {
                    model: btImagesSection.getAvailableDevices()
                    delegate: Rectangle {
                        width: 240
                        height: 76
                        radius: Appearance.rounding.large
                        color: isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerLow
                        border.color: isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colOutlineVariant
                        border.width: 1
                        
                        readonly property bool isSelected: btImagesSection.pendingMac === (modelData ? modelData.address : "")
                        
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 14

                            Item {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42

                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: 42
                                    color: isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                    
                                    function rollShape() {
                                        const shapes = ["Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Clover8Leaf", "SoftBurst", "Circle", "Sunny"];
                                        shapeString = shapes[Math.floor(Math.random() * shapes.length)];
                                    }
                                    Component.onCompleted: rollShape()
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "bluetooth"
                                    iconSize: 22
                                    fill: 1
                                    color: isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    text: (modelData && modelData.name) ? modelData.name : "Unknown"
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                StyledText {
                                    text: (modelData && modelData.address) ? modelData.address : ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                    opacity: isSelected ? 0.9 : 0.7
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData) btImagesSection.pendingMac = modelData.address
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("2. Assign Image")
            visible: btImagesSection.pendingMac !== ""
            
            Rectangle {
                Layout.fillWidth: true
                height: 120
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh
                border.color: Appearance.colors.colPrimary
                border.width: 1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 14
                    
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2
                        StyledText {
                            text: Translation.tr("Preparing to style: ") + btImagesSection.getDeviceName(btImagesSection.pendingMac)
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                            Layout.alignment: Qt.AlignHCenter
                        }
                        StyledText {
                            text: btImagesSection.pendingMac
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOutline
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignHCenter
                        materialIcon: "add_photo_alternate"
                        mainText: Translation.tr("Upload Artwork")
                        onClicked: pickerProc.exec([btImagesSection.manageScript, "pick"])
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Managed Devices")
            visible: btImagesSection.getDeviceImages().length > 0
            
            Flow {
                Layout.fillWidth: true
                spacing: 16
                
                Repeater {
                    model: btImagesSection.getDeviceImages()
                    delegate: Rectangle {
                        width: 180
                        height: 220
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colSurfaceContainerLow
                        border.color: Appearance.colors.colOutlineVariant
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            // Image Container
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 110
                                color: Appearance.colors.colSurfaceContainerHighest
                                radius: Appearance.rounding.large
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    source: (modelData && modelData.image) ? Qt.resolvedUrl("../../assets/images/devices/" + modelData.image) : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                            }

                            // Info Container
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                
                                StyledText {
                                    text: modelData ? btImagesSection.getDeviceName(modelData.mac) : ""
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSurface
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    text: modelData ? modelData.mac : ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.numbers
                                    color: Appearance.colors.colOnSurfaceVariant
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }
                            }

                            // Delete Action
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true } // Spacer pushes button to right
                                
                                IconToolbarButton {
                                    text: "delete"
                                    onClicked: {
                                        let list = btImagesSection.getDeviceImages();
                                        list.splice(index, 1);
                                        Config.options.apps.bluetoothDeviceImages = list;
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
