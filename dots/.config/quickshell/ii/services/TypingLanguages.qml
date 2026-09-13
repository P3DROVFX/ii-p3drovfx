pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

/**
 * Local word-pack catalogue for the Overview typing test.
 *
 * The manifest and packs are checked into the shell assets. This singleton
 * deliberately has no Process, HTTP or network dependency at runtime.
 */
Singleton {
    id: root

    property var languages: []
    property var currentPack: null
    property string currentLanguageId: ""
    property string requestedLanguageId: ""
    property bool manifestLoaded: false
    property bool loading: false
    property string errorText: ""
    property var packCache: ({})

    readonly property string assetsPath: FileUtils.trimFileProtocol(Quickshell.shellPath("assets/typing"))
    readonly property string fallbackLanguageId: "english_1k"

    function languageFor(id) {
        return root.languages.find(language => language.id === id) ?? null;
    }

    function request(languageId) {
        const wanted = root.languageFor(languageId) ? languageId : root.fallbackLanguageId;
        root.requestedLanguageId = wanted;
        if (!root.manifestLoaded) {
            root.loading = true;
            manifestFile.reload();
            return;
        }
        root.loadRequestedPack();
    }

    function loadRequestedPack() {
        const entry = root.languageFor(root.requestedLanguageId)
            ?? root.languageFor(root.fallbackLanguageId);
        if (!entry) {
            root.loading = false;
            root.errorText = qsTr("No bundled typing language is available.");
            return;
        }
        const cached = root.packCache[entry.id];
        if (cached) {
            root.currentPack = cached;
            root.currentLanguageId = entry.id;
            root.loading = false;
            root.errorText = "";
            return;
        }
        root.loading = true;
        root.errorText = "";
        packFile.path = root.assetsPath + "/" + entry.file;
        packFile.reload();
    }

    FileView {
        id: manifestFile
        path: root.assetsPath + "/languages-manifest.json"

        onLoaded: {
            try {
                const manifest = JSON.parse(text());
                const entries = Array.from(manifest?.languages ?? []).filter(entry =>
                    typeof entry?.id === "string" && typeof entry?.file === "string");
                if (entries.length === 0)
                    throw new Error("empty manifest");
                root.languages = entries;
                root.manifestLoaded = true;
                root.loadRequestedPack();
            } catch (error) {
                root.loading = false;
                root.errorText = qsTr("Typing language catalogue could not be read.");
                console.warn("[TypingLanguages] manifest error:", error);
            }
        }

        onLoadFailed: error => {
            root.loading = false;
            root.errorText = qsTr("Typing language catalogue is unavailable.");
            console.warn("[TypingLanguages] manifest load failed:", error);
        }
    }

    FileView {
        id: packFile

        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                const words = Array.from(parsed?.words ?? []).filter(word =>
                    typeof word === "string" && word.trim().length > 0);
                if (words.length === 0)
                    throw new Error("empty words");
                const entry = root.languageFor(root.requestedLanguageId)
                    ?? root.languageFor(root.fallbackLanguageId);
                const pack = {
                    id: entry.id,
                    name: String(parsed?.name ?? entry.label),
                    bcp47: String(parsed?.bcp47 ?? entry.bcp47 ?? ""),
                    rightToLeft: Boolean(parsed?.rightToLeft ?? entry.rightToLeft),
                    joiningScript: Boolean(parsed?.joiningScript ?? entry.joiningScript),
                    preferredFont: String(parsed?.preferredFont ?? ""),
                    words: words
                };
                root.packCache = Object.assign({}, root.packCache, { [pack.id]: pack });
                root.currentPack = pack;
                root.currentLanguageId = pack.id;
                root.loading = false;
                root.errorText = "";
            } catch (error) {
                root.loading = false;
                root.errorText = qsTr("Typing language pack could not be read.");
                console.warn("[TypingLanguages] pack error:", error);
            }
        }

        onLoadFailed: error => {
            const fallback = root.languageFor(root.fallbackLanguageId);
            if (root.requestedLanguageId !== root.fallbackLanguageId && fallback) {
                root.errorText = qsTr("Language pack unavailable; using English.");
                root.requestedLanguageId = root.fallbackLanguageId;
                root.loadRequestedPack();
                return;
            }
            root.loading = false;
            root.errorText = qsTr("Typing language pack is unavailable.");
            console.warn("[TypingLanguages] pack load failed:", error);
        }
    }

    Component.onCompleted: root.request(root.fallbackLanguageId)
}
