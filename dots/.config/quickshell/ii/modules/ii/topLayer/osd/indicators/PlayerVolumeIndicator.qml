import qs.services
import QtQuick
import qs.modules.ii.topLayer.osd
import qs.modules.common.widgets

OsdConnectValueIndicator {
    id: osdValues
    value: MprisController.activePlayer?.volume ?? 0
    icon: "music_note"
    name: Translation.tr("Music")
    shape: MaterialShape.Shape.Cookie4Sided

    onValueUpdateRequested: (newValue) => {
        if (MprisController.activePlayer) {
            MprisController.activePlayer.volume = newValue;
        }
    }
}
