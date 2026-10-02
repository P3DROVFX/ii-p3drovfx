import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * A Material shape carrying a glyph: the badge of a preset, an effect, a device or a
 * section. The glyph is half the badge, whatever its size, so every badge in the app has
 * the same proportions. Swap `shape` to morph it (hover, "in use"); it never spins.
 */
MaterialShapeWrappedMaterialSymbol {
    id: root

    /// Width and height of the badge.
    property real size: EasyEffectsStyle.deviceColumnBadge

    iconSize: Math.round(root.size * 0.5)
    padding: (root.size - root.iconSize) / 2
    fill: 1
    color: EasyEffectsStyle.colSecondaryContainer
    colSymbol: EasyEffectsStyle.colOnSecondaryContainer
}
