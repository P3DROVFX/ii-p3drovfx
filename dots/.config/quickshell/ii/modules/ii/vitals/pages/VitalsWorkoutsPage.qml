import QtQuick
import qs.services
import qs.modules.ii.clock.components
import qs.modules.ii.vitals.components

/** The Workouts destination. Placeholder until its page is built (phase 4). */
VitalsPage {
    id: root

    ClockEmptyState {
        anchors.centerIn: parent
        symbol: "exercise"
        title: Translation.tr("Workouts")
        subtitle: Translation.tr("Every session with its pace, heart rate and route.")
    }
}
