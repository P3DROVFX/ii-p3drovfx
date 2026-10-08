pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import "WorkspacesCatalog.js" as Catalog

/**
 * The workspace row live on a pretend bar over the wallpaper. The focus tours the
 * workspaces on its own (click a workspace to take over), the windows of the one in
 * focus slide in below, and holding the Super key cap shows the numbers after the
 * configured delay. `caption` names what the pointer is trying on.
 */
Item {
    id: root

    required property WorkspacesPreviewState preview
    property string caption: ""
    property string captionIcon: "visibility"

    readonly property real stageHeight: 248
    readonly property real stageRadius: Appearance.rounding.windowRounding
    readonly property real barHeight: 46
    readonly property real barMargin: 14
    readonly property real unit: 28
    readonly property real groupPadding: 10
    readonly property real wallpaperDim: 0.2
    readonly property real windowWidth: 132
    readonly property real windowHeight: 84
    readonly property real windowGap: 12
    readonly property real windowSlide: 56
    readonly property real controlHeight: 42
    readonly property real chipMargin: 12
    readonly property color barColor: Appearance.colors.colLayer0
    readonly property color groupColor: Appearance.colors.colLayer1

    readonly property var windows: Catalog.DEMO_WINDOWS[root.preview.activeSlot % Catalog.DEMO_WINDOWS.length]
    readonly property string workspaceLabel: Catalog.label(root.preview.numberMap, root.preview.activeSlot)

    implicitHeight: root.stageHeight

    ClippingRectangle {
        anchors.fill: parent
        radius: root.stageRadius
        color: Appearance.colors.colLayer2

        ColorsWallpaperImage {
            anchors.fill: parent
            targetMode: "desktop"
            visible: root.visible
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            opacity: root.wallpaperDim
        }

        Rectangle {
            id: bar
            x: root.barMargin
            y: root.barMargin
            width: parent.width - root.barMargin * 2
            height: root.barHeight
            radius: height / 2
            color: root.barColor

            Row {
                anchors.left: parent.left
                anchors.leftMargin: root.groupPadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: bar.width > group.width + 220

                MaterialShapeWrappedMaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    iconSize: 16
                    padding: 6
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54
                    height: 8
                    radius: 4
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.25
                }
            }

            Rectangle {
                id: group
                anchors.centerIn: parent
                width: strip.implicitWidth + root.groupPadding * 2
                height: parent.height - 8
                radius: height / 2
                color: root.groupColor
                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                WorkspacesLiveStrip {
                    id: strip
                    anchors.centerIn: parent
                    preview: root.preview
                    unit: root.unit
                    barColor: root.groupColor
                    interactive: true
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: root.groupPadding + 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                visible: bar.width > group.width + 220

                Repeater {
                    model: ["wifi", "volume_up", "battery_full"]
                    delegate: MaterialSymbol {
                        required property string modelData
                        text: modelData
                        iconSize: 16
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.6
                    }
                }
            }
        }

        Item {
            id: desk
            anchors.top: bar.bottom
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.controlHeight + root.chipMargin
            width: parent.width

            property real slide: 0
            property real fade: 1

            Connections {
                target: root.preview
                function onActiveSlotChanged() {
                    deskSwitch.from = root.preview.activeSlot > deskSwitch.lastSlot ? root.windowSlide : -root.windowSlide;
                    deskSwitch.lastSlot = root.preview.activeSlot;
                    deskSwitch.restart();
                }
            }

            ParallelAnimation {
                id: deskSwitch
                property real from: 0
                property int lastSlot: 0
                NumberAnimation {
                    target: desk
                    property: "slide"
                    from: deskSwitch.from
                    to: 0
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: desk
                    property: "fade"
                    from: 0
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                }
            }

            Row {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: desk.slide
                spacing: root.windowGap
                opacity: desk.fade

                Repeater {
                    model: root.windows
                    delegate: Rectangle {
                        id: win
                        required property string modelData
                        required property int index
                        readonly property bool beyond: win.index >= root.preview.maxWindows
                        width: root.windowWidth
                        height: root.windowHeight
                        radius: Appearance.rounding.large
                        color: ColorUtils.applyAlpha(Appearance.colors.colSurfaceContainer, 0.92)
                        border.width: win.beyond ? 1 : 0
                        border.color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.6)

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            IconImage {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 30
                                source: Quickshell.iconPath(AppSearch.guessIcon(win.modelData), "image-missing")
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: root.windowWidth - 16
                                text: win.modelData
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        StyledToolTip {
                            visible: win.beyond && winHover.hovered
                            text: Translation.tr("Past the window limit: the bar leaves this one out")
                        }
                        HoverHandler {
                            id: winHover
                        }
                    }
                }

                StyledText {
                    visible: root.windows.length === 0
                    text: Translation.tr("Empty workspace")
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.7
                }
            }
        }

        Rectangle {
            id: tag
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: root.chipMargin
            height: root.controlHeight
            width: Math.min(parent.width - controls.width - root.chipMargin * 3, tagRow.implicitWidth + 28)
            radius: height / 2
            color: root.caption !== "" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on width {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: tagRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                MaterialShapeWrappedMaterialSymbol {
                    text: root.caption !== "" ? root.captionIcon : "tab"
                    iconSize: 15
                    padding: 6
                    fill: 1
                    shape: root.caption !== "" ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Circle
                    color: root.caption !== "" ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: root.caption !== "" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.caption !== "" ? root.caption
                        : Translation.tr("Workspace %1 · %2").arg(root.workspaceLabel).arg(root.windows.length === 1
                            ? Translation.tr("1 window") : Translation.tr("%1 windows").arg(root.windows.length))
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: root.caption !== "" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
            }
        }

        Row {
            id: controls
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: root.chipMargin
            spacing: 6

            WorkspacesKeyCap {
                id: superKey
                height: root.controlHeight
                label: "Super"
                holdDuration: root.preview.numberDelay
                visible: !root.preview.alwaysNumbers && Catalog.style(root.preview.styleId).numbers
                onHeldChanged: root.preview.superHeld = superKey.held
                StyledToolTip {
                    text: Translation.tr("Hold to see the numbers appear after the delay")
                }
            }

            RippleButton {
                implicitWidth: root.controlHeight
                implicitHeight: root.controlHeight
                buttonRadius: root.preview.playing ? height / 2 : Appearance.rounding.normal
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.preview.playing = !root.preview.playing
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.preview.playing ? "pause" : "play_arrow"
                    iconSize: 20
                    fill: 1
                    color: Appearance.colors.colOnSurface
                }
                StyledToolTip {
                    text: root.preview.playing ? Translation.tr("Pause the tour") : Translation.tr("Tour the workspaces")
                }
            }
        }
    }
}
