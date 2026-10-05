import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UtilityFiles.js" as UtilityFiles

/**
 * Send: drop files on it to send them — to the phone over KDE Connect, or to
 * a LocalSend device on the network. The target is picked in the panel and
 * remembered. Files dropped with no reachable target wait in the panel until
 * one is chosen.
 */
UtilityTile {
    id: tile

    readonly property var cfg: Config.options?.dock?.utilities?.send ?? null
    readonly property bool localSend: (tile.cfg?.backend ?? "kdeconnect") === "localsend"

    readonly property string kdeDeviceId: String(tile.cfg?.kdeDevice ?? "") || KdeConnectService.activeDeviceId
    readonly property var kdeDevice: (KdeConnectService.devices ?? []).find(device => device.id === tile.kdeDeviceId) ?? null
    readonly property string localIp: String(tile.cfg?.localsendIp ?? "")
    readonly property string localAlias: String(tile.cfg?.localsendAlias ?? "")

    readonly property bool ready: tile.localSend
        ? (LocalSend.available && tile.localIp.length > 0)
        : (tile.kdeDevice?.reachable === true)
    readonly property string targetName: tile.localSend
        ? (tile.localAlias || Translation.tr("No device chosen"))
        : (tile.kdeDevice?.name || Translation.tr("No phone paired"))
    readonly property bool sending: tile.localSend && LocalSend.sending

    // Files dropped while nothing could take them.
    property var pending: []
    property int lastSentCount: 0

    function send(paths) {
        if (paths.length === 0)
            return;
        if (!tile.ready) {
            tile.pending = UtilityFiles.dedupe(tile.pending.concat(paths));
            tile.host?.openPanel();
            return;
        }
        if (tile.localSend) {
            LocalSend.clearDroppedFiles();
            for (const path of paths)
                LocalSend.addDroppedFile(path);
            LocalSend.sendToDevice(tile.localIp);
        } else {
            for (const path of paths)
                KdeConnectService.shareUrl(tile.kdeDeviceId, UtilityFiles.fileUri(path));
        }
        tile.pending = [];
        tile.lastSentCount = paths.length;
        sentTimer.restart();
    }

    function dropFiles(urls) {
        tile.send(UtilityFiles.dedupe(urls));
    }

    Timer {
        id: sentTimer
        interval: 3500
        onTriggered: tile.lastSentCount = 0
    }

    readonly property bool justSent: tile.lastSentCount > 0 && !tile.sending
    readonly property string symbol: tile.localSend ? "near_me" : "smartphone"

    surfaceColor: tile.dropHovering ? ClockStyle.colPrimaryContainer
        : tile.justSent ? ClockStyle.colTertiaryContainer
        : tile.sending ? ClockStyle.colSecondaryContainer
        : ClockStyle.colSurfaceHigh
    contentColor: tile.dropHovering ? ClockStyle.colOnPrimaryContainer
        : tile.justSent ? ClockStyle.colOnTertiaryContainer
        : tile.sending ? ClockStyle.colOnSecondaryContainer
        : ClockStyle.colOnSurface

    readonly property string stateText: tile.dropHovering ? Translation.tr("Drop to send")
        : tile.sending ? Translation.tr("Sending…")
        : tile.justSent ? (tile.lastSentCount === 1 ? Translation.tr("Sent 1 file") : Translation.tr("Sent %1 files").arg(tile.lastSentCount))
        : !tile.ready ? (tile.localSend ? Translation.tr("Choose a device") : Translation.tr("Phone offline"))
        : (tile.localSend ? "LocalSend" : "KDE Connect")

    tooltipText: (tile.localSend ? "LocalSend" : "KDE Connect") + " · " + tile.targetName + " · " + tile.stateText
    panelSubtitle: (tile.localSend ? "LocalSend" : "KDE Connect") + " · " + tile.targetName
    panelWidth: 360

    readonly property int phoneCharge: !tile.localSend && tile.ready ? (tile.kdeDevice?.charge ?? -1) : -1

    // Square: the phone's charge as a ring around the badge.
    ClockProgressRing {
        anchors.fill: parent
        anchors.margins: Math.round(tile.side * 0.08)
        visible: !tile.wide && tile.phoneCharge >= 0 && !tile.dropHovering
        value: tile.phoneCharge / 100
        thickness: Math.max(3, Math.round(tile.side * 0.07))
        wavy: false
        colIndicator: tile.phoneCharge <= 15 ? ClockStyle.colError : ClockStyle.colTertiary
        colTrack: ColorUtils.applyAlpha(tile.contentColor, 0.12)
    }

    // ── The badge: idle, hovered by a drag, sent — three shapes of one badge ──
    TileBadge {
        id: badge
        readonly property real size: tile.wide ? tile.badgeSize
            : Math.round(tile.side * (tile.phoneCharge >= 0 && !tile.dropHovering ? 0.56 : 0.74))
        x: tile.wide ? tile.pad : (tile.width - badge.size) / 2
        y: (tile.height - badge.size) / 2
        width: badge.size
        height: badge.size
        renderScale: tile.renderScale
        shape: tile.dropHovering ? MaterialShape.Shape.Sunny
            : tile.justSent ? MaterialShape.Shape.Cookie12Sided
            : MaterialShape.Shape.Cookie6Sided
        color: tile.dropHovering ? ClockStyle.colPrimary
            : tile.justSent ? ClockStyle.colTertiary
            : tile.ready ? ClockStyle.colTertiaryContainer : ColorUtils.applyAlpha(tile.contentColor, 0.1)
        colSymbol: tile.dropHovering ? ClockStyle.colOnPrimary
            : tile.justSent ? ClockStyle.colOnTertiary
            : tile.ready ? ClockStyle.colOnTertiaryContainer : tile.captionColor
        text: tile.dropHovering ? "file_upload" : tile.justSent ? "check" : tile.sending ? "sync" : tile.symbol
        iconScale: 0.5
    }

    // ── Wide ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: tile.pad * 2 + tile.badgeSize
        anchors.rightMargin: tile.pad * 2
        visible: tile.wide
        spacing: 0
        Item { Layout.fillHeight: true }
        TileText {
            Layout.fillWidth: true
            text: tile.dropHovering ? Translation.tr("Drop to send") : tile.targetName
            color: tile.contentColor
            font.pixelSize: Math.round(tile.height * 0.27)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        TileCaption {
            Layout.fillWidth: true
            text: tile.dropHovering ? tile.targetName
                : tile.stateText + (!tile.localSend && tile.ready && (tile.kdeDevice?.charge ?? -1) >= 0
                    ? " · " + tile.kdeDevice.charge + "%" : "")
            color: tile.captionColor
            font.pixelSize: tile.captionSize
        }
        Item { Layout.fillHeight: true }
    }
}
