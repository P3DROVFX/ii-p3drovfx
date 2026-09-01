pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property bool vertical: false

    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    readonly property string sizeMode: Config.options.bar.searchWidget.sizeMode ?? "compact"
    readonly property string colorMode: Config.options.bar.searchWidget.colorMode ?? "tonal"
    readonly property bool compact: root.sizeMode === "compact"
    readonly property bool extended: root.sizeMode === "extended"
    readonly property bool hasLabel: !root.compact
    readonly property bool hasShortcut: root.extended
        && (Config.options.bar.searchWidget.showShortcutHint ?? true)
    readonly property bool activated: GlobalStates.overviewOpen
        && GlobalStates.searchOnlyMode
        && (root.screenName === "" || GlobalStates.activeSearchMonitor === root.screenName)
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property int contentRotation: root.vertical
        ? (Config.options.bar.bottom ? 90 : -90)
        : 0
    readonly property real verticalLabelMaxLength: Appearance.sizes.verticalBarWidth
        * (root.extended ? 3 : 2)
    readonly property real targetLength: root.compact
        ? root.thickness
        : (root.vertical ? neuralContent.implicitHeight + 12 : neuralContent.implicitWidth + 14)
    property real animatedLength: root.targetLength

    readonly property color containerColor: root.colorMode === "vibrant"
        ? Appearance.colors.colPrimaryContainer
        : root.colorMode === "neutral"
            ? Appearance.colors.colSurfaceContainerHighest
            : Appearance.colors.colTertiaryContainer
    readonly property color containerHoverColor: root.colorMode === "vibrant"
        ? Appearance.colors.colPrimaryContainerHover
        : root.colorMode === "neutral"
            ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.colors.colTertiaryContainerHover
    readonly property color containerActiveColor: root.colorMode === "vibrant"
        ? Appearance.colors.colPrimaryContainerActive
        : root.colorMode === "neutral"
            ? Appearance.colors.colSurfaceContainerHighestActive
            : Appearance.colors.colTertiaryContainerActive
    readonly property color contentColor: root.colorMode === "vibrant"
        ? Appearance.colors.colOnPrimaryContainer
        : root.colorMode === "neutral"
            ? Appearance.colors.colOnSurface
            : Appearance.colors.colOnTertiaryContainer
    readonly property color accentColor: root.colorMode === "vibrant"
        ? Appearance.colors.colPrimary
        : root.colorMode === "neutral"
            ? Appearance.colors.colSecondaryContainer
            : Appearance.colors.colTertiary
    readonly property color onAccentColor: root.colorMode === "vibrant"
        ? Appearance.colors.colOnPrimary
        : root.colorMode === "neutral"
            ? Appearance.colors.colOnSecondaryContainer
            : Appearance.colors.colOnTertiary

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength
    implicitHeight: root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight

    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    RippleButton {
        id: neuralCapsule
        anchors.centerIn: parent
        width: root.vertical ? root.thickness : root.animatedLength
        height: root.vertical ? root.animatedLength : root.thickness
        buttonRadius: root.compact
            ? Appearance.rounding.full
            : Appearance.rounding.large
        colBackground: root.containerColor
        colBackgroundHover: root.containerHoverColor
        colBackgroundActive: root.containerActiveColor
        colRipple: root.containerActiveColor
        onPressed: GlobalStates.toggleSearchOnly(root.screenName)

        GridLayout {
            id: neuralContent
            anchors.centerIn: parent
            columns: root.vertical
                ? 1
                : (root.hasShortcut ? 4 : (root.hasLabel ? 3 : 1))
            rowSpacing: 3
            columnSpacing: 7

            MaterialShape {
                Layout.alignment: Qt.AlignCenter
                implicitSize: 26
                shape: root.activated
                    ? MaterialShape.Shape.Sunny
                    : MaterialShape.Shape.SoftBurst
                color: root.accentColor

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "search"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.onAccentColor
                }
            }

            Item {
                visible: root.hasLabel
                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.vertical ? neuralLabels.height : neuralLabels.width
                implicitHeight: root.vertical ? neuralLabels.width : neuralLabels.height

                ColumnLayout {
                    id: neuralLabels
                    anchors.centerIn: parent
                    width: root.vertical
                        ? Math.min(implicitWidth, root.verticalLabelMaxLength)
                        : implicitWidth
                    height: implicitHeight
                    rotation: root.contentRotation
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Search")
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        fontSizeMode: Text.Fit
                        minimumPixelSize: Appearance.font.pixelSize.smallest
                        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
                        color: root.contentColor
                    }

                    StyledText {
                        visible: root.extended
                        Layout.fillWidth: true
                        text: Translation.tr("Apps & commands")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        fontSizeMode: Text.Fit
                        minimumPixelSize: Appearance.font.pixelSize.smallest
                        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
                        color: root.contentColor
                        opacity: 0.72
                    }
                }
            }

            RowLayout {
                visible: root.hasLabel
                Layout.alignment: Qt.AlignCenter
                spacing: 3

                Repeater {
                    model: 3

                    delegate: MaterialShape {
                        required property int index
                        implicitSize: index === 1 ? 7 : 5
                        shape: index === 1
                            ? MaterialShape.Shape.SoftBurst
                            : MaterialShape.Shape.Circle
                        color: root.contentColor
                        opacity: index === 1 ? 0.88 : 0.54
                    }
                }
            }

            SearchShortcutBadge {
                visible: root.hasShortcut
                Layout.alignment: Qt.AlignCenter
                badgeColor: root.accentColor
                glyphColor: root.onAccentColor
            }
        }
    }

    StyledToolTip {
        text: Translation.tr("Open launcher")
        alternativeVisibleCondition: neuralCapsule.hovered
        extraVisibleCondition: false
        requireOverlay: false
    }
}
