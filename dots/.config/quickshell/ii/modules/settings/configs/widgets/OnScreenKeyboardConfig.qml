import QtQuick
import QtQuick.Layouts
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
                text: Translation.tr("On-Screen Keyboard")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        KeyboardShortcutBox {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            text: Translation.tr("Toggle On-Screen Keyboard")
            keys: ["Super", "K"]
        }

        ContentSection {
            title: Translation.tr("General")
            icon: "tune"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Show on-screen keyboard")
                    checked: GlobalStates.oskOpen
                    onCheckedChanged: {
                        GlobalStates.oskOpen = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Open or close the virtual keyboard on screen")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "splitscreen"
                    text: Translation.tr("Split the keyboard for thumb typing")
                    checked: Config.options.osk.split
                    onCheckedChanged: Config.options.osk.split = checked

                    StyledToolTip {
                        text: Translation.tr("Pushes the two halves apart with an empty middle. On a tablet held in two hands the middle columns of a full-width keyboard are out of reach of either thumb.")
                    }
                }
            }
        }

        ContentSection {
            title: Translation.tr("Automatic keyboard")
            icon: "touch_app"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ConfigSwitch {
                    buttonIcon: "touch_app"
                    text: Translation.tr("Raise the keyboard when a text field is tapped")
                    checked: Config.options.osk.autoShow.enable
                    onCheckedChanged: Config.options.osk.autoShow.enable = checked

                    StyledToolTip {
                        text: Translation.tr("Only focus caused by a finger or a pen counts. A mouse click or Tab never raises the keyboard.")
                    }
                }

                // The switch above is the user's intent; this is whether it can be honoured.
                // Without the box, turning the switch on does nothing and says nothing.
                //
                // The button matters more than the snippet here. Pasting a command into a
                // terminal needs a keyboard, and the whole point of this switch is a
                // device that has none — so the box that unblocks the keyboard cannot
                // itself require one.
                HelperCodeBox {
                    visible: Config.options.osk.autoShow.enable
                        && (!OskAutoShow.binaryExists || OskAutoShow.building
                            || OskAutoShow.buildResult === "failed")
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    icon: "terminal"
                    title: Translation.tr("Compile the keyboard helper")
                    text: Translation.tr("Wayland tells an input method when a text field is focused, and Quickshell has no binding for that protocol — so a small helper observes it. It only has to be built once, and it starts working straight away — no restart.")
                    codeSnippet: "cd " + Directories.scriptPath + "/osk/osk_autoshow_src && cargo build --release && cp target/release/osk_autoshow ../osk_autoshow"
                    snippetWrapMode: Text.Wrap

                    actionText: Translation.tr("Build it now")
                    actionIcon: "build"
                    actionBusy: OskAutoShow.building
                    busyText: Translation.tr("Building…")
                    statusIsError: OskAutoShow.buildResult === "failed" || !OskAutoShow.cargoAvailable
                    statusText: {
                        if (!OskAutoShow.cargoAvailable)
                            return Translation.tr("Rust and cargo are not installed, so the build cannot run here.");
                        if (OskAutoShow.building)
                            return Translation.tr("Compiling — this takes about a minute the first time.");
                        if (OskAutoShow.buildResult === "failed")
                            return Translation.tr("The build failed: %1").arg(
                                OskAutoShow.buildOutput.split("\n").slice(-3).join(" "));
                        return "";
                    }
                    onActionClicked: OskAutoShow.buildHelper()
                }

                // Built, switched on, and still nothing happens: the helper has to be able
                // to read /dev/input to tell a finger from a mouse, and that is a group
                // membership rather than anything the shell can grant itself.
                HelperCodeBox {
                    visible: Config.options.osk.autoShow.enable && OskAutoShow.binaryExists
                        && OskAutoShow.permissionDenied
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    icon: "vpn_key"
                    title: Translation.tr("Input device permissions")
                    text: Translation.tr("The helper cannot read /dev/input, so it cannot tell a finger from a mouse. Add your user to the input group and log back in:")
                    codeSnippet: "sudo usermod -aG input $USER"
                    snippetWrapMode: Text.Wrap
                }

                ConfigSwitch {
                    buttonIcon: "pan_tool"
                    text: Translation.tr("Trigger with finger")
                    enabled: Config.options.osk.autoShow.enable
                    checked: Config.options.osk.autoShow.allowTouch
                    onCheckedChanged: Config.options.osk.autoShow.allowTouch = checked

                    StyledToolTip {
                        text: Translation.tr("Automatically show the virtual keyboard when tapping text fields with a finger on touchscreen")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "stylus"
                    text: Translation.tr("Trigger with pen")
                    enabled: Config.options.osk.autoShow.enable
                    checked: Config.options.osk.autoShow.allowPen
                    onCheckedChanged: Config.options.osk.autoShow.allowPen = checked

                    StyledToolTip {
                        text: Translation.tr("Automatically show the virtual keyboard when tapping text fields with a stylus or pen")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "mouse"
                    text: Translation.tr("Trigger with mouse click")
                    enabled: Config.options.osk.autoShow.enable
                    checked: Config.options.osk.autoShow.allowMouse
                    onCheckedChanged: Config.options.osk.autoShow.allowMouse = checked

                    StyledToolTip {
                        text: Translation.tr("Off by default, and best left off on a device with a touchscreen — someone using a mouse has a keyboard. It is here so the feature can be tried on a machine that has no touch panel, where every other switch on this page is inert.")
                    }
                }

                // The last of the four ways this could silently do nothing. The helper is
                // built, the switch is on, permissions are fine — and there is simply no
                // device on this machine that can fire the trigger.
                NoticeBox {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    visible: Config.options.osk.autoShow.enable && OskAutoShow.binaryExists
                        && OskAutoShow.deviceReportReceived && !OskAutoShow.anyTriggerDevice
                    materialIcon: "touch_app"
                    text: OskAutoShow.touchDeviceCount === 0 && OskAutoShow.penDeviceCount === 0
                        ? Translation.tr("No touchscreen or pen was found on this machine, so nothing can raise the keyboard. Turn on the mouse trigger above to try it with a pointer.")
                        : Translation.tr("Every device that could raise the keyboard is switched off above.")
                }

                ConfigSwitch {
                    buttonIcon: "keyboard_hide"
                    text: Translation.tr("Hide when typing on a real keyboard")
                    enabled: Config.options.osk.autoShow.enable
                    checked: Config.options.osk.autoShow.hideOnPhysicalKey
                    onCheckedChanged: Config.options.osk.autoShow.hideOnPhysicalKey = checked

                    StyledToolTip {
                        text: Translation.tr("Automatically dismiss the virtual keyboard as soon as physical keystrokes are detected")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "gesture"
                    text: Translation.tr("Hide when tapping outside")
                    enabled: Config.options.osk.autoShow.enable
                    checked: Config.options.osk.autoShow.hideOnTouchOutside
                    onCheckedChanged: Config.options.osk.autoShow.hideOnTouchOutside = checked

                    StyledToolTip {
                        text: Translation.tr("Dismiss the virtual keyboard when touching outside the active keyboard and text area")
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Touch window (ms)")
                    enabled: Config.options.osk.autoShow.enable
                    value: Config.options.osk.autoShow.touchWindowMs
                    from: 200
                    to: 5000
                    stepSize: 100
                    onValueChanged: Config.options.osk.autoShow.touchWindowMs = value
                }
            }
        }
    }
}
