import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Which media player the shell follows: a pinned app, and whether music apps
 * win over browsers and phone bridges.
 *
 * The pin used to be a free-text field that had to hold the player's desktop
 * entry exactly, which nobody could guess. Here the running players are listed
 * as they are, an installed app can be found by name before it runs, and the
 * stored value is whatever `MprisController.playerKey` answers for it — the
 * controller matches it leniently, so older hand-typed values keep working.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 8

    readonly property string pinnedKey: Config.options.media.priorityPlayer
    readonly property string query: searchField.text.trim()

    function sameKey(a, b) {
        return String(a ?? "").toLowerCase() === String(b ?? "").toLowerCase();
    }

    function iconFor(player) {
        const entry = player.desktopEntry ? DesktopEntries.heuristicLookup(player.desktopEntry) : null;
        return entry?.icon || player.desktopEntry || AppSearch.guessIcon(player.identity ?? "");
    }

    // Live D-Bus list rather than `applicationPlayers`, which only refreshes
    // every ten seconds: a player that just started should be pickable now.
    readonly property var runningPlayers: Mpris.players.values.filter(player =>
        MprisController.isRealPlayer(player) && !MprisController.isLocalPlayer(player))

    readonly property var candidates: {
        const result = [];
        const taken = [];
        const add = item => {
            const lower = item.key.toLowerCase();
            if (item.key === "" || taken.indexOf(lower) !== -1)
                return;
            taken.push(lower);
            result.push(item);
        };

        let pinnedRunning = false;
        for (const player of root.runningPlayers) {
            const key = MprisController.playerKey(player);
            const pinned = MprisController.playerMatchesKey(player, root.pinnedKey);
            pinnedRunning = pinnedRunning || pinned;
            const music = MprisController.isMusicPlayer(player);
            const state = player.isPlaying ? Translation.tr("Playing") : Translation.tr("Paused");
            add({
                key: pinned ? root.pinnedKey : key,
                name: player.identity || key,
                icon: root.iconFor(player),
                detail: music ? Translation.tr("%1 · Music app").arg(state) : state
            });
        }

        if (root.pinnedKey !== "" && !pinnedRunning) {
            const entry = DesktopEntries.heuristicLookup(root.pinnedKey);
            add({
                key: root.pinnedKey,
                name: entry?.name || root.pinnedKey,
                icon: entry?.icon || AppSearch.guessIcon(root.pinnedKey),
                detail: Translation.tr("Not running")
            });
        }

        if (root.query !== "") {
            for (const entry of AppSearch.fuzzyQuery(root.query).slice(0, 6)) {
                add({
                    key: entry.id || entry.name,
                    name: entry.name,
                    icon: entry.icon,
                    detail: Translation.tr("Installed app")
                });
            }
        }
        return result;
    }

    ConfigSwitch {
        buttonIcon: "library_music"
        text: Translation.tr("Prefer music apps")
        checked: Config.options.media.preferMusicPlayers
        onCheckedChanged: Config.options.media.preferMusicPlayers = checked
        StyledToolTip {
            text: Translation.tr("Spotify, YouTube Music and local music players stay in charge of the media controls over browsers, KDE Connect and video players")
        }
    }

    ContentSubsectionLabel {
        text: Translation.tr("Pinned player")
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("A pinned player stays in the bar and media controls while it runs, even when another app starts playing.")
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        PlayerRow {
            playerKey: ""
            name: Translation.tr("Automatic")
            detail: Translation.tr("Follow the player that played last")
            symbol: "auto_mode"
        }

        Repeater {
            model: root.candidates
            delegate: PlayerRow {
                required property var modelData
                playerKey: modelData.key
                name: modelData.name
                detail: modelData.detail
                appIcon: modelData.icon
            }
        }
    }

    StyledText {
        visible: root.runningPlayers.length === 0 && root.query === ""
        Layout.fillWidth: true
        text: Translation.tr("No player is running. Start one, or search for an installed app to pin it.")
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    MaterialTextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search installed apps")
    }

    component PlayerRow: RippleButton {
        id: row

        property string playerKey
        property string name
        property string detail
        property string appIcon: ""
        property string symbol: ""
        readonly property bool chosen: root.sameKey(row.playerKey, root.pinnedKey)

        Layout.fillWidth: true
        implicitHeight: 56
        useDynamicRadius: true
        colBackground: row.chosen ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: row.chosen ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
        colRipple: row.chosen ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active

        onClicked: Config.options.media.priorityPlayer = row.playerKey

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            IconImage {
                visible: row.symbol === ""
                Layout.alignment: Qt.AlignVCenter
                implicitSize: 30
                source: row.symbol === "" ? Quickshell.iconPath(row.appIcon, "audio-x-generic") : ""
            }

            MaterialShapeWrappedMaterialSymbol {
                visible: row.symbol !== ""
                Layout.alignment: Qt.AlignVCenter
                text: row.symbol
                shape: MaterialShape.Shape.Circle
                iconSize: 18
                padding: 6
                fill: 0
                color: row.chosen ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                colSymbol: row.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: row.name
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: row.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: row.detail
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: row.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                }
            }

            MaterialSymbol {
                visible: row.chosen
                Layout.alignment: Qt.AlignVCenter
                text: "keep"
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
    }
}
