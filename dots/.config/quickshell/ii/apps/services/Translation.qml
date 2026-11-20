pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Translation for standalone apps: the shell's tr() over the same locale files,
 * without the language scanner processes. en_US is the source language, so it
 * reads nothing (the shell avoids retaining the 1.26 MB en_US.json the same way).
 *
 * This is the only service apps/ provides; shared widgets that import qs.services
 * resolve here, and any other service name stays undefined instead of booting.
 */
Singleton {
    id: root

    readonly property string translationKeepSuffix: "/*keep*/"
    readonly property string languageCode: {
        const configLang = Config.options?.language?.ui ?? "auto";
        return configLang !== "auto" ? configLang : Qt.locale().name;
    }
    readonly property bool isSource: root.languageCode === "en_US"
    property var translations: ({})

    FileView {
        path: root.isSource ? "" : Quickshell.shellPath(`translations/${root.languageCode}.json`)
        onLoaded: {
            try {
                root.translations = JSON.parse(text());
            } catch (e) {
                console.warn("[apps Translation] unreadable", root.languageCode, e);
            }
        }
    }

    function tr(text) {
        if (!text)
            return "";
        const key = text.toString();
        let translation = root.translations[key];
        if (!translation)
            return key;
        if (translation.endsWith(root.translationKeepSuffix))
            translation = translation.substring(0, translation.length - root.translationKeepSuffix.length).trim();
        return translation;
    }
}
