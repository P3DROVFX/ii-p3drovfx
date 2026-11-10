import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for the Lock Screen page: security and notification options (tiles on the page). The page itself draws these
// options as a live preview, sliders and tiles; SearchRegistry indexes this file
// (see SettingsPageRegistry `searchSources`) so the options stay searchable.
ColumnLayout {
    ContentSection {
        icon: "security"
        title: Translation.tr("Security")

        ConfigSwitch {
            buttonIcon: "fingerprint"
            text: Translation.tr("Unlock with fingerprint")
            checked: Config.options.lock.security.fingerprint.enable
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
            onCheckedChanged: {
                Config.options.lock.notifications.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Toggle notifications on lockscreen. Click button text for position, rules, and privacy controls.")
            }
        }
    }
}
