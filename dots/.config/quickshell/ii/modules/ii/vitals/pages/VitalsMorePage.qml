import QtQuick
import qs.services
import qs.modules.ii.clock.components
import qs.modules.ii.vitals.components

/** The More destination. Placeholder until its page is built (phase 4). */
VitalsPage {
    id: root

    ClockEmptyState {
        anchors.centerIn: parent
        symbol: "category"
        title: Translation.tr("More")
        subtitle: Translation.tr("Every other type the phone shares.")
    }
}
