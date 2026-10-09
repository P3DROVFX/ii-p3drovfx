pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.dock

/**
 * The bar's workspace widget, live, on the wallpaper it sits over.
 *
 * It is the bar's own widget file loaded in a bar-height group, so it reads the same
 * Config and the same Hyprland state: the style, numbers, icons, indicator and colour
 * the page changes show here as they would on the bar. A style can be tried on
 * (`styleOverride`) before it is chosen. Nothing on the stage takes input.
 */
Item {
    id: root

    readonly property real stageMinHeight: 176
    readonly property real stageMaxHeight: 232
    readonly property real stageAspect: 4.4
    readonly property real scrimOpacity: 0.16
    readonly property real groupPadding: 5
    readonly property real groupInset: 4
    readonly property real fillRatio: 0.55
    readonly property real zoomMin: 1
    readonly property real zoomMax: 2
    readonly property real zoomStep: 0.05
    readonly property real edgeMargin: 11
    readonly property real pillPadding: 18
    readonly property real tagGap: 12
    readonly property real compactBreak: 600

    property string styleOverride: ""
    property string tagTitle: ""
    property string tagSubtitle: ""
    property string actionLabel: ""
    property string actionSymbol: ""

    signal actionClicked()

    readonly property string style: root.styleOverride.length > 0
        ? root.styleOverride : (Config.options.bar.styles.workspaces ?? "default")
    readonly property var widgetFiles: ({
        "default": "Workspaces.qml",
        "minimal": "MinimalWorkspaces.qml",
        "expressive": "ExpressiveWorkspaces.qml",
        "dock": "DockWorkspaces.qml",
        "index": "IndexWorkspaces.qml"
    })
    readonly property string widgetSource: Qt.resolvedUrl("../../../ii/bar/widgets/workspaces/"
        + (root.widgetFiles[root.style] ?? root.widgetFiles["default"]))

    readonly property real preferredHeight: Math.max(root.stageMinHeight, Math.min(root.stageMaxHeight, root.width / root.stageAspect))
    readonly property bool compact: root.width < root.compactBreak

    property real liveZoom: {
        const natural = strip.width;
        if (natural <= 0)
            return root.zoomMin;
        const fit = Math.floor(root.width * root.fillRatio / natural / root.zoomStep) * root.zoomStep;
        return Math.max(root.zoomMin, Math.min(root.zoomMax, fit));
    }
    Behavior on liveZoom {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    ClippingRectangle {
        id: backdrop
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer2

        ColorsWallpaperImage {
            anchors.fill: parent
            targetMode: "desktop"
            visible: root.visible
        }
        // Keeps a light wallpaper from swallowing a light bar, and the other way round.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            opacity: root.scrimOpacity
        }

        Item {
            id: strip
            anchors.centerIn: parent
            width: loader.width + root.groupPadding * 2
            height: Appearance.sizes.baseBarHeight
            scale: root.liveZoom

            Rectangle {
                anchors {
                    fill: parent
                    topMargin: root.groupInset
                    bottomMargin: root.groupInset
                }
                radius: Math.min(height / 2, Appearance.rounding.large)
                color: Appearance.colors.colLayer1
            }

            // The widgets carry Qt5Compat effects, which pin a window that is already gone.
            Loader {
                id: loader
                x: root.groupPadding
                anchors.verticalCenter: parent.verticalCenter
                active: root.Window.window !== null
                source: root.widgetSource
                // The preview is always a horizontal strip, whatever the bar does.
                onLoaded: {
                    if (item && item.hasOwnProperty("vertical"))
                        item.vertical = false;
                }
            }
        }

        DockInputShield {}
    }

    // Name tag: the page's name over what it currently shows.
    Rectangle {
        id: tag
        x: root.edgeMargin
        y: root.height - height - root.edgeMargin
        height: tagColumn.implicitHeight + 12
        width: Math.min(root.width - action.width - root.edgeMargin * 2 - root.tagGap,
                        tagColumn.implicitWidth + root.pillPadding * 2)
        radius: Math.min(height / 2, Appearance.rounding.large)
        color: Appearance.colors.colSurfaceContainerHigh

        ColumnLayout {
            id: tagColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: root.pillPadding
                rightMargin: root.pillPadding
            }
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.tagTitle
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.tagSubtitle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }

    // Status: this is the real bar widget, not a drawing of it.
    Rectangle {
        id: status
        x: root.edgeMargin
        y: root.edgeMargin
        height: statusRow.implicitHeight + 12
        width: statusRow.implicitWidth + root.pillPadding * 1.5
        radius: height / 2
        color: Appearance.colors.colSurfaceContainerHigh

        RowLayout {
            id: statusRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                implicitWidth: 7
                implicitHeight: 7
                radius: 3.5
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: Translation.tr("Live")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }
        }
    }

    // The page's main action: same height as the tag, same edge.
    RippleButton {
        id: action
        anchors {
            right: parent.right
            rightMargin: root.edgeMargin
        }
        y: tag.y
        implicitHeight: tag.height
        implicitWidth: root.compact ? tag.height : actionRow.implicitWidth + root.pillPadding * 2
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.small
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        onClicked: root.actionClicked()

        StyledToolTip {
            visible: root.compact && action.hovered
            text: root.actionLabel
        }

        contentItem: Item {
            RowLayout {
                id: actionRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: root.actionSymbol
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
                StyledText {
                    visible: !root.compact
                    text: root.actionLabel
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
