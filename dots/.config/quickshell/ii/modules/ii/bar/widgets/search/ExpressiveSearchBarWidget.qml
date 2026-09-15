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
        : (root.vertical ? content.implicitHeight + 12 : content.implicitWidth + 14)
    property real animatedLength: root.targetLength

    readonly property color containerColor: root.colorMode === "vibrant"
        ? Appearance.colors.colPrimary
        : root.colorMode === "neutral"
            ? Appearance.colors.colSurfaceContainerHighest
            : Appearance.colors.colSecondaryContainer
    readonly property color containerHoverColor: root.colorMode === "vibrant"
        ? Appearance.colors.colPrimaryHover
        : root.colorMode === "neutral"
            ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.colors.colSecondaryContainerHover
    readonly property color containerActiveColor: root.colorMode === "vibrant"
        ? Appearance.colors.colPrimaryActive
        : root.colorMode === "neutral"
            ? Appearance.colors.colSurfaceContainerHighestActive
            : Appearance.colors.colSecondaryContainerActive
    readonly property color contentColor: root.colorMode === "vibrant"
        ? Appearance.colors.colOnPrimary
        : root.colorMode === "neutral"
            ? Appearance.colors.colOnSurface
            : Appearance.colors.colOnSecondaryContainer
    readonly property color shapeColor: root.colorMode === "vibrant"
        ? Appearance.colors.colOnPrimary
        : root.colorMode === "neutral"
            ? Appearance.colors.colSecondaryContainer
            : Appearance.colors.colPrimary
    readonly property color shapeContentColor: root.colorMode === "vibrant"
        ? Appearance.colors.colPrimary
        : root.colorMode === "neutral"
            ? Appearance.colors.colOnSecondaryContainer
            : Appearance.colors.colOnPrimary

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength
    implicitHeight: root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight

    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    RippleButton {
        id: capsule
        anchors.centerIn: parent
        width: root.vertical ? root.thickness : root.animatedLength
        height: root.vertical ? root.animatedLength : root.thickness
        buttonRadius: root.compact
            ? Appearance.rounding.full
            : (Config.options.bar.barGroupStyle === 1
                ? Appearance.rounding.windowRounding
                : Appearance.rounding.full)
        colBackground: root.containerColor
        colBackgroundHover: root.containerHoverColor
        colBackgroundActive: root.containerActiveColor
        colRipple: root.containerActiveColor
        onPressed: GlobalStates.toggleSearchOnly(root.screenName)

        GridLayout {
            id: content
            anchors.centerIn: parent
            columns: root.vertical ? 1 : (root.hasShortcut ? 3 : (root.hasLabel ? 2 : 1))
            rowSpacing: 4
            columnSpacing: 7

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignCenter
                text: "search"
                iconSize: Appearance.font.pixelSize.normal
                padding: 4
                shape: root.activated
                    ? MaterialShape.Shape.Clover4Leaf
                    : MaterialShape.Shape.Cookie9Sided
                color: root.shapeColor
                colSymbol: root.shapeContentColor
            }

            Item {
                visible: root.hasLabel
                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.vertical ? expressiveLabel.height : expressiveLabel.width
                implicitHeight: root.vertical ? expressiveLabel.width : expressiveLabel.height

                StyledText {
                    id: expressiveLabel
                    anchors.centerIn: parent
                    width: root.vertical
                        ? Math.min(implicitWidth, root.verticalLabelMaxLength)
                        : implicitWidth
                    height: root.vertical ? root.thickness - 8 : implicitHeight
                    rotation: root.contentRotation
                    text: root.extended
                        ? Translation.tr("Search everything")
                        : Translation.tr("Search")
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    fontSizeMode: Text.Fit
                    minimumPixelSize: Appearance.font.pixelSize.smallest
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: root.contentColor
                }
            }

            SearchShortcutBadge {
                visible: root.hasShortcut
                Layout.alignment: Qt.AlignCenter
                badgeColor: root.shapeColor
                glyphColor: root.shapeContentColor
            }
        }
    }

    StyledToolTip {
        text: Translation.tr("Open launcher")
        alternativeVisibleCondition: capsule.hovered
        extraVisibleCondition: false
        requireOverlay: false
    }
}
