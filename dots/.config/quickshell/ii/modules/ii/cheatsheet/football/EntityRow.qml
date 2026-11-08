import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A competition or team in a grouped list: crest, name, a secondary line and
 * a trailing control. Same group shape and selection notch as MatchRow.
 */
RippleButton {
    id: root

    property string logo: ""
    property string title: ""
    property string subtitle: ""
    property bool selected: false
    property bool isFirst: true
    property bool isLast: true
    property bool prevSelected: false
    property bool nextSelected: false
    default property alias trailing: trailingSlot.data

    implicitHeight: FootballStyle.compactRowHeight + 4
    padding: 0
    toggled: root.selected
    colBackground: FootballStyle.colRow
    colBackgroundHover: FootballStyle.colRowHover
    colRipple: FootballStyle.colRowActive
    colBackgroundToggled: FootballStyle.colSecondaryContainer
    colBackgroundToggledHover: FootballStyle.colSecondaryContainerHover
    colRippleToggled: FootballStyle.colSecondaryContainerActive

    readonly property real pillRadius: Math.min(root.implicitHeight / 2, FootballStyle.radiusLarge)
    readonly property bool topPill: root.selected || root.down || root.prevSelected
    readonly property bool bottomPill: root.selected || root.down || root.nextSelected
    topLeftRadius: root.topPill ? root.pillRadius : (root.isFirst ? FootballStyle.radiusLarge : FootballStyle.radiusJoin)
    topRightRadius: root.topLeftRadius
    bottomLeftRadius: root.bottomPill ? root.pillRadius : (root.isLast ? FootballStyle.radiusLarge : FootballStyle.radiusJoin)
    bottomRightRadius: root.bottomLeftRadius
    Behavior on topLeftRadius {
        enabled: !FootballStyle.reducedMotion
        animation: FootballStyle.motionFast.numberAnimation.createObject(this)
    }
    Behavior on bottomLeftRadius {
        enabled: !FootballStyle.reducedMotion
        animation: FootballStyle.motionFast.numberAnimation.createObject(this)
    }

    contentItem: Item {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: FootballStyle.gap
            anchors.rightMargin: FootballStyle.gapSmall
            spacing: FootballStyle.gap

            TeamCrest {
                size: 36
                source: root.logo
                plate: root.selected ? FootballStyle.colField : FootballStyle.colPane
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: FootballStyle.textNormal
                    font.weight: Font.DemiBold
                    color: root.selected ? FootballStyle.colOnSecondaryContainer : FootballStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: FootballStyle.textSmaller
                    color: root.selected ? FootballStyle.colOnSecondaryContainer : FootballStyle.colSubtext
                }
            }
            Item {
                id: trailingSlot
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }
}
