pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Pick the pointer.
 *
 * Themes are found the way XCursor finds them - XCURSOR_PATH, then ~/.icons, then the data home,
 * then /usr/share/icons - and the first theme of a given name wins, which is what would really
 * happen. Bibata-Modern-Classic exists three times over on this machine and only one of them is
 * ever used, so listing all three would be a lie.
 *
 * There is no picture of the cursor here. XCursor files are a binary image format and hyprcursor
 * ships compressed archives; neither is something QML can draw. Choosing one applies it
 * immediately instead, which is a better preview than a thumbnail would be.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    property string rawQuery: ""
    readonly property string query: subPageRoot.rawQuery.trim().toLowerCase()

    function matchesTheme(theme: var): bool {
        return subPageRoot.query === ""
            || theme.title.toLowerCase().indexOf(subPageRoot.query) >= 0
            || theme.name.toLowerCase().indexOf(subPageRoot.query) >= 0;
    }

    /// Only for the empty-state text: the rows themselves hide rather than being rebuilt on
    /// every letter typed into the search box.
    readonly property int matchCount: Array.from(HyprlandEnv.themes)
        .filter(theme => subPageRoot.matchesTheme(theme)).length

    /// Fresh from disk each time the picker opens, so a theme installed since the shell
    /// started still shows up - the walk no longer runs on every config reload.
    Component.onCompleted: HyprlandEnv.refreshThemes()

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
                    text: Translation.tr("Cursor theme")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Changes as soon as you pick one.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        ContentSection {
            title: Translation.tr("Installed themes")
            icon: "arrow_selector_tool"

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search themes")
                onTextChanged: subPageRoot.rawQuery = text
            }

            StyledText {
                Layout.fillWidth: true
                visible: HyprlandEnv.themesReady && subPageRoot.matchCount === 0
                text: HyprlandEnv.themes.length === 0
                    ? Translation.tr("No cursor themes were found. They live in ~/.icons, ~/.local/share/icons or /usr/share/icons, in a folder holding a cursors or hyprcursors directory.")
                    : Translation.tr("Nothing matches \"%1\".").arg(subPageRoot.rawQuery.trim())
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: HyprlandEnv.themes

                delegate: ThemeRow {
                    required property var modelData

                    visible: subPageRoot.matchesTheme(modelData)
                    theme: modelData
                }
            }

            HyprOptionNote {
                notes: [
                    { "icon": "bolt", "text": Translation.tr("Picking one tells the compositor straight away and brings every other copy of the setting along: GTK, KDE apps, the X11 fallback Steam reads, and flatpaks. With xsettingsd installed, running X11 apps follow at once; the rest keep the old pointer until they are restarted.") },
                    { "icon": "layers", "text": Translation.tr("A theme with both formats is drawn by hyprcursor, which scales without blurring. X11 windows always use the older format.") }
                ]
            }
        }
    }

    component ThemeRow: RippleButton {
        id: themeRow

        required property var theme

        readonly property bool current: themeRow.theme.name === HyprlandEnv.cursorTheme

        Layout.fillWidth: true
        implicitHeight: themeLayout.implicitHeight + 20
        useDynamicRadius: true

        colBackground: themeRow.current ? Appearance.colors.colSecondaryContainer
            : Appearance.colors.colLayer2
        colBackgroundHover: themeRow.current ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: themeRow.current ? Appearance.colors.colSecondaryContainerActive
            : Appearance.colors.colLayer2Active

        onClicked: HyprlandEnv.applyCursor(themeRow.theme.name, HyprlandEnv.cursorSize)

        contentItem: Item {
            anchors.fill: parent

            RowLayout {
                id: themeLayout
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
                        text: themeRow.theme.title
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: themeRow.current ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const parts = [];
                            if (themeRow.theme.title !== themeRow.theme.name) parts.push(themeRow.theme.name);
                            parts.push(themeRow.theme.hypr && themeRow.theme.xcursor
                                ? Translation.tr("hyprcursor and X11")
                                : (themeRow.theme.hypr ? Translation.tr("hyprcursor only")
                                    : Translation.tr("X11 only")));
                            if (themeRow.theme.shapes > 0)
                                parts.push(Translation.tr("%1 shapes").arg(themeRow.theme.shapes));
                            parts.push(subPageRoot.shortDir(themeRow.theme.dir));
                            return parts.join(" · ");
                        }
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: themeRow.current
                    text: "check"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }
}
