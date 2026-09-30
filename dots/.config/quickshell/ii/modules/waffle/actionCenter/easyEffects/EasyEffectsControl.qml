import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

/**
 * The EasyEffects toggle's page in the action center: effects off, or one of the output
 * device's presets, in the Windows sound-effects list's shape. "More settings" opens the
 * EasyEffects app.
 */
Item {
    id: root

    Component.onCompleted: EasyEffects.hold("waffleControl", true)
    Component.onDestruction: EasyEffects.hold("waffleControl", false)

    WPanelPageColumn {
        anchors.fill: parent

        BodyRectangle {
            implicitHeight: 400
            implicitWidth: 50

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                HeaderRow {
                    Layout.fillWidth: true
                    title: Translation.tr("Sound effects")
                }

                StyledFlickable {
                    id: flickable
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    contentHeight: choices.implicitHeight
                    contentWidth: width
                    clip: true

                    EasyEffectsChoices {
                        id: choices
                        width: flickable.width
                    }
                }
            }
        }

        WPanelSeparator {}

        FooterRectangle {
            WButton {
                id: moreSettingsButton
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                }
                implicitHeight: 40
                implicitWidth: contentItem.implicitWidth + 30
                color: "transparent"
                visible: Config.options.easyEffects?.appEnable ?? true

                onClicked: GlobalStates.openEasyEffectsApp("presets")

                contentItem: Item {
                    anchors.centerIn: parent
                    implicitWidth: buttonText.implicitWidth
                    WText {
                        id: buttonText
                        anchors.centerIn: parent
                        text: Translation.tr("More sound effect settings")
                        color: moreSettingsButton.pressed ? Looks.colors.fg : Looks.colors.fg1
                    }
                }
            }
        }
    }
}
