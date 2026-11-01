pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The review's one control slot, a constant 64 px: "Show answer" as a full-width
 * primary pill while the question is up, then Anki's four ratings as a connected button
 * group (outer corners round, joins tight, the pressed one turns pill and its
 * neighbours follow). Each rating carries the interval Anki would schedule.
 */
Item {
    id: root

    property bool revealed: false
    property bool busy: false
    property var labels: ["", "", "", ""]

    signal revealRequested()
    signal rated(int ease)

    implicitHeight: 64

    readonly property var ratings: [
        {
            "label": Translation.tr("Again"),
            "bg": ClockStyle.colErrorContainer,
            "bgHover": ClockStyle.colErrorContainerHover,
            "fg": ClockStyle.colOnErrorContainer
        },
        {
            "label": Translation.tr("Hard"),
            "bg": ClockStyle.colSecondaryContainer,
            "bgHover": ClockStyle.colSecondaryContainerHover,
            "fg": ClockStyle.colOnSecondaryContainer
        },
        {
            "label": Translation.tr("Good"),
            "bg": ClockStyle.colPrimary,
            "bgHover": ClockStyle.colPrimaryHover,
            "fg": ClockStyle.colOnPrimary
        },
        {
            "label": Translation.tr("Easy"),
            "bg": ClockStyle.colTertiaryContainer,
            "bgHover": ClockStyle.colTertiaryContainerHover,
            "fg": ClockStyle.colOnTertiaryContainer
        }
    ]

    // 0 = show answer, 1 = ratings. One value drives both layers' fade and lift.
    property real progress: root.revealed ? 1 : 0
    Behavior on progress {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    RippleButton {
        id: showButton
        anchors.fill: parent
        visible: root.progress < 1
        enabled: !root.revealed && !root.busy
        opacity: 1 - root.progress
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: Appearance.rounding.normal
        colBackground: ClockStyle.colPrimary
        colBackgroundHover: ClockStyle.colPrimaryHover
        colBackgroundActive: ClockStyle.colPrimaryActive
        colRipple: ClockStyle.colPrimaryActive
        onClicked: root.revealRequested()

        contentItem: RowLayout {
            spacing: ClockStyle.gapSmall
            Item {
                Layout.fillWidth: true
            }
            MaterialSymbol {
                text: "visibility"
                iconSize: 22
                fill: 1
                color: ClockStyle.colOnPrimary
            }
            StyledText {
                text: Translation.tr("Show answer")
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: Appearance.font.pixelSize.larger
                color: ClockStyle.colOnPrimary
            }
            StyledText {
                Layout.leftMargin: ClockStyle.gapTiny
                text: Translation.tr("Space")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: ColorUtils.applyAlpha(ClockStyle.colOnPrimary, 0.7)
            }
            Item {
                Layout.fillWidth: true
            }
        }
    }

    RowLayout {
        id: ratingRow
        anchors.fill: parent
        visible: root.progress > 0
        enabled: root.revealed && !root.busy
        opacity: root.progress
        spacing: 3
        transform: Translate {
            y: (1 - root.progress) * 12
        }

        Repeater {
            model: root.ratings

            RippleButton {
                id: rateButton
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                useDynamicRadius: true
                colBackground: rateButton.modelData.bg
                colBackgroundHover: rateButton.modelData.bgHover
                colBackgroundActive: ColorUtils.mix(rateButton.modelData.bg, rateButton.modelData.fg, 0.8)
                colRipple: ColorUtils.mix(rateButton.modelData.bg, rateButton.modelData.fg, 0.75)
                onClicked: root.rated(rateButton.index + 1)

                contentItem: ColumnLayout {
                    spacing: 0
                    Item {
                        Layout.fillHeight: true
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: rateButton.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: rateButton.modelData.fg
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.labels[rateButton.index] ?? ""
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigits
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: ColorUtils.applyAlpha(rateButton.modelData.fg, 0.8)
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                }

                StyledToolTip {
                    text: Translation.tr("%1 (key %2)").arg(rateButton.modelData.label).arg(rateButton.index + 1)
                }
            }
        }
    }
}
