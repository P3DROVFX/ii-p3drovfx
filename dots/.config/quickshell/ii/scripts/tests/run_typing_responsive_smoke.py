"""Responsive Typing Test controls in Qt offscreen; no Quickshell or IPC."""

from pathlib import Path
import os
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


with tempfile.TemporaryDirectory(prefix="ii-typing-responsive-") as directory:
    out = Path(directory)

    def put(name: str, content: str) -> None:
        path = out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    for name in ("TypingTestToolbar.qml",):
        put("qs/modules/ii/overview/typing/" + name,
            (ROOT / "modules/ii/overview/typing" / name).read_text(encoding="utf-8"))
    hint_bar = (ROOT / "modules/common/widgets/KeyHintBar.qml").read_text(encoding="utf-8")
    # The smoke test is interested in Flow geometry; its key-face palette is
    # supplied by the full shell and is intentionally outside this fixture.
    hint_bar = hint_bar.replace("    property color onSurface: Appearance.colors.colOnSurface\n", "")
    hint_bar = hint_bar.replace("                onSurface: root.onSurface\n", "")
    hint_bar = hint_bar.replace("root.onSurface", '"white"')
    put("qs/modules/common/widgets/KeyHintBar.qml", hint_bar)

    put("qs/modules/common/Appearance.qml", '''pragma Singleton
import QtQuick
QtObject {
 property var colors: ({colOnPrimary:"#ffffff",colOnSurfaceVariant:"#dddddd",colPrimary:"#4455aa",colPrimaryHover:"#5566bb",colPrimaryActive:"#334499",colSurfaceContainerHigh:"#333333",colSurfaceContainerHighestHover:"#444444",colSurfaceContainerHighestActive:"#555555"})
 property var rounding: ({full:999})
 property var font: ({pixelSize:{small:15,smallest:12,normal:16}})
 property var sizes: ({elevationMargin:10})
 property var animation: ({elementMoveFast:{duration:0,type:0,bezierCurve:[]}})
}
''')
    put("qs/services/Translation.qml", '''pragma Singleton
import QtQuick
QtObject { function tr(text) { return text; } }
''')
    for name, content in {
        "StyledText": 'import QtQuick\nText { font.pixelSize: 15; color: "white" }',
        "MaterialSymbol": 'import QtQuick\nText { property real iconSize: 16; property real fill: 0; font.pixelSize: iconSize }',
        "StyledToolTip": 'import QtQuick\nItem { property string text: "" }',
        "ConfiguredKeyHint": '''import QtQuick
Item {
 property string actionId: ""
 property var fallbackKeys: []
 property color surface: "transparent"
 implicitWidth: label.implicitWidth + 10
 implicitHeight: label.implicitHeight + 4
 Text { id: label; anchors.centerIn: parent; text: fallbackKeys.join("+"); font.pixelSize: 12 }
}
''',
        "RippleButton": '''import QtQuick
Item {
 property real buttonRadius: 0
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colRipple: "transparent"
 property bool hovered: false
 signal clicked()
}
''',
    }.items():
        put("qs/modules/common/widgets/" + name + ".qml", content)

    for folder in list(out.rglob("*")):
        if not folder.is_dir():
            continue
        qmls = list(folder.glob("*.qml"))
        if qmls:
            module = ".".join(folder.relative_to(out).parts)
            entries = []
            for qml in qmls:
                singleton = "singleton " if "pragma Singleton" in qml.read_text(encoding="utf-8") else ""
                entries.append(f"{singleton}{qml.stem} 1.0 {qml.name}")
            put(str(folder.relative_to(out) / "qmldir"), "module " + module + "\n" + "\n".join(entries))

    put("tests/tst_responsive.qml", '''import QtQuick
import QtQuick.Layouts
import QtTest
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview.typing
import qs.services

Item {
 width: 1100; height: 600
 QtObject {
  id: engine
  property string state: "ready"
  property bool hasTarget: true
  property bool punctuation: false
  property bool numbers: false
  property string mode: "time"
  property int timeLimitSeconds: 15
  property int wordLimit: 10
 }
 Component { id: toolbar; TypingTestToolbar { engine: engine } }
 Component { id: hints; KeyHintBar {} }
 TestCase {
  name: "TypingResponsive"; when: windowShown
  function verifyChildrenFit(item) {
   for (let index = 0; index < item.children.length; index++) {
    const child = item.children[index];
    if (!child.visible || child.width === 0) continue;
    verify(child.x >= -1, "Child begins outside the responsive row: " + child.x);
    verify(child.x + child.width <= item.width + 1, "Child exceeds the responsive row: " + (child.x + child.width) + " / " + item.width);
   }
  }
  function test_toolbar_reflows_without_overflow() {
   const widths = [1000, 700, 320];
   const columns = [4, 2, 1];
   for (let index = 0; index < widths.length; index++) {
    const panel = createTemporaryObject(toolbar, parent, {width: widths[index]});
    verify(panel !== null); wait(5);
    const controls = findChild(panel, "typingTestControls");
    verify(controls !== null); compare(panel.controlColumns, columns[index]);
    verify(panel.implicitHeight >= panel.pillHeight);
    verify(controls.width <= panel.width + 0.01);
    verifyChildrenFit(controls);
    panel.destroy(); wait(1);
   }
  }
  function test_shortcuts_wrap_as_complete_pairs() {
   const strip = createTemporaryObject(hints, parent, {width: 180,
    hints: [
     {label:"Back",keys:["Esc"]}, {label:"Restart",keys:["Tab","Enter"]},
     {label:"Next test",keys:["Shift","Enter"]}, {label:"Mode",keys:["Ctrl","1-3"]},
     {label:"Settings",keys:["Ctrl",","]}
    ]
   });
   verify(strip !== null); wait(5);
   verify(strip.implicitHeight > 20, "The shortcut strip must gain rows instead of clipping");
   const flow = strip.children[0];
   verify(flow !== null); verifyChildrenFit(flow);
   verify(flow.children[1].y > flow.children[0].y, "At least one complete shortcut should wrap");
  }
 }
}
''')

    result = subprocess.run(
        ["/usr/lib64/qt6/bin/qmltestrunner", "-input", str(out / "tests"), "-import", str(out)],
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
        timeout=30,
        capture_output=True,
        text=True,
    )
    print(result.stdout, end="")
    print(result.stderr, end="")
    if re.search(r"ReferenceError|TypeError|Binding loop|Unable to assign|is not defined", result.stdout + result.stderr):
        raise SystemExit(1)
    raise SystemExit(result.returncode)
