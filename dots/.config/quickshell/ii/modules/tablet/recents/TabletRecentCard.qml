pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One open window in Recents: the window itself, and nothing around it.
 *
 * The card used to be a plate with a title strip stacked above a snapshot. Android does not
 * do that, and the reason is worth keeping in mind: the snapshot *is* the card. A surface
 * drawn behind it only shows where the snapshot fails to reach — which, once the card is
 * sized to the window's own aspect ratio, is nowhere. So the plate is gone, the corners are
 * on the snapshot itself, and the app's name rides on top of it as a pill, exactly as it
 * does on a Pixel Tablet.
 *
 * Flinging the card upwards closes the window. The threshold is deliberately generous —
 * closing something by accident while scrubbing sideways through the list is far worse than
 * having to repeat a deliberate flick.
 */
Item {
    id: root

    required property var toplevel
    /// Hyprland's row for the same window, joined on the address by the host. Carries the
    /// real pixel size, which is what the card's shape and the screenshot's resolution
    /// both come from — the toplevel does not expose it.
    property var client: null

    property real cardRadius: Appearance.rounding.large
    /// How tall the snapshot is. The width follows from the window's aspect ratio, so a
    /// portrait window reads as a portrait card instead of being stretched into a landscape
    /// one — which is the other half of "the snapshot is the card".
    property real cardHeight: 300
    /// Room kept below every card for the action row, so cards do not shift when it appears.
    property real actionRowHeight: 0
    /// Empty space above the card. The list clips, and the dismiss fling needs somewhere to
    /// travel to inside that clip — see TabletRecentsContent.dragHeadroom.
    property real topInset: 0
    /// This is the card in the middle of the viewport, so it is the one the actions act on.
    property bool showActions: false

    signal activated
    signal closed
    /// The header pill was decoration. On Android it is the handle for everything you can
    /// do to a window without opening it, so it raises this with its own position.
    signal menuRequested(real x, real y)
    signal splitRequested

    readonly property string appId: root.toplevel?.appId ?? ""
    readonly property string title: root.toplevel?.title ?? ""

    /// The app you were in when Recents opened. Marked by tinting its pill, not by an
    /// outline or a size: this project bans borders outright and treats a permanent scale
    /// difference as decoration.
    property bool isCurrent: false

    readonly property real windowWidth: Number(root.client?.size?.[0] ?? 0)
    readonly property real windowHeight: Number(root.client?.size?.[1] ?? 0)
    /// Clamped so a freakish window — a 40px-tall notification shell, a very wide terminal —
    /// still produces a card a finger can hit and a row can hold.
    readonly property real aspect: (root.windowWidth > 0 && root.windowHeight > 0)
        ? Math.max(0.55, Math.min(2.2, root.windowWidth / root.windowHeight))
        : 16 / 10

    implicitWidth: Math.round(root.cardHeight * root.aspect)
    implicitHeight: root.topInset + root.cardHeight + root.actionRowHeight

    // How far up the card has been dragged. Reset unless the drag commits.
    property real dragOffset: 0
    readonly property real dismissDistance: Math.max(120, root.cardHeight * 0.28)

    Behavior on dragOffset {
        enabled: !dragArea.pressed
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    transform: Translate {
        y: -root.dragOffset
    }
    opacity: Math.max(0, 1 - (root.dragOffset / (root.dismissDistance * 1.6)))

    // ── Screenshot ──────────────────────────────────────────────────────────
    /**
     * Save this window on its own, at its real resolution.
     *
     * Grabbing the ScreencopyView rather than shelling out to `grim -g` is what makes this
     * work for a window on another workspace. `grim` photographs an output, so it can only
     * ever capture what is currently on screen; the view here is holding the toplevel's own
     * buffer, which exists whether or not the window is in front. `targetSize` is the
     * window's real pixel size, so the file is the window at full resolution rather than at
     * the size the card happens to be drawn.
     *
     * The file lands in the shell's temp directory first — that one is created at startup
     * and is guaranteed to exist — and the move into Pictures is what creates the album
     * folder. Saving straight into a folder that may not exist fails silently.
     */
    function takeScreenshot() {
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH.mm.ss");
        const tempPath = `${Directories.screenshotTemp}/window-${stamp}.png`;
        const size = (root.windowWidth > 0 && root.windowHeight > 0)
            ? Qt.size(Math.round(root.windowWidth), Math.round(root.windowHeight))
            : Qt.size(Math.round(snapshot.width), Math.round(snapshot.height));

        const started = snapshot.grabToImage(result => {
            if (!result.saveToFile(tempPath)) {
                console.warn("[Recents] Could not write the window screenshot to", tempPath);
                return;
            }
            Quickshell.execDetached(["bash", "-c",
                `dir="$(xdg-user-dir PICTURES)/Screenshots" && mkdir -p "$dir" `
                + `&& dest="$dir/Screenshot_${stamp}.png" && mv '${tempPath}' "$dest" `
                + `&& wl-copy < "$dest" `
                + `&& notify-send -i camera-photo -t 4000 'Window captured' "$dest"`]);
        }, size);

        if (!started) {
            console.warn("[Recents] grabToImage refused to start for", root.appId);
            return;
        }
        SoundService.playEvent("screenshot", ["camera-shutter", "screen-capture"]);
    }

    // ── The window ──────────────────────────────────────────────────────────
    ClippingRectangle {
        id: snapshot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root.topInset
        height: root.cardHeight
        radius: root.cardRadius
        // No plate. Sized to the window's aspect ratio, the capture reaches every corner,
        // so anything painted behind it would only ever be a rim around a picture.
        color: "transparent"

        ScreencopyView {
            anchors.fill: parent
            captureSource: root.toplevel
            // One capture per open, not a live feed: a row of live captures is a continuous
            // screencopy per card, and the window is not moving anyway.
            live: false
        }

        // Fallback for a window that will not capture — better a labelled surface than an
        // empty hole in the row.
        Rectangle {
            anchors.fill: parent
            visible: root.toplevel === null
            color: Appearance.colors.colLayer1

            IconImage {
                anchors.centerIn: parent
                implicitSize: 64
                source: Quickshell.iconPath(TaskbarApps.getCachedIcon(root.appId), "image-missing")
            }
        }
    }

    // ── The header pill ─────────────────────────────────────────────────────
    // On the card, not above it. The chevron is the affordance Android uses for "there is a
    // menu here", and it is the only thing on the card that is not the window.
    RippleButton {
        id: header
        anchors.left: snapshot.left
        anchors.top: snapshot.top
        anchors.margins: 10
        implicitHeight: Math.max(Appearance.sizes.minimumTouchTarget - 12, 34)
        implicitWidth: Math.min(snapshot.width - 20, headerRow.implicitWidth + 24)

        buttonRadius: Appearance.rounding.full
        // Raw palette colours, not the layer tokens. The layer tokens carry the user's
        // content transparency, and this pill sits on an arbitrary screenshot — the app's
        // own title bar was reading straight through it. A label over a photograph has to
        // be opaque, the same rule the dock's glyph outlines follow over the wallpaper.
        colBackground: root.isCurrent
            ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundHover: root.isCurrent
            ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
        colBackgroundActive: root.isCurrent
            ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
        colRipple: root.isCurrent
            ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive

        readonly property color contentColor: root.isCurrent
            ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface

        onClicked: {
            const point = header.mapToItem(null, header.width / 2, header.height);
            root.menuRequested(point.x, point.y);
        }

        contentItem: RowLayout {
            id: headerRow
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 7

            IconImage {
                implicitSize: 20
                source: Quickshell.iconPath(TaskbarApps.getCachedIcon(root.appId), "image-missing")
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title.length > 0 ? root.title : root.appId
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: header.contentColor
                elide: Text.ElideRight
            }

            MaterialSymbol {
                text: "expand_more"
                iconSize: 18
                color: header.contentColor
            }
        }
    }

    /// Closing without a fling, for anyone who would rather tap than gesture.
    RippleButton {
        id: closeButton
        anchors.right: snapshot.right
        anchors.top: snapshot.top
        anchors.margins: 10
        implicitWidth: header.implicitHeight
        implicitHeight: header.implicitHeight
        buttonRadius: Appearance.rounding.full
        // Opaque for the same reason as the header pill: it sits on a screenshot.
        colBackground: Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
        colRipple: Appearance.colors.colSurfaceContainerHighestActive
        onClicked: root.closed()

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: "close"
            iconSize: 18
            color: Appearance.m3colors.m3onSurface
        }
    }

    // ── Actions under the card ──────────────────────────────────────────────
    // Android puts these under the card in the middle of the view, and only there: a row
    // under every card would be a wall of buttons in a surface whose subject is the
    // pictures. The host says which card is in the middle.
    RowLayout {
        id: actionRow
        anchors.horizontalCenter: snapshot.horizontalCenter
        anchors.top: snapshot.bottom
        anchors.topMargin: Math.max(0, (root.actionRowHeight - 44) / 2)
        spacing: 10
        visible: root.actionRowHeight > 0 && opacity > 0.01
        opacity: root.showActions ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(actionRow)
        }

        TabletRecentsActionPill {
            symbol: "screenshot_region"
            label: Translation.tr("Screenshot")
            onTriggered: root.takeScreenshot()
        }

        TabletRecentsActionPill {
            symbol: "splitscreen"
            label: Translation.tr("Split")
            onTriggered: root.splitRequested()
        }
    }

    // ── Gestures on the window itself ───────────────────────────────────────
    MouseArea {
        id: dragArea
        anchors.fill: snapshot
        // Stops short of the pill row. Declared after the layout, so it sits on top and
        // would otherwise swallow every press meant for the header's own button.
        anchors.topMargin: header.height + 20

        // No `drag` block: the card itself must not move — only dragOffset does, so the
        // layout stays put — and a MouseArea with a drag target suppresses `clicked`, which
        // cost the tap-to-focus path until it was removed.
        property real pressY: 0

        onPressed: mouse => {
            dragArea.pressY = mouse.y;
        }

        onPositionChanged: mouse => {
            if (!dragArea.pressed)
                return;
            root.dragOffset = Math.max(0, dragArea.pressY - mouse.y);
        }

        onReleased: {
            if (root.dragOffset >= root.dismissDistance) {
                root.closed();
                return;
            }
            root.dragOffset = 0;
        }

        onClicked: {
            if (root.dragOffset < 4)
                root.activated();
        }
    }
}
