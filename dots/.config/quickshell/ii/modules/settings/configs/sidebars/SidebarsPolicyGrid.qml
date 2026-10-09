pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * Every tab of the policies sidebar as a feature tile. A tab with a third state (AI local
 * only, Weeb in the closet) keeps it as a chip on the tile: the switch is shown / hidden,
 * the chip picks the variant. Exposes how many tabs are shown for the hero.
 */
Item {
    id: root

    readonly property int gap: 12
    readonly property real tileMin: 280
    readonly property int tileHeight: 200
    readonly property string hidden: Translation.tr("Not shown in the sidebar")
    readonly property var policies: [
        {
            key: "ai",
            symbol: "smart_toy",
            shape: MaterialShape.Shape.Cookie12Sided,
            title: Translation.tr("AI"),
            summaries: [root.hidden, Translation.tr("Chat with cloud models"), Translation.tr("Chat with local models only")],
            alt: { label: Translation.tr("Local only"), symbol: "sync_saved_locally" }
        },
        {
            key: "weeb",
            symbol: "face",
            shape: MaterialShape.Shape.Flower,
            title: Translation.tr("Weeb"),
            summaries: [root.hidden, Translation.tr("Anime image browser"), Translation.tr("Tucked away in the closet")],
            alt: { label: Translation.tr("Closet"), symbol: "ev_shadow" }
        },
        {
            key: "wallpapers",
            symbol: "wallpaper",
            shape: MaterialShape.Shape.SoftBurst,
            title: Translation.tr("Wallpaper browser"),
            summaries: [root.hidden, Translation.tr("Browse and set wallpapers")]
        },
        {
            key: "translator",
            symbol: "translate",
            shape: MaterialShape.Shape.Clover4Leaf,
            title: Translation.tr("Translator"),
            summaries: [root.hidden, Translation.tr("Translate text without leaving the desktop")]
        },
        {
            key: "player",
            symbol: "music_note",
            shape: MaterialShape.Shape.Cookie7Sided,
            title: Translation.tr("Sidebar player"),
            summaries: [root.hidden, Translation.tr("What is playing, with its controls")]
        },
        {
            key: "phone",
            symbol: "smartphone",
            shape: MaterialShape.Shape.Cookie4Sided,
            title: Translation.tr("Phone"),
            summaries: [root.hidden, Translation.tr("Mirror and control your connected phone")]
        }
    ]

    readonly property var levels: ({
        "ai": Config.options.policies.ai,
        "weeb": Config.options.policies.weeb,
        "wallpapers": Config.options.policies.wallpapers,
        "translator": Config.options.policies.translator,
        "player": Config.options.policies.player,
        "phone": Config.options.policies.phone
    })
    readonly property int total: root.policies.length
    readonly property int shown: root.policies.filter(policy => root.levels[policy.key] !== 0).length

    // Six tiles: three across, two across or a column, never a lone straggler.
    readonly property int fits: Math.max(1, Math.floor((width + root.gap) / (root.tileMin + root.gap)))
    readonly property int columns: root.fits >= 3 ? 3 : root.fits >= 2 ? 2 : 1
    readonly property int tileWidth: Math.floor((width - root.gap * (root.columns - 1)) / root.columns)

    Layout.fillWidth: true
    implicitHeight: flow.implicitHeight

    Flow {
        id: flow
        width: parent.width
        spacing: root.gap

        Repeater {
            model: root.policies

            delegate: ColorsFeatureTile {
                id: tile

                required property var modelData
                readonly property int level: root.levels[tile.modelData.key] ?? 0

                width: root.tileWidth
                height: root.tileHeight
                symbol: tile.modelData.symbol
                shapeOn: tile.modelData.shape
                title: tile.modelData.title
                summary: tile.modelData.summaries[Math.min(tile.level, tile.modelData.summaries.length - 1)]
                checked: tile.level !== 0
                onToggled: value => Config.options.policies[tile.modelData.key] = value ? 1 : 0

                ColorsChip {
                    visible: tile.modelData.alt !== undefined
                    enabled: tile.checked
                    label: tile.modelData.alt?.label ?? ""
                    symbol: tile.modelData.alt?.symbol ?? ""
                    chosen: tile.level === 2
                    colContent: tile.colContent
                    colChosen: Appearance.colors.colPrimary
                    colOnChosen: Appearance.colors.colOnPrimary
                    onClicked: Config.options.policies[tile.modelData.key] = chosen ? 1 : 2
                }
            }
        }
    }
}
