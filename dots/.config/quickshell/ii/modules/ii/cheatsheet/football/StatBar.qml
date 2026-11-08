import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One statistic compared: values on both ends, the label between, and two
 * bars growing from the middle in each team's voice. The larger side is bold.
 */
ColumnLayout {
    id: root

    property var stat: null
    readonly property real total: Math.max(0.0001, (root.stat?.homeValue ?? 0) + (root.stat?.awayValue ?? 0))
    readonly property real homeShare: (root.stat?.homeValue ?? 0) / root.total
    readonly property real awayShare: (root.stat?.awayValue ?? 0) / root.total
    readonly property bool homeLeads: (root.stat?.homeValue ?? 0) > (root.stat?.awayValue ?? 0)
    readonly property bool awayLeads: (root.stat?.awayValue ?? 0) > (root.stat?.homeValue ?? 0)

    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            shouldUseNumberFont: false
            text: root.stat?.home ?? ""
            font.pixelSize: FootballStyle.textLarger
            font.variableAxes: root.homeLeads ? FootballStyle.axesScoreHeavy : FootballStyle.axesScoreLight
            color: FootballStyle.colOnSurface
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: (root.stat?.label ?? "").toUpperCase()
            elide: Text.ElideRight
            font.pixelSize: FootballStyle.textSmallest
            font.variableAxes: FootballStyle.axesCaps
            font.letterSpacing: 1.2
            color: FootballStyle.colOnSurfaceVariant
        }
        StyledText {
            shouldUseNumberFont: false
            text: root.stat?.away ?? ""
            font.pixelSize: FootballStyle.textLarger
            font.variableAxes: root.awayLeads ? FootballStyle.axesScoreHeavy : FootballStyle.axesScoreLight
            color: FootballStyle.colOnSurface
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: 8

        Rectangle {
            anchors.right: parent.horizontalCenter
            anchors.rightMargin: 2
            height: parent.height
            width: Math.max(height, (parent.width / 2 - 2) * root.homeShare)
            radius: height / 2
            color: root.homeLeads || !root.awayLeads ? FootballStyle.colPrimary : FootballStyle.colPrimaryContainer
            Behavior on width {
                enabled: !FootballStyle.reducedMotion
                animation: FootballStyle.motionDefault.numberAnimation.createObject(this)
            }
        }
        Rectangle {
            anchors.left: parent.horizontalCenter
            anchors.leftMargin: 2
            height: parent.height
            width: Math.max(height, (parent.width / 2 - 2) * root.awayShare)
            radius: height / 2
            color: root.awayLeads || !root.homeLeads ? FootballStyle.colTertiary : FootballStyle.colTertiaryContainer
            Behavior on width {
                enabled: !FootballStyle.reducedMotion
                animation: FootballStyle.motionDefault.numberAnimation.createObject(this)
            }
        }
    }
}
