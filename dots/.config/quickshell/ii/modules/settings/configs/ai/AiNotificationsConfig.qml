import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("AI Notifications")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "notifications"
            title: Translation.tr("Notifications")
            tooltip: Translation.tr("Alerts and banners for completed responses.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "notifications_active"
                    text: Translation.tr("Notify when an answer is ready")
                    checked: Config.options.ai.notify.whenDone
                    onCheckedChanged: {
                        Config.options.ai.notify.whenDone = checked;
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.ai.notify.whenDone
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Only while the chat is out of view")
                    checked: Config.options.ai.notify.onlyWhenAway
                    onCheckedChanged: {
                        Config.options.ai.notify.onlyWhenAway = checked;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.ai.notify.whenDone
                    icon: "timer"
                    text: Translation.tr("Minimum answer time before notifying (seconds)")
                    value: Config.options.ai.notify.minimumSeconds
                    from: 0
                    to: 60
                    stepSize: 1
                    onValueChanged: {
                        Config.options.ai.notify.minimumSeconds = value;
                    }
                }
            }
        }
    }
}
