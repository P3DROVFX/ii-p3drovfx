pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Dynamic Island widget for Phone Mirroring via scrcpy.
 *
 * Contracted: Glance shown when mirror starts or inside notch resting face.
 * Expanded: Material 3 Expressive card opened on auxiliary bubble hover with common phone controls.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false
    /** The header avatar, handed over from the bubble's glance (see AuxiliaryBubble's hero). */
    readonly property var heroItems: root.isExpanded ? [headerAvatar] : []

    readonly property string deviceName: KdeConnectService.activeDeviceDisplayName || Translation.tr("Phone")
    readonly property bool isFlexDisplay: Boolean(Config.options?.phone?.scrcpy?.appMode?.flexDisplay)
    readonly property string deviceImageSource: BluetoothDeviceImages.sourceForPhone(KdeConnectService.activeDeviceDisplayName)

    readonly property real preferredExpandedHeight: 14 + 36 + 12 + 40 + 8 + 40 + 14 // 164

    // ── Contracted: Notice in the notch ─────────────────────────────────────
    RowLayout {
        visible: !root.isExpanded
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 16
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(22, Math.min(30, root.height - 10))
            implicitHeight: implicitWidth
            radius: width / 2
            color: Appearance.colors.colPrimaryContainer
            clip: true

            Image {
                id: contractedImg
                anchors.fill: parent
                anchors.margins: 2
                source: root.deviceImageSource
                fillMode: Image.PreserveAspectFit
                visible: root.deviceImageSource !== "" && status === Image.Ready
                smooth: true
                mipmap: true
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !contractedImg.visible || root.deviceImageSource === ""
                text: "smartphone"
                fill: 1
                iconSize: Math.round(parent.width * 0.58)
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.deviceName + " · " + (root.isFlexDisplay ? Translation.tr("Flex Display") : Translation.tr("Mirroring"))
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Expanded: Material 3 Expressive Card ────────────────────────────────
    ColumnLayout {
        visible: root.isExpanded
        anchors.fill: parent
        anchors.margins: 14
        spacing: 0

        // Header: Avatar, Name & Status, Stop Pill
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 10

            // Device Avatar (Image or Icon)
            Rectangle {
                id: headerAvatar
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 36
                implicitHeight: 36
                radius: 18
                color: Appearance.colors.colPrimaryContainer
                clip: true

                Image {
                    id: headerDeviceImg
                    anchors.fill: parent
                    anchors.margins: 2
                    source: root.deviceImageSource
                    fillMode: Image.PreserveAspectFit
                    visible: root.deviceImageSource !== "" && status === Image.Ready
                    smooth: true
                    mipmap: true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !headerDeviceImg.visible || root.deviceImageSource === ""
                    text: "smartphone"
                    fill: 1
                    iconSize: 20
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            // Name & Status
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.deviceName
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.isFlexDisplay ? Translation.tr("Flex Display (PC)") : Translation.tr("Screen Mirror active")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            // Stop screen sharing button
            RippleButton {
                id: stopBtn
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 32
                implicitWidth: stopContent.implicitWidth + 20
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colError
                colBackgroundActive: Appearance.colors.colErrorActive
                colRipple: Appearance.colors.colErrorActive
                scale: pressed ? 0.92 : (hovered ? 1.05 : 1.0)

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(stopBtn)
                }

                contentItem: RowLayout {
                    id: stopContent
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialSymbol {
                        text: "stop_screen_share"
                        iconSize: 16
                        color: stopBtn.hovered ? Appearance.colors.colOnError : Appearance.colors.colOnErrorContainer

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }
                    }

                    StyledText {
                        text: Translation.tr("Stop")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: stopBtn.hovered ? Appearance.colors.colOnError : Appearance.colors.colOnErrorContainer

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }
                    }
                }

                onClicked: {
                    PhoneScrcpyService.stopMirror();
                }

                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Stop screensharing")
                }
            }
        }

        Item {
            Layout.preferredHeight: 10
        }

        // Row 1: Expressive Navigation Pill (Back, Home, Recents) + Flex Display Toggle
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: 8

            // Expressive container for navigation
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colSurfaceContainerHighest

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 4

                    // Back
                    RippleButton {
                        id: navBackBtn
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colSecondaryContainer
                        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                        scale: pressed ? 0.88 : (hovered ? 1.08 : 1.0)

                        Behavior on scale {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(navBackBtn)
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_back_ios_new"
                            iconSize: 18
                            color: navBackBtn.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                            Behavior on color {
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                }
                            }
                        }

                        onClicked: PhoneMirrorService.goBack()

                        StyledToolTip {
                            requireOverlay: false
                            text: Translation.tr("Back")
                        }
                    }

                    // Home
                    RippleButton {
                        id: navHomeBtn
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colSecondaryContainer
                        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                        scale: pressed ? 0.88 : (hovered ? 1.08 : 1.0)

                        Behavior on scale {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(navHomeBtn)
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "circle"
                            iconSize: 16
                            color: navHomeBtn.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                            Behavior on color {
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                }
                            }
                        }

                        onClicked: PhoneMirrorService.goHome()

                        StyledToolTip {
                            requireOverlay: false
                            text: Translation.tr("Home")
                        }
                    }

                    // Recents
                    RippleButton {
                        id: navRecentsBtn
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colSecondaryContainer
                        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                        scale: pressed ? 0.88 : (hovered ? 1.08 : 1.0)

                        Behavior on scale {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(navRecentsBtn)
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "square"
                            iconSize: 16
                            color: navRecentsBtn.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                            Behavior on color {
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                }
                            }
                        }

                        onClicked: PhoneMirrorService.goRecents()

                        StyledToolTip {
                            requireOverlay: false
                            text: Translation.tr("Recents")
                        }
                    }
                }
            }

            // Mode Toggle (Flex / Normal)
            RippleButton {
                id: flexToggleBtn
                Layout.preferredWidth: 44
                Layout.preferredHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: root.isFlexDisplay ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: root.isFlexDisplay ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                colBackgroundActive: root.isFlexDisplay ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive
                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(flexToggleBtn)
                }
                Behavior on colBackground {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(flexToggleBtn)
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isFlexDisplay ? "desktop_windows" : "smartphone"
                    fill: 1
                    iconSize: 18
                    color: (root.isFlexDisplay || flexToggleBtn.hovered) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }

                onClicked: {
                    const current = Boolean(Config.options?.phone?.scrcpy?.appMode?.flexDisplay);
                    Config.options.phone.scrcpy.appMode.flexDisplay = !current;
                    if (PhoneScrcpyService.mirrorRunning) {
                        PhoneScrcpyService.restartMirror();
                    } else {
                        PhoneScrcpyService.launchMirror();
                    }
                }

                StyledToolTip {
                    requireOverlay: false
                    text: root.isFlexDisplay ? Translation.tr("Flex Display (PC)") : Translation.tr("Normal mode (Phone)")
                }
            }
        }

        Item {
            Layout.preferredHeight: 8
        }

        // Row 2: Secondary Controls (Volume -, Volume +, Notifications, Power)
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: 8

            // Volume Down
            RippleButton {
                id: volDownBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colSecondaryContainer
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(volDownBtn)
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "volume_down"
                    iconSize: 18
                    color: volDownBtn.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }

                onClicked: PhoneMirrorService.volumeDown()

                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Volume down")
                }
            }

            // Volume Up
            RippleButton {
                id: volUpBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colSecondaryContainer
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(volUpBtn)
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "volume_up"
                    iconSize: 18
                    color: volUpBtn.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }

                onClicked: PhoneMirrorService.volumeUp()

                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Volume up")
                }
            }

            // Open Notifications
            RippleButton {
                id: notifBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colSecondaryContainer
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(notifBtn)
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "expand_more"
                    iconSize: 20
                    color: notifBtn.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }

                onClicked: PhoneMirrorService.openNotifications()

                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Notifications")
                }
            }

            // Power
            RippleButton {
                id: powerBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colErrorContainer
                colBackgroundActive: Appearance.colors.colErrorContainerActive
                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(powerBtn)
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "power_settings_new"
                    iconSize: 18
                    color: powerBtn.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurface

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }

                onClicked: PhoneMirrorService.togglePower()

                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Power")
                }
            }
        }
    }
}
