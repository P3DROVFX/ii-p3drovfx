import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    signal goBack()

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
            text: Translation.tr("Network & Performance Utilities")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }
    ContentSection {
        icon: "speed"
        title: Translation.tr("Network & Performance Utilities")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("User agent string")
            text: Config.options.networking.userAgent
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.networking.userAgent = text;
            }
        }

        ConfigSpinBox {
            icon: "memory"
            text: Translation.tr("Resources polling interval (ms)")
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
        icon: "memory"
        title: Translation.tr("Settings Window Memory")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ConfigSwitch {
                id: settingsUnloadSwitch
                Layout.fillWidth: true
                buttonIcon: "memory"
                text: Translation.tr("Free Settings memory after closing")
                checked: Config.options.settingsApp.unloadAfterSeconds > 0
                onCheckedChanged: {
                    Config.options.settingsApp.unloadAfterSeconds = checked ? 300 : 0
                }
            }

            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "help"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }

                HoverHandler { id: helpHover }

                StyledToolTip {
                    parent: parent
                    extraVisibleCondition: helpHover.hovered
                    text: Translation.tr("When enabled, the Settings app is removed from memory 5 minutes after it is closed. The next opening will have a short cold-start delay.")
                }
            }
        }
    }
}
