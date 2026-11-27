import QtQuick
import qs.services
import qs.modules.ii.clock.components
import qs.modules.ii.vitals.components

/** The Heart destination. Placeholder until its page is built (phase 4). */
VitalsPage {
    id: root

    ClockEmptyState {
        anchors.centerIn: parent
        symbol: "favorite"
        title: Translation.tr("Heart")
        subtitle: Translation.tr("Heart rate through the day and its range over two weeks.")
    }
}
