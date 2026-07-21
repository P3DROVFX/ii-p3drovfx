import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

RippleButton {
    id: button

    property bool isExpanded: false
    property bool hasExpandableIndicator: true
    property real buttonHeight: 56
    property real expandedProgress: 0.0
    property bool showText: true

    visible: hasExpandableIndicator
    Layout.preferredWidth: buttonHeight
    Layout.preferredHeight: buttonHeight
    buttonRadius: expandedProgress > 0.01 ? Appearance.rounding.windowRounding : buttonHeight / 2
    rippleEnabled: true

    // Standard colors per Task C.1
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colSecondaryContainerActive

    contentItem: RowLayout {
        spacing: 8 * button.expandedProgress
        anchors.fill: parent
        anchors.leftMargin: (button.showText && button.expandedProgress > 0.01) ? 16 : 0
        anchors.rightMargin: (button.showText && button.expandedProgress > 0.01) ? 16 : 0

        MaterialSymbol {
            id: collapseIcon
            text: "keyboard_arrow_left"
            color: Appearance.colors.colOnSecondaryContainer
            iconSize: 20
            Layout.alignment: Qt.AlignVCenter | ((button.showText && button.expandedProgress > 0.01) ? Qt.AlignLeft : Qt.AlignHCenter)

            rotation: button.isExpanded ? 180 : 0
            Behavior on rotation {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.InOutQuad
                }
            }
        }

        StyledText {
            text: button.isExpanded ? Translation.tr("Collapse OSD") : Translation.tr("Expand OSD")
            color: Appearance.colors.colOnSecondaryContainer
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            visible: button.showText && button.expandedProgress > 0.5
            opacity: (button.expandedProgress - 0.5) * 2
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    StyledToolTip {
        text: button.isExpanded ? Translation.tr("Collapse OSD") : Translation.tr("Expand OSD")
        extraVisibleCondition: button.hovered
    }
}
