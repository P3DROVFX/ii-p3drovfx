import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The app bar: the rail toggle, the page's name in the expressive title face with the
 * device and preset beneath it, the page's actions, and close. Actions are round tonal
 * buttons, so the bar reads as one row of the same kind of thing.
 */
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool showBack: false
    property bool showRailToggle: false
    property bool railExpanded: true
    default property alias actions: actionRow.data
    /// Between the title and the actions: whatever should take the room that is left
    /// (the device strip), scrolling or clipping itself.
    property alias center: centerSlot.data
    /// Whether the middle slot is in use; otherwise the title takes the room.
    property bool centerActive: false

    signal backRequested()
    signal railToggled()
    signal closeRequested()

    implicitHeight: ClockStyle.topBarHeight

    RowLayout {
        anchors {
            fill: parent
            leftMargin: EasyEffectsStyle.gapTiny
            rightMargin: EasyEffectsStyle.gapTiny
        }
        spacing: EasyEffectsStyle.gap

        ClockIconButton {
            visible: root.showBack
            size: EasyEffectsStyle.iconButton
            symbol: "arrow_back"
            tooltip: Translation.tr("Back")
            onClicked: root.backRequested()
        }

        ClockIconButton {
            visible: root.showRailToggle && !root.showBack
            size: EasyEffectsStyle.iconButton
            symbol: root.railExpanded ? "menu_open" : "menu"
            tooltip: root.railExpanded ? Translation.tr("Collapse") : Translation.tr("Expand")
            colIcon: EasyEffectsStyle.colOnBackground
            onClicked: root.railToggled()
        }

        ColumnLayout {
            // The title keeps what it needs (up to a limit); the middle gets the rest.
            Layout.fillWidth: !root.centerActive
            Layout.maximumWidth: Math.max(EasyEffectsStyle.sheetWidth * 0.4, root.width * 0.28)
            Layout.minimumWidth: 0
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: EasyEffectsStyle.fontTitle
                font.variableAxes: EasyEffectsStyle.axesTitle
                font.pixelSize: EasyEffectsStyle.textHeading + EasyEffectsStyle.gapSmall
                color: EasyEffectsStyle.colOnBackground
                animateChange: !EasyEffectsStyle.reducedMotion
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                elide: Text.ElideRight
                font.pixelSize: EasyEffectsStyle.textNormal - 1
                color: EasyEffectsStyle.colSubtext
            }
        }

        Item {
            id: centerSlot
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            visible: root.centerActive
            clip: true
        }

        RowLayout {
            id: actionRow
            spacing: EasyEffectsStyle.gapSmall
        }

        EasyEffectsButton {
            iconOnly: true
            symbol: "close"
            label: Translation.tr("Close")
            onClicked: root.closeRequested()
        }
    }
}
