import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode

/**
 * The desktop menu's "Colors & themes" page: every scheme Settings offers in
 * one three-column grid - the ones generated from the wallpaper first, then
 * the built-in themes, then any custom ones the config lists - with the
 * light/dark pair pinned under it so the mode is never scrolled away.
 *
 * The swatches are Settings' own ColorPreviewButton and the pair is Settings'
 * ConfigLightDarkToggle, so a click here does exactly what it does there.
 * The grid is built here rather than stacked from three ColorPreviewGrids:
 * each of those ends its own last row, and the wallpaper set (eleven) would
 * leave a hole before the built-in themes start.
 */
ColumnLayout {
    id: root

    signal backRequested()

    spacing: 8

    // The page change, 0 -> 1, driven by the card. Each block takes its own
    // slice so the header, the grid and the mode pair arrive a step apart.
    property real reveal: 1
    function slice(index: int): real {
        const t = (root.reveal - index * 0.14) / 0.72;
        return Math.max(0, Math.min(1, t));
    }

    // The palette under the pointer names itself in the title.
    property string hoveredName: ""

    readonly property list<string> wallpaperSchemes: ["scheme-auto", "scheme-content", "scheme-tonal-spot", "scheme-fidelity", "scheme-intense", "scheme-vibrant", "scheme-fruit-salad", "scheme-expressive", "scheme-rainbow", "scheme-neutral", "scheme-monochrome"]
    readonly property list<string> builtInSchemes: ["angel_light", "angel", "ayu", "cobalt2", "cursor", "dracula", "flexoki", "frappe", "github", "gruvbox", "kanagawa", "latte", "macchiato", "material_ocean", "matrix", "mercury", "mocha", "nord", "nothing_os", "open_code", "orng", "osaka_jade", "rose_pine", "sakura", "samurai", "synthwave84", "vercel", "vesper", "zen_burn", "zen_garden"]
    readonly property var customSchemes: Config.options.appearance.customColorSchemes ?? []

    readonly property var schemes: {
        const list = root.wallpaperSchemes.map(s => ({ "scheme": s, "kind": "wallpaper" }));
        for (const s of root.builtInSchemes)
            list.push({ "scheme": s, "kind": "builtin" });
        for (const s of root.customSchemes)
            list.push({ "scheme": String(s), "kind": "custom" });
        return list;
    }

    function displayName(entry) {
        const text = entry.kind === "wallpaper" ? entry.scheme.split("-").slice(1).join(" ") : entry.scheme;
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    // Three and a half rows on show: the half row says there is more.
    readonly property real cellHeight: 64
    readonly property real cellSpacing: 4
    readonly property real gridViewportHeight: root.cellHeight * 3.5 + root.cellSpacing * 3

    // ── Header ───────────────────────────────────────────────────────────────
    EditMenuPageHeader {
        title: root.hoveredName !== "" ? root.hoveredName : Translation.tr("Colors & themes")
        opacity: root.slice(0)
        transform: Translate { x: (1 - root.slice(0)) * 16 }
        onBackRequested: root.backRequested()
    }

    // ── Swatches ─────────────────────────────────────────────────────────────
    // The swatches sit on a well of their own, the grid inset from its edge.
    Rectangle {
        id: gridWell
        readonly property real inset: 6
        Layout.fillWidth: true
        Layout.preferredHeight: root.gridViewportHeight + gridWell.inset * 2
        radius: Math.max(Appearance.rounding.verysmall, Appearance.rounding.windowRounding - 8)
        color: Appearance.colors.colLayer1
        opacity: root.slice(1)
        transform: Translate { x: (1 - root.slice(1)) * 16 }

        StyledFlickable {
            id: flick
            anchors.fill: parent
            anchors.margins: gridWell.inset
            contentHeight: grid.implicitHeight
            clip: true

            GridLayout {
                id: grid
                width: flick.width
                columns: 3
                rowSpacing: root.cellSpacing
                columnSpacing: root.cellSpacing

                // A few ticks for the whole grid, as ColorPreviewGrid does:
                // swatches read shared caches, and fifty at once on the frame
                // the page opens is a hitch the card's own motion would show.
                property int loadedCount: 0

                Repeater {
                    model: root.schemes

                    delegate: ColorPreviewButton {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.cellHeight
                        colorScheme: modelData.scheme
                        colorSchemeDisplayName: root.displayName(modelData)
                        builtInTheme: modelData.kind === "builtin"
                        customTheme: modelData.kind === "custom"
                        shouldLoad: index < grid.loadedCount
                        onHoveredChanged: {
                            if (hovered)
                                root.hoveredName = colorSchemeDisplayName;
                            else if (root.hoveredName === colorSchemeDisplayName)
                                root.hoveredName = "";
                        }
                    }
                }

                Timer {
                    id: loadTimer
                    interval: 20
                    repeat: true
                    onTriggered: {
                        grid.loadedCount += Math.max(1, Math.ceil(root.schemes.length / 4));
                        if (grid.loadedCount >= root.schemes.length)
                            loadTimer.stop();
                    }
                }
                Component.onCompleted: Qt.callLater(() => loadTimer.start())
            }
        }
    }

    // ── Mode, pinned ─────────────────────────────────────────────────────────
    ConfigLightDarkToggle {
        Layout.fillWidth: true
        opacity: root.slice(2)
        transform: Translate { x: (1 - root.slice(2)) * 16 }
    }
}
