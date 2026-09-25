pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The seven repeat days of an alarm, starting on the week start the user chose.
 * `days` is indexed like `Date.getDay()`: 0 is Sunday.
 */
RowLayout {
    id: root

    property var days: [false, false, false, false, false, false, false]
    property real chipSize: ClockStyle.iconButton
    property bool interactive: true
    property color colOn: ClockStyle.colPrimary
    property color colOnText: ClockStyle.colOnPrimary
    property color colOff: ClockStyle.colSurfaceHighest
    property color colOffText: ClockStyle.colOnSurfaceVariant

    signal toggled(int day)

    // Config: 0 Monday … 6 Sunday. Date: 0 Sunday … 6 Saturday.
    readonly property int firstDay: ((Config.options?.time?.firstDayOfWeek ?? 6) + 1) % 7

    spacing: ClockStyle.gapTiny

    Repeater {
        model: 7

        RippleButton {
            id: dayChip
            required property int index
            readonly property int day: (root.firstDay + dayChip.index) % 7
            readonly property bool on: Boolean(root.days?.[dayChip.day])

            Layout.fillWidth: true
            Layout.maximumWidth: root.chipSize * 1.4
            implicitWidth: root.chipSize
            implicitHeight: root.chipSize
            enabled: root.interactive
            buttonRadius: dayChip.on ? ClockStyle.radiusNormal : ClockStyle.pill(root.chipSize)
            buttonRadiusPressed: ClockStyle.radiusSmall
            colBackground: dayChip.on ? root.colOn : root.colOff
            colBackgroundHover: dayChip.on ? ClockStyle.colPrimaryHover : ClockStyle.colSurfaceHover
            colRipple: dayChip.on ? ClockStyle.colPrimaryActive : ClockStyle.colSurfaceActive
            onClicked: root.toggled(dayChip.day)

            contentItem: Item {
                StyledText {
                    anchors.centerIn: parent
                    text: Qt.locale().dayName(dayChip.day, Locale.NarrowFormat)
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: dayChip.on ? root.colOnText : root.colOffText
                }
            }
        }
    }
}
