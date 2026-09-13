import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.services

AbstractBackgroundWidget {
    id: root

    property bool wallpaperSafetyTriggered: false
    // State from Appearance m3colors
    readonly property bool isActive: Appearance.m3colors.darkmode
    readonly property color pillBgColor: isActive ? WidgetColorScheme.accentColor : WidgetColorScheme.cardBgColor
    readonly property color contentColor: isActive ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg

    configEntryName: "dark_mode_pill"
    implicitWidth: 240
    implicitHeight: 120

    // Shadow Effect
    StyledDropShadow {
        id: shadowEffect

        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer

        anchors.fill: parent
        radius: height / 2
        color: WidgetColorScheme.tintBackground(root.pillBgColor)

        // Icon Button (Large circular click area on the left)
        RippleButton {
            id: iconButton

            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 64
            implicitHeight: 64
            topLeftRadius: 37
            topRightRadius: 37
            bottomLeftRadius: 37
            bottomRightRadius: 37
            colBackground: "transparent"
            colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.15)
            colRipple: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.3)
            onClicked: {
                if (Appearance.m3colors.darkmode)
                    Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
                else
                    Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.isActive ? "dark_mode" : "light_mode"
                iconSize: 38
                color: root.contentColor

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }

                }

            }

        }

        // Label Text (Positioned close to the Icon Button)
        StyledText {
            anchors.left: iconButton.right
            anchors.leftMargin: 0
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.isActive ? Translation.tr("Dark Mode") : Translation.tr("Light Mode")
            font.pixelSize: 24
            font.weight: Font.Bold
            color: root.contentColor
            elide: Text.ElideRight

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }

            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }

        }

    }

}
