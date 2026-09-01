import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
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
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Lockscreen Widgets & Layout")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Widgets & Layout")
            icon: "widgets"

            NoticeBox {
                Layout.fillWidth: true
                text: Translation.tr("You can also set per-widget lock behavior in the Widgets settings page. Multiple widgets can be centered simultaneously.")
            }

            ConfigSwitch {
                buttonIcon: "timer_off"
                text: Translation.tr("Disable clock animation on lock")
                checked: Config.options.background.widgets.clock_cookie.disableAnimationOnLock
                onCheckedChanged: Config.options.background.widgets.clock_cookie.disableAnimationOnLock = checked
            }

            ConfigSlider {
                text: Translation.tr("Center spacing")
                value: Config.options.lock.centerSpacing ?? 20
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: Config.options.lock.centerSpacing = value
            }

            ContentSubsection {
                title: Translation.tr("Lockscreen widgets alignment")
                icon: "align_vertical_center"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.lock.centerAlignment ?? "horizontal"
                    onSelected: newValue => Config.options.lock.centerAlignment = newValue
                    options: [
                        { displayName: Translation.tr("Vertical"), icon: "view_column", value: "vertical" },
                        { displayName: Translation.tr("Horizontal"), icon: "view_stream", value: "horizontal" }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "text_fields"
                text: Translation.tr("Show \"Locked\" text")
                checked: Config.options.lock.showLockedText
                onCheckedChanged: Config.options.lock.showLockedText = checked
            }

            ConfigSwitch {
                buttonIcon: "category"
                text: Translation.tr("Use varying shapes for password characters")
                checked: Config.options.lock.materialShapeChars
                onCheckedChanged: Config.options.lock.materialShapeChars = checked
            }

            ConfigSwitch {
                buttonIcon: "waves"
                text: Translation.tr("Ripple effect on touch")
                checked: Config.options.lock.rippleEffect ?? true
                onCheckedChanged: Config.options.lock.rippleEffect = checked
            }

            ConfigSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Show Now Playing widget")
                checked: Config.options.lock.nowPlaying ?? true
                onCheckedChanged: Config.options.lock.nowPlaying = checked
            }

            ConfigSwitch {
                buttonIcon: "sports_soccer"
                text: Translation.tr("Show sports widget")
                checked: Config.options.lock.sports ?? true
                onCheckedChanged: Config.options.lock.sports = checked
            }

            ConfigSwitch {
                buttonIcon: "alarm"
                text: Translation.tr("Show next alarm")
                checked: Config.options.lock.showAlarm ?? true
                onCheckedChanged: Config.options.lock.showAlarm = checked
            }

            ConfigSwitch {
                buttonIcon: "cloud"
                text: Translation.tr("Show weather icon")
                checked: Config.options.lock.showWeather ?? true
                onCheckedChanged: Config.options.lock.showWeather = checked
            }
        }
    }
}
