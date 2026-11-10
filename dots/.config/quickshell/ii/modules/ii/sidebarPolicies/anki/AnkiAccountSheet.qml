import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The signed-in AnkiWeb account: who, sync now, and sign out (which forgets the session
 * key only; the collection stays on this computer).
 */
AnkiSheet {
    id: root

    title: Translation.tr("AnkiWeb")
    subtitle: Anki.username

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: infoColumn.implicitHeight + ClockStyle.gapLarge * 2
        radius: Appearance.rounding.small
        color: ClockStyle.colField

        ColumnLayout {
            id: infoColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: ClockStyle.gapLarge
            }
            spacing: 2
            StyledText {
                text: Translation.tr("Collection")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: ClockStyle.colOnSurfaceVariant
            }
            StyledText {
                text: Translation.tr("%1 cards · Anki %2").arg(Anki.cardCount).arg(Anki.version)
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: ClockStyle.colOnSurface
            }
            StyledText {
                Layout.fillWidth: true
                visible: Anki.lastSyncMessage.length > 0
                wrapMode: Text.Wrap
                text: Anki.lastSyncMessage
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }
    }

    footer: [
        ClockSheetAction {
            danger: true
            symbol: "logout"
            label: Translation.tr("Sign out")
            onClicked: {
                Anki.logout();
                root.dismissed();
            }
        },
        ClockSheetAction {
            primary: true
            enabled: !Anki.syncing
            symbol: "sync"
            label: Anki.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
            onClicked: Anki.sync()
        }
    ]
}
