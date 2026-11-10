import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Header of a competition or club page, in the match hero's voice: the crest
 * on a Material shape, an overline in wide capitals, the name as a big slanted
 * headline and a clipped ornament. Actions go in the default slot.
 */
Item {
    id: root

    property string logo: ""
    property string overline: ""
    property string title: ""
    property string subtitle: ""
    property int crestShape: MaterialShape.Shape.Cookie12Sided
    property int ornamentShape: MaterialShape.Shape.SoftBurst
    default property alias actions: actionRow.data

    implicitHeight: row.implicitHeight + FootballStyle.gapHuge * 2

    Rectangle {
        id: mask
        width: surface.width
        height: surface.height
        radius: FootballStyle.radiusCard
        visible: false
        layer.enabled: true
    }

    Item {
        id: surface
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        Rectangle {
            anchors.fill: parent
            color: FootballStyle.colPrimaryContainer
        }
        MaterialShape {
            implicitSize: root.height * 2.1
            x: root.width - implicitSize * 0.38
            y: (root.height - implicitSize) / 2
            shape: root.ornamentShape
            color: FootballStyle.colOnPrimaryContainer
            opacity: 0.08
        }
    }

    RowLayout {
        id: row
        x: FootballStyle.gapHuge
        y: FootballStyle.gapHuge
        width: root.width - FootballStyle.gapHuge * 2
        spacing: FootballStyle.gapHuge

        Item {
            implicitWidth: 112
            implicitHeight: 112
            MaterialShape {
                anchors.fill: parent
                implicitSize: 112
                shape: root.crestShape
                color: FootballStyle.colField
            }
            StyledImage {
                anchors.centerIn: parent
                width: 64
                height: 64
                source: root.logo
                fillMode: Image.PreserveAspectFit
                mipmap: true
                cache: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                visible: root.overline !== ""
                text: root.overline.toUpperCase()
                font.pixelSize: FootballStyle.textSmaller
                font.variableAxes: FootballStyle.axesCaps
                font.letterSpacing: 2
                color: FootballStyle.colOnPrimaryContainer
                opacity: 0.8
            }
            StyledText {
                Layout.fillWidth: true
                text: root.title.toUpperCase()
                elide: Text.ElideRight
                font.pixelSize: 40
                font.variableAxes: FootballStyle.axesHeadline
                color: FootballStyle.colOnPrimaryContainer
            }
            StyledText {
                shouldUseNumberFont: false
                Layout.fillWidth: true
                visible: root.subtitle !== ""
                text: root.subtitle
                elide: Text.ElideRight
                font.pixelSize: FootballStyle.textNormal
                font.variableAxes: FootballStyle.axesCondensed
                color: FootballStyle.colOnPrimaryContainer
            }
        }

        RowLayout {
            id: actionRow
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            spacing: FootballStyle.gapSmall
        }
    }
}
