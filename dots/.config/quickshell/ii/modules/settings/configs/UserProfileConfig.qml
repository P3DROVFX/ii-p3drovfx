import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: backgroundRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var avatarShapeOptions: ([
        "Cookie9Sided", "Cookie12Sided", "Circle", "Rectangle", "Clover4Leaf", "Burst",
        "Heart", "Bun", "Flower", "Puffy", "PuffyDiamond", "Sunny",
        "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Ghostish",
        "Clover8Leaf", "SoftBurst", "Boom", "SoftBoom", "Gem", "Diamond",
        "Pentagon", "Square", "Arch", "Fan", "Arrow", "SemiCircle",
        "Oval", "Pill", "Triangle", "Slanted", "ClamShell", "PixelCircle", "PixelTriangle"
    ]).map((shapeName) => {
        return ({
            "displayName": "",
            "shape": shapeName,
            "value": shapeName
        });
    })

    Process {
        id: pickImageProc

        command: ["bash", "-c", "if command -v kdialog &> /dev/null; then FILE=$(kdialog --getopenfilename \"$HOME\" \"*.png *.jpg *.jpeg *.gif *.webp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP\" 2>/dev/null); elif command -v zenity &> /dev/null; then FILE=$(zenity --file-selection --file-filter=\"Images | *.png *.jpg *.jpeg *.gif *.webp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP\" 2>/dev/null); fi; if [ -n \"$FILE\" ] && [ -f \"$FILE\" ]; then EXT=\"${FILE##*.}\"; mkdir -p ~/.config/illogical-impulse && cp \"$FILE\" \"$HOME/.config/illogical-impulse/profile.${EXT}\" && cp \"$FILE\" ~/.config/illogical-impulse/profile.png; echo \"$EXT\"; fi"]

        stdout: SplitParser {
            onRead: (data) => {
                const ext = data.trim();
                if (ext.length > 0) {
                    const targetPath = Directories.shellConfig + "/profile." + ext;
                    Config.options.userProfile.imagePath = "";
                    Config.options.userProfile.imagePath = targetPath;
                }
            }
        }
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
    

        // Hero card: avatar left, inputs right
        ContentSection {
            title: Translation.tr("Profile")
            icon: "person"

            TipBox {
                Layout.fillWidth: true
                Layout.bottomMargin: 12
                text: Translation.tr("For best results, use an image with a 1:1 aspect ratio and at least 256x256 resolution.")
                isFirst: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Avatar
                Item {
                    Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                    implicitWidth: 120
                    implicitHeight: 120

                    UserProfileAvatar {
                        anchors.centerIn: parent
                        width: 110
                        height: 110
                        fontPixelSize: 56
                        fontWeight: Font.Black
                        interactive: Config.options.userProfile.imageStyle === "custom"
                        active: GlobalStates.settingsOpen
                        onClicked: {
                            if (Config.options.userProfile.imageStyle === "custom") {
                                pickImageProc.running = false;
                                pickImageProc.running = true;
                            }
                        }
                    }
                }
            
                // Right column: image style + inputs
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 0

                    // Image style selector
                    ConfigSelectionArray {
                        Layout.fillWidth: true
                        currentValue: Config.options.userProfile.imageStyle
                        onSelected: (v) => {
                            Config.options.userProfile.imageStyle = v;
                            if (v === "custom") {
                                pickImageProc.running = false;
                                pickImageProc.running = true;
                            }
                        }
                        options: [{
                            "displayName": Translation.tr("Initial"),
                            "icon": "title",
                            "value": "initial"
                        }, {
                            "displayName": Translation.tr("Expressive"),
                            "icon": "cookie",
                            "value": "expressive"
                        }, {
                            "displayName": Translation.tr("Custom"),
                            "icon": "image",
                            "value": "custom"
                        }]
                    }

                    Item {
                        implicitHeight: 8
                    }

                    ConfigTextField {
                        text: Translation.tr("Your name")
                        icon: "badge"
                        placeholderText: Translation.tr("Leave empty for system username")
                        inputText: Config.options.userProfile.customName
                        textField.onTextChanged: Config.options.userProfile.customName = textField.text
                    }

                    ConfigTextField {
                        text: Translation.tr("Custom greeting")
                        icon: "waving_hand"
                        placeholderText: Translation.tr("Leave empty for system username")
                        inputText: Config.options.userProfile.customGreeting
                        textField.onTextChanged: Config.options.userProfile.customGreeting = textField.text
                    }
                }
            }
        }

        // Avatar appearance
        ContentSection {
            title: Translation.tr("Avatar Appearance")
            icon: "palette"

            ContentSubsection {
                title: Translation.tr("Color")
                icon: "palette"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.userProfile.avatarColor
                    onSelected: (v) => {
                        return Config.options.userProfile.avatarColor = v;
                    }
                    options: [{
                        "displayName": Translation.tr("Primary"),
                        "icon": "circle",
                        "color": Appearance.colors.colPrimary.toString(),
                        "value": "primary"
                    }, {
                        "displayName": Translation.tr("Secondary"),
                        "icon": "circle",
                        "color": Appearance.colors.colSecondary.toString(),
                        "value": "secondary"
                    }, {
                        "displayName": Translation.tr("Tertiary"),
                        "icon": "circle",
                        "color": Appearance.colors.colTertiary.toString(),
                        "value": "tertiary"
                    }, {
                        "displayName": Translation.tr("Error"),
                        "icon": "circle",
                        "color": Appearance.colors.colError.toString(),
                        "value": "error"
                    }]
                }
            }

            ContentSubsection {
                title: Translation.tr("Shape")
                icon: "category"
                tooltip: Translation.tr("Applies everywhere except the right sidebar header, which has its own shape setting.")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.userProfile.avatarShape
                    onSelected: (v) => {
                        return Config.options.userProfile.avatarShape = v;
                    }
                    options: backgroundRoot.avatarShapeOptions
                }
            }
        }

        ContentSection {
            title: Translation.tr("Sidebar Header")
            icon: "account_circle"

            ContentSubsection {
                title: Translation.tr("Profile image type")
                icon: "image"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.sidebar.dashboardHeader.profileImageType
                    onSelected: (newValue) => {
                        Config.options.sidebar.dashboardHeader.profileImageType = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("User Profile"),
                        "icon": "account_circle",
                        "value": "user_profile"
                    }, {
                        "displayName": Translation.tr("Distro Icon"),
                        "icon": "computer",
                        "value": "distro"
                    }, {
                        "displayName": Translation.tr("None"),
                        "icon": "do_not_disturb",
                        "value": "none"
                    }]
                }
            }

            ContentSubsection {
                title: Translation.tr("Avatar shape")
                icon: "category"
                tooltip: Translation.tr("Shape of the sidebar avatar only, independent from the general avatar shape.")
                visible: Config.options.sidebar.dashboardHeader.profileImageType === "user_profile"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.sidebar.dashboardHeader.avatarShape
                    onSelected: (v) => {
                        return Config.options.sidebar.dashboardHeader.avatarShape = v;
                    }
                    options: backgroundRoot.avatarShapeOptions
                }
            }

            ContentSubsection {
                title: Translation.tr("Sidebar greeting text")
                icon: "title"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.sidebar.dashboardHeader.textMode
                    onSelected: (newValue) => {
                        Config.options.sidebar.dashboardHeader.textMode = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Username"),
                        "icon": "person",
                        "value": "username"
                    }, {
                        "displayName": Translation.tr("Uptime"),
                        "icon": "schedule",
                        "value": "uptime"
                    }, {
                        "displayName": Translation.tr("Custom Text"),
                        "icon": "edit",
                        "value": "custom"
                    }, {
                        "displayName": Translation.tr("None"),
                        "icon": "do_not_disturb",
                        "value": "none"
                    }]
                }
            }

            ContentSubsection {
                visible: Config.options.sidebar.dashboardHeader.textMode === "custom"
                title: Translation.tr("Custom Header Text")
                icon: "edit_note"
                Layout.fillWidth: true

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Enter custom text")
                    text: Config.options.sidebar.dashboardHeader.customText
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: {
                        Config.options.sidebar.dashboardHeader.customText = text;
                    }
                }
            }
        }

        ContentSection {
            title: Translation.tr("Right Sidebar Banner")
            icon: "widgets"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ConfigSwitch {
                    buttonIcon: "image"
                    text: Translation.tr("Enable sidebar banner")
                    checked: Config.options.sidebar.enableBanner
                    onCheckedChanged: {
                        Config.options.sidebar.enableBanner = checked;
                    }
                }

                ConfigSwitch {
                    visible: Config.options.sidebar.enableBanner
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Custom banner image")
                    checked: Config.options.sidebar.useCustomBanner
                    configPage: Qt.resolvedUrl("widgets/BannerImageConfig.qml")
                    onCheckedChanged: {
                        Config.options.sidebar.useCustomBanner = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("When enabled, lets you pick a custom banner image instead of using the wallpaper.")
                    }
                }
            
                ContentSubsection {
                    title: Translation.tr("Sidebar greeting subtext")
                    icon: "text_fields"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.sidebar.dashboardSubHeader.greetingSubtextMode
                        onSelected: (newValue) => {
                            Config.options.sidebar.dashboardSubHeader.greetingSubtextMode = newValue;
                        }

                        options: [{
                            displayName: Translation.tr("Uptime"),
                            icon: "schedule",
                            value: "uptime"
                        }, {
                            displayName: Translation.tr("Custom Text"),
                            icon: "edit",
                            value: "custom"
                        }, {
                            displayName: Translation.tr("None"),
                            icon: "do_not_disturb",
                            value: "none"
                        }]
                    }
                }

                ContentSubsection {
                    visible: Config.options.sidebar.enableBanner && Config.options.sidebar.dashboardSubHeader.greetingSubtextMode === "custom"
                    title: Translation.tr("Custom Header Text")
                    icon: "edit_note"
                    Layout.fillWidth: true

                    MaterialTextArea {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Enter custom text")
                        text: Config.options.sidebar.dashboardSubHeader.customText
                        wrapMode: TextEdit.NoWrap
                        onTextChanged: {
                            Config.options.sidebar.dashboardSubHeader.customText = text;
                        }
                    }
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
