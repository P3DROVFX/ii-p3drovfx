pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.draw

/**
 * Live draw on the desktop: annotate the screen, over every application, while
 * recording it or sharing it.
 *
 * The tablet's pen tray, ported: the same sheets, the same tray, the same store
 * (services/LiveDraw.qml). What changes is what it is for. On the tablet it is a pen
 * coming out of its slot; here it is somebody pointing at something in a video call or a
 * screencast — so the tray can be dragged off whatever is being shown and folded down to
 * the pen, and the ink still belongs to the workspace it was drawn on.
 *
 * Opened from the keybind (Super+Alt+D), the dashboard's quick toggle, the bar's utility
 * buttons, the dock's widget, the recording controls in the bar popup and the island,
 * the search and `qs -c ii ipc call liveDraw toggle`. All of them call LiveDraw.toggle().
 *
 * One surface per screen, and only while there is a reason: the tray is open, or that
 * screen has ink on one of its workspaces. An always-mapped Overlay layer is a surface
 * the compositor blends over every frame for nothing — and one that keeps a fullscreen
 * game off direct scanout.
 */
Scope {
    id: root

    GlobalShortcut {
        name: "liveDrawToggle"
        description: "Draw on the screen"
        onPressed: LiveDraw.toggle()
    }

    GlobalShortcut {
        name: "liveDrawSpotlight"
        description: "Live draw: spotlight around the pointer"
        onPressed: LiveDraw.setSpotlight(!LiveDraw.spotlight)
    }

    GlobalShortcut {
        name: "liveDrawZoom"
        description: "Live draw: zoom around the pointer"
        onPressed: LiveDraw.setZoom(!LiveDraw.zoom)
    }

    /**
     * Live draw for scripts: `qs -c ii ipc call liveDraw <function> [argument]`.
     *
     * Everything the toolbar and the keyboard do, so a personal script can drive it — a
     * key held to draw (`quick` on press, `stop` on release), a stream deck page, a
     * hotkey that drops an arrow tool and a red ink in one go. Every function answers
     * with what it did, and `status` with the whole state as JSON.
     */
    IpcHandler {
        target: "liveDraw"

        function draw(): string {
            if (!LiveDraw.enabled)
                return "Live draw is off (Settings > Overlays & OSD > Live Draw).";
            LiveDraw.open();
            return "Drawing.";
        }

        /// Draw with no toolbar on screen; `stop` ends it. For hold-to-draw scripts.
        function quick(): string {
            if (!LiveDraw.enabled)
                return "Live draw is off (Settings > Overlays & OSD > Live Draw).";
            LiveDraw.quick();
            return "Drawing without the toolbar.";
        }

        function stop(): string {
            LiveDraw.close();
            return "Closed. Anything drawn stays on its workspace.";
        }

        function toggle(): string {
            return LiveDraw.trayOpen ? stop() : draw();
        }

        /// The pen down (`on`), up so clicks go through (`off`), or the other way (`toggle`).
        function pen(state: string): string {
            if (!LiveDraw.trayOpen)
                LiveDraw.open();
            LiveDraw.drawing = state === "on" ? true : state === "off" ? false : !LiveDraw.drawing;
            return LiveDraw.drawing ? "Pen down." : "Pen up: clicks go through.";
        }

        /// pen, highlighter, laser, line, arrow, rect, ellipse — or eraser.
        function tool(name: string): string {
            if (name === "eraser") {
                LiveDraw.eraser = true;
                return "Eraser.";
            }
            return LiveDraw.setTool(name) ? `Tool: ${name}.` : `Unknown tool "${name}". Tools: ${LiveDraw.tools.join(", ")}, eraser.`;
        }

        /// A colour as #rrggbb, or 1–9 for the palette's inks.
        function color(value: string): string {
            LiveDraw.ensureTools();
            const index = parseInt(value);
            const ink = /^[1-9]$/.test(value) ? LiveDraw.palette[index - 1] : value;
            if (!ink || !/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(ink))
                return `Not a colour: "${value}". Use #rrggbb or 1-${LiveDraw.palette.length}.`;
            LiveDraw.color = ink;
            LiveDraw.eraser = false;
            return `Ink: ${ink}.`;
        }

        function width(px: int): string {
            LiveDraw.width = Math.max(1, Math.min(24, px));
            return `Thickness: ${LiveDraw.width} px.`;
        }

        /// light, dark or off (also: toggle).
        function board(tone: string): string {
            if (tone === "toggle")
                LiveDraw.setBoard(LiveDraw.boardOn ? "" : "light");
            else
                LiveDraw.setBoard(tone === "off" ? "" : tone, true);
            return LiveDraw.boardOn ? `Board: ${LiveDraw.board}.` : "Board off.";
        }

        function spotlight(): string {
            LiveDraw.setSpotlight(!LiveDraw.spotlight);
            return LiveDraw.spotlight ? "Spotlight on. Esc or a click leaves." : "Spotlight off.";
        }

        function zoom(): string {
            LiveDraw.setZoom(!LiveDraw.zoom);
            return LiveDraw.zoom ? "Zoom on. Scroll to magnify, Esc or a click leaves." : "Zoom off.";
        }

        /// workspace or screen.
        function sheet(mode: string): string {
            if (mode !== "workspace" && mode !== "screen")
                return "Use workspace or screen.";
            Config.options.liveDraw.sheetMode = mode;
            return `Drawings belong to: ${mode}.`;
        }

        /// show, hide or toggle the toolbar while live draw stays on.
        function toolbar(state: string): string {
            LiveDraw.trayHidden = state === "hide" ? true : state === "show" ? false : !LiveDraw.trayHidden;
            return LiveDraw.trayHidden ? "Toolbar hidden." : "Toolbar shown.";
        }

        function undo(): string {
            LiveDraw.command("undo", null);
            return "Undone on the focused screen.";
        }

        function redo(): string {
            LiveDraw.command("redo", null);
            return "Redone on the focused screen.";
        }

        /// Rubs out the focused screen's drawing (undoable from the toolbar).
        function clear(): string {
            LiveDraw.command("clear", null);
            return "Focused screen cleared.";
        }

        /// Every drawing on every screen and workspace, and closes. Not undoable.
        function clearAll(): string {
            LiveDraw.clearAll();
            LiveDraw.close();
            return "Every drawing rubbed out.";
        }

        /// The focused screen's drawing to the clipboard (transparent PNG).
        function copy(): string {
            LiveDraw.command("copy", null);
            return "Copying the drawing.";
        }

        /// The focused screen with its drawing to the clipboard.
        function copyScreen(): string {
            LiveDraw.command("copyScreen", null);
            return "Copying the screen.";
        }

        /// png or svg, into Pictures/Drawings.
        function exportAs(format: string): string {
            LiveDraw.command(format === "svg" ? "exportSvg" : "exportPng", null);
            return `Saving the drawing as ${format === "svg" ? "SVG" : "PNG"} in Pictures/Drawings.`;
        }

        /// Files the focused screen's drawing into Notes.
        function save(): string {
            LiveDraw.command("save", null);
            return "Saving the focused screen's drawing to Notes.";
        }

        function screenshot(): string {
            LiveDraw.command("screenshot", null);
            return "Taking a screenshot with the drawing.";
        }

        function status(): string {
            return JSON.stringify({
                enabled: LiveDraw.enabled,
                open: LiveDraw.trayOpen,
                drawing: LiveDraw.drawing,
                toolbarHidden: LiveDraw.trayHidden,
                tool: LiveDraw.eraser ? "eraser" : LiveDraw.tool,
                color: LiveDraw.color,
                width: LiveDraw.width,
                board: LiveDraw.board,
                spotlight: LiveDraw.spotlight,
                zoom: LiveDraw.zoom,
                sheetMode: LiveDraw.sheetMode,
                drawings: LiveDraw.sheetCount
            });
        }
    }

    // The search and the touch gestures reach live draw through the family's handler.
    readonly property var handler: () => LiveDraw.toggle()
    Component.onCompleted: GlobalStates.liveDrawHandler = root.handler

    Component.onDestruction: {
        // Only our own: on a reload the next scope may already have installed its.
        if (GlobalStates.liveDrawHandler === root.handler)
            GlobalStates.liveDrawHandler = null;
        // Leaving the family closes live draw in the store (LiveDraw.family), not here:
        // a reload destroys this scope too, and must keep the pen where it was.
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                // The tray lives on the focused monitor only, so the other monitors need a
                // surface only for ink of their own.
                readonly property bool focused: String(Hyprland.focusedMonitor?.name ?? "") === screenScope.modelData.name
                active: LiveDraw.enabled
                    && (((LiveDraw.trayOpen || LiveDraw.spotlight || LiveDraw.zoom) && focused)
                        || LiveDraw.screenHasInk(screenScope.modelData.name))

                sourceComponent: LiveDrawWindow {
                    screen: screenScope.modelData
                    namespace: "quickshell:liveDraw"
                    // Surfaces that replace the desktop: ink over them would annotate the
                    // wrong thing.
                    coveredByShell: GlobalStates.overviewOpen
                        || GlobalStates.sessionOpen
                        || GlobalStates.screenLocked
                    // Tools that need the pointer for a moment. The ink stays, since it is
                    // usually what the screenshot or the translation is of.
                    inputSuspended: GlobalStates.regionSelectorOpen
                        || GlobalStates.screenTranslatorOpen
                    trayMovable: true
                    // Just above the dock when it sits at the bottom, which is the dock's
                    // own published thickness at rest (the lens never moves the tray).
                    // A bottom bar is cleared the same way.
                    trayBottomMargin: {
                        const inset = GlobalStates.dockInsets[screenScope.modelData.name];
                        return (inset?.side === "bottom" ? inset.thickness : 0)
                            + (BarPlacement.bottom && !BarPlacement.vertical ? Appearance.sizes.barHeight : 0)
                            + Appearance.sizes.elevationMargin * 2;
                    }
                    parallaxEnabled: Config.options?.tablet?.liveDraw?.workspaceParallax ?? true
                }
            }
        }
    }
}
