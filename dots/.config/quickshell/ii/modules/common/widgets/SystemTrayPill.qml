import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common

/**
 * The system tray pill: a wide button saying how many background apps are alive,
 * which opens whatever surface the host keeps the tray in.
 *
 * Extracted verbatim from the tablet shade's action row so the shade and the
 * island's dashboard tile are the same component — same pill, same metrics, one
 * place to change. Everything is a function of `rowHeight`, so it stays thumb-sized
 * in the shade and tile-sized in the grid; hosts that only have a row of pixels
 * (56 in the island's grid) set `rowHeight` to the surface height and the pill
 * follows.
 *
 * The pill does not own the tray surface: a click emits `trayRequested` and the
 * host opens its own dialog/page. `interactionEnabled` lets a host freeze clicks
 * without dimming the pill — the dashboard tile switches it off while editing, so a
 * press starts a drag instead of opening the dialog.
 */
RippleButton {
    id: pill

    /** The height this pill is laid out for; every inner metric derives from it. */
    property real rowHeight: 64
    /** False while the host wants presses for something else (edit-mode drag). */
    property bool interactionEnabled: true

    signal trayRequested()

    readonly property int trayItemCount: TrayService.allItems.length

    buttonRadius: Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.large
    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colRipple: Appearance.colors.colLayer1Active

    enabled: pill.interactionEnabled && pill.trayItemCount > 0
    opacity: pill.trayItemCount > 0 ? 1.0 : 0.6
    onClicked: pill.trayRequested()

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: Math.round(pill.rowHeight * 0.24)
            rightMargin: Math.round(pill.rowHeight * 0.28)
        }
        spacing: Math.round(pill.rowHeight * 0.22)

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "info"
            iconSize: Math.round(pill.rowHeight * 0.38)
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Math.round(Appearance.font.pixelSize.normal * 1.15)
            font.weight: 500
            text: {
                if (pill.trayItemCount === 0)
                    return Translation.tr("No background apps");
                if (pill.trayItemCount === 1)
                    return Translation.tr("1 app is active");
                return Translation.tr("%1 apps are active").arg(pill.trayItemCount);
            }
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            visible: pill.trayItemCount > 0
            text: "chevron_right"
            iconSize: Math.round(pill.rowHeight * 0.38)
            color: Appearance.colors.colSubtext
        }
    }
}
