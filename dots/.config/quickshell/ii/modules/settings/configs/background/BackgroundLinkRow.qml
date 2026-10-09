pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A slim row that opens a sub-page: a shape badge, what it is, an optional status pill and
 * a chevron that slides when the pointer arrives. Quieter than a card, for the things that
 * are worth a page but not a place on this one.
 */
RippleButton {
    id: root

    readonly property real inset: 16
    readonly property real iconSize: 20
    readonly property real iconPadding: 10
    readonly property real contentSpacing: 14
    readonly property real chevronShift: 4
    readonly property real pillHeight: 26
    readonly property real pillPadding: 10

    property string symbol: ""
    property var shapeIdle: MaterialShape.Shape.Circle
    property var shapeEngaged: MaterialShape.Shape.Cookie9Sided
    property string title: ""
    property string summary: ""
    property string status: ""
    property bool statusPositive: false

    implicitHeight: row.implicitHeight + root.inset * 2
    interactionScale: root.animationsEnabled && root.down ? 0.97 : 1.0
    buttonRadius: Appearance.rounding.large
    buttonRadiusPressed: Appearance.rounding.normal
    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colRipple: Appearance.colors.colLayer1Active

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
            spacing: root.contentSpacing

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: root.iconSize
                padding: root.iconPadding
                fill: root.hovered ? 1 : 0
                shape: root.hovered ? root.shapeEngaged : root.shapeIdle
                color: Appearance.colors.colSecondaryContainer
                colSymbol: Appearance.colors.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.summary
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                visible: root.status.length > 0
                implicitHeight: root.pillHeight
                implicitWidth: statusText.implicitWidth + root.pillPadding * 2
                radius: height / 2
                color: root.statusPositive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer

                StyledText {
                    id: statusText
                    anchors.centerIn: parent
                    text: root.status
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: root.statusPositive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                }
            }

            MaterialSymbol {
                text: "chevron_right"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
                Layout.leftMargin: root.hovered ? root.chevronShift : 0
                Behavior on Layout.leftMargin {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
