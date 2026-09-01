pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

/**
 * Catalogue of the vendored Monkeytype key-press sound packs.
 *
 * Like TypingLanguages, this reads one small manifest that ships with the
 * shell and never touches the network. It exists so the settings page, the
 * player and the contract test all agree on which packs exist and how many
 * variants each one has, instead of three hardcoded lists drifting apart.
 */
Singleton {
    id: root

    property var clickPacks: []
    property var errorPacks: []
    property bool loaded: false

    readonly property string assetsPath: FileUtils.trimFileProtocol(Quickshell.shellPath("assets/typing"))
    readonly property string packsPath: root.assetsPath + "/sounds"
    readonly property string fallbackClickId: "click1"
    readonly property string fallbackErrorId: "error1"

    function clickPack(id) {
        return root.clickPacks.find(pack => pack.id === id)
            ?? root.clickPacks.find(pack => pack.id === root.fallbackClickId)
            ?? null;
    }

    function errorPack(id) {
        return root.errorPacks.find(pack => pack.id === id)
            ?? root.errorPacks.find(pack => pack.id === root.fallbackErrorId)
            ?? null;
    }

    /** file:// url for one variant, wrapping around a pack's variant count. */
    function variantUrl(pack, index) {
        if (!pack || (pack.files?.length ?? 0) === 0)
            return "";
        const files = pack.files;
        return "file://" + root.packsPath + "/" + pack.id + "/" + files[index % files.length];
    }

    FileView {
        path: root.assetsPath + "/sounds-manifest.json"

        onLoaded: {
            try {
                const manifest = JSON.parse(text());
                root.clickPacks = Array.from(manifest?.clickPacks ?? []);
                root.errorPacks = Array.from(manifest?.errorPacks ?? []);
                root.loaded = root.clickPacks.length > 0;
            } catch (error) {
                console.warn("[TypingSoundPacks] manifest error:", error);
            }
        }

        onLoadFailed: error => console.warn("[TypingSoundPacks] manifest load failed:", error)
    }
}
