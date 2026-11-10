import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Main pane: the interface language. Header states the language in use (the
 * hovered option while the pointer is over one); the options are a balanced
 * grid of every installed locale plus "Auto".
 */
Rectangle {
    id: root

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    implicitHeight: content.implicitHeight + 40

    readonly property int gap: 6
    readonly property int minCell: 132

    function nativeName(code) {
        if (code === "auto")
            return Translation.tr("Auto");
        const name = Qt.locale(code).nativeLanguageName;
        return name.length > 0 ? name.charAt(0).toUpperCase() + name.slice(1) : code;
    }

    readonly property var options: ["auto", ...Translation.allAvailableLanguages.filter(code => code.length > 0)]
    readonly property string current: Config.options.language.ui
    property int hoveredIndex: -1

    function describe(code) {
        if (code === "auto")
            return Translation.tr("Follows the system locale · %1").arg(root.nativeName(Qt.locale().name));
        return "%1 · %2".arg(root.nativeName(code)).arg(code);
    }

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                text: "translate"
                iconSize: 24
                padding: 12
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: Translation.tr("Interface language")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.describe(root.hoveredIndex >= 0 ? root.options[root.hoveredIndex] : root.current)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        Grid {
            id: grid
            Layout.fillWidth: true
            spacing: root.gap
            // Balanced over the rows the set needs, so no row ends with a straggler.
            readonly property int maxCols: Math.max(1, Math.floor((width + spacing) / (root.minCell + spacing)))
            readonly property int rowCount: Math.ceil(root.options.length / maxCols)
            columns: Math.max(1, Math.ceil(root.options.length / Math.max(1, rowCount)))
            readonly property real cellWidth: (width - (columns - 1) * spacing) / columns

            Repeater {
                model: root.options
                delegate: RippleButton {
                    id: option
                    required property string modelData
                    required property int index
                    readonly property bool chosen: root.current === modelData
                    property real corner: option.chosen ? height / 2 : Appearance.rounding.normal
                    Behavior on corner { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }

                    width: grid.cellWidth
                    implicitHeight: 64
                    buttonRadius: Appearance.rounding.scale === 0 ? 0 : option.corner
                    colBackground: option.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: option.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: option.chosen ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: Config.options.language.ui = modelData
                    onHoveredChanged: root.hoveredIndex = hovered ? index : (root.hoveredIndex === index ? -1 : root.hoveredIndex)

                    contentItem: Item {
                    RowLayout {
                        spacing: 10
                        anchors {
                            fill: parent
                            leftMargin: 16
                            rightMargin: 14
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: root.nativeName(option.modelData)
                                horizontalAlignment: Text.AlignLeft
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: option.chosen ? Font.DemiBold : Font.Normal
                                color: option.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: option.modelData === "auto" ? Translation.tr("System") : option.modelData
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: option.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                opacity: 0.8
                                elide: Text.ElideRight
                            }
                        }
                        MaterialSymbol {
                            visible: option.chosen
                            text: "check"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                    }
                    }
                }
            }
        }
    }
}
