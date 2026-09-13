import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Material 3 FAB.
 */
RippleButton {
    id: root
    property string iconText: "add"
    property bool expanded: false
    property real baseSize: 56
    property real iconSize: 26
    property real elementSpacing: 5
    clip: true

    padding: 0
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    bottomPadding: 0

    readonly property bool canExpand: root.expanded && !!root.buttonText && root.buttonText.length > 0
    readonly property real targetProgress: canExpand ? 1.0 : 0.0
    property real expandProgress: targetProgress

    Behavior on expandProgress {
        NumberAnimation {
            duration: root.expanded
                ? (Appearance?.animation?.elementMoveEnter?.duration ?? 350)
                : (Appearance?.animation?.elementMoveExit?.duration ?? 220)
            easing.type: Easing.OutCubic
        }
    }

    readonly property real extraWidth: (buttonText.implicitWidth > 0)
        ? (buttonText.implicitWidth + root.elementSpacing)
        : 0

    implicitWidth: baseSize + Math.round(extraWidth * expandProgress)
    implicitHeight: baseSize
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    readonly property bool sharpMode: Config.options.appearance.sharpMode
    buttonRadius: sharpMode ? 0 : baseSize / 14 * 4
    
    colBackground: Appearance.colors.colPrimaryContainer
    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
    colRipple: Appearance.colors.colPrimaryContainerActive
    property color colOnBackground: Appearance.colors.colOnPrimaryContainer

    contentItem: Row {
        id: contentRowLayout
        property real horizontalMargins: (root.baseSize - icon.width) / 2
        anchors {
            verticalCenter: parent ? parent.verticalCenter : undefined
            left: parent ? parent.left : undefined
            leftMargin: contentRowLayout.horizontalMargins
        }
        spacing: 0

        MaterialSymbol {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: root.iconSize
            width: root.iconSize
            height: root.iconSize
            color: root.colOnBackground
            text: root.iconText
        }

        Item {
            id: textRevealer
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.round(root.extraWidth * root.expandProgress))
            implicitWidth: width
            height: buttonText.implicitHeight
            implicitHeight: height
            clip: true
            visible: !!root.buttonText && root.buttonText.length > 0

            StyledText {
                id: buttonText
                anchors.left: parent.left
                anchors.leftMargin: root.elementSpacing
                anchors.verticalCenter: parent.verticalCenter
                text: root.buttonText
                color: root.colOnBackground
                font.pixelSize: 14
                font.weight: 450
                opacity: root.expandProgress
                scale: 0.90 + 0.10 * root.expandProgress
                transformOrigin: Item.Left
            }
        }
    }
}
