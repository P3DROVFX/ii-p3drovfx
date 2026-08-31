pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root

    required property var quota
    property bool showGroupName: true
    property bool startAnim: false
    property int animDelay: 0
    property color accentColor: Appearance.colors.colSecondary
    property color accentContainer: Appearance.colors.colSecondaryContainer
    property color onAccentContainer: Appearance.colors.colOnSecondaryContainer
    readonly property bool creditBalance: String(root.quota.metricKind ?? "quota") === "credits"

    Layout.fillWidth: true
    implicitHeight: 66
    radius: Appearance.rounding.small
    color: Appearance.colors.colSurfaceContainerHighest
    opacity: 0.0

    transform: Translate {
        id: rowTranslate
        y: 14
    }

    onStartAnimChanged: {
        rowAnim.stop();
        root.opacity = 0.0;
        rowTranslate.y = 14;
        if (root.startAnim)
            Qt.callLater(function() { rowAnim.start(); });
    }

    SequentialAnimation {
        id: rowAnim

        PauseAnimation {
            duration: root.animDelay
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 1.0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            NumberAnimation {
                target: rowTranslate
                property: "y"
                to: 0
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        MaterialShape {
            implicitSize: 36
            shapeString: {
                switch (String(root.quota.windowKind ?? "short")) {
                case "balance": return "Circle";
                case "weekly": return "Cookie9Sided";
                case "daily": return "Clover4Leaf";
                default: return "SoftBurst";
                }
            }
            color: root.accentContainer

            CustomIcon {
                anchors.centerIn: parent
                width: 19
                height: width
                source: String(root.quota.providerIcon ?? AiPlanUsage.providerIcon(String(root.quota.providerId ?? "")))
                colorize: true
                color: root.onAccentContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: {
                    const group = String(root.quota.groupName ?? "");
                    return root.showGroupName && group.length > 0
                        ? group + " · " + String(root.quota.windowLabel ?? "")
                        : String(root.quota.windowLabel ?? Translation.tr("Quota"));
                }
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.creditBalance
                    ? Translation.tr("Credits remaining")
                    : AiPlanUsage.formatReset(root.quota.resetsAt)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            Layout.preferredWidth: root.creditBalance ? 102 : 88
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.creditBalance
                    ? AiPlanUsage.creditAmountText(root.quota) + " " + Translation.tr("remaining")
                    : AiPlanUsage.percentText(root.quota) + " " + AiPlanUsage.metricLabel(root.quota)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: AiPlanUsage.isLow(root.quota)
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnSurface
            }

            StyledProgressBar {
                visible: !root.creditBalance
                Layout.alignment: Qt.AlignRight
                value: AiPlanUsage.displayFraction(root.quota)
                valueBarWidth: 88
                valueBarHeight: Math.max(5, Appearance.rounding.unsharpen + 3)
                highlightColor: AiPlanUsage.isLow(root.quota)
                    ? Appearance.colors.colError
                    : root.accentColor
                trackColor: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.82)
            }
        }
    }
}
