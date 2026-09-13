pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.services
import qs.services.notes
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * A link, as a card.
 *
 * The title, the description and the picture come from the site, fetched once by
 * `NotesLinkPreview` and kept on disk. Nothing here is loaded from the network by the
 * card itself: `localOnly` below refuses any source that is not a file, so a preference
 * that says "nothing leaves this machine" holds at paint time too, and a favicon that has
 * moved cannot be re-requested on every repaint.
 *
 * The four buttons that used to sit in this card's header — refresh, open, copy, remove —
 * were on screen at all times, which made a quiet reference to a page look like a control
 * panel. They wait for the pointer now, and opening the page is the card itself.
 */
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    readonly property string url: root.block ? String(root.block.url ?? "") : ""
    readonly property string domain: {
        try {
            const match = root.url.match(/^https?:\/\/([^\/?#]+)/i);
            return match ? match[1] : root.url;
        } catch (e) {
            return root.url;
        }
    }

    readonly property bool loading: root.block && (!root.block.title || root.block.title.length === 0) && (root.block.fetchedAt === 0 || root.block.fetchedAt === undefined)

    /// A file, or nothing at all. Never a URL: an `Image` given one fetches it.
    function localOnly(path) {
        const value = String(path ?? "");
        return value.startsWith("/") ? `file://${value}` : "";
    }

    implicitHeight: Math.ceil((card.height + 16) / NotesMetrics.paperLineHeight) * NotesMetrics.paperLineHeight

    function refreshPreview(refresh = false): void {
        if (!root.url || !root.editor || !root.block)
            return;
        NotesLinkPreview.fetchPreview(root.url, data => {
            if (!root.block || !root.editor)
                return;
            const success = data && data.ok;
            root.editor.apply([{
                op: "update",
                id: root.block.id,
                patch: {
                    title: (success && data.title) ? data.title : root.domain,
                    description: (success && data.description) ? data.description : "",
                    image: (success && data.image) ? data.image : "",
                    favicon: (success && data.favicon) ? data.favicon : "",
                    fetchedAt: (data && data.fetchedAt) ? data.fetchedAt : Math.floor(Date.now() / 1000)
                }
            }], false);
        }, refresh);
    }

    /**
     * Fetch when the block arrives, not when the item is built.
     *
     * `NoteBlockDelegate` assigns `editor` and `block` in its loader's `onLoaded`, which
     * runs *after* this component completes — so the check that used to live in
     * `Component.onCompleted` always found `block` null and never asked for anything. The
     * card sat on "Loading preview…" for as long as the note was open.
     */
    onBlockChanged: root.fetchIfNeeded()
    Component.onCompleted: root.fetchIfNeeded()

    function fetchIfNeeded(): void {
        if (!root.block || root.url.length === 0)
            return;
        const title = String(root.block.title ?? "");
        if (title.length === 0 || Number(root.block.fetchedAt ?? 0) === 0)
            root.refreshPreview();
    }

    Rectangle {
        id: card
        x: NotesMetrics.readingPadding
        y: Math.round((root.implicitHeight - height) / 2)
        width: Math.max(160, Math.min(NotesMetrics.readingWidth,
            root.width - NotesMetrics.readingPadding * 2))
        height: contentLayout.implicitHeight + 24
        radius: Appearance.rounding.large
        // On the page, not a hole in it. `surfaceContainerLowest` is all but black, and a
        // near-black card is the one thing on a written page that shouts.
        color: Appearance.m3colors.m3surfaceContainerHighest
        clip: true

        // Subtle hover indicator
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Appearance.colors.colOnSurface
            opacity: cardHovered.hovered ? 0.04 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        /**
         * Hover for the whole card, buttons included.
         *
         * A `MouseArea`'s `containsMouse` goes false the moment a sibling on top of it
         * takes the pointer, so binding the actions' opacity to it made them vanish
         * exactly as the hand arrived — and the click then fell through to this area,
         * which opens the page. The buttons could not be pressed at all.
         *
         * A `HoverHandler` on the card stays hovered while anything inside it is.
         */
        HoverHandler {
            id: cardHovered
        }

        MouseArea {
            id: cardHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.url.length > 0)
                    Qt.openUrlExternally(root.url);
            }
        }

        ColumnLayout {
            id: contentLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            // ── Header line: favicon, domain, and actions ─────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16

                    Image {
                        id: faviconImage
                        anchors.fill: parent
                        source: root.block ? root.localOnly(root.block.favicon) : ""
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                        asynchronous: true
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "language"
                        iconSize: 15
                        color: Appearance.colors.colSubtext
                        visible: faviconImage.status !== Image.Ready
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.domain
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    opacity: cardHovered.hovered ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    NotesIconButton {
                        symbol: "refresh"
                        size: 32
                        iconSize: 17
                        tooltipText: Translation.tr("Ask the site again")
                        onTriggered: {
                            if (root.url.length > 0) {
                                NotesLinkPreview.invalidate(root.url);
                                root.refreshPreview(true);
                            }
                        }
                    }

                    NotesIconButton {
                        symbol: "content_copy"
                        size: 32
                        iconSize: 17
                        tooltipText: Translation.tr("Copy the link")
                        onTriggered: {
                            if (root.url.length > 0)
                                Quickshell.execDetached(["wl-copy", root.url]);
                        }
                    }

                    NotesIconButton {
                        symbol: "delete"
                        size: 32
                        iconSize: 17
                        colIcon: Appearance.colors.colSubtext
                        tooltipText: Translation.tr("Remove this card")
                        onTriggered: {
                            if (root.editor && root.block)
                                root.editor.removeBlock(root.block.id);
                        }
                    }
                }
            }

            // ── Body line: title & description on the left, thumbnail on right ─
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        text: root.loading ? Translation.tr("Asking the site…") : (root.block && root.block.title ? root.block.title : root.domain)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.block && root.block.description ? root.block.description : root.url
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                // Thumbnail image if present
                // Sixteen by nine, because that is the shape of nearly every picture a
                // page offers about itself. An 84×64 box cropped a video still into a
                // stamp with black bars down its sides.
                Rectangle {
                    Layout.preferredWidth: 128
                    Layout.preferredHeight: 72
                    Layout.alignment: Qt.AlignVCenter
                    visible: thumbImage.status === Image.Ready
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    clip: true

                    Image {
                        id: thumbImage
                        anchors.fill: parent
                        source: root.block ? root.localOnly(root.block.image) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        sourceSize.width: 512
                    }
                }
            }
        }
    }
}
