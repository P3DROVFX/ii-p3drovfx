pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root

    property bool vertical: false
    property color onActivatedColor: Appearance.colors.colOnPrimary

    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    readonly property string sizeMode: Config.options.bar.searchWidget.sizeMode ?? "compact"
    readonly property bool compact: root.sizeMode === "compact"
    readonly property bool extended: root.sizeMode === "extended"
    readonly property bool hasLabel: !root.compact
    readonly property bool hasShortcut: root.extended
        && (Config.options.bar.searchWidget.showShortcutHint ?? true)
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property int contentRotation: root.vertical
        ? (Config.options.bar.bottom ? 90 : -90)
        : 0
    readonly property real verticalLabelMaxLength: Appearance.sizes.verticalBarWidth
        * (root.extended ? 3 : 2)
    readonly property bool activated: GlobalStates.overviewOpen
        && GlobalStates.searchOnlyMode
        && (root.screenName === "" || GlobalStates.activeSearchMonitor === root.screenName)

    implicitWidth: root.vertical
        ? root.thickness
        : Math.max(root.thickness, content.implicitWidth + 10)
    implicitHeight: root.vertical
        ? Math.max(root.thickness, content.implicitHeight + 10)
        : root.thickness

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onPressed: GlobalStates.toggleSearchOnly(root.screenName)

    contentItem: Item {
        GridLayout {
            id: content
            anchors.centerIn: parent
            columns: root.vertical ? 1 : (root.hasShortcut ? 3 : (root.hasLabel ? 2 : 1))
            rowSpacing: 3
            columnSpacing: 6

            MaterialSymbol {
                Layout.alignment: Qt.AlignCenter
                text: "search"
                iconSize: Appearance.font.pixelSize.larger
                color: root.activated
                    ? root.onActivatedColor
                    : Appearance.colors.colOnLayer0
            }

            Item {
                visible: root.hasLabel
                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.vertical ? searchLabel.height : searchLabel.width
                implicitHeight: root.vertical ? searchLabel.width : searchLabel.height

                StyledText {
                    id: searchLabel
                    anchors.centerIn: parent
                    width: root.vertical
                        ? Math.min(implicitWidth, root.verticalLabelMaxLength)
                        : implicitWidth
                    height: root.vertical ? root.thickness - 8 : implicitHeight
                    rotation: root.contentRotation
                    text: root.extended
                        ? Translation.tr("Search apps")
                        : Translation.tr("Search")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    fontSizeMode: Text.Fit
                    minimumPixelSize: Appearance.font.pixelSize.smallest
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: root.activated
                        ? root.onActivatedColor
                        : Appearance.colors.colOnLayer0
                }
            }

            SearchShortcutBadge {
                visible: root.hasShortcut
                Layout.alignment: Qt.AlignCenter
                badgeColor: Appearance.colors.colLayer2
                glyphColor: Appearance.colors.colOnLayer2
            }
        }
    }

    StyledToolTip {
        text: Translation.tr("Open launcher")
        alternativeVisibleCondition: root.hovered
        extraVisibleCondition: false
        requireOverlay: false
    }
}
