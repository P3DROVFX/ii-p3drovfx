pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `brightness` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: brightnessCol
    required property var row

    spacing: 10

    readonly property int level: Number(typeof row.value === "object" ? row.obj.level : row.value) || 0

    RowLayout {
        spacing: 12

        StyledSlider {
            id: brightnessSlider
            Layout.fillWidth: true
            from: 1
            to: 100
            stepSize: 1
            value: brightnessCol.level
            // The default tooltip normalises against `from`, which is 1 here.
            tooltipContent: `${Math.round(value)} %`
            onPressedChanged: {
                if (!pressed)
                    row.patchValue({ level: Math.round(value), scope: row.obj.scope ?? "all" });
            }
        }

        StyledText {
            text: `${Math.round(brightnessSlider.value)} %`
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnLayer2
        }
    }

    FormChoice {
        current: row.obj.scope ?? "all"
        onPicked: v => row.patchValue({ level: brightnessCol.level, scope: v })
        options: [
            { displayName: Translation.tr("All monitors"), value: "all" },
            { displayName: Translation.tr("Focused monitor"), value: "focused" }
        ]
    }
}
