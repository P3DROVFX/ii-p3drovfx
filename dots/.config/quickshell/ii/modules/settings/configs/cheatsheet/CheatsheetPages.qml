pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * Every page the cheatsheet can hold. The two that carry an account or a schedule
 * (Timetable, Email) are feature tiles with a live summary; the reference pages are
 * compact toggle rows. Exposes `pages` (Keybinds included, always on) for the hero's rail.
 */
Item {
    id: root

    readonly property int gap: 12
    // ContentSection's own spacing: what a block needs on top of it to sit one gap away.
    readonly property real sectionSpacing: 4
    readonly property real tileMin: 300
    readonly property int tileHeight: 160
    readonly property real rowMin: 300
    readonly property string hidden: Translation.tr("Hidden from the cheatsheet")

    readonly property var featured: [
        {
            key: "enableTimetable",
            symbol: "calendar_month",
            shape: MaterialShape.Shape.Cookie12Sided,
            name: Translation.tr("Timetable"),
            summary: Translation.tr("Weekly and monthly calendar with events, alarms and sports")
        },
        {
            key: "enableGmail",
            symbol: "mail",
            shape: MaterialShape.Shape.Flower,
            name: Translation.tr("Email"),
            summary: Translation.tr("Unread Gmail messages, right in the cheatsheet")
        }
    ]
    readonly property var compact: [
        {
            key: "enablePeriodicTable",
            symbol: "experiment",
            shape: MaterialShape.Shape.Cookie6Sided,
            name: Translation.tr("Elements"),
            summary: Translation.tr("Interactive periodic table")
        },
        {
            key: "enableAminoAcids",
            symbol: "biotech",
            shape: MaterialShape.Shape.Clover4Leaf,
            name: Translation.tr("Amino acids"),
            summary: Translation.tr("Structures and side-chain classes")
        },
        {
            key: "enableCommands",
            symbol: "terminal",
            shape: MaterialShape.Shape.Cookie7Sided,
            name: Translation.tr("Commands"),
            summary: Translation.tr("Terminal commands reference")
        },
        {
            key: "enableWorkspaceProfiles",
            symbol: "dashboard",
            shape: MaterialShape.Shape.SoftBurst,
            name: Translation.tr("Workspaces"),
            summary: Translation.tr("Profiles, layouts and monitors")
        },
        {
            key: "enableTypingTest",
            symbol: "speed",
            shape: MaterialShape.Shape.Cookie4Sided,
            name: Translation.tr("Typing test"),
            summary: Translation.tr("Offline test with score history")
        },
        {
            key: "enableDevTools",
            symbol: "handyman",
            shape: MaterialShape.Shape.Cookie9Sided,
            name: Translation.tr("Dev tools"),
            summary: Translation.tr("Generators, encoders and converters")
        }
    ]

    readonly property var enabledMap: ({
        "enableTimetable": Config.options.cheatsheet.enableTimetable,
        "enableGmail": Config.options.cheatsheet.enableGmail,
        "enablePeriodicTable": Config.options.cheatsheet.enablePeriodicTable,
        "enableAminoAcids": Config.options.cheatsheet.enableAminoAcids,
        "enableCommands": Config.options.cheatsheet.enableCommands,
        "enableWorkspaceProfiles": Config.options.cheatsheet.enableWorkspaceProfiles,
        "enableTypingTest": Config.options.cheatsheet.enableTypingTest,
        "enableDevTools": Config.options.cheatsheet.enableDevTools
    })
    // In the order of the cheatsheet's own tab bar.
    readonly property var pages: {
        const entry = page => ({ key: page.key, symbol: page.symbol, name: page.name, enabled: root.enabledMap[page.key] === true });
        const [timetable, email] = root.featured;
        return [entry(timetable), { key: "", symbol: "keyboard", name: Translation.tr("Keybinds"), enabled: true }]
            .concat(root.compact.slice(0, 4).map(entry), [entry(email)], root.compact.slice(4).map(entry));
    }

    readonly property int tileColumns: Math.floor((width + root.gap) / (root.tileMin + root.gap)) >= 2 ? 2 : 1
    readonly property int tileWidth: Math.floor((width - root.gap * (root.tileColumns - 1)) / root.tileColumns)
    // Six rows: three across, two across or a column, never a lone straggler.
    readonly property int rowFits: Math.max(1, Math.floor((width + root.gap) / (root.rowMin + root.gap)))
    readonly property int rowColumns: root.rowFits >= 3 ? 3 : root.rowFits >= 2 ? 2 : 1
    readonly property int rowWidth: Math.floor((width - root.gap * (root.rowColumns - 1)) / root.rowColumns)

    Layout.fillWidth: true
    Layout.topMargin: root.gap - root.sectionSpacing
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        width: parent.width
        spacing: root.gap

        Flow {
            Layout.fillWidth: true
            spacing: root.gap

            Repeater {
                model: root.featured

                delegate: ColorsFeatureTile {
                    id: tile

                    required property var modelData

                    width: root.tileWidth
                    height: root.tileHeight
                    symbol: tile.modelData.symbol
                    shapeOn: tile.modelData.shape
                    title: tile.modelData.name
                    summary: tile.checked ? tile.modelData.summary : root.hidden
                    checked: root.enabledMap[tile.modelData.key] === true
                    onToggled: value => Config.options.cheatsheet[tile.modelData.key] = value
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: root.gap

            Repeater {
                model: root.compact

                delegate: CheatsheetPageToggle {
                    id: row

                    required property var modelData

                    width: root.rowWidth
                    symbol: row.modelData.symbol
                    shapeOn: row.modelData.shape
                    title: row.modelData.name
                    summary: row.modelData.summary
                    checked: root.enabledMap[row.modelData.key] === true
                    onToggled: value => Config.options.cheatsheet[row.modelData.key] = value
                }
            }
        }
    }
}
