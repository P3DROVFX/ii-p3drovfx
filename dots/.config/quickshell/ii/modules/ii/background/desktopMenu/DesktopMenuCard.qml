import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode
import qs.modules.ii.background.shortcuts

/**
 * The desktop's right-click menu: what the desktop offers when a click lands
 * on no widget. Four rows, deliberately (decision D6): the wallpaper picker,
 * the catalogue for whatever was clicked, the layout editor, and Settings.
 *
 * The bar and the dock ask for the same menu. Where the click landed decides
 * the rows: a bar is not a place to pick a wallpaper from, the bar's
 * catalogue row opens the bar's widgets instead of the desktop's, and the
 * dock keeps only its own way into the mode - its page in the catalogue -
 * because the dock's icons already carry their own menu.
 */
Item {
    id: root

    // The exit runs HERE, inside the live surface: GlobalStates only flags
    // `closing`, the reveal scalar plays it down (rows leaving in reverse,
    // the cascade running backwards for free) and `exitFinished` lets the
    // host unload the window. Same contract as ItemContextDialog's
    // closeRequested.
    property bool closing: false
    property real reveal: 0
    signal exitFinished()

    signal dismissRequested()

    // "desktop", "bar" or "dock".
    property string origin: "desktop"
    readonly property bool onBar: root.origin === "bar"
    readonly property bool onDock: root.origin === "dock"

    readonly property real padding: 6
    implicitWidth: 236
    implicitHeight: card.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // One scalar, arithmetic on it, no timers: the edit-mode toolbar's
    // cascade rule. The scalar runs LINEAR and every slice eases itself
    // (smoothstep) — the edit-mode sidebar's rhythm, where each row owns a
    // ~400 ms fade 26 ms apart. Easing the scalar globally was the blink:
    // emphasizedDecel is ~85% done at 30% of its time, so the whole cascade
    // collapsed into the first frames and all rows flashed at once. And the
    // two clocks stay SEPARATE: the card itself lands in the first slice and
    // STANDS STILL while the rows wave in inside it — a card that grows for
    // the whole window is the menu performing as a cascade item instead of
    // its buttons. Rows are declared, not Repeater-built, so each carries
    // its slot number; the count is the full run of 9 (separator included)
    // and hidden slots simply cost a skipped step.
    readonly property real bodySpan: 0.22
    readonly property real rowLead: 0.2
    readonly property real rowSpan: 0.55
    readonly property real rowStep: (1 - 0.2 - 0.55) / 8
    function ease(t: real): real {
        return t * t * (3 - 2 * t);
    }
    readonly property real bodyReveal: root.ease(Math.min(1, root.reveal / root.bodySpan))
    function rowReveal(index: int): real {
        const t = (root.reveal - root.rowLead - index * root.rowStep) / root.rowSpan;
        return root.ease(Math.max(0, Math.min(1, t)));
    }

    // `to` and `duration` are set by playReveal, never bound: a binding on
    // `closing` updates AFTER onClosingChanged has already restarted the
    // animation, so the exit ran the enter's values (1 -> 1 over 640 ms) and
    // the menu hung frozen, then vanished with no exit at all.
    NumberAnimation {
        id: revealMotion
        target: root
        property: "reveal"
        easing.type: Easing.Linear
        onFinished: { if (root.closing) root.exitFinished(); }
    }
    function playReveal() {
        revealMotion.stop();
        revealMotion.to = root.closing ? 0 : 1;
        revealMotion.duration = Appearance.reducedMotion ? 0
            : root.closing ? Appearance.animation.popupExit.duration
                : Appearance.animation.popupEnter.duration;
        revealMotion.start();
    }
    // The exit is a reaction: `closing` flips while the surface is up. The
    // enter is an event — beginEnter — because the host window is built once
    // and then shown per open (DesktopMenu keeps it alive), so completion
    // only describes the first one. The `reveal > 0` arm handles the menu
    // being RE-opened mid-exit: the scalar turns around in flight. Without
    // it the host's cleanup (closing → false at reveal 0) would restart the
    // enter on an unmapped window — wasted frames and a dead animation on
    // the next real open.
    onClosingChanged: { if (closing || reveal > 0) root.playReveal(); }
    Component.onCompleted: {
        root.playReveal();
        probePaste();
    }
    function beginEnter() {
        root.playReveal();
        probePaste();
    }

    // ── Desktop file operations ────────────────────────────────────────────
    // Paste: the desktop half of the item menu's Copy. When the clipboard
    // carries a file-URI list (a file manager's copy, or our own), the menu
    // offers to place those files as shortcuts on THIS screen. Probed on
    // open only — wl-paste lives milliseconds and a menu is a rare gesture;
    // never a timer, never a clipboard watcher. A payload over 4 KiB is not
    // a file list, it is someone's text: rejected without parsing.
    property var pasteUrls: []
    readonly property bool pasteAvailable: root.pasteUrls.length > 0
        && !root.onBar && !root.onDock
    readonly property bool hasIcons: PanelFamily.isIi && !root.onBar && !root.onDock
        && DesktopShortcuts.itemsFor(GlobalStates.desktopMenuScreenName).length > 0
    readonly property bool iconsLocked: Config.options.background.desktopIconsLocked ?? false

    Process {
        id: pasteProbe
        command: ["wl-paste", "-n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text;
                if (t.length === 0 || t.length > 4096) {
                    root.pasteUrls = [];
                    return;
                }
                const lines = t.split("\n").map(s => s.trim()).filter(s => s.length > 0);
                const urls = lines.filter(s => s.startsWith("file://") || s.startsWith("/"));
                root.pasteUrls = lines.length > 0 && urls.length === lines.length ? urls : [];
            }
        }
        onExited: (exitCode) => { if (exitCode !== 0) root.pasteUrls = []; }
    }
    function probePaste() {
        if (root.origin !== "desktop" || !PanelFamily.isIi) {
            root.pasteUrls = [];
            return;
        }
        if (!pasteProbe.running)
            pasteProbe.running = true;
    }
    function pasteNow() {
        if (root.pasteUrls.length === 0)
            return;
        const screen = Quickshell.screens.find(s => s.name === GlobalStates.desktopMenuScreenName);
        DesktopShortcuts.importUrls(GlobalStates.desktopMenuScreenName, root.pasteUrls,
            GlobalStates.desktopMenuX, GlobalStates.desktopMenuY, "",
            screen?.width ?? 1920, screen?.height ?? 1080);
        root.pasteUrls = [];
        root.dismissRequested();
    }

    // The popup body: opacity lands at once and the grow + rise finish on
    // the FIRST slice (~140 ms) — the card pops out of the corner under the
    // cursor and is settled before the rows have all arrived, exactly like
    // the sidebar's drawer, whose panel is still while its list fills.
    // TopLeft origin keeps that corner pinned, and the whole subtree —
    // shadow included — fades with it.
    opacity: Math.min(1, root.reveal * 8)
    scale: 0.94 + 0.06 * root.bodyReveal
    transformOrigin: Item.TopLeft
    transform: Translate { y: (1 - root.bodyReveal) * 10 }
    enabled: !root.closing

    // Clicks on the card's own padding must not reach the closer behind it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: column.implicitHeight + root.padding * 2
        radius: Appearance.rounding.windowRounding
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: root.padding
            spacing: 2

            EditMenuRow {
                readonly property real arrived: root.rowReveal(0)
                opacity: arrived
                visualScale: 0.965 + 0.035 * arrived
                transformOrigin: Item.TopLeft
                opacityBehaviorEnabled: root.reveal >= 1
                visible: !root.onBar
                cardPadding: root.padding
                symbol: "wallpaper"
                label: Translation.tr("Wallpaper & style")
                onClicked: {
                    root.dismissRequested();
                    GlobalStates.openEditCatalogue("style", GlobalStates.desktopMenuScreenName);
                }
            }
            EditMenuRow {
                readonly property real arrived: root.rowReveal(1)
                opacity: arrived
                visualScale: 0.965 + 0.035 * arrived
                transformOrigin: Item.TopLeft
                opacityBehaviorEnabled: root.reveal >= 1
                visible: !root.onDock
                cardPadding: root.padding
                symbol: "widgets"
                label: root.onBar ? Translation.tr("Bar widgets") : Translation.tr("Desktop widgets")
                onClicked: {
                    root.dismissRequested();
                    const section = root.onBar ? "bar" : "widgets";
                    GlobalStates.openEditCatalogue(section, GlobalStates.desktopMenuScreenName);
                }
            }
            EditMenuRow {
                readonly property real arrived: root.rowReveal(2)
                opacity: arrived
                visualScale: 0.965 + 0.035 * arrived
                transformOrigin: Item.TopLeft
                opacityBehaviorEnabled: root.reveal >= 1
                visible: PanelFamily.touchFirst && !root.onBar && !root.onDock
                cardPadding: root.padding
                symbol: "apps"
                label: Translation.tr("Home screen apps")
                onClicked: {
                    root.dismissRequested();
                    GlobalStates.openEditCatalogue("apps", GlobalStates.desktopMenuScreenName);
                }
            }
            // From the dock, the mode opens on the dock's own page: what was
            // clicked is what gets edited, the same rule as the rows above.
            EditMenuRow {
                readonly property real arrived: root.rowReveal(3)
                opacity: arrived
                visualScale: 0.965 + 0.035 * arrived
                transformOrigin: Item.TopLeft
                opacityBehaviorEnabled: root.reveal >= 1
                cardPadding: root.padding
                symbol: GlobalStates.editMode ? "done" : (root.onDock ? (PanelFamily.touchFirst ? "dock_to_bottom" : "dock") : "edit")
                label: GlobalStates.editMode ? Translation.tr("Done editing")
                    : root.onDock ? (PanelFamily.touchFirst ? Translation.tr("Edit taskbar") : Translation.tr("Edit dock"))
                    : Translation.tr("Edit layout")
                onClicked: {
                    root.dismissRequested();
                    if (GlobalStates.editMode) {
                        GlobalStates.closeEditMode();
                        return;
                    }
                    if (root.onDock) {
                        GlobalStates.openEditCatalogue("dock", GlobalStates.desktopMenuScreenName, "appearance");
                        return;
                    }
                    GlobalStates.openEditMode(GlobalStates.desktopMenuScreenName);
                }
            }

            // The desktop's file operations, between the edit rows and the
            // settings seam: they all speak of THIS screen's icons, so bar
            // and dock origins hide them by their own visibility rules.
            EditMenuRow {
                readonly property real arrived: root.rowReveal(4)
                opacity: arrived
                visualScale: 0.965 + 0.035 * arrived
                transformOrigin: Item.TopLeft
                opacityBehaviorEnabled: root.reveal >= 1
                visible: root.pasteAvailable
                cardPadding: root.padding
                symbol: "content_paste"
                label: Translation.tr("Paste")
                onClicked: root.pasteNow()
            }
            EditMenuRow {
                readonly property real arrived: root.rowReveal(5)
                opacity: arrived
                visualScale: 0.965 + 0.035 * arrived
                transformOrigin: Item.TopLeft
                opacityBehaviorEnabled: root.reveal >= 1
                visible: root.hasIcons
                cardPadding: root.padding
                symbol: "grid_on"
                label: Translation.tr("Align icons")
                onClicked: {
                    root.dismissRequested();
                    DesktopShortcuts.alignToGrid(GlobalStates.desktopMenuScreenName);
                }
            }
            EditMenuRow {
                readonly property real arrived: root.rowReveal(6)
                opacity: arrived
                visualScale: 0.965 + 0.035 * arrived
                transformOrigin: Item.TopLeft
                opacityBehaviorEnabled: root.reveal >= 1
                visible: root.hasIcons
                cardPadding: root.padding
                symbol: root.iconsLocked ? "lock" : "lock_open"
                label: root.iconsLocked ? Translation.tr("Unlock icons") : Translation.tr("Lock icons")
                onClicked: {
                    root.dismissRequested();
                    Config.options.background.desktopIconsLocked = !root.iconsLocked;
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: root.rowReveal(7)
            }


            EditMenuRow {
                readonly property real arrived: root.rowReveal(8)
                opacity: arrived
                visualScale: 0.965 + 0.035 * arrived
                transformOrigin: Item.TopLeft
                opacityBehaviorEnabled: root.reveal >= 1
                cardPadding: root.padding
                symbol: "settings"
                label: Translation.tr("Settings")
                onClicked: {
                    root.dismissRequested();
                    GlobalStates.openSettingsFromEditMode("");
                }
            }
        }
    }
}
