import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    property string configEntryName: "photo"
    property string widgetIdName: "photo"
    property string titleText: Translation.tr("Photo Widget Options")

    signal goBack


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
            text: root.titleText
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
            visible: !Config.isWidgetActive(root.widgetIdName)

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
            visible: Config.isWidgetActive(root.widgetIdName)

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "folder_open"
                mainText: Translation.tr("Choose Image")
                enabled: !WidgetPhotoPicker.picking
                onClicked: WidgetPhotoPicker.pick(root.configEntryName)
            }

            StyledText {
                Layout.fillWidth: true
                visible: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.imagePath && entry.imagePath !== "";
                }
                text: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    let path = entry ? entry.imagePath : "";
                    return Translation.tr("Current image: %1").arg(path);
                }
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.imagePath && entry.imagePath !== "";
                }
                materialIcon: "delete"
                mainText: Translation.tr("Remove Image")
                onClicked: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    if (entry) entry.imagePath = "";
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "subtitles"
                text: Translation.tr("Show Info Overlay/Badge")
                visible: root.configEntryName !== "photo"
                checked: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.showOverlay !== undefined ? entry.showOverlay : true;
                }
                onCheckedChanged: {
                    if (root.configEntryName === "photo") return;
                    let entry = Config.options.background.widgets[root.configEntryName];
                    if (entry && entry.showOverlay !== undefined) {
                        entry.showOverlay = checked;
                    }
                }
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
