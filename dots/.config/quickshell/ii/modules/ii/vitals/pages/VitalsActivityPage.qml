import QtQuick
import qs.services
import qs.modules.ii.clock.components
import qs.modules.ii.vitals.components

/** The Activity destination. Placeholder until its page is built (phase 4). */
VitalsPage {
    id: root

    ClockEmptyState {
        anchors.centerIn: parent
        symbol: "directions_walk"
        title: Translation.tr("Activity")
        subtitle: Translation.tr("Steps, distance, floors and calories by day, week and month.")
    }
}
