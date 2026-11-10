import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One data source on the APIs page: provider overline, name as a headline,
 * a live summary, big stat figures and a row of crests. On = primary container
 * with the icon morphing to the card's own shape; the card opens its page.
 * An optional switch sits top-right (clicks go to it, not to the card).
 */
RippleButton {
    id: root

    property string symbol: "api"
    property int shapeOn: MaterialShape.Shape.Cookie12Sided
    property string provider: ""
    property string title: ""
    property string summary: ""
    property var stats: []          // [{ value, label }]
    property var logos: []          // crest URLs
    property bool isOn: true
    property bool hasSwitch: false
    property string actionLabel: Translation.tr("Open")

    signal switchToggled(bool value)
    signal opened()

    readonly property color colContent: root.isOn ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
    readonly property var digitAxes: ({ "wght": 1000, "wdth": 50, "ROND": 100 })

    implicitHeight: column.implicitHeight + 40
    padding: 0
    buttonRadius: Appearance.rounding.verylarge
    buttonRadiusPressed: Appearance.rounding.large
    colBackground: root.isOn ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: root.isOn ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: ColorUtils.applyAlpha(root.colContent, 0.16)
    onClicked: root.opened()

    contentItem: Item {
        ColumnLayout {
            id: column
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                MaterialShapeWrappedMaterialSymbol {
                    text: root.symbol
                    iconSize: 26
                    padding: 13
                    shape: root.isOn ? (root.hovered ? MaterialShape.Shape.VerySunny : root.shapeOn) : MaterialShape.Shape.Circle
                    color: root.isOn ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: root.provider.toUpperCase()
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.variableAxes: ({ "wght": 800, "wdth": 120, "ROND": 0 })
                        font.letterSpacing: 1.8
                        color: root.colContent
                        opacity: 0.75
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.title.toUpperCase()
                        elide: Text.ElideRight
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 16
                        font.pixelSize: 26
                        font.variableAxes: ({ "wght": 850, "wdth": 75, "slnt": -10, "ROND": 0 })
                        color: root.colContent
                    }
                }
                StyledSwitch {
                    visible: root.hasSwitch
                    checked: root.isOn
                    activeColor: Appearance.colors.colPrimary
                    onClicked: root.switchToggled(checked)
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.summary
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.colContent
                opacity: 0.85
            }

            // Figures
            RowLayout {
                Layout.fillWidth: true
                visible: root.stats.length > 0
                spacing: 24
                Repeater {
                    model: root.stats
                    delegate: ColumnLayout {
                        required property var modelData
                        spacing: -4
                        StyledText {
                            shouldUseNumberFont: false
                            text: modelData.value
                            font.pixelSize: 44
                            font.variableAxes: root.digitAxes
                            color: root.colContent
                        }
                        StyledText {
                            text: String(modelData.label).toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.variableAxes: ({ "wght": 800, "wdth": 120, "ROND": 0 })
                            font.letterSpacing: 1.2
                            color: root.colContent
                            opacity: 0.75
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Row {
                    spacing: -8
                    Repeater {
                        model: root.logos.slice(0, 7)
                        delegate: Rectangle {
                            required property string modelData
                            width: 34
                            height: 34
                            radius: 17
                            color: Appearance.m3colors.m3surfaceContainerHighest
                            CrestImage {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                url: modelData
                                fillMode: Image.PreserveAspectFit
                                mipmap: true
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitHeight: 36
                    implicitWidth: actionRow.implicitWidth + 28
                    radius: 18
                    color: ColorUtils.applyAlpha(root.colContent, root.hovered ? 0.18 : 0.1)
                    RowLayout {
                        id: actionRow
                        anchors.centerIn: parent
                        spacing: 6
                        StyledText {
                            text: root.actionLabel
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: root.colContent
                        }
                        MaterialSymbol {
                            text: "arrow_forward"
                            iconSize: 18
                            color: root.colContent
                        }
                    }
                }
            }
        }
    }
}
