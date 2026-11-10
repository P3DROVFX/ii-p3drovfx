pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A wide card that opens a sub-page: the secondary container with the page's own shape
 * (it morphs under the pointer) and an arrow chip at the far end.
 */
RippleButton {
    id: root

    readonly property real inset: 20
    readonly property real iconSize: 26
    readonly property real iconPadding: 13
    readonly property real arrowSize: 44
    readonly property real arrowIconSize: 22

    property string symbol: ""
    property var shapeIdle: MaterialShape.Shape.Cookie9Sided
    property var shapeEngaged: MaterialShape.Shape.Cookie12Sided
    property string title: ""
    property string summary: ""

    implicitHeight: row.implicitHeight + root.inset * 2
    // Full width inside a clipped page: a hover grow would be cut at both edges, so only the press shrinks.
    interactionScale: root.animationsEnabled && root.down ? 0.96 : 1.0
    buttonRadius: Appearance.rounding.verylarge
    buttonRadiusPressed: Appearance.rounding.large
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundActive: Appearance.colors.colSecondaryContainerActive
    colRipple: Appearance.colors.colSecondaryContainerActive

    contentItem: Item {
        implicitHeight: row.implicitHeight

        RowLayout {
            id: row
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: root.inset
                rightMargin: root.inset
            }
            spacing: 16

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: root.iconSize
                padding: root.iconPadding
                fill: 1
                shape: root.hovered ? root.shapeEngaged : root.shapeIdle
                color: Appearance.colors.colSecondary
                colSymbol: Appearance.colors.colOnSecondary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.summary
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.8
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                implicitWidth: root.arrowSize
                implicitHeight: root.arrowSize
                radius: width / 2
                color: Appearance.colors.colSecondary

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_forward"
                    iconSize: root.arrowIconSize
                    color: Appearance.colors.colOnSecondary
                }
            }
        }
    }
}
