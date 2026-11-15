pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/*
 * One album in the gallery's strip: its newest photo cut to a shape that says the
 * state (rounded square idle, Cookie9 on hover, Cookie12 when it is the filter), and
 * the name under it, in a secondary pill when selected.
 */
RippleButton {
    id: root

    property string name: ""
    property int count: 0
    property var coverId: null
    property string glyph: "photo_library"
    property bool selected: false

    readonly property string coverSource: (root.coverId !== null && PhoneGalleryService.thumbRevision >= 0
            && PhoneGalleryService.hasThumb(root.coverId))
        ? PhoneGalleryService.thumbPath(root.coverId)
        : ""

    implicitWidth: 76
    implicitHeight: column.implicitHeight + 8
    buttonRadius: Appearance.rounding.normal
    colBackground: "transparent"
    colBackgroundHover: "transparent"
    colRipple: Appearance.colors.colLayer3Active ?? Appearance.colors.colLayer3Hover

    contentItem: Column {
        id: column
        anchors.top: parent.top
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 5

        PhoneGalleryShapedThumb {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 60
            height: 60
            source: root.coverSource
            placeholderIcon: root.glyph
            placeholderColor: root.selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
            placeholderIconColor: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            shape: root.selected
                ? MaterialShape.Shape.Cookie12Sided
                : (root.hovered ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Square)
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(root.width, nameText.implicitWidth + 14)
            height: nameText.implicitHeight + 4
            radius: height / 2
            color: root.selected ? Appearance.colors.colSecondaryContainer : "transparent"

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            StyledText {
                id: nameText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, root.width - 14)
                horizontalAlignment: Text.AlignHCenter
                text: root.name
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: root.selected ? Font.Bold : Font.DemiBold
                font.variableAxes: ({ "wght": root.selected ? 700 : 560, "wdth": 88, "ROND": 100 })
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.count > 0 ? String(root.count) : ""
            visible: text.length > 0
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.variableAxes: ({ "wght": 640, "wdth": 50, "ROND": 100 })
            color: Appearance.colors.colSubtext
        }
    }

    StyledToolTip {
        extraVisibleCondition: nameText.truncated
        text: root.name
    }
}
