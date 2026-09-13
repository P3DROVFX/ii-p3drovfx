import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.configs.widgets
import qs.services

Item {
    id: root

    property bool nextButtonHovered: false

    readonly property var clockOptions: [
        { label: Translation.tr("24-hour"), value: "hh:mm", icon: "schedule" },
        { label: Translation.tr("12-hour · am/pm"), value: "h:mm ap", icon: "schedule" }
    ]
    readonly property var dateOptions: [
        { label: Translation.tr("Day first · 31/12"), value: "dd/MM, ddd", icon: "calendar_today" },
        { label: Translation.tr("Month first · 12/31"), value: "MM/dd, ddd", icon: "calendar_today" }
    ]

    // A first-time reader has no idea what `dd/MM, ddd` renders as, and the
    // page is asking them to pick between renderings. The buttons show the
    // format applied to the current date and time instead of the format
    // itself, which is the thing being chosen.
    SystemClock {
        id: sampleClock
        precision: SystemClock.Minutes
    }

    function sampleFor(format: string): string {
        return Qt.locale().toString(sampleClock.date, format);
    }

    function selectedIndex(options, value): int {
        const index = options.findIndex(option => option.value === value);
        return index >= 0 ? index : 0;
    }

    function selectClock(value: string) {
        DateUtils.syncHyprlockTimeFormat(value);
        Config.options.time.format = value;
    }

    function selectDate(value: string) {
        Config.options.time.dateFormat = value;
    }

    component TimeOptionButton: RippleButton {
        id: optionButton
        required property string optionLabel
        required property string optionValue
        required property string optionIcon
        readonly property string optionSample: root.sampleFor(optionButton.optionValue)
        property bool selected: false

        Layout.fillWidth: true
        implicitHeight: Appearance.rounding.large * 2.5
        toggled: selected
        buttonRadius: Appearance.rounding.normal
        colBackground: selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
        colBackgroundHover: selected ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
        colBackgroundActive: selected ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active
        colRipple: selected ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Appearance.rounding.normal
            anchors.rightMargin: Appearance.rounding.normal
            spacing: Appearance.rounding.small

            MaterialSymbol {
                text: optionButton.optionIcon
                iconSize: Appearance.font.pixelSize.large
                color: optionButton.selected
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                text: optionButton.optionLabel
                color: optionButton.selected
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: optionButton.selected ? Font.Bold : Font.DemiBold
            }

            StyledText {
                text: optionButton.optionSample
                color: optionButton.selected
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colSubtext
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }

            MaterialSymbol {
                visible: optionButton.selected
                text: "check"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.large
        anchors.rightMargin: Appearance.rounding.large
        anchors.topMargin: Appearance.rounding.small
        spacing: Appearance.rounding.small

        TimeDatePreview {
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            columns: width >= 700 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: Appearance.rounding.small
            rowSpacing: Appearance.rounding.small

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Appearance.rounding.verysmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Clock format")
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                }

                Repeater {
                    model: root.clockOptions
                    delegate: TimeOptionButton {
                        required property var modelData
                        optionLabel: modelData.label
                        optionValue: modelData.value
                        optionIcon: modelData.icon
                        selected: Config.options.time.format === modelData.value
                        onClicked: root.selectClock(modelData.value)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Appearance.rounding.verysmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Date format")
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                }

                Repeater {
                    model: root.dateOptions
                    delegate: TimeOptionButton {
                        required property var modelData
                        optionLabel: modelData.label
                        optionValue: modelData.value
                        optionIcon: modelData.icon
                        selected: Config.options.time.dateFormat === modelData.value
                        onClicked: root.selectDate(modelData.value)
                    }
                }
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            forceUniformRadius: true
            buttonIcon: "calendar_view_week"
            text: Translation.tr("Start week on Monday")
            checked: Config.options.time.firstDayOfWeek === 0
            onCheckedChanged: Config.options.time.firstDayOfWeek = checked ? 0 : 6
        }
    }
}
