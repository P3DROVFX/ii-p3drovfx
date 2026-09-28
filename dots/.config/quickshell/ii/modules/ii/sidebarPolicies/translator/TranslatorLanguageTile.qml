import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One end of the translator's language bar: a small caption over the language name,
 * the whole tile opening the language list.
 *
 * A compact pill that squares off a little while pressed (shape is state). The chevron
 * rides beside the caption so the name gets the tile's full width, and a long name
 * ("Português Brasileiro") steps its size down to stay on one line.
 */
RippleButton {
    id: root

    property string caption: ""
    property string language: ""

    leftPadding: 0
    rightPadding: 0
    implicitHeight: ClockStyle.rowHeight
    implicitWidth: content.implicitWidth + ClockStyle.gapLarge * 2
    buttonRadius: ClockStyle.pill(ClockStyle.rowHeight)
    buttonRadiusPressed: ClockStyle.radiusNormal
    colBackground: ClockStyle.colSecondaryContainer
    colBackgroundHover: ClockStyle.colSecondaryContainerHover
    colRipple: ClockStyle.colSecondaryContainerActive

    contentItem: Item {
        ColumnLayout {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: ClockStyle.gapLarge + 4
                rightMargin: ClockStyle.gapLarge
            }
            spacing: 0

            // Caption with the chevron beside it, so the name gets the tile's full width.
            RowLayout {
                id: captionRow
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 2

                StyledText {
                    text: root.caption
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSecondaryContainer
                    opacity: 0.72
                }

                MaterialSymbol {
                    text: "expand_more"
                    iconSize: Appearance.font.pixelSize.small
                    color: ClockStyle.colOnSecondaryContainer
                    opacity: 0.72
                    rotation: root.down ? 180 : 0
                    Behavior on rotation {
                        enabled: !ClockStyle.reducedMotion
                        animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            StyledText {
                id: nameText
                Layout.fillWidth: true
                text: root.language
                // Long names step down in size before they elide, keeping one line.
                font.family: ClockStyle.fontMain
                font.variableAxes: ({ "wght": 620, "wdth": 82, "ROND": 100 })
                font.pixelSize: ClockStyle.textLarge
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Appearance.font.pixelSize.smallie
                color: ClockStyle.colOnSecondaryContainer
                elide: Text.ElideRight
            }
        }
    }

    StyledToolTip {
        text: root.language
        extraVisibleCondition: nameText.truncated
    }
}
