#!/usr/bin/env bash
# Run Dev tools cases in BOTH Node and Qt 6's QML engine (QV4) and diff them.
# QV4 lacks Intl, BigInt, Array.prototype.flat/flatMap, regex named groups and
# lookbehind, Object.fromEntries on some builds, etc. — code that works in Node
# can throw or silently differ there.
#
#   scripts/dev/devtools_qv4_check.sh CASES.json
#   CASES.json = [["tool_id", "input", {options}], ...]
#
# Prints "ALL MATCH" or each differing case with both outputs.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASES="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ENGINE="$ROOT/modules/common/functions/devtools.js"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

node - "$ENGINE" "$CASES" > "$WORK/node.txt" <<'EOF'
const fs = require("fs"), vm = require("vm");
const code = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/m, "");
const sb = { module: { exports: {} }, TextEncoder, TextDecoder };
vm.createContext(sb); vm.runInContext(code, sb);
const d = sb.module.exports;
for (const c of JSON.parse(fs.readFileSync(process.argv[3], "utf8"))) {
    let line;
    try { const r = d.runTool(c[0], c[1], c[2] || {}); line = r.error ? "ERR " + r.error : "OK " + r.output; }
    catch (e) { line = "EXC " + e; }
    console.log(JSON.stringify(line));
}
EOF

python3 -I - "$ENGINE" "$CASES" "$WORK/check.qml" <<'EOF'
import json, sys
engine, cases, out = sys.argv[1:4]
data = json.load(open(cases))
open(out, "w").write(f'''import QtQuick
import QtQuick.Window
import "file://{engine}" as D
Window {{ Component.onCompleted: {{
  const cases = {json.dumps(data)};
  for (const c of cases) {{
    let line;
    try {{ const r = D.runTool(c[0], c[1], c[2] || {{}}); line = r.error ? "ERR " + r.error : "OK " + r.output; }}
    catch (e) {{ line = "EXC " + e; }}
    console.log("QV4CASE|" + JSON.stringify(line));
  }}
  Qt.quit();
}} }}
''')
EOF

QT_LOGGING_RULES="*.debug=true;*.info=true;*.warning=true" QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    timeout 120 /usr/lib64/qt6/bin/qml "$WORK/check.qml" > "$WORK/qv4.log" 2>&1
grep -a "QV4CASE|" "$WORK/qv4.log" | sed 's/^.*QV4CASE|//' > "$WORK/qv4.txt"
grep -aE "check.qml|devtools.js" "$WORK/qv4.log" | grep -av diskcache | grep -aiE "error|exception" | head -5

python3 -I - "$CASES" "$WORK/node.txt" "$WORK/qv4.txt" <<'EOF'
import json, sys
cases = json.load(open(sys.argv[1]))
node = [json.loads(l) for l in open(sys.argv[2])]
qv4 = [json.loads(l) for l in open(sys.argv[3])]
if len(qv4) != len(cases):
    print(f"QV4 ran {len(qv4)} of {len(cases)} cases (engine failed to load or crashed?)")
bad = 0
for c, a, b in zip(cases, node, qv4):
    if a != b:
        bad += 1
        print(f"DIFF {c[0]} {json.dumps(c[1])[:60]}\n  node: {a[:300]!r}\n  qv4 : {b[:300]!r}")
    elif a.startswith("EXC"):
        print(f"EXCEPTION in both: {c[0]} {a[:200]}")
if bad == 0 and len(qv4) == len(cases):
    print(f"ALL MATCH ({len(cases)} cases)")
EOF
