import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One place the island can live, as a card: on, it takes the primary container and
 * its glyph morphs into the card's own shape; off, it is the pane colour. A place
 * the current bar cannot host says why instead of offering a switch that refuses,
 * with the way to the setting that unlocks it.
 */
Rectangle {
    id: root

    property string symbol: ""
    property var shapeOn: MaterialShape.Shape.Cookie9Sided
    property string title: ""
    property string summary: ""
    property bool checked: false
    /** The bar allows this place; otherwise `blockedText` says what it needs. */
    property bool available: true
    property string blockedText: ""
    property string fixLabel: ""

    signal toggledByUser(bool value)
    signal fixRequested()

    readonly property bool engaged: cardHover.hovered && root.available
    readonly property color colContent: root.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

    implicitHeight: 176
    radius: Appearance.rounding.verylarge
    color: root.checked
        ? (root.engaged ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }
    // Under the content, so the switch and the button keep their own clicks.
    MouseArea {
        anchors.fill: parent
        enabled: root.available
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggledByUser(!root.checked)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        anchors.topMargin: 18
        anchors.rightMargin: 18
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: 22
                padding: 11
                fill: root.checked ? 1 : 0
                shape: root.checked ? root.shapeOn : (root.engaged ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle)
                color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                opacity: root.available ? 1 : 0.6
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledSwitch {
                id: toggle
                visible: root.available
                sizeScale: 0.85
                checked: root.checked
                activeColor: Appearance.colors.colPrimary
                activeThumbColor: Appearance.colors.colOnPrimary
                inactiveColor: Appearance.colors.colSurfaceContainerHighest
                onToggled: {
                    root.toggledByUser(toggle.checked);
                    toggle.checked = Qt.binding(() => root.checked);
                }
            }

            MaterialSymbol {
                visible: !root.available
                text: "lock"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 14
            text: root.title
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.larger
            color: root.colContent
            opacity: root.available ? 1 : 0.7
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 2
            text: root.available ? root.summary : root.blockedText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colContent
            opacity: 0.8
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 8
        }

        RippleButton {
            visible: !root.available && root.fixLabel !== ""
            implicitHeight: 34
            implicitWidth: fixRow.implicitWidth + 26
            buttonRadius: height / 2
            buttonRadiusPressed: Appearance.rounding.small
            colBackground: ColorUtils.applyAlpha(root.colContent, 0.1)
            colBackgroundHover: ColorUtils.applyAlpha(root.colContent, 0.18)
            colRipple: ColorUtils.applyAlpha(root.colContent, 0.26)
            onClicked: root.fixRequested()

            contentItem: Item {
                RowLayout {
                    id: fixRow
                    anchors.centerIn: parent
                    spacing: 6
                    StyledText {
                        text: root.fixLabel
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: root.colContent
                    }
                    MaterialSymbol {
                        text: "arrow_forward"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.colContent
                    }
                }
            }
        }
    }
}
