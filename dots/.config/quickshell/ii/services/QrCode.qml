pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services
import "../modules/common/functions/devtools.js" as DevToolsEngine
import "../modules/common/widgets/shapes/material-shapes.js" as MaterialShapes

/**
 * Shared QR code service for the whole shell.
 *
 * Single QML entry point for encoding text to QR matrices, normalizing external
 * matrices (e.g. ii-link pairing rows), resolving contrast-guarded Material You
 * palettes, rendering Pixel / Blob / Classic SVGs with cached Material shapes,
 * and exporting PNGs to the clipboard or disk via scripts/images/qr_png.py.
 */
Singleton {
    id: root

    readonly property string style: {
        const s = Config.options?.appearance?.qrStyle ?? "pixel";
        return (s === "blob" || s === "classic") ? s : "pixel";
    }
    readonly property bool decoration: Config.options?.appearance?.qrDecoration ?? true

    readonly property var _shapesCache: {
        const extract = poly => poly.cubics.map(c => c.points.slice());
        return {
            cookie4Sided: extract(MaterialShapes.getCookie4Sided()),
            cookie6Sided: extract(MaterialShapes.getCookie6Sided()),
            cookie7Sided: extract(MaterialShapes.getCookie7Sided()),
            cookie9Sided: extract(MaterialShapes.getCookie9Sided())
        };
    }

    function _colorHex(c): string {
        const col = Qt.color(c);
        const ch = n => Math.round(Math.max(0, Math.min(255, n * 255))).toString(16).padStart(2, "0").toUpperCase();
        return "#" + ch(col.r) + ch(col.g) + ch(col.b);
    }

    readonly property var themeColors: ({
        darkmode: Boolean(Appearance.m3colors.darkmode),
        surface: root._colorHex(Appearance.m3colors.m3surface),
        surfaceLow: root._colorHex(Appearance.m3colors.m3surfaceContainerLow),
        surfaceHigh: root._colorHex(Appearance.m3colors.m3surfaceContainerHigh),
        onSurface: root._colorHex(Appearance.m3colors.m3onSurface),
        primary: root._colorHex(Appearance.m3colors.m3primary),
        primaryContainer: root._colorHex(Appearance.m3colors.m3primaryContainer),
        secondary: root._colorHex(Appearance.m3colors.m3secondary),
        tertiary: root._colorHex(Appearance.m3colors.m3tertiary)
    })

    signal copyFinished(bool success, string message)
    signal saveFinished(bool success, string path, string message)

    function _normalizeStyle(style, matrix): string {
        const raw = style || matrix?.style || root.style;
        return (raw === "blob" || raw === "classic") ? raw : "pixel";
    }

    function _rowsString(matrix): string {
        if (!matrix)
            return "";
        if (matrix.rows && typeof matrix.rows.length === "number") {
            const out = [];
            for (let i = 0; i < matrix.rows.length; i++)
                out.push(String(matrix.rows[i] ?? ""));
            return out.join(",");
        }
        if (matrix.modules && typeof matrix.modules.length === "number") {
            const out = [];
            for (let y = 0; y < matrix.modules.length; y++) {
                const modRow = matrix.modules[y];
                let line = "";
                for (let x = 0; x < modRow.length; x++)
                    line += modRow[x] ? "1" : "0";
                out.push(line);
            }
            return out.join(",");
        }
        return "";
    }

    function encode(text, ecc = "M"): var {
        return DevToolsEngine.qrEncode(text, ecc);
    }

    function fromRows(rows): var {
        return DevToolsEngine.qrMatrixFromRows(rows);
    }

    function colors(style = "", overrides = null): var {
        const resolvedStyle = root._normalizeStyle(style, null);
        const palette = overrides ? Object.assign({}, root.themeColors, overrides) : root.themeColors;
        return DevToolsEngine.qrSvgResolveColors(resolvedStyle, palette);
    }

    function svg(matrix, style = "", options = ({})): string {
        if (!matrix)
            return "";
        const opts = options ?? ({});
        const resolvedStyle = root._normalizeStyle(style || opts.style, matrix);
        const resolvedDecoration = opts.decoration !== undefined
            ? Boolean(opts.decoration)
            : (matrix.decoration !== undefined ? Boolean(matrix.decoration) : root.decoration);
        const resolvedColors = opts.colors
            ? Object.assign({}, root.themeColors, opts.colors)
            : root.themeColors;
        const engineOpts = Object.assign({}, opts, {
            style: resolvedStyle,
            decoration: resolvedDecoration,
            shapes: opts.shapes ?? root._shapesCache
        });
        return DevToolsEngine.qrSvg(matrix, resolvedColors, engineOpts);
    }

    function copyImage(matrix, style = "", options = ({}), callback = null): void {
        let opts = options;
        let cb = callback;
        if (typeof opts === "function") {
            cb = opts;
            opts = ({});
        }
        const rows = root._rowsString(matrix);
        if (rows.length === 0) {
            const msg = Translation.tr("Could not copy the QR code (rsvg-convert or Pillow is needed)");
            if (typeof cb === "function")
                cb(false, msg);
            root.copyFinished(false, msg);
            return;
        }
        const resolvedStyle = root._normalizeStyle(style || opts?.style, matrix);
        const sizePx = opts?.sizePx ?? 800;
        const isStyled = resolvedStyle === "pixel" || resolvedStyle === "blob";
        let svgText = "";
        let cmd;
        if (isStyled) {
            svgText = root.svg(matrix, resolvedStyle, Object.assign({}, opts ?? ({}), { sizePx: sizePx }));
            cmd = ["bash", "-c", '"$@" | wl-copy --type image/png >/dev/null 2>&1', "qr",
                "python3", `${Directories.scriptPath}/images/qr_png.py`, "--svg", "-", "--rows", rows, "--size", String(sizePx), "-"];
        } else {
            cmd = ["bash", "-c", '"$@" | wl-copy --type image/png >/dev/null 2>&1', "qr",
                "python3", `${Directories.scriptPath}/images/qr_png.py`, rows, "-"];
        }
        const proc = exportProcComponent.createObject(root, {
            mode: "copy",
            pendingSvg: svgText,
            stdinEnabled: svgText.length > 0,
            command: cmd,
            callback: cb
        });
        if (proc)
            proc.running = true;
    }

    function savePng(matrix, style = "", path = "", options = ({}), callback = null): void {
        let targetPath = path;
        let opts = options;
        let cb = callback;
        if (typeof targetPath === "function") {
            cb = targetPath;
            targetPath = "";
            opts = ({});
        } else if (typeof opts === "function") {
            cb = opts;
            opts = ({});
        }
        const rows = root._rowsString(matrix);
        if (rows.length === 0) {
            const msg = Translation.tr("Could not save the QR code (python3 with Pillow or rsvg-convert is needed)");
            if (typeof cb === "function")
                cb(false, "", msg);
            root.saveFinished(false, "", msg);
            return;
        }
        const trimmed = String(targetPath ?? "").trim();
        let resolvedPath = trimmed.length > 0 ? FileUtils.trimFileProtocol(trimmed) : "";
        if (resolvedPath.length === 0) {
            const folder = FileUtils.trimFileProtocol(Directories.pictures);
            const stamp = new Date().toISOString().replace(/[:T]/g, "-").slice(0, 19);
            resolvedPath = `${folder}/qr-${stamp}.png`;
        }
        const resolvedStyle = root._normalizeStyle(style || opts?.style, matrix);
        const sizePx = opts?.sizePx ?? 800;
        const isStyled = resolvedStyle === "pixel" || resolvedStyle === "blob";
        let svgText = "";
        let cmd;
        if (isStyled) {
            svgText = root.svg(matrix, resolvedStyle, Object.assign({}, opts ?? ({}), { sizePx: sizePx }));
            cmd = ["python3", `${Directories.scriptPath}/images/qr_png.py`, "--svg", "-", "--rows", rows, "--size", String(sizePx), resolvedPath];
        } else {
            cmd = ["python3", `${Directories.scriptPath}/images/qr_png.py`, rows, resolvedPath];
        }
        const proc = exportProcComponent.createObject(root, {
            mode: "save",
            targetPath: resolvedPath,
            pendingSvg: svgText,
            stdinEnabled: svgText.length > 0,
            command: cmd,
            callback: cb
        });
        if (proc)
            proc.running = true;
    }

    Component {
        id: exportProcComponent

        Process {
            id: proc
            property string mode: "copy"
            property string targetPath: ""
            property string pendingSvg: ""
            property var callback: null

            onStarted: {
                if (proc.pendingSvg.length > 0) {
                    proc.write(proc.pendingSvg);
                    proc.pendingSvg = "";
                }
                proc.stdinEnabled = false;
            }

            onExited: (exitCode, exitStatus) => {
                const ok = exitCode === 0;
                if (proc.mode === "copy") {
                    const msg = ok
                        ? Translation.tr("QR code copied as an image")
                        : Translation.tr("Could not copy the QR code (rsvg-convert or Pillow is needed)");
                    if (typeof proc.callback === "function")
                        proc.callback(ok, msg);
                    root.copyFinished(ok, msg);
                } else {
                    const msg = ok
                        ? Translation.tr("Saved %1").arg(proc.targetPath)
                        : Translation.tr("Could not save the QR code (python3 with Pillow or rsvg-convert is needed)");
                    if (typeof proc.callback === "function")
                        proc.callback(ok, proc.targetPath, msg);
                    root.saveFinished(ok, proc.targetPath, msg);
                }
                Qt.callLater(() => proc.destroy());
            }
        }
    }
}
