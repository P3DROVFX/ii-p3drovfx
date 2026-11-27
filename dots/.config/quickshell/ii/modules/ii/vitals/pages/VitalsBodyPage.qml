import QtQuick
import qs.services
import qs.modules.ii.clock.components
import qs.modules.ii.vitals.components

/** The Body destination. Placeholder until its page is built (phase 4). */
VitalsPage {
    id: root

    ClockEmptyState {
        anchors.centerIn: parent
        symbol: "monitor_weight"
        title: Translation.tr("Body")
        subtitle: Translation.tr("Weight, body composition and nightly skin temperature.")
    }
}
