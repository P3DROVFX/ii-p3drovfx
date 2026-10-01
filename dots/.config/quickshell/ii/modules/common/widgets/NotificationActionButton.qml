import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

RippleButton {
    id: button
    property string buttonText
    /**
     * Optional leading glyph. Server (freedesktop) actions carry none; the shell's own do.
     *
     * Not `icon`: `AbstractButton.icon` is final in Qt 6.10+, and shadowing it fails the
     * component at load time.
     */
    property string actionIcon
    /**
     * Glyph without a label (Open), for rows with no width to spare: the label still
     * exists - it becomes the tooltip.
     */
    property bool iconOnly: false
    property string urgency

    implicitHeight: 34
    leftPadding: 15
    rightPadding: 15
    buttonRadius: Appearance.rounding.small
    colBackground: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer4
    colBackgroundHover: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer4Hover
    colRipple: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer4Active
    readonly property color colText: (urgency == NotificationUrgency.Critical) ? Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface

    // The row is what centres: the button is stretched by the action row it sits in, so
    // the glyph and the label travel together instead of pairing at the left edge.
    contentItem: Item {
        implicitWidth: actionRow.implicitWidth
        implicitHeight: actionRow.implicitHeight

        RowLayout {
            id: actionRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: button.actionIcon !== ""
                text: button.actionIcon
                iconSize: Appearance.font.pixelSize.larger
                color: button.colText
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: !button.iconOnly
                text: button.buttonText
                color: button.colText
            }
        }
    }

    StyledToolTip {
        text: button.buttonText
        extraVisibleCondition: button.iconOnly
    }
}
