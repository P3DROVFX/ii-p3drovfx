pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings v2 sidebar navigation button.
 *
 * Implements "smart radius" logic:
 *   - Active item       → full radius on all 4 corners
 *   - Item above active → full radius on bottom corners, verysmall on top
 *   - Item below active → full radius on top corners, verysmall on bottom
 *   - First in group    → full radius on top-outer corners
 *   - Last in group     → full radius on bottom-outer corners
 *   - Everything else   → verysmall radius on all corners
 */
Item {
    id: root

    scale: isPressed ? 0.95 : (mouseArea.containsMouse ? 1.03 : 1.0)
    z: mouseArea.containsMouse || isPressed ? 1 : 0

    Behavior on scale {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutQuad
        }
    }

    // ── Position context (set by parent Repeater) ──────────────────────────
    property bool isFirst: false
    property bool isLast: false
    property bool isActive: false
    property bool prevIsActive: false   // item immediately above is active
    property bool nextIsActive: false   // item immediately below is active

    property bool isPressed: mouseArea.pressed
    property bool prevIsPressed: false
    property bool nextIsPressed: false

    // ── Page data ──────────────────────────────────────────────────────────
    property string iconName: ""
    property string pageLabel: ""

    // ── Geometry ───────────────────────────────────────────────────────────
    property real itemHeight: 52

    Layout.fillWidth: true
    implicitWidth: 100
    implicitHeight: itemHeight

    // ── Radius helpers ─────────────────────────────────────────────────────
    readonly property real _rFull:      itemHeight / 2
    readonly property real _rTiny:      Appearance.rounding.verysmall

    // Top corners
    readonly property real _topLeftRadius: {
        if (isActive || isPressed)        return _rFull;
        if (prevIsActive || prevIsPressed)    return _rFull;  // Top of item below active (i.e. prev is active)
        if (isFirst)         return _rFull;
        return _rTiny;
    }
    readonly property real _topRightRadius: {
        if (isActive || isPressed)        return _rFull;
        if (prevIsActive || prevIsPressed)    return _rFull;
        if (isFirst)         return _rFull;
        return _rTiny;
    }

    // Bottom corners
    readonly property real _bottomLeftRadius: {
        if (isActive || isPressed)        return _rFull;
        if (nextIsActive || nextIsPressed)    return _rFull;  // Bottom of item above active (i.e. next is active)
        if (isLast)          return _rFull;
        return _rTiny;
    }
    readonly property real _bottomRightRadius: {
        if (isActive || isPressed)        return _rFull;
        if (nextIsActive || nextIsPressed)    return _rFull;
        if (isLast)          return _rFull;
        return _rTiny;
    }

    // ── Signal ─────────────────────────────────────────────────────────────
    signal clicked()

    // ── Background ─────────────────────────────────────────────────────────
    Rectangle {
        id: btnBg
        anchors.fill: parent
        antialiasing: true

        topLeftRadius:     root._topLeftRadius
        topRightRadius:    root._topRightRadius
        bottomLeftRadius:  root._bottomLeftRadius
        bottomRightRadius: root._bottomRightRadius

        color: isActive
            ? (mouseArea.pressed
                ? Appearance.colors.colPrimaryActive
                : mouseArea.containsMouse
                    ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colPrimary)
            : (mouseArea.pressed
                ? Appearance.colors.colLayer2Active
                : mouseArea.containsMouse
                    ? Appearance.colors.colLayer2Hover
                    : Appearance.colors.colLayer2)

        Behavior on color            { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(btnBg) }
        Behavior on topLeftRadius    { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(btnBg) }
        Behavior on topRightRadius   { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(btnBg) }
        Behavior on bottomLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(btnBg) }
        Behavior on bottomRightRadius{ animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(btnBg) }

        // Clip content to rounded rect
        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: btnBg.width; height: btnBg.height
                topLeftRadius:     btnBg.topLeftRadius
                topRightRadius:    btnBg.topRightRadius
                bottomLeftRadius:  btnBg.bottomLeftRadius
                bottomRightRadius: btnBg.bottomRightRadius
                antialiasing: true
            }
        }
    }

    // ── Content ────────────────────────────────────────────────────────────
    RowLayout {
        anchors {
            fill: parent
            leftMargin: 2
            rightMargin: 12
        }
        spacing: 10

        // Circle icon container
        Rectangle {
            id: iconCircle
            implicitWidth:  root.itemHeight - 8
            implicitHeight: root.itemHeight - 8
            radius: width / 2
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 4

            color: isActive
                ? Qt.rgba(1, 1, 1, 0.18)
                : Qt.rgba(
                    Appearance.colors.colOnLayer2.r,
                    Appearance.colors.colOnLayer2.g,
                    Appearance.colors.colOnLayer2.b,
                    0.10
                  )

            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.iconName
                iconSize: 18
                fill: isActive ? 1 : 0
                color: isActive
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer2

                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                Behavior on fill  { NumberAnimation { duration: 150 } }
            }
        }

        // Label
        StyledText {
            text: root.pageLabel
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: isActive ? Font.DemiBold : Font.Normal
            color: isActive
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnLayer2

            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }
    }

    // ── Interaction ────────────────────────────────────────────────────────
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
