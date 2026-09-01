import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: lockScreenRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        ContentSection {
            icon: "lock"
            title: Translation.tr("General")

            ConfigSwitch {
                buttonIcon: "lock_outline"
                text: Translation.tr("Use Hyprlock instead of Quickshell")
                checked: Config.options.lock.useHyprlock
                onCheckedChanged: {
                    Config.options.lock.useHyprlock = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Enforce the use of the external Hyprlock over the default Quickshell lockscreen overlay.")
                }
            }

            ConfigSwitch {
                buttonIcon: "power_settings_new"
                text: Translation.tr("Launch on startup")
                checked: Config.options.lock.launchOnStartup
                onCheckedChanged: {
                    Config.options.lock.launchOnStartup = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Start the lock screen daemon when the session begins.")
                }
            }

            ShortcutBox {
                Layout.fillWidth: true
                value: Translation.tr("Wallpaper zoom")
                targetPageId: "wallpaper"
                targetSectionTitle: Translation.tr("Parallax Engine")
                materialIcon: "loupe"
            }
        }

        ContentSection {
            icon: "security"
            title: Translation.tr("Security")

            ConfigSwitch {
                buttonIcon: "fingerprint"
                text: Translation.tr("Unlock with fingerprint")
                checked: Config.options.lock.security.fingerprint.enable
                configPage: Qt.resolvedUrl("widgets/FingerprintConfig.qml")
                onCheckedChanged: {
                    Config.options.lock.security.fingerprint.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Unlock the screen with the fingerprint reader. Click button text to enroll fingerprints, rename or remove them, and test the reader.")
                }
            }

            ConfigSwitch {
                buttonIcon: "password"
                text: Translation.tr("Require password to power off/restart")
                checked: Config.options.lock.security.requirePasswordToPower
                onCheckedChanged: {
                    Config.options.lock.security.requirePasswordToPower = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Block the system power menu until the screen is unlocked.")
                }
            }

            ConfigSwitch {
                buttonIcon: "key"
                text: Translation.tr("Also unlock keyring")
                checked: Config.options.lock.security.unlockKeyring
                onCheckedChanged: {
                    Config.options.lock.security.unlockKeyring = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Automatically unlock the login keyring when unlocking the session.")
                }
            }
        }

        ContentSection {
            icon: "notifications"
            title: Translation.tr("Notifications")

            ConfigSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Show notifications on lock screen")
                checked: Config.options.lock.notifications.enable
                configPage: Qt.resolvedUrl("widgets/LockscreenNotificationsConfig.qml")
                onCheckedChanged: {
                    Config.options.lock.notifications.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Toggle notifications on lockscreen. Click button text for position, rules, and privacy controls.")
                }
            }
        }

        ContentSection {
            icon: "style"
            title: Translation.tr("Widgets & Layout")

            ConfigSwitch {
                buttonIcon: "widgets"
                text: Translation.tr("Lockscreen widgets and layout")
                checked: true
                subPageOnly: true
                configPage: Qt.resolvedUrl("widgets/LockscreenWidgetsConfig.qml")
                StyledToolTip {
                    text: Translation.tr("Click button text to configure lockscreen clock animation, alignment, spacing, and widget visibility.")
                }
            }
        }

        ContentSection {
            icon: "blur_on"
            title: Translation.tr("Lock Screen Effects")

            ConfigSwitch {
                buttonIcon: "auto_fix_high"
                text: Translation.tr("Enable visual effects")
                checked: Config.options.lock.blur.enable || Config.options.lock.desaturate.enable || Config.options.lock.colorWash.enable || Config.options.lock.vignette.enable
                configPage: Qt.resolvedUrl("widgets/LockscreenEffectsConfig.qml")
                property bool readyForToggle: false
                Component.onCompleted: readyForToggle = true
                onCheckedChanged: {
                    if (!readyForToggle)
                        return;
                    Config.options.lock.blur.enable = checked;
                    Config.options.lock.desaturate.enable = checked;
                    Config.options.lock.colorWash.enable = checked;
                    Config.options.lock.vignette.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Configure wallpaper blur, desaturation, color wash tint, and vignette effects on lock screen.")
                }
            }
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "windows"
                    label: Translation.tr("Window blur")
                    sectionHighlight: Translation.tr("Transparency & Blur")
                }

                RelatedChip {
                    pageId: "wallpaper"
                    label: Translation.tr("Wallpaper blur")
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
