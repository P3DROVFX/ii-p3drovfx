import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects

StyledFlickable {
    id: root

    Layout.fillWidth: true
    Layout.fillHeight: true

    contentHeight: mainLayout.implicitHeight + 36
    clip: true

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Item {
            id: maskRoot
            width: root.width
            height: root.height

            property color topFadeColor: root.atYBeginning ? Appearance.colors.colOnSurface : "transparent"
            property color bottomFadeColor: root.atYEnd ? Appearance.colors.colOnSurface : "transparent"

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: Math.min(46, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: maskRoot.topFadeColor
                        }
                        GradientStop {
                            position: 1.0
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(0, parent.height - Math.min(46, parent.height / 2) - Math.min(56, parent.height / 2))
                    color: Appearance.colors.colOnSurface
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(56, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Appearance.colors.colOnSurface
                        }
                        GradientStop {
                            position: 1.0
                            color: maskRoot.bottomFadeColor
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        width: root.width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        spacing: 12

        StyledIndeterminateProgressBar {
            visible: ScreenShader.loading
            Layout.fillWidth: true
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: !ScreenShader.loading && ScreenShader.shaders.length === 0

            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "tonality"
                title: ScreenShader.hyprshadeAvailable ? Translation.tr("No shaders found") : Translation.tr("hyprshade isn't installed")
                description: ScreenShader.hyprshadeAvailable ? Translation.tr("Drop a .glsl file into ~/.config/hypr/shaders to add one.") : Translation.tr("Install it with your package manager to get the built-in filters.")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }

        // Error notice
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: errorText.implicitHeight + 20
            visible: ScreenShader.errorMessage.length > 0
            radius: Appearance.rounding.normal
            color: Appearance.colors.colErrorContainer

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                MaterialSymbol {
                    text: "error"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnErrorContainer
                }

                StyledText {
                    id: errorText
                    Layout.fillWidth: true
                    text: ScreenShader.errorMessage
                    color: Appearance.colors.colOnErrorContainer
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── Section: Active filter ──────────────────────────
        StyledText {
            visible: ScreenShader.active
            text: Translation.tr("Active filter")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            Layout.fillWidth: true
        }

        Item {
            visible: ScreenShader.active
            Layout.fillWidth: true
            implicitHeight: 56
            height: implicitHeight

            RowLayout {
                anchors.fill: parent
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12

                        MaterialSymbol {
                            text: ScreenShader.iconFor(ScreenShader.activeName)
                            iconSize: 22
                            color: Appearance.colors.colOnPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: ScreenShader.displayName(ScreenShader.activeName)
                                font.bold: true
                                horizontalAlignment: Text.AlignLeft
                                color: Appearance.colors.colOnPrimary
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: ScreenShader.activePath
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                horizontalAlignment: Text.AlignLeft
                                color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.2)
                                elide: Text.ElideLeft
                            }
                        }
                    }
                }

                RippleButton {
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 22
                        color: Appearance.colors.colOnPrimary
                    }
                    onClicked: ScreenShader.clear()

                    StyledToolTip {
                        text: Translation.tr("Turn off")
                    }
                }
            }
        }

        // ── Section: Filters ────────────────────────────────
        StyledText {
            visible: ScreenShader.shaders.length > 0
            text: Translation.tr("Filters")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            Layout.fillWidth: true
        }

        ColumnLayout {
            visible: ScreenShader.shaders.length > 0
            Layout.fillWidth: true
            spacing: 4

            ShaderRow {
                Layout.fillWidth: true
                shaderIcon: "block"
                title: Translation.tr("Off")
                subtitle: Translation.tr("No filter")
                selected: !ScreenShader.active
                onClicked: ScreenShader.clear()
            }

            Repeater {
                model: ScreenShader.shaders

                delegate: ShaderRow {
                    required property var modelData
                    Layout.fillWidth: true
                    shaderIcon: ScreenShader.iconFor(modelData.name)
                    title: ScreenShader.displayName(modelData.name)
                    subtitle: modelData.dir
                    selected: ScreenShader.activeName === modelData.name
                    onClicked: ScreenShader.apply(modelData.name)
                }
            }
        }

        // hyprshade note
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "info"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Filters come from hyprshade — install it for the built-in set. Your own .glsl files in ~/.config/hypr/shaders show up here too.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }

    component ShaderRow: RippleButton {
        id: shaderRow

        property string shaderIcon: "tonality"
        property string title: ""
        property string subtitle: ""
        property bool selected: false

        implicitHeight: 56
        padding: 0
        leftPadding: 20
        rightPadding: 20
        buttonRadius: Appearance.rounding.full
        colBackground: shaderRow.selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest
        colBackgroundHover: shaderRow.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
        colRipple: shaderRow.selected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive

        readonly property color colForeground: shaderRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

        contentItem: RowLayout {
            spacing: 12

            MaterialSymbol {
                text: shaderRow.shaderIcon
                iconSize: 22
                color: shaderRow.colForeground
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: shaderRow.title
                    font.bold: shaderRow.selected
                    horizontalAlignment: Text.AlignLeft
                    color: shaderRow.colForeground
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: shaderRow.subtitle.length > 0
                    text: shaderRow.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    horizontalAlignment: Text.AlignLeft
                    color: ColorUtils.transparentize(shaderRow.colForeground, 0.35)
                    elide: Text.ElideLeft
                }
            }

            MaterialSymbol {
                visible: shaderRow.selected
                text: "check"
                iconSize: 20
                color: shaderRow.colForeground
            }
        }
    }
}
