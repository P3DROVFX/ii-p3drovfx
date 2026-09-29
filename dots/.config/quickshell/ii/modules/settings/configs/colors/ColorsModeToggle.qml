import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Light / dark as an M3 Expressive connected button group: two segments joined by
 * small inner corners; the current one fills with primary and rounds into a pill,
 * and its icon sits in a shape that morphs (circle → sun or scalloped moon).
 */
RowLayout {
    id: root

    property real segmentHeight: 48

    spacing: 3

    function setDark(dark: bool) {
        if (Appearance.m3colors.darkmode === dark)
            return;
        const background = Config.options?.background;
        if (background?.useSeparateLightModeWallpaper) {
            const path = dark ? background.wallpaperPath : background.lightModeWallpaperPath;
            if (path && path !== "") {
                if (dark)
                    Wallpapers.apply(path, true);
                else
                    Wallpapers.applyLightModeWallpaper(path);
                return;
            }
        }
        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
    }

    Segment {
        dark: false
        first: true
        symbol: "light_mode"
        label: Translation.tr("Light")
        activeShape: MaterialShape.Shape.Sunny
    }

    Segment {
        dark: true
        first: false
        symbol: "dark_mode"
        label: Translation.tr("Dark")
        activeShape: MaterialShape.Shape.Cookie9Sided
    }

    component Segment: RippleButton {
        id: segment

        required property bool dark
        required property bool first
        required property string symbol
        required property string label
        required property var activeShape

        readonly property bool current: Appearance.m3colors.darkmode === segment.dark
        readonly property real outer: Math.min(height / 2, Appearance.rounding.full)
        // Animated here rather than on the corners: RippleButton already owns a
        // Behavior on each corner radius.
        property real inner: segment.current ? segment.outer : Appearance.rounding.verysmall
        Behavior on inner {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        readonly property color colContent: segment.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitWidth: segmentRow.implicitWidth + 36
        implicitHeight: root.segmentHeight

        topLeftRadius: segment.first ? segment.outer : segment.inner
        bottomLeftRadius: segment.first ? segment.outer : segment.inner
        topRightRadius: segment.first ? segment.inner : segment.outer
        bottomRightRadius: segment.first ? segment.inner : segment.outer

        toggled: segment.current
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: root.setDark(segment.dark)

        contentItem: Item {
            RowLayout {
                id: segmentRow
                anchors.centerIn: parent
                spacing: 8

                MaterialShapeWrappedMaterialSymbol {
                    text: segment.symbol
                    iconSize: 18
                    padding: 5
                    fill: segment.current ? 1 : 0
                    shape: segment.current ? segment.activeShape : MaterialShape.Shape.Circle
                    color: segment.current ? Appearance.colors.colOnPrimary : "transparent"
                    colSymbol: segment.current ? Appearance.colors.colPrimary : segment.colContent
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    text: segment.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: segment.colContent
                }
            }
        }
    }
}
