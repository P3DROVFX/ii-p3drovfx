import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The colour scheme, as a page of Edit Mode's panel: the same swatch grid the
 * Welcome and the Colours page draw, fed the wallpaper on the card. A click
 * regenerates the palette and the whole shell follows, the card included.
 *
 * Three sources, as Settings has them: schemes derived from the wallpaper,
 * the built-in themes, and any custom ones the config lists. Only the last is
 * hidden when there are none - a chip for an empty grid is a promise.
 */
StyledFlickable {
    id: root

    contentHeight: column.implicitHeight
    clip: true

    property string source: "wallpaper"
    readonly property var customSchemes: Config.options.appearance.customColorSchemes ?? []

    ColumnLayout {
        id: column
        width: root.width
        spacing: 4

        EditOptionChips {
            label: Translation.tr("Source")
            compact: false
            currentValue: root.source
            options: {
                const list = [
                    { "displayName": Translation.tr("Wallpaper"), "icon": "wallpaper", "value": "wallpaper" },
                    { "displayName": Translation.tr("Built-in"), "icon": "palette", "value": "builtin" }
                ];
                if (root.customSchemes.length > 0)
                    list.push({ "displayName": Translation.tr("Custom"), "icon": "brush", "value": "custom" });
                return list;
            }
            onSelected: value => root.source = value
        }

        EditPanelNotice {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: root.source === "wallpaper" && (Config.options.background.useWallpaperEngine ?? false)
            symbol: "info"
            text: Translation.tr("With a Wallpaper Engine scene the swatches are drawn from the last image wallpaper.")
        }

        ColorPreviewGrid {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            builtInTheme: root.source === "builtin"
            customTheme: root.source === "custom"
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
