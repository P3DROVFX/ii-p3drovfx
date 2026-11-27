import QtQuick
import qs.services
import qs.modules.ii.clock.components
import qs.modules.ii.vitals.components

/** The Sleep destination. Placeholder until its page is built (phase 4). */
VitalsPage {
    id: root

    ClockEmptyState {
        anchors.centerIn: parent
        symbol: "bedtime"
        title: Translation.tr("Sleep")
        subtitle: Translation.tr("Last night's stages and every night's bed and wake times.")
    }
}
