// TeX → SVG for the Anki tab (scripts/anki/anki_daemon.py), with MathJax 3 — the same
// engine Anki's reviewer uses, so \( \) and \[ \] read as they do in Anki.
//
// Runs from ~/.local/share/ii-anki/mathjax (the installer copies it next to its
// node_modules; ES modules resolve imports from the script's own folder). One JSON
// request per stdin line: {"tex": "...", "display": bool}; one JSON reply per line:
// {"svg": "..."} or {"error": "..."}. The SVG keeps `currentColor` and ex units; the
// daemon colours and sizes it.
import { mathjax } from "mathjax-full/js/mathjax.js";
import { TeX } from "mathjax-full/js/input/tex.js";
import { SVG } from "mathjax-full/js/output/svg.js";
import { liteAdaptor } from "mathjax-full/js/adaptors/liteAdaptor.js";
import { RegisterHTMLHandler } from "mathjax-full/js/handlers/html.js";
import { AllPackages } from "mathjax-full/js/input/tex/AllPackages.js";
import readline from "node:readline";

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
const doc = mathjax.document("", {
    InputJax: new TeX({ packages: AllPackages.filter(p => p !== "bussproofs") }),
    // Paths inline: Qt's SVG renderer has no <use> cache to resolve against.
    OutputJax: new SVG({ fontCache: "none" }),
});

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", line => {
    let reply;
    try {
        const req = JSON.parse(line);
        const node = doc.convert(req.tex, { display: !!req.display });
        let svg = adaptor.outerHTML(node);
        svg = svg.replace(/^<mjx-container[^>]*>/, "").replace(/<\/mjx-container>$/, "");
        // MathJax reports TeX errors as an <merror> inside a valid SVG.
        reply = svg.includes('data-mml-node="merror"') ? { error: "TeX error" } : { svg };
    } catch (e) {
        reply = { error: String(e && e.message || e) };
    }
    process.stdout.write(JSON.stringify(reply) + "\n");
});
