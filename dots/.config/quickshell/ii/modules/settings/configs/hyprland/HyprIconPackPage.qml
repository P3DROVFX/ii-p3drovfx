pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Pick the icon pack.
 *
 * Packs are found the way icon lookup finds them - ~/.icons, then the data home, then
 * /usr/share/icons - and the first pack of a given name wins. Only real icon packs are listed:
 * a theme whose index.theme declares no icon directories is a cursor theme, and has its own
 * page.
 *
 * When themed icons are on, the desktop draws with DynamicTheme, a recolored copy of a base
 * pack. Picking here then changes the base and rebuilds the copy, so the choice still shows -
 * it just arrives wearing the wallpaper's colors.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    property string rawQuery: ""
    readonly property string query: subPageRoot.rawQuery.trim().toLowerCase()

    function matchesPack(pack: var): bool {
        return subPageRoot.query === ""
            || pack.title.toLowerCase().indexOf(subPageRoot.query) >= 0
            || pack.name.toLowerCase().indexOf(subPageRoot.query) >= 0;
    }

    /// Only for the empty-state text: the rows themselves hide rather than being rebuilt on
    /// every letter typed into the search box.
    readonly property int matchCount: Array.from(IconThemes.packs)
        .filter(pack => subPageRoot.matchesPack(pack)).length

    /// Fresh from disk each time the picker opens, so a pack installed since the shell
    /// started still shows up.
    Component.onCompleted: IconThemes.refreshPacks()

    function shortDir(dir: string): string {
        const home = FileUtils.trimFileProtocol(String(Directories.home ?? ""));
        return home !== "" && dir.startsWith(home) ? "~" + dir.slice(home.length) : dir;
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Icon pack")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: IconThemes.themed
                        ? Translation.tr("Becomes the base the shell recolors.")
                        : Translation.tr("Changes as soon as you pick one.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        ContentSection {
            title: Translation.tr("Installed icon packs")
            icon: "apps"

            ConfigSwitch {
                buttonIcon: "magic_button"
                text: Translation.tr("Recolor the pack to match the wallpaper")
                checked: IconThemes.themed
                onCheckedChanged: IconThemes.setThemed(checked)

                StyledToolTip {
                    text: Translation.tr("On, the desktop draws with a copy of the pack, recolored to the wallpaper's palette. Off, the pack is used exactly as it ships.")
                }
            }

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search icon packs")
                onTextChanged: subPageRoot.rawQuery = text
            }

            StyledText {
                Layout.fillWidth: true
                visible: IconThemes.packsReady && subPageRoot.matchCount === 0
                text: IconThemes.packs.length === 0
                    ? Translation.tr("No icon packs were found. They live in ~/.icons, ~/.local/share/icons or /usr/share/icons, in a folder holding an index.theme that lists icon directories.")
                    : Translation.tr("Nothing matches \"%1\".").arg(subPageRoot.rawQuery.trim())
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: IconThemes.packs

                delegate: PackRow {
                    required property var modelData

                    visible: subPageRoot.matchesPack(modelData)
                    pack: modelData
                }
            }

            HyprOptionNote {
                notes: {
                    const out = [];
                    if (IconThemes.themed)
                        out.push({ "icon": "magic_button", "text": Translation.tr("Recoloring is on, so the pack you pick becomes the base of the wallpaper-colored copy the desktop draws with. Flip the switch above to use packs as they ship.") });
                    out.push({ "icon": "bolt", "text": Translation.tr("Picking one updates GTK, KDE and this shell together. Most running apps follow at once; the stubborn ones keep their old icons until restarted.") });
                    return out;
                }
            }
        }
    }

    component PackRow: RippleButton {
        id: packRow

        required property var pack

        readonly property bool current: packRow.pack.name === IconThemes.currentPack

        Layout.fillWidth: true
        implicitHeight: packLayout.implicitHeight + 20
        useDynamicRadius: true

        colBackground: packRow.current ? Appearance.colors.colSecondaryContainer
            : Appearance.colors.colLayer2
        colBackgroundHover: packRow.current ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: packRow.current ? Appearance.colors.colSecondaryContainerActive
            : Appearance.colors.colLayer2Active

        onClicked: IconThemes.applyPack(packRow.pack.name)

        contentItem: Item {
            anchors.fill: parent

            RowLayout {
                id: packLayout
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: packRow.pack.title
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: packRow.current ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const parts = [];
                            if (packRow.pack.title !== packRow.pack.name) parts.push(packRow.pack.name);
                            if (!packRow.pack.hasApps) parts.push(Translation.tr("no app icons"));
                            if (packRow.pack.inherits !== "")
                                parts.push(Translation.tr("based on %1").arg(packRow.pack.inherits));
                            parts.push(subPageRoot.shortDir(packRow.pack.dir));
                            return parts.join(" · ");
                        }
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: packRow.current
                    text: "check"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }
}
