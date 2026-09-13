import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property var quota: ({})
    property bool vertical: false
    property bool useAccentForeground: false
    property string visualization: Config.options.bar.aiPlanUsage.visualization
    property bool showWindowLabel: Config.options.bar.aiPlanUsage.showWindowLabel
    property int indicatorSize: Math.max(24, root.vertical
        ? Appearance.sizes.verticalBarWidth - 18
        : Appearance.sizes.baseBarHeight - (root.showWindowLabel ? 18 : 12))
    property color contentColor: Appearance.colors.colOnLayer1

    readonly property bool quotaAvailable: root.quota?.available !== false
    readonly property bool low: AiPlanUsage.isLow(root.quota)
    readonly property real value: AiPlanUsage.displayFraction(root.quota)
    readonly property string providerId: String(root.quota?.providerId ?? "")
    readonly property string groupId: String(root.quota?.groupId ?? "")

    readonly property color providerAccent: {
        if (root.providerId === "chatgpt")
            return Appearance.colors.colSecondary;
        if (root.providerId === "claude")
            return Appearance.colors.colTertiary;
        if (root.providerId === "antigravity" && root.groupId === "other")
            return Appearance.colors.colSecondary;
        return Appearance.colors.colPrimary;
    }
    readonly property color providerOnAccent: {
        if (root.providerId === "chatgpt")
            return Appearance.colors.colOnSecondary;
        if (root.providerId === "claude")
            return Appearance.colors.colOnTertiary;
        if (root.providerId === "antigravity" && root.groupId === "other")
            return Appearance.colors.colOnSecondary;
        return Appearance.colors.colOnPrimary;
    }
    readonly property color providerContainer: {
        if (root.providerId === "chatgpt")
            return Appearance.colors.colSecondaryContainer;
        if (root.providerId === "claude")
            return Appearance.colors.colTertiaryContainer;
        if (root.providerId === "antigravity" && root.groupId === "other")
            return Appearance.colors.colSecondaryContainer;
        return Appearance.colors.colPrimaryContainer;
    }
    readonly property color providerOnContainer: {
        if (root.providerId === "chatgpt")
            return Appearance.colors.colOnSecondaryContainer;
        if (root.providerId === "claude")
            return Appearance.colors.colOnTertiaryContainer;
        if (root.providerId === "antigravity" && root.groupId === "other")
            return Appearance.colors.colOnSecondaryContainer;
        return Appearance.colors.colOnPrimaryContainer;
    }

    readonly property color resolvedAccent: root.low ? Appearance.colors.colError : root.providerAccent
    readonly property color resolvedOnAccent: root.low ? Appearance.colors.colOnError : root.providerOnAccent
    readonly property color resolvedContainer: root.low ? Appearance.colors.colErrorContainer : root.providerContainer
    readonly property color resolvedOnContainer: root.low ? Appearance.colors.colOnErrorContainer : root.providerOnContainer
    readonly property color resolvedContent: root.low
        ? Appearance.colors.colError
        : (root.useAccentForeground ? root.providerAccent : root.contentColor)
    readonly property int verticalCellWidth: Math.max(30, Appearance.sizes.verticalBarWidth - 12)
    readonly property string shapeName: {
        switch (root.providerId) {
        case "chatgpt": return "Cookie9Sided";
        case "claude": return "Clover4Leaf";
        case "antigravity": return root.groupId === "other" ? "SoftBurst" : "Sunny";
        case "zai": return "Sunny";
        case "kimi": return "SoftBurst";
        case "opencode": return "Cookie9Sided";
        case "openrouter": return "Circle";
        default: return "Circle";
        }
    }

    function shortWindowLabel(): string {
        switch (String(root.quota?.windowKind ?? "short")) {
        case "balance": return String(root.quota?.currency ?? "USD");
        case "weekly": return "7d";
        case "daily": return "24h";
        case "monthly": return "30d";
        default:
            return Number(root.quota?.windowMinutes ?? 0) === 300 ? "5h" : Translation.tr("Now");
        }
    }

    implicitWidth: indicatorColumn.implicitWidth
    implicitHeight: indicatorColumn.implicitHeight
    opacity: root.quotaAvailable ? 1.0 : 0.5

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: indicatorColumn
        anchors.centerIn: parent
        spacing: root.vertical ? 2 : 1

        Loader {
            id: visualLoader
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: {
                switch (root.visualization) {
                case "semicircle": return semiComponent;
                case "circle": return circleComponent;
                case "shape": return shapeComponent;
                case "bar": return barComponent;
                case "text": return textComponent;
                default: return resourceComponent;
                }
            }
        }

        StyledText {
            visible: root.showWindowLabel && root.visualization !== "text"
            Layout.alignment: Qt.AlignHCenter
            text: root.shortWindowLabel()
            font.pixelSize: root.vertical
                ? Appearance.font.pixelSize.smallest
                : Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: root.resolvedContent
        }
    }

    Component {
        id: resourceComponent

        Item {
            implicitWidth: root.indicatorSize
            implicitHeight: root.indicatorSize

            MaterialShape {
                anchors.fill: parent
                shapeString: root.shapeName
                color: root.resolvedAccent

                ClippedFilledCircularProgress {
                    anchors.centerIn: parent
                    implicitSize: root.indicatorSize - 6
                    lineWidth: 0
                    value: root.value
                    colPrimary: ColorUtils.transparentize(root.resolvedOnAccent, 0.62)
                    colSecondary: "transparent"
                    enableAnimation: false
                    accountForLightBleeding: false
                }

                CustomIcon {
                    anchors.centerIn: parent
                    width: Math.round(root.indicatorSize * 0.48)
                    height: width
                    source: String(root.quota?.providerIcon ?? AiPlanUsage.providerIcon(root.providerId))
                    colorize: true
                    color: root.resolvedOnAccent
                }
            }
        }
    }

    Component {
        id: circleComponent

        Item {
            implicitWidth: root.indicatorSize
            implicitHeight: root.indicatorSize

            CircularProgress {
                anchors.centerIn: parent
                implicitSize: root.indicatorSize
                lineWidth: Math.max(2, Math.round(root.indicatorSize * 0.1))
                value: root.value
                colPrimary: root.resolvedAccent
                colSecondary: root.resolvedContainer
                enableAnimation: true
                animationDuration: Appearance.animation.elementMove.duration

                CustomIcon {
                    anchors.centerIn: parent
                    width: Math.round(root.indicatorSize * 0.43)
                    height: width
                    source: String(root.quota?.providerIcon ?? AiPlanUsage.providerIcon(root.providerId))
                    colorize: true
                    color: root.resolvedContent
                }
            }
        }
    }

    Component {
        id: semiComponent

        Item {
            implicitWidth: root.vertical ? root.verticalCellWidth : root.indicatorSize + 6
            implicitHeight: Math.max(22, Math.round(root.indicatorSize * 0.72))

            AiQuotaArcGauge {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                implicitSize: Math.min(parent.width, root.indicatorSize + 4)
                lineWidth: Math.max(2, Math.round(root.indicatorSize * 0.1))
                value: root.value
                highlightColor: root.resolvedAccent
                trackColor: root.resolvedContainer
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -1
                text: AiPlanUsage.percentText(root.quota)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: root.resolvedContent
            }
        }
    }

    Component {
        id: shapeComponent

        Item {
            implicitWidth: root.indicatorSize
            implicitHeight: root.indicatorSize

            MaterialShape {
                anchors.fill: parent
                shapeString: root.shapeName
                color: root.resolvedContainer
            }

            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * root.value
                clip: true

                MaterialShape {
                    width: parent.width
                    height: root.indicatorSize
                    y: -(root.indicatorSize - parent.height)
                    implicitSize: root.indicatorSize
                    shapeString: root.shapeName
                    color: root.resolvedAccent
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(root.indicatorSize * 0.55)
                height: width
                radius: Appearance.rounding.full
                color: root.resolvedAccent

                CustomIcon {
                    anchors.centerIn: parent
                    width: Math.round(parent.width * 0.62)
                    height: width
                    source: String(root.quota?.providerIcon ?? AiPlanUsage.providerIcon(root.providerId))
                    colorize: true
                    color: root.resolvedOnAccent
                }
            }
        }
    }

    Component {
        id: barComponent

        Loader {
            sourceComponent: root.vertical ? verticalBarComponent : horizontalBarComponent
        }
    }

    Component {
        id: horizontalBarComponent

        RowLayout {
            spacing: 6

            StyledProgressBar {
                Layout.alignment: Qt.AlignVCenter
                value: root.value
                valueBarWidth: 44
                valueBarHeight: Math.max(5, Appearance.rounding.unsharpen + 3)
                highlightColor: root.resolvedAccent
                trackColor: root.resolvedContainer
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: AiPlanUsage.percentText(root.quota)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: root.resolvedContent
            }
        }
    }

    Component {
        id: verticalBarComponent

        ColumnLayout {
            implicitWidth: root.verticalCellWidth
            spacing: 2

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: AiPlanUsage.percentText(root.quota)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: root.resolvedContent
            }

            StyledProgressBar {
                id: verticalProgress
                Layout.alignment: Qt.AlignHCenter
                value: root.value
                valueBarWidth: Math.max(22, root.verticalCellWidth - 8)
                valueBarHeight: Math.max(4, Appearance.rounding.unsharpen + 2)
                valueBarGap: 2
                highlightColor: root.resolvedContent
                trackColor: ColorUtils.transparentize(root.resolvedContent, 0.72)
            }
        }
    }

    Component {
        id: textComponent

        StyledText {
            id: textValue
            text: AiPlanUsage.percentText(root.quota)
            font.pixelSize: root.vertical
                ? Appearance.font.pixelSize.smaller
                : Appearance.font.pixelSize.small
            font.weight: Font.Bold
            color: root.resolvedContent
            animateChange: true
        }
    }
}
