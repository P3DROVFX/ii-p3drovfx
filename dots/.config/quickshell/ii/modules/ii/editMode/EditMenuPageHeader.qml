import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The header of a menu page (the desktop menu's, the icon menu's): Edit Mode's drawer header - the way
 * back in a circle, the page title beside it - and, when the page names one
 * (`actionSymbol`), an outlined circle on the right for the way further out
 * (the page's full version in Settings).
 */
RowLayout {
    id: root

    property string title: ""
    property string actionSymbol: ""
    property string actionTooltip: ""
    // The compact context menus: smaller circles and title. A page shown
    // beside its menu (cascade) has nothing to go back to and drops the
    // back circle.
    property bool dense: false
    property bool showBack: true
    readonly property real circleSize: root.dense ? 28 : 38
    signal backRequested()
    signal actionRequested()

    Layout.fillWidth: true
    Layout.leftMargin: root.showBack ? 2 : (root.dense ? 8 : 10)
    Layout.rightMargin: 4
    Layout.topMargin: !root.showBack && root.dense ? 4 : 0
    spacing: root.dense ? 8 : 10

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: root.showBack
        implicitWidth: root.circleSize
        implicitHeight: root.circleSize
        radius: width / 2
        color: backMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
            : Appearance.colors.colSurfaceContainerHigh

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Hover as a state layer (EditPanelRow's hoverLayer says why).
        Rectangle {
            id: backHoverLayer
            anchors.fill: parent
            radius: width / 2
            color: Appearance.colors.colOnSurface
            opacity: backMouse.containsMouse && !backMouse.containsPress ? 0.08 : 0

            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(backHoverLayer)
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_back"
            iconSize: root.dense ? 18 : 22
            color: Appearance.colors.colOnSurface
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.backRequested()
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: root.title
        font.pixelSize: root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.large
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnSurface
        elide: Text.ElideRight
    }

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: root.actionSymbol !== ""
        implicitWidth: root.circleSize
        implicitHeight: root.circleSize
        radius: width / 2
        color: actionMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
            : actionMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighest
            : "transparent"
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.actionSymbol
            iconSize: root.dense ? 17 : 20
            color: Appearance.colors.colOnSurface
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.actionRequested()
        }

        StyledToolTip {
            extraVisibleCondition: actionMouse.containsMouse && root.actionTooltip !== ""
            text: root.actionTooltip
        }
    }
}
