import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * An ESPN crest that prefers the dark-surface artwork ("500-dark") in a dark
 * theme and falls back to the regular one when ESPN has no dark version.
 */
StyledImage {
    id: root

    property string url: ""
    property bool fallback: false

    readonly property string darkUrl: {
        const value = String(root.url ?? "");
        if (!Appearance.m3colors.darkmode || value.indexOf("espncdn.com") === -1 || value.indexOf("500-dark") !== -1)
            return value;
        return value.replace(/\/(leaguelogos|teamlogos)\/([a-z-]+)\/500\//, "/$1/$2/500-dark/");
    }

    onUrlChanged: root.fallback = false
    source: root.fallback ? root.url : root.darkUrl
    onStatusChanged: {
        if (status === Image.Error && !root.fallback && root.darkUrl !== root.url)
            root.fallback = true;
    }
    fillMode: Image.PreserveAspectFit
    mipmap: true
    cache: true
}
