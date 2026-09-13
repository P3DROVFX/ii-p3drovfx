pragma Singleton
pragma ComponentBehavior: Bound

// From https://git.outfoxxed.me/outfoxxed/nixnew
// It does not have a license, but the author is okay with redistribution.

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common

/**
 * A service that provides easy access to the active Mpris player.
 */
Singleton {
	id: root;
	property list<MprisPlayer> allPlayers;
	property list<MprisPlayer> players;
	property list<MprisPlayer> applicationPlayers;
	property MprisPlayer localPlayer: null;
	property MprisPlayer lastExternalPlayer: null;
	property bool localPlayerSelected: false;
	readonly property string localPlayerBusName: "org.mpris.MediaPlayer2.ii_local";

	function updatePlayersList() {
		allPlayers = Mpris.players.values;
		players = Mpris.players.values.filter(player => isRealPlayer(player));
		localPlayer = allPlayers.find(player => isLocalPlayer(player)) ?? null;
		applicationPlayers = players.filter(player => !isLocalPlayer(player));
		if (localPlayerSelected && !localPlayer) {
			localPlayerSelected = false;
		}
	}

	Component.onCompleted: {
		updatePlayersList();
	}

	Timer {
		id: playersRefreshTimer
		interval: 10000
		running: true
		repeat: true
		onTriggered: root.updatePlayersList()
	}

	property MprisPlayer trackedPlayer: null;
	property MprisPlayer activePlayer: localPlayerSelected && localPlayer
		? localPlayer
		: (trackedPlayer ?? applicationPlayers[0] ?? Mpris.players.values[0] ?? null);
	signal trackChanged(reverse: bool);

    // This is an intent for Media Mode only. The explicit local-session claim
    // below intentionally makes the exported local MPRIS player active for
    // the existing bar and multimedia-key consumers; picking an application
    // releases that claim and restores the previous external selection.
    property string mediaModeSourceIntent: "applications"
    readonly property string effectiveMediaModeSource: mediaModeSourceIntent === "local" || !activePlayer
        ? "local"
        : "applications"

    function setMediaModeSource(source: string): void {
        if (source === "applications" || source === "local")
            root.mediaModeSourceIntent = source;
    }

    function selectMediaModeApplicationPlayer(player: MprisPlayer): void {
        root.releaseLocalPlayer();
        root.setMediaModeSource("applications");
        root.setActivePlayer(player);
    }

	function isLocalPlayer(player: MprisPlayer): bool {
		return player?.dbusName === root.localPlayerBusName;
	}

	function activateLocalPlayer(): bool {
		const candidate = Mpris.players.values.find(player => root.isLocalPlayer(player)) ?? null;
		if (!candidate)
			return false;
		if (!root.isLocalPlayer(root.trackedPlayer))
			root.lastExternalPlayer = root.trackedPlayer;
		root.localPlayer = candidate;
		root.localPlayerSelected = true;
		root.trackedPlayer = candidate;
		return true;
	}

	function releaseLocalPlayer(): void {
		if (!root.localPlayerSelected)
			return;
		root.localPlayerSelected = false;
		if (root.isLocalPlayer(root.trackedPlayer)) {
			const fallback = root.lastExternalPlayer
				&& Mpris.players.values.indexOf(root.lastExternalPlayer) !== -1
				? root.lastExternalPlayer
				: root.applicationPlayers[0] ?? null;
			root.trackedPlayer = fallback;
		}
	}

	property string priorityPlayer: Config.options.media.priorityPlayer;

	property bool __reverse: false;

	property var activeTrack;
	property string _artUrlFallback: "";
	readonly property string artUrl: {
		const url = activePlayer?.trackArtUrl;
		return (url && url !== "") ? url : _artUrlFallback;
	}

	onAllPlayersChanged: {
		if (root.localPlayerSelected && root.localPlayer) {
			root.trackedPlayer = root.localPlayer;
			return;
		}
		if (root.trackedPlayer) {
			const stillExists = Mpris.players.values.indexOf(root.trackedPlayer) !== -1;
			if (!stillExists)
				root.trackedPlayer = null;
		}
		if (root.trackedPlayer == null) {
			const priority = applicationPlayers.find(player => player.desktopEntry === root.priorityPlayer);
			if (priority) {
				root.trackedPlayer = priority;
			} else {
				const playing = applicationPlayers.find(player => player && player.isPlaying);
				if (playing) {
					root.trackedPlayer = playing;
				} else if (applicationPlayers.length > 0) {
					root.trackedPlayer = applicationPlayers[0];
				} else if (players.length > 0) {
					root.trackedPlayer = players[0];
				}
			}
		}
	}

	property bool hasActivePlasmaIntegration: false
    Process {
        id: plasmaIntegrationAvailabilityCheckProc
        running: true
        command: ["bash", "-c", "command -v plasma-browser-integration-host"]
        onExited: (exitCode, exitStatus) => {
            root.hasActivePlasmaIntegration = (exitCode === 0);
        }
    }
	function isRealPlayer(player) {
        if (!Config.options.media.filterDuplicatePlayers) {
            return true;
        }
        return (
            // Remove native browser buses only if plasma-browser-integration is actually active on D-Bus
            !(root.hasActivePlasmaIntegration && player.dbusName.startsWith('org.mpris.MediaPlayer2.firefox')) && !(root.hasActivePlasmaIntegration && player.dbusName.startsWith('org.mpris.MediaPlayer2.chromium')) &&
            // playerctld just copies other buses and we don't need duplicates
            !player.dbusName?.startsWith('org.mpris.MediaPlayer2.playerctld') &&
            // Non-instance mpd bus
            !(player.dbusName?.endsWith('.mpd') && !player.dbusName.endsWith('MediaPlayer2.mpd')));
    }

	// Original stuff from fox below
	Instantiator {
		model: Mpris.players;

		Connections {
			required property MprisPlayer modelData;
			target: modelData;

			Component.onCompleted: {
				if (root.localPlayerSelected && !root.isLocalPlayer(modelData)) {
					root.updatePlayersList();
					return;
				}
				if (root.trackedPlayer == null || modelData.isPlaying) {
					root.trackedPlayer = modelData;
				}
				root.updatePlayersList();
			}

			Component.onDestruction: {
				const removedLocalPlayer = root.isLocalPlayer(modelData);
				if (root.trackedPlayer === modelData) {
					root.trackedPlayer = null;
				}
				if (removedLocalPlayer) {
					root.localPlayer = null;
					root.localPlayerSelected = false;
					if (root.lastExternalPlayer && Mpris.players.values.indexOf(root.lastExternalPlayer) !== -1)
						root.trackedPlayer = root.lastExternalPlayer;
				}
				if (root.localPlayerSelected) {
					Qt.callLater(() => root.updatePlayersList());
					return;
				}
				if (root.trackedPlayer == null || !root.trackedPlayer.isPlaying) {
					for (const player of Mpris.players.values) {
						if (!root.isLocalPlayer(player) && player.playbackState.isPlaying) {
							root.trackedPlayer = player;
							break;
						}
					}

					if (root.trackedPlayer == null && root.applicationPlayers.length != 0) {
						root.trackedPlayer = root.applicationPlayers[0];
					}
				}
				Qt.callLater(() => root.updatePlayersList());
			}

			function onPlaybackStateChanged() {
				if (root.localPlayerSelected && !root.isLocalPlayer(modelData))
					return;
				if (root.trackedPlayer !== modelData) root.trackedPlayer = modelData;
			}
		}
	}

	Connections {
		target: activePlayer

		function onPostTrackChanged() {
			if (root.activePlayer?.trackArtUrl) {
				root._artUrlFallback = root.activePlayer.trackArtUrl;
				root.updateTrack();
			}
		}

		function onTrackArtUrlChanged() {
			const url = root.activePlayer?.trackArtUrl;
			if (url && url !== "") {
				root._artUrlFallback = url;
			}
			if (root.activeTrack && root.activeTrack.artUrl === url) return;
			const r = root.__reverse;
			root.updateTrack();
			root.__reverse = r;
		}
	}

	onActivePlayerChanged: {
		if (root.activePlayer?.trackArtUrl) {
			root._artUrlFallback = root.activePlayer.trackArtUrl;
			root.updateTrack();
		}
	}

	function updateTrack() {
		//console.log(`update: ${this.activePlayer?.trackTitle ?? ""} : ${this.activePlayer?.trackArtists}`)
		this.activeTrack = {
			uniqueId: this.activePlayer?.uniqueId ?? 0,
			artUrl: this.artUrl,
			title: this.activePlayer?.trackTitle || Translation.tr("Unknown Title"),
			artist: this.activePlayer?.trackArtist || Translation.tr("Unknown Artist"),
			album: this.activePlayer?.trackAlbum || Translation.tr("Unknown Album"),
		};

		this.trackChanged(__reverse);
		this.__reverse = false;
	}

	property bool isPlaying: this.activePlayer && this.activePlayer.isPlaying;
	property bool canTogglePlaying: this.activePlayer?.canTogglePlaying ?? false;
	function togglePlaying() {
		if (this.canTogglePlaying) this.activePlayer.togglePlaying();
	}

	property bool canGoPrevious: this.activePlayer?.canGoPrevious ?? false;
	function previous() {
		if (this.canGoPrevious) {
			this.__reverse = true;
			this.activePlayer.previous();
		}
	}

	property bool canGoNext: this.activePlayer?.canGoNext ?? false;
	function next() {
		if (this.canGoNext) {
			this.__reverse = false;
			this.activePlayer.next();
		}
	}

    property bool canChangeVolume: this.activePlayer && this.activePlayer.volumeSupported && this.activePlayer.canControl;
    readonly property real volumeStep: this.activePlayer ? (this.activePlayer.volume < 0.10 ? 0.01 : 0.02) : 0.02
	function incrementVolume() {
		if (!this.canChangeVolume)
			return;
		this.activePlayer.volume = Math.min(1, (this.activePlayer.volume ?? 1) + this.volumeStep);
	}
	function decrementVolume() {
		if (!this.canChangeVolume)
			return;
		this.activePlayer.volume = Math.max(0, (this.activePlayer.volume ?? 1) - this.volumeStep);
	}

	property bool loopSupported: this.activePlayer && this.activePlayer.loopSupported && this.activePlayer.canControl;
	property var loopState: this.activePlayer?.loopState ?? MprisLoopState.None;
	function setLoopState(loopState: var) {
		if (this.loopSupported) {
			this.activePlayer.loopState = loopState;
		}
	}

	property bool shuffleSupported: this.activePlayer && this.activePlayer.shuffleSupported && this.activePlayer.canControl;
	property bool hasShuffle: this.activePlayer?.shuffle ?? false;
	function setShuffle(shuffle: bool) {
		if (this.shuffleSupported) {
			this.activePlayer.shuffle = shuffle;
		}
	}

	function setActivePlayer(player: MprisPlayer) {
		const targetPlayer = player ?? Mpris.players[0];
		if (targetPlayer && !root.isLocalPlayer(targetPlayer))
			root.releaseLocalPlayer();
		console.log(`[Mpris] Active player ${targetPlayer} << ${activePlayer}`)

		if (targetPlayer && this.activePlayer) {
			this.__reverse = Mpris.players.indexOf(targetPlayer) < Mpris.players.indexOf(this.activePlayer);
		} else {
			// always animate forward if going to null
			this.__reverse = false;
		}

		this.trackedPlayer = targetPlayer;
	}

	IpcHandler {
		target: "mpris"

		function pauseAll(): void {
			for (const player of Mpris.players.values) {
				if (player.canPause) player.pause();
			}
		}

		function playPause(): void { root.togglePlaying(); }
		function previous(): void { root.previous(); }
		function next(): void { root.next(); }
	}
}
