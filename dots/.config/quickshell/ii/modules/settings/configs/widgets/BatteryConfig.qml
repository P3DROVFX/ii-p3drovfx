import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false

    signal goBack

    // ── Back button row ───────────────────────────────────────────────────
    RowLayout {
        spacing: 12

        RippleButton {
            id: backButton
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
            text: Translation.tr("Battery Settings")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "battery_full"
        title: Translation.tr("Battery")

        ContentSubsection {
            title: Translation.tr("Battery Icon Style")
            icon: "style"
            Layout.fillWidth: true

            StyledComboBox {
                buttonIcon: "style"
                textRole: "displayName"
                model: [
                    {
                        displayName: Translation.tr("Windows 11"),
                        value: "windows11"
                    },
                    {
                        displayName: Translation.tr("Android 16"),
                        value: "android16"
                    },
                    {
                        displayName: Translation.tr("One UI"),
                        value: "oneui"
                    }
                ]
                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.battery.style);
                    return index !== -1 ? index : 0;
                }
                onActivated: index => {
                    Config.options.battery.style = model[index].value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Show Percentage")
            enabled: Config.options.battery.style === "windows11"
            icon: "percent"
            Layout.fillWidth: true

            StyledComboBox {
                buttonIcon: "percent"
                textRole: "displayName"
                model: [
                    {
                        displayName: Translation.tr("Off"),
                        value: "off"
                    },
                    {
                        displayName: Translation.tr("Left"),
                        value: "left"
                    },
                    {
                        displayName: Translation.tr("Right"),
                        value: "right"
                    }
                ]

                currentIndex: {
                    const val = Config.options.battery.showPercentage || "off";
                    const index = model.findIndex(item => item.value === val);
                    return index !== -1 ? index : 0;
                }

                onActivated: index => {
                    Config.options.battery.showPercentage = model[index].value;
                }
            }
        }
    }
}
