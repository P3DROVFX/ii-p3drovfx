pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * A bare 0–100 level (`playerVolume`). `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: levelCol
    required property var row

    spacing: 10

    RowLayout {
        spacing: 12

        StyledSlider {
            id: levelSlider
            Layout.fillWidth: true
            from: 0
            to: 100
            stepSize: 1
            value: Number(row.value) || 0
            tooltipContent: `${Math.round(value)} %`
            onPressedChanged: {
                if (!pressed)
                    row.setValue(Math.round(value));
            }
        }

        StyledText {
            text: `${Math.round(levelSlider.value)} %`
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnLayer2
        }
    }

    FormHint {
        visible: row.type === "playerVolume"
        text: MprisController.activePlayer
            ? Translation.tr("On the active player, %1 right now").arg(MprisController.activePlayer.identity ?? "")
            : Translation.tr("On whichever media player is active when the action runs")
    }
}
