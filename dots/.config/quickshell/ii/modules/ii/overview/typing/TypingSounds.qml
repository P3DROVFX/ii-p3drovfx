pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import qs.modules.common
import qs.services

/**
 * Key-press feedback for the typing test.
 *
 * The samples are Monkeytype's own, vendored into the shell assets (see
 * scripts/typing/sync_monkeytype_sounds.py). They are played through
 * SoundEffect rather than the XDG event player: this is per-keystroke
 * feedback, so it must not be rate limited, must not go through the system
 * sound theme, and must be able to overlap itself at 100+ WPM.
 *
 * Nothing is instantiated until the feature is switched on — QtMultimedia
 * links its backend and starts an audio thread the moment a player exists.
 */
Item {
    id: root

    property bool soundEnabled: Config.options.search.typingTest.sounds.enable
    property bool errorSound: Config.options.search.typingTest.sounds.errorSound
    property real volume: Math.max(0, Math.min(100, Config.options.search.typingTest.sounds.volume)) / 100

    readonly property var clickPack: TypingSoundPacks.clickPack(Config.options.search.typingTest.sounds.theme)
    readonly property var errorPack: TypingSoundPacks.errorPack(Config.options.search.typingTest.sounds.errorTheme)
    // Two players per variant so a fast typist never cuts a sample short by
    // restarting the one that is still ringing.
    readonly property int poolSize: Math.max(1, (root.clickPack?.files?.length ?? 1) * 2)
    property int _next: 0

    function playKey() {
        if (!root.soundEnabled || !poolLoader.item)
            return;
        const player = poolLoader.item.keyAt(root._next);
        root._next = (root._next + 1) % root.poolSize;
        if (player)
            player.play();
    }

    function playError() {
        if (!root.soundEnabled || !root.errorSound || !poolLoader.item)
            return;
        poolLoader.item.errorPlayer.play();
    }

    Loader {
        id: poolLoader
        active: root.soundEnabled && TypingSoundPacks.loaded

        sourceComponent: Item {
            readonly property alias errorPlayer: errorEffect

            function keyAt(index) {
                return keyPool.objectAt(index);
            }

            Instantiator {
                id: keyPool
                model: root.poolSize

                delegate: SoundEffect {
                    required property int index
                    source: TypingSoundPacks.variantUrl(root.clickPack, index)
                    volume: root.volume
                }
            }

            SoundEffect {
                id: errorEffect
                source: TypingSoundPacks.variantUrl(root.errorPack, 0)
                volume: root.volume
            }
        }
    }
}
