import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

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
            targetPageIndex: 2
            targetSectionTitle: Translation.tr("Parallax Engine")
            materialIcon: "loupe"
        }
    }

    ContentSection {
        icon: "security"
        title: Translation.tr("Security")

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
                text: Translation.tr("Anyone with physical access to the machine will be able to see them.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Position")
            icon: "picture_in_picture"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.lock.notifications.position
                onSelected: newValue => {
                    Config.options.lock.notifications.position = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Top left"),
                        icon: "north_west",
                        value: "top_left"
                    },
                    {
                        displayName: Translation.tr("Top right"),
                        icon: "north_east",
                        value: "top_right"
                    },
                    {
                        displayName: Translation.tr("Bottom left"),
                        icon: "south_west",
                        value: "bottom_left"
                    },
                    {
                        displayName: Translation.tr("Bottom right"),
                        icon: "south_east",
                        value: "bottom_right"
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Privacy level")
            icon: "visibility"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.lock.notifications.privacy
                onSelected: newValue => {
                    Config.options.lock.notifications.privacy = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Full content"),
                        icon: "visibility",
                        value: "full"
                    },
                    {
                        displayName: Translation.tr("Hide content"),
                        icon: "visibility_off",
                        value: "redacted"
                    },
                    {
                        displayName: Translation.tr("Count only"),
                        icon: "numbers",
                        value: "countOnly"
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "history"
            text: Translation.tr("Only notifications received while locked")
            checked: Config.options.lock.notifications.onlySinceLock
            onCheckedChanged: {
                Config.options.lock.notifications.onlySinceLock = checked;
            }
        }

        ConfigSpinBox {
            icon: "format_list_numbered"
            text: Translation.tr("Maximum notifications shown")
            value: Config.options.lock.notifications.maxShown
            from: 1
            to: 10
            stepSize: 1
            onValueChanged: {
                Config.options.lock.notifications.maxShown = value;
            }
        }

        ConfigSpinBox {
            icon: "zoom_in"
            text: Translation.tr("Notification size (%)")
            value: Config.options.lock.notifications.zoomPercent
            from: 50
            to: 200
            stepSize: 10
            onValueChanged: {
                Config.options.lock.notifications.zoomPercent = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("App rules")
            icon: "apps"
            Layout.fillWidth: true

            AppRulesEditor {}
        }

        ContentSubsection {
            title: Translation.tr("Filters")
            icon: "filter_alt"
            Layout.fillWidth: true

            ConfigSwitch {
                buttonIcon: "hourglass_disabled"
                text: Translation.tr("Hide transient notifications")
                checked: Config.options.lock.notifications.filters.skipTransient
                onCheckedChanged: {
                    Config.options.lock.notifications.filters.skipTransient = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "low_priority"
                text: Translation.tr("Hide low-urgency notifications")
                checked: Config.options.lock.notifications.filters.skipLowUrgency
                onCheckedChanged: {
                    Config.options.lock.notifications.filters.skipLowUrgency = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Critical notifications")
            icon: "priority_high"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.lock.notifications.filters.criticalOverride
                onSelected: newValue => {
                    Config.options.lock.notifications.filters.criticalOverride = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Always show full"),
                        icon: "priority_high",
                        value: "full"
                    },
                    {
                        displayName: Translation.tr("No exception"),
                        icon: "do_not_disturb_on",
                        value: "none"
                    }
                ]
            }
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Style: General")

        ContentSubsection {
            title: Translation.tr("Lockscreen widget")
            icon: "widgets"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.lock.centerWidget
                onSelected: newValue => {
                    Config.options.lock.centerWidget = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Clock"),
                        icon: "schedule",
                        value: "clock"
                    },
                    {
                        displayName: Translation.tr("Media"),
                        icon: "music_note",
                        value: "media"
                    },
                    {
                        displayName: Translation.tr("None"),
                        icon: "do_not_disturb",
                        value: "none"
                    }
                ]
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr("You can also set per-widget lock behavior in the Widgets settings page. Multiple widgets can be centered simultaneously.")
        }

        ConfigSlider {
            Layout.fillWidth: true
            text: Translation.tr("Center spacing")
            value: Config.options.lock.centerSpacing ?? 20
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.lock.centerSpacing = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Lockscreen widgets aligment")
            icon: "align_vertical_center"
            Layout.fillWidth: true
            ConfigSelectionArray {
                currentValue: Config.options.lock.centerAlignment ?? "horizontal"
                onSelected: newValue => {
                    Config.options.lock.centerAlignment = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Vertical"),
                        icon: "view_column",
                        value: "vertical"
                    },
                    {
                        displayName: Translation.tr("Horizontal"),
                        icon: "view_stream",
                        value: "horizontal"
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "text_fields"
            text: Translation.tr("Show \"Locked\" text")
            checked: Config.options.lock.showLockedText
            onCheckedChanged: {
                Config.options.lock.showLockedText = checked;
            }
            StyledToolTip {
                text: Translation.tr("Display an explicit indicator text below the password field.")
            }
        }

        ConfigSwitch {
            buttonIcon: "category"
            text: Translation.tr("Use varying shapes for password characters")
            checked: Config.options.lock.materialShapeChars
            onCheckedChanged: {
                Config.options.lock.materialShapeChars = checked;
            }
            StyledToolTip {
                text: Translation.tr("Replace the standard dots with random Material You shapes when typing the password.")
            }
        }

        ConfigSwitch {
            buttonIcon: "waves"
            text: Translation.tr("Ripple effect on touch")
            checked: Config.options.lock.rippleEffect ?? true
            onCheckedChanged: {
                Config.options.lock.rippleEffect = checked;
            }
            StyledToolTip {
                text: Translation.tr("Show a ripple animation when clicking anywhere on the lock screen.")
            }
        }
    }

    component AppRulesEditor: ColumnLayout {
        id: editor

        readonly property var conf: Config.options.lock.notifications
        readonly property string query: searchField.text.trim()

        function ruleFor(name) {
            const lower = name.toLowerCase();
            if (conf.neverShowApps.some(app => app.toLowerCase() === lower))
                return "hide";
            if (conf.alwaysShowApps.some(app => app.toLowerCase() === lower))
                return "show";
            return "default";
        }

        function setRule(name, rule) {
            const lower = name.toLowerCase();
            conf.alwaysShowApps = conf.alwaysShowApps.filter(app => app.toLowerCase() !== lower);
            conf.neverShowApps = conf.neverShowApps.filter(app => app.toLowerCase() !== lower);
            if (rule === "show")
                conf.alwaysShowApps = [...conf.alwaysShowApps, name];
            else if (rule === "hide")
                conf.neverShowApps = [...conf.neverShowApps, name];
        }

        // Apps with explicit rules, then (while searching) installed apps and
        // the raw query as a free-text fallback, since notification app names
        // can differ from any desktop entry
        readonly property var displayedApps: {
            const lowerQuery = query.toLowerCase();
            const taken = new Set();
            const result = [];
            const add = (name, icon) => {
                if (!name || taken.has(name.toLowerCase()))
                    return;
                taken.add(name.toLowerCase());
                result.push({
                    name: name,
                    icon: icon
                });
            };
            const matches = name => lowerQuery === "" || name.toLowerCase().includes(lowerQuery);

            [...conf.alwaysShowApps, ...conf.neverShowApps].filter(matches).forEach(name => add(name, ""));
            if (lowerQuery !== "") {
                AppSearch.fuzzyQuery(query).slice(0, 8).forEach(entry => add(entry.name, entry.icon));
                add(query, "");
            }
            return result;
        }

        spacing: 8

        ConfigSelectionArray {
            currentValue: editor.conf.defaultPolicy
            onSelected: newValue => {
                editor.conf.defaultPolicy = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Show by default"),
                    icon: "visibility",
                    value: "show"
                },
                {
                    displayName: Translation.tr("Hide by default"),
                    icon: "visibility_off",
                    value: "hide"
                }
            ]
        }

        MaterialTextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search apps or type a name")
        }

        StyledText {
            visible: editor.displayedApps.length === 0
            Layout.fillWidth: true
            text: Translation.tr("No rules yet. Search to pick an installed app, or type any name a notification reports.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: editor.displayedApps
            delegate: RowLayout {
                id: appRow
                required property var modelData
                readonly property string rule: editor.ruleFor(modelData.name)

                Layout.fillWidth: true
                spacing: 10

                IconImage {
                    implicitSize: 28
                    source: Quickshell.iconPath(appRow.modelData.icon !== "" ? appRow.modelData.icon : AppSearch.guessIcon(appRow.modelData.name), "image-missing")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: appRow.modelData.name
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnSecondaryContainer
                }

                SelectionGroupButton {
                    leftmost: true
                    buttonIcon: "remove"
                    toggled: appRow.rule === "default"
                    onClicked: editor.setRule(appRow.modelData.name, "default")
                    StyledToolTip {
                        text: Translation.tr("Follow default")
                    }
                }
                SelectionGroupButton {
                    buttonIcon: "visibility"
                    toggled: appRow.rule === "show"
                    onClicked: editor.setRule(appRow.modelData.name, "show")
                    StyledToolTip {
                        text: Translation.tr("Always show")
                    }
                }
                SelectionGroupButton {
                    rightmost: true
                    buttonIcon: "visibility_off"
                    toggled: appRow.rule === "hide"
                    onClicked: editor.setRule(appRow.modelData.name, "hide")
                    StyledToolTip {
                        text: Translation.tr("Never show")
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "blur_on"
        title: Translation.tr("Style: Blurred")

        ConfigSwitch {
            buttonIcon: "lens_blur"
            text: Translation.tr("Enable blur")
            checked: Config.options.lock.blur.enable
            onCheckedChanged: {
                Config.options.lock.blur.enable = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "blur_circular"
            text: Translation.tr("Blur intensity")
            enabled: Config.options.lock.blur.enable
            from: 0
            to: 200
            stepSize: 5
            value: Config.options.lock.blur.radius
            usePercentTooltip: false
            onValueChanged: {
                Config.options.lock.blur.radius = value;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.lock.blur.enable
            icon: "zoom_in"
            text: Translation.tr("Extra wallpaper zoom (%)")
            value: Config.options.lock.blur.extraZoom * 100
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.lock.blur.extraZoom = value / 100;
            }
        }
    }
}
