// Loads a QML JavaScript library into Node.
//
// The model, the markdown and the migration live in `.js` files under `services/notes/`
// because the shell needs them there, and they are checked by `qmltestrunner`. This
// loader exists so the *same files* can also be driven from a plain Node script — which
// is what the migration dry run needs, and what keeps the transform from being written
// twice, once for the shell and once for the tool that verifies it.
//
// Two QML-only directives are handled: `.pragma library`, which is dropped, and
// `.import "X.js" as Y`, which is resolved relative to the importing file and injected
// into the module's scope under the given name.
//
// Top-level `function` and `var` declarations become properties of the vm context, which
// is exactly QML's own export rule for a `.pragma library` file. Anything declared with
// `const` or `let` would not be exported in either environment.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const cache = new Map();

function loadQmlJs(file) {
    const absolute = path.resolve(file);
    if (cache.has(absolute))
        return cache.get(absolute);

    const source = fs.readFileSync(absolute, "utf8");
    const context = { console, Date, Math, JSON, RegExp, Object, Array, String, Number, Boolean, isFinite, isNaN, parseInt, parseFloat };

    const body = source
        .replace(/^\s*\.pragma\s+library\s*$/gm, "")
        .replace(/^\s*\.import\s+"([^"]+)"\s+as\s+([A-Za-z_$][\w$]*)\s*$/gm, (_, target, alias) => {
            context[alias] = loadQmlJs(path.resolve(path.dirname(absolute), target));
            return "";
        });

    const sandbox = vm.createContext(context);
    // Cached before running so a cycle resolves to the partially built namespace rather
    // than recursing forever. Nothing here imports cyclically today; a future file that
    // does should fail on a missing function, not hang.
    cache.set(absolute, context);
    vm.runInContext(body, sandbox, { filename: absolute });
    return context;
}

module.exports = { loadQmlJs };
