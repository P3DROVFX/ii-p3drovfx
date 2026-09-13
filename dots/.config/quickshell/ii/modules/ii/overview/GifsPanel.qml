pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * GIF search backed by KLIPY. Tenor's public API shut down in June 2026 and
 * KLIPY is the drop-in successor with a free tier.
 *
 * Network stays inside this panel: nothing is requested until it is open, and
 * a keystroke only restarts a debounce. The app key lives in the keyring, not
 * in config.json, and is entered through the search field itself so the panel
 * never needs a second input competing for focus.
 */
Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property string noticeText: ""
    property var gifs: []
    property bool loading: false
    property string errorText: ""
    // Responses can arrive out of order; only the newest request may publish.
    property int requestSerial: 0

    readonly property string apiKey: String(KeyringStorage.keyringData?.apiKeys?.klipy ?? "").trim()
    readonly property bool needsKey: root.apiKey.length === 0
    readonly property int columns: Math.max(2, Config.options.search.modules.gifs.columns)
    readonly property real gap: Appearance.sizes.elevationMargin / 2
    readonly property var selectedGif: root.selectedIndex >= 0 && root.selectedIndex < root.gifs.length
        ? root.gifs[root.selectedIndex]
        : null
    readonly property string statusText: {
        if (root.noticeText.length > 0)
            return root.noticeText;
        if (root.needsKey)
            return Translation.tr("Paste your KLIPY app key into the search field and press Enter");
        if (root.errorText.length > 0)
            return root.errorText;
        if (root.loading)
            return Translation.tr("Searching KLIPY…");
        if (root.selectedGif)
            return root.selectedGif.title;
        return Translation.tr("Powered by KLIPY");
    }

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function pickGif(item, qualities) {
        for (let i = 0; i < qualities.length; i++) {
            const format = item?.file?.[qualities[i]]?.gif;
            if (format?.url)
                return format;
        }
        return null;
    }

    function normalize(item) {
        // KLIPY interleaves sponsored items into the list; they are not GIFs.
        if (item?.type && item.type !== "gif")
            return null;
        const full = root.pickGif(item, ["md", "hd", "sm", "xs"]);
        const preview = root.pickGif(item, ["sm", "xs", "md", "hd"]);
        if (!full || !preview)
            return null;
        return {
            id: String(item.slug || item.id || ""),
            title: String(item.title || item.tags?.[0] || "GIF"),
            previewUrl: String(preview.url),
            gifUrl: String(full.url)
        };
    }

    function refresh() {
        const serial = ++root.requestSerial;
        if (root.needsKey) {
            root.gifs = [];
            root.loading = false;
            return;
        }
        const query = root.searchQuery.trim();
        const settings = Config.options.search.modules.gifs;
        const params = [
            "page=1",
            "per_page=" + Math.max(8, Math.min(50, settings.perPage)),
            "format_filter=gif",
            "content_filter=" + encodeURIComponent(settings.contentFilter),
            "customer_id=" + encodeURIComponent("quickshell-" + SystemInfo.username)
        ];
        if (query.length > 0)
            params.push("q=" + encodeURIComponent(query));
        const endpoint = query.length > 0 ? "search" : "trending";
        const url = `https://api.klipy.com/api/v1/${encodeURIComponent(root.apiKey)}/gifs/${endpoint}?${params.join("&")}`;

        root.loading = true;
        root.errorText = "";
        const request = new XMLHttpRequest();
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE || serial !== root.requestSerial)
                return;
            root.loading = false;
            let body = null;
            try {
                body = JSON.parse(request.responseText);
            } catch (e) {
                body = null;
            }
            // A bad key comes back as 404 with `result: false`; the envelope's
            // own message is the useful part, not the status code.
            if (request.status < 200 || request.status >= 300 || !body || body.result === false) {
                const message = body?.errors?.message;
                root.errorText = Array.isArray(message) && message.length > 0
                    ? message.join(" ")
                    : Translation.tr("KLIPY request failed (%1). Ctrl+E changes the app key.").arg(String(request.status));
                root.gifs = [];
                return;
            }
            root.gifs = Array.from(body.data?.data ?? []).map(item => root.normalize(item)).filter(Boolean);
            root.selectedIndex = root.gifs.length > 0 ? 0 : -1;
        };
        request.open("GET", url);
        request.send();
    }

    function moveBy(step): bool {
        const target = root.selectedIndex + step;
        if (root.gifs.length === 0 || target < 0 || target >= root.gifs.length)
            return false;
        root.selectedIndex = target;
        gifGrid.positionViewAtIndex(target, GridView.Contain);
        return true;
    }

    function navigateLeft(): bool { return root.moveBy(-1); }
    function navigateRight(): bool { return root.moveBy(1); }
    function navigateUp(): bool { return root.moveBy(-root.columns); }
    function navigateDown(): bool { return root.moveBy(root.columns); }
    function focusInput(): bool { return false; }

    function saveKey(): bool {
        const key = root.searchQuery.trim();
        if (key.length < 8) {
            root.showNotice(Translation.tr("That does not look like a KLIPY app key"));
            return true;
        }
        KeyringStorage.setNestedField(["apiKeys", "klipy"], key);
        // The key must not linger in the field, nor reach search history.
        LauncherSearch.query = "";
        root.showNotice(Translation.tr("KLIPY app key saved"));
        return true;
    }

    function activateSelected(): bool {
        if (root.needsKey)
            return root.saveKey();
        if (!root.selectedGif)
            return false;
        Quickshell.clipboardText = root.selectedGif.gifUrl;
        GlobalStates.closeSearchSurfaces();
        return true;
    }

    function copySelected(): bool {
        if (!root.selectedGif)
            return false;
        Quickshell.clipboardText = root.selectedGif.gifUrl;
        root.showNotice(Translation.tr("GIF link copied"));
        return true;
    }

    // Chat apps that refuse a link still accept the image itself.
    function secondaryActivateSelected(): bool {
        if (!root.selectedGif)
            return false;
        const directory = FileUtils.trimFileProtocol(String(Directories.cache)) + "/gifs";
        const file = `${directory}/${root.selectedGif.id || Date.now()}.gif`;
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && curl -fsSL "$2" -o "$3" && wl-copy --type image/gif < "$3"',
            "gif-copy", directory, root.selectedGif.gifUrl, file]);
        root.showNotice(Translation.tr("Copying the GIF as an image…"));
        return true;
    }

    function saveSelected(): bool {
        if (!root.selectedGif)
            return false;
        const directory = FileUtils.trimFileProtocol(String(Directories.pictures)) + "/GIFs";
        const file = `${directory}/${root.selectedGif.id || Date.now()}.gif`;
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && curl -fsSL "$2" -o "$3"',
            "gif-save", directory, root.selectedGif.gifUrl, file]);
        root.showNotice(Translation.tr("Saving to %1").arg(file));
        return true;
    }

    function editSelected(): bool {
        KeyringStorage.setNestedField(["apiKeys", "klipy"], "");
        root.showNotice(Translation.tr("Paste a new KLIPY app key and press Enter"));
        return true;
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    onSearchQueryChanged: {
        if (!root.needsKey)
            refreshDebounce.restart();
    }
    onApiKeyChanged: root.refresh()
    Component.onCompleted: root.refresh()

    Timer {
        id: refreshDebounce
        interval: 350
        onTriggered: root.refresh()
    }

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("GIFs")
        icon: "gif_box"
        accent: true
        showStatus: true
        statusText: root.statusText
        primaryHint: root.needsKey
            ? ({ label: Translation.tr("Save key"), actionId: "activate", keys: ["↵"] })
            : ({ label: Translation.tr("Copy link"), actionId: "activate", keys: ["↵"] })
        hints: root.needsKey ? [] : [
            { label: Translation.tr("Copy GIF"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Save"), actionId: "save", keys: ["Ctrl", "S"] },
            { label: Translation.tr("Change key"), actionId: "edit", keys: ["Ctrl", "E"] }
        ]

        Item {
            width: parent.width
            height: parent.height

            GridView {
                id: gifGrid
                anchors.fill: parent
                visible: !root.needsKey
                clip: true
                cellWidth: Math.floor(width / root.columns)
                cellHeight: cellWidth
                model: root.gifs

                delegate: RippleButton {
                    id: gifCell
                    required property int index
                    required property var modelData
                    readonly property bool selected: root.selectedIndex === index
                    width: gifGrid.cellWidth - root.gap
                    height: gifGrid.cellHeight - root.gap
                    buttonRadius: Appearance.rounding.normal
                    colBackground: gifCell.selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: gifCell.selected ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: gifCell.selected ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: {
                        root.selectedIndex = index;
                        root.activateSelected();
                    }

                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gifCell.width
                                height: gifCell.height
                                radius: Appearance.rounding.normal
                            }
                        }

                        AnimatedImage {
                            anchors.fill: parent
                            source: gifCell.modelData.previewUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            playing: true
                            opacity: gifCell.selected || root.selectedIndex < 0 ? 1 : 0.72

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: gifCell.selected
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Appearance.sizes.elevationMargin / 2
                        implicitWidth: checkIcon.implicitWidth + Appearance.sizes.elevationMargin / 2
                        implicitHeight: implicitWidth
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary

                        MaterialSymbol {
                            id: checkIcon
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: root.needsKey || (root.gifs.length === 0 && !root.loading)
                width: Math.min(parent.width, Appearance.sizes.elevationMargin * 40)
                spacing: Appearance.sizes.elevationMargin / 2

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.needsKey ? "key" : (root.errorText.length > 0 ? "cloud_off" : "gif_box")
                    iconSize: Appearance.font.pixelSize.huge
                    color: root.errorText.length > 0 && !root.needsKey ? Appearance.colors.colError : Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    text: root.needsKey
                        ? Translation.tr("GIF search uses KLIPY. Create a free app key at klipy.com/developers, paste it into the search field and press Enter. It is stored in the keyring.")
                        : (root.errorText.length > 0 ? root.errorText : Translation.tr("No GIFs found"))
                }
            }

            MaterialLoadingIndicator {
                anchors.centerIn: parent
                visible: root.loading && root.gifs.length === 0
                implicitWidth: Appearance.sizes.elevationMargin * 3
                implicitHeight: implicitWidth
            }
        }
    }
}
