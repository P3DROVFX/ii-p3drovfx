import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

    Process {
        id: pickImageProc
        command: ["bash", "-c", "if command -v kdialog &> /dev/null; then FILE=$(kdialog --getopenfilename \"$HOME\" \"*.png *.jpg *.jpeg\" 2>/dev/null); elif command -v zenity &> /dev/null; then FILE=$(zenity --file-selection --file-filter=\"Images | *.png *.jpg *.jpeg\" 2>/dev/null); fi; if [ -n \"$FILE\" ] && [ -f \"$FILE\" ]; then cp \"$FILE\" ~/.config/quickshell/ii/assets/profile.png; echo 'success'; fi"]
        stdout: SplitParser {
            onRead: data => {
                if (data.trim() === "success") {
                    Config.options.userProfile.imagePath = Directories.home + "/.config/quickshell/ii/assets/profile.png?rand=" + Math.random();
                }
            }
        }
    }

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

                MaterialShape {
                    id: heroShape
                    anchors.centerIn: parent
                    width: 110
                    height: 110

                    function resolveShape(s) {
                        switch (s) {
                            case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided;
                            case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided;
                            case "Squircle":      return MaterialShape.Shape.Squircle;
                            case "Circle":        return MaterialShape.Shape.Circle;
                            case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf;
                            case "Burst":         return MaterialShape.Shape.Burst;
                            case "Heart":         return MaterialShape.Shape.Heart;
                            case "Bun":           return MaterialShape.Shape.Bun;
                            default:              return MaterialShape.Shape.Cookie9Sided;
                        }
                    }
                    shape: resolveShape(Config.options.userProfile.avatarShape)

                    color: {
                        switch (Config.options.userProfile.avatarColor) {
                            case "secondary": return Appearance.colors.colSecondary;
                            case "tertiary":  return Appearance.colors.colTertiary;
                            case "error":     return Appearance.colors.colError;
                            default:          return Appearance.colors.colPrimary;
                        }
                    }

                    readonly property color onColor: {
                        switch (Config.options.userProfile.avatarColor) {
                            case "secondary": return Appearance.colors.colOnSecondary;
                            case "tertiary":  return Appearance.colors.colOnTertiary;
                            case "error":     return Appearance.colors.colOnError;
                            default:          return Appearance.colors.colOnPrimary;
                        }
                    }

                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        source: {
                            if (Config.options.userProfile.imageStyle === "custom")
                                return "file://" + Config.options.userProfile.imagePath;
                            if (Config.options.userProfile.imageStyle === "initial")
                                return Directories.userAvatarPathAccountsService;
                            return "";
                        }
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                    }

                    OpacityMask {
                        anchors.fill: parent
                        source: avatarImg
                        maskSource: heroShape
                        visible: avatarImg.status === Image.Ready && Config.options.userProfile.imageStyle !== "expressive"
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: {
                            let n = Config.options.userProfile.customName || SystemInfo.username;
                            return n.charAt(0).toUpperCase();
                        }
                        color: parent.onColor
                        font.pixelSize: 56
                        font.weight: Font.Black
                        font.family: Appearance.font.family.expressive
                        visible: avatarImg.status !== Image.Ready || Config.options.userProfile.imageStyle === "expressive"
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Config.options.userProfile.imageStyle === "custom" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (Config.options.userProfile.imageStyle === "custom") {
                                pickImageProc.running = false;
                                pickImageProc.running = true;
                            }
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
                    onSelected: v => {
                        Config.options.userProfile.imageStyle = v
                        if (v === "custom") {
                            pickImageProc.running = false;
                            pickImageProc.running = true;
                        }
                    }
                    options: [
                        { displayName: Translation.tr("Initial"),    icon: "title",  value: "initial"    },
                        { displayName: Translation.tr("Expressive"), icon: "cookie", value: "expressive" },
                        { displayName: Translation.tr("Custom"),     icon: "image",  value: "custom"     }
                    ]
                }

                Item { implicitHeight: 8 }

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
                onSelected: v => Config.options.userProfile.avatarColor = v
                options: [
                    { displayName: Translation.tr("Primary"),   icon: "circle", color: Appearance.colors.colPrimary.toString(),   value: "primary"   },
                    { displayName: Translation.tr("Secondary"), icon: "circle", color: Appearance.colors.colSecondary.toString(), value: "secondary" },
                    { displayName: Translation.tr("Tertiary"),  icon: "circle", color: Appearance.colors.colTertiary.toString(),  value: "tertiary"  },
                    { displayName: Translation.tr("Error"),     icon: "circle", color: Appearance.colors.colError.toString(),     value: "error"     }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Shape")
            icon: "category"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.userProfile.avatarShape
                onSelected: v => Config.options.userProfile.avatarShape = v
                options: (["Cookie9Sided", "Cookie12Sided", "Squircle", "Circle", "Clover4Leaf", "Burst", "Heart", "Bun"]).map(s => ({
                    displayName: "",
                    shape: s,
                    value: s
                }))
            }
        }
    }
}
