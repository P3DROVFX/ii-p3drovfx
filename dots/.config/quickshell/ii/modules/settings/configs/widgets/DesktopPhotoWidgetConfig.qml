import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    Process {
        id: pickImageProc
        command: ["bash", "-c", "if command -v kdialog &> /dev/null; then FILE=$(kdialog --getopenfilename \"$HOME\" \"Images | *.png *.jpg *.jpeg *.webp *.bmp\" 2>/dev/null); elif command -v zenity &> /dev/null; then FILE=$(zenity --file-selection --file-filter=\"Images | *.png *.jpg *.jpeg *.webp *.bmp\" 2>/dev/null); fi; if [ -n \"$FILE\" ] && [ -f \"$FILE\" ]; then echo \"$FILE\"; fi"]
        stdout: SplitParser {
            onRead: data => {
                let path = data.trim();
                if (path.length > 0) {
                    Config.options.background.widgets.photo.imagePath = path;
                }
            }
        }
    }

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

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Photo Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Photo Settings")
        icon: "image"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("photo_default")

            PagePlaceholder {
                anchors.fill: parent
                icon: "image"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Photo widget disabled")
                description: Translation.tr("Enable the desktop photo widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("photo_default")

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "folder_open"
                mainText: Translation.tr("Choose Image")
                onClicked: {
                    pickImageProc.running = false;
                    pickImageProc.running = true;
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: Config.options.background.widgets.photo.imagePath !== ""
                text: Translation.tr("Current image: %1").arg(Config.options.background.widgets.photo.imagePath)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: Config.options.background.widgets.photo.imagePath !== ""
                materialIcon: "delete"
                mainText: Translation.tr("Remove Image")
                onClicked: {
                    Config.options.background.widgets.photo.imagePath = "";
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.enableShadows = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable Inner Shadows")
                checked: Config.options.background.widgets.enableInnerShadow ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.enableInnerShadow = checked;
                }
            }
        }
    }
}
