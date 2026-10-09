import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.background

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property bool videoLocked: Wallpapers.videoWallpaperActive

    ContentPage {
        id: root
        anchors.fill: parent
        forceWidth: false

        BackgroundSubPageHeader {
            visible: subPageRoot.showBackButton
            title: Translation.tr("Depth Effect")
            onBackRequested: subPageRoot.goBack()
        }

        ContentSection {
            title: Translation.tr("Depth Effect")
            icon: "layers"

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: Translation.tr("Cuts the subject out of the wallpaper and draws it over the desktop widgets, so a clock can sit behind a person. A model runs once per picture, in the background, then exits; on the desktop it costs one image. Nothing is downloaded until you pick a model here.")
            }

            ConfigSwitch {
                buttonIcon: "layers"
                text: Translation.tr("Subject in front of widgets")
                enabled: DepthEffect.anyInstalled && !subPageRoot.videoLocked
                checked: Config.options.background.depthEffect.enable
                onCheckedChanged: {
                    Config.options.background.depthEffect.enable = checked;
                }
                StyledToolTip {
                    text: DepthEffect.anyInstalled
                        ? Translation.tr("Each wallpaper can use another model, or none, from Edit Mode's Wallpaper tab.")
                        : Translation.tr("Download a model below first.")
                }
            }

            ConfigSwitch {
                buttonIcon: "border_outer"
                text: Translation.tr("Widget outlines over the subject")
                enabled: DepthEffect.anyInstalled && Config.options.background.depthEffect.enable
                checked: Config.options.background.depthEffect.outline ?? false
                onCheckedChanged: {
                    Config.options.background.depthEffect.outline = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Where the subject covers a widget, the widget's outline stays drawn on top of it in the widget's own colour, with no fill.")
                }
            }

            ConfigSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Notify while cutting out")
                enabled: DepthEffect.anyInstalled
                checked: Config.options.background.depthEffect.notify ?? true
                onCheckedChanged: {
                    Config.options.background.depthEffect.notify = checked;
                }
                StyledToolTip {
                    text: Translation.tr("A notification when a model starts on a picture and when its cutout is ready. Pictures already cut out stay silent.")
                }
            }
        }

        ContentSection {
            title: Translation.tr("Models")
            icon: "download"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: Translation.tr("The first download also installs the ONNX runtime (~70 MB); removing the last model removes it and every cutout.")
            }

            Repeater {
                model: DepthEffect.models
                delegate: BackgroundModelRow {}
            }

            ContentSubsection {
                visible: DepthEffect.installedModels.length > 1
                title: Translation.tr("Default model")
                icon: "tune"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: DepthEffect.defaultModel
                    options: DepthEffect.installedModels.map(m => ({
                        "displayName": m.name,
                        "icon": m.icon,
                        "value": m.id
                    }))
                    onSelected: newValue => {
                        Config.options.background.depthEffect.model = newValue;
                    }
                }
            }
        }
    }
}
