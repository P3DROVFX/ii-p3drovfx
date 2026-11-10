// Desktop widgets share one full-screen layer: a single widget that keeps ticking
// while windows cover the desktop re-renders every widget on every frame. Every
// continuous driver in a widget must therefore be gated on the widget's `live`
// (AbstractBackgroundWidget: not paused by the host, visible, not transparent).
//
// Continuous drivers: a repeating Timer, a SystemClock, a FrameAnimation and any
// animation with `loops: Animation.Infinite`. Their `running:`/`enabled:` must read
// `live`, or one of the older equivalents that already stop with windows on screen
// (`hasActiveWindows`, MediaPlayerSource's `onScreen`/`animate`). A driver that is not
// continuous in practice can say so with a `live-exempt: <reason>` comment inside it.
//
// Run: node --test tests/background/widget_live.test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {test} = require('node:test');

const widgetsDir = path.resolve(__dirname, '../../modules/ii/background/widgets');
// The host machinery, not widgets: its timers are one-shot layout/animation helpers.
const infrastructure = new Set(['AbstractBackgroundWidget.qml', 'WidgetDelegate.qml', 'WidgetStateManager.qml']);
const gate = /\b(live|hasActiveWindows|onScreen|animate)\b/;

function qmlFiles(dir) {
    return fs.readdirSync(dir, {withFileTypes: true}).flatMap(entry => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory())
            return qmlFiles(full);
        return entry.name.endsWith('.qml') && !infrastructure.has(entry.name) ? [full] : [];
    });
}

// The text of the `{ ... }` block opening on `lines[start]`, by brace depth.
function block(lines, start) {
    let depth = 0;
    const out = [];
    for (let i = start; i < lines.length; i++) {
        const line = lines[i].replace(/\/\/(?!.*live-exempt).*$/, '');
        out.push(lines[i]);
        for (const ch of line) {
            if (ch === '{')
                depth++;
            else if (ch === '}')
                depth--;
        }
        if (depth <= 0 && i > start)
            break;
        if (depth <= 0 && line.includes('}'))
            break;
    }
    return out;
}

// Lines that belong to the block itself, not to blocks nested inside it.
function ownLines(text) {
    let depth = 0;
    return text.filter(line => {
        const own = depth === 1;
        for (const ch of line.replace(/\/\/.*$/, '')) {
            if (ch === '{')
                depth++;
            else if (ch === '}')
                depth--;
        }
        return own;
    });
}

function continuousDrivers(file) {
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    const found = [];
    lines.forEach((line, index) => {
        const match = line.match(/^\s*(?:property\s+\w+\s+\w+\s*:\s*)?(Timer|SystemClock|FrameAnimation|\w*Animation)\b[^{]*\{\s*$/);
        if (!match)
            return;
        const text = block(lines, index);
        const own = ownLines(text);
        const kind = match[1];
        const continuous = kind === 'SystemClock' || kind === 'FrameAnimation'
            || (kind === 'Timer' && own.some(l => /^\s*repeat\s*:\s*true\b/.test(l)))
            || (kind.endsWith('Animation') && own.some(l => /loops\s*:\s*Animation\.Infinite/.test(l)));
        if (!continuous || text.some(l => l.includes('live-exempt')))
            return;
        const gated = own.some(l => /^\s*(running|enabled)\s*:/.test(l) && gate.test(l));
        if (!gated)
            found.push(`${path.relative(widgetsDir, file)}:${index + 1} ${kind}`);
    });
    return found;
}

test('every continuous widget driver stops while the desktop is covered', () => {
    const ungated = qmlFiles(widgetsDir).flatMap(continuousDrivers);
    assert.deepEqual(ungated, [], `Gate these on the widget's \`live\` (see AbstractBackgroundWidget):\n  ${ungated.join('\n  ')}`);
});
