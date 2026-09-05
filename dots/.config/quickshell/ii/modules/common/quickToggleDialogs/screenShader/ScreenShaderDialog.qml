import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 560

    readonly property string userShaderDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr/shaders`)

    Component.onCompleted: ScreenShader.refresh()

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Screen filter")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: ScreenShader.active
            enabled: ScreenShader.shaders.length > 0
            onToggled: ScreenShader.toggle()
        }
    }

    ScreenShaderDialogContent {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    // Footer actions
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 12

        RippleButton {
            id: folderBtn
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            colRipple: Appearance.colors.colSurfaceContainerHighestActive
            implicitHeight: 36
            implicitWidth: folderText.implicitWidth + 32

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: folderBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                radius: parent.buttonEffectiveRadius

                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            contentItem: StyledText {
                id: folderText
                text: Translation.tr("Shader folder")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 500
                    })
                color: folderBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }
            onClicked: {
                const dir = StringUtils.shellSingleQuoteEscape(root.userShaderDir);
                Quickshell.execDetached(["bash", "-c", `mkdir -p '${dir}' && xdg-open '${dir}'`]);
            }

            StyledToolTip {
                text: Translation.tr("Drop .glsl files here to add your own")
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RippleButton {
            id: doneBtn
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            implicitHeight: 36
            implicitWidth: doneText.implicitWidth + 48

            contentItem: StyledText {
                id: doneText
                text: Translation.tr("Done")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 700
                    })
                color: Appearance.colors.colOnPrimary
            }
            onClicked: root.dismiss()
        }
    }
}
