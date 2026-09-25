import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    RowLayout {
        visible: root.showBackButton
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
            text: Translation.tr("Event Sound Triggers")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("System Sound Events")
        icon: "notifications_active"

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Notifications")
            checked: Config.options.sounds.notifications
            onCheckedChanged: {
                Config.options.sounds.notifications = checked;
            }
            StyledToolTip {
                text: Translation.tr("Play a sound when a notification arrives. Muted in Do Not Disturb mode.")
            }
        }

        ConfigSwitch {
            buttonIcon: "volume_up"
            text: Translation.tr("Volume change")
            checked: Config.options.sounds.volumeChange
            onCheckedChanged: {
                Config.options.sounds.volumeChange = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "battery_alert"
            text: Translation.tr("Battery & power")
            checked: Config.options.sounds.battery
            onCheckedChanged: {
                Config.options.sounds.battery = checked;
            }
            StyledToolTip {
                text: Translation.tr("Charger plug/unplug, battery low and battery full.")
            }
        }

        ConfigSwitch {
            buttonIcon: "photo_camera"
            text: Translation.tr("Screenshot shutter")
            checked: Config.options.sounds.screenshot
            onCheckedChanged: {
                Config.options.sounds.screenshot = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "bluetooth_connected"
            text: Translation.tr("Device connections")
            checked: Config.options.sounds.devices
            onCheckedChanged: {
                Config.options.sounds.devices = checked;
            }
            StyledToolTip {
                text: Translation.tr("Bluetooth devices connecting/disconnecting and KDE Connect phone reachability.")
            }
        }

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Screen lock & unlock")
            checked: Config.options.sounds.lock
            onCheckedChanged: {
                Config.options.sounds.lock = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "av_timer"
            text: Translation.tr("Pomodoro")
            checked: Config.options.sounds.pomodoro
            onCheckedChanged: {
                Config.options.sounds.pomodoro = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "hourglass_top"
            text: Translation.tr("Timer finished")
            checked: Config.options.sounds.timer
            onCheckedChanged: {
                Config.options.sounds.timer = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "alarm"
            text: Translation.tr("Alarm ring")
            checked: Config.options.sounds.alarm
            onCheckedChanged: {
                Config.options.sounds.alarm = checked;
            }
            StyledToolTip {
                text: Translation.tr("Rings even when system sounds are disabled, so the master switch can't silence your alarm.")
            }
        }

        ConfigSwitch {
            buttonIcon: "waves"
            text: Translation.tr("Gentle wake (alarm fade-in)")
            enabled: Config.options.sounds.alarm
            checked: Config.options.sounds.alarmFadeIn
            onCheckedChanged: {
                Config.options.sounds.alarmFadeIn = checked;
            }
            StyledToolTip {
                text: Translation.tr("The alarm starts silent and ramps up to full volume instead of blasting instantly.")
            }
        }

        ConfigSpinBox {
            visible: Config.options.sounds.alarm && Config.options.sounds.alarmFadeIn
            icon: "schedule"
            text: Translation.tr("Fade-in duration (seconds)")
            value: Config.options.sounds.alarmFadeInSeconds
            from: 5
            to: 120
            stepSize: 5
            onValueChanged: {
                Config.options.sounds.alarmFadeInSeconds = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "login"
            text: Translation.tr("Login")
            checked: Config.options.sounds.session
            onCheckedChanged: {
                Config.options.sounds.session = checked;
            }
            StyledToolTip {
                text: Translation.tr("Play a welcome sound when the shell starts.")
            }
        }
    }
}
