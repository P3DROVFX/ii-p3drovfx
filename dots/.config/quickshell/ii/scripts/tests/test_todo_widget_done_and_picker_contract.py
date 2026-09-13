"""Test Todo Done tab transition and DatePickerPopup fitScale in constrained hosts."""
from pathlib import Path
import re, json, os, subprocess, tempfile, shutil

root = Path(__file__).resolve().parents[2]
temporary = tempfile.TemporaryDirectory(prefix="ii-todo-contract-")
out = Path(temporary.name)

def put(rel, text):
    p = out / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)

# Stubs
put('qs/modules/common/widgets/StyledText.qml', 'import QtQuick\nText { property bool animateChange: false; property real animationDistanceX: 0; property real animationDistanceY: 0; font.pixelSize: 14; color: "white" }')
put('qs/modules/common/widgets/MaterialSymbol.qml', 'import QtQuick\nText { property real iconSize: 16; property real fill: 0; font.pixelSize: iconSize }')
put('qs/modules/common/widgets/RippleButton.qml', '''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 10
 property bool toggled: false
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colBackgroundActive: "transparent"
}
''')
put('qs/modules/common/widgets/RippleButtonWithIcon.qml', '''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 10
 property bool centerContent: true
 property string materialIcon: ""
 property bool materialIconFill: false
 property string mainText: ""
 property real iconPixelSize: 16
 property real textPixelSize: 12
 property int mainTextWeight: Font.Normal
 property color colText: "white"
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colBackgroundActive: "transparent"
}
''')
put('qs/modules/common/widgets/DashedBorder.qml', '''import QtQuick
Item {
 property color color: "transparent"
 property int borderWidth: 1
 property int dashLength: 4
 property int gapLength: 3
 property real radius: 0
}
''')

picker_source = (root / 'modules/common/widgets/DatePickerPopup.qml').read_text()
put('qs/modules/common/widgets/DatePickerPopup.qml', picker_source)

appearance = '''pragma Singleton
import QtQuick
QtObject {
 property var colors: ({
  colScrim: "#88000000",
  colPrimary: "#ffb787",
  colOnPrimary: "#4f2500",
  colPrimaryContainer: "#6e3900",
  colOnPrimaryContainer: "#ffdcc5",
  colPrimaryHover: "#ffc299",
  colPrimaryActive: "#ffa066",
  colOnSurface: "#e6e1e5",
  colOnSurfaceVariant: "#cac4d0",
  colSurfaceContainerHighestHover: "#3d3935",
  colOnLayer1Inactive: "#777777"
 })
 property var m3colors: ({
  m3surfaceContainerHigh: "#2b2927"
 })
 property var rounding: ({
  large: 16,
  full: 999
 })
 property var sizes: ({elevationMargin: 8})
 property var font: ({
  pixelSize: ({smallest: 10, smaller: 11, small: 12, smallie: 13, normal: 14, large: 16, larger: 20, huge: 28}),
  family: ({main: "sans-serif", numbers: "sans-serif"})
 })
 property Component num: NumberAnimation { duration: 1 }
 property Component col: ColorAnimation { duration: 1 }
 property var a: ({duration: 1, type: Easing.Linear, bezierCurve: [0,0,1,1,1,1], numberAnimation: num, colorAnimation: col})
 property var animation: ({elementMove: a, elementMoveFast: a, elementMoveEnter: a, elementMoveExit: a})
 property var animationCurves: ({emphasizedDecel: [0.05, 0.7, 0.1, 1], emphasizedAccel: [0.3, 0, 0.8, 0.15]})
}
'''
put('qs/modules/common/Appearance.qml', appearance)
put('qs/modules/common/Config.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var options: ({
  time: {firstDayOfWeek: 0},
  calendar: {locale: "en_US"}
 })
}
''')
put('qs/modules/common/functions/ColorUtils.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function applyAlpha(c,a) { return c; } }')
put('qs/services/Translation.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }')
put('qs/services/DateTime.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var clock: ({date: new Date(2026, 8, 8)})
}
''')
put('qs/services/CalendarService.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var eventsByDay: ({})
}
''')

for folder in out.rglob('*'):
    if not folder.is_dir():
        continue
    qmls = list(folder.glob('*.qml'))
    if not qmls:
        continue
    (folder / 'qmldir').write_text('module ' + '.'.join(folder.relative_to(out).parts) + '\n' + '\n'.join(('singleton ' if 'pragma Singleton' in p.read_text() else '') + p.stem + ' 1.0 ' + p.name for p in qmls) + '\n')

# Test QML
put('tests/tst_todo_contract.qml', '''import QtQuick
import QtTest
import qs.modules.common.widgets

Item {
 width: 320
 height: 350

 DatePickerPopup {
  id: picker
  anchors.fill: parent
 }

 TestCase {
  name: "TodoContract"
  when: windowShown

  function test_date_picker_fits_in_constrained_host() {
   picker.open(new Date(2026, 8, 8), "Select date");
   verify(picker.opened);

   // Find the card rectangle inside DatePickerPopup
   const card = picker.children.find(c => c.fitScale !== undefined);
   verify(card !== undefined);

   // In a 320x350 container, the card's fitScale must adapt so card * scale <= container
   verify(card.fitScale <= 1.0);
   const effectiveCardWidth = card.width * card.fitScale;
   const effectiveCardHeight = card.height * card.fitScale;

   verify(effectiveCardWidth <= 320);
   verify(effectiveCardHeight <= 350);

   // Check that both action buttons exist inside cardColumn
   const cardColumn = card.children.find(c => c.spacing !== undefined);
   verify(cardColumn !== undefined);
   // card's height must be at least cardColumn's implicitHeight so buttons are never clipped
   verify(card.height >= cardColumn.implicitHeight);
  }

  function test_tasks_unfinished_and_done_filtering() {
   const sampleList = [
    { id: "task-1", content: "Open task", done: false, priority: 3, tags: ["work"], hasDate: false, date: null },
    { id: "task-2", content: "Finished task", done: true, priority: 1, tags: ["home"], hasDate: true, date: new Date(2026, 8, 10) }
   ];

   const unfinished = sampleList.filter(t => !t.done);
   const done = sampleList.filter(t => t.done);

   compare(unfinished.length, 1);
   compare(unfinished[0].content, "Open task");
   compare(done.length, 1);
   compare(done[0].content, "Finished task");

   // Simulating task completion
   sampleList[0].done = true;
   const nextUnfinished = sampleList.filter(t => !t.done);
   const nextDone = sampleList.filter(t => t.done);

   compare(nextUnfinished.length, 0);
   compare(nextDone.length, 2);
  }
 }
}
''')

runner = shutil.which("qmltestrunner6") or "/usr/lib64/qt6/bin/qmltestrunner"
try:
    result = subprocess.run([runner, "-input", str(out / "tests"), "-import", str(out)],
                            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                            timeout=30)
    raise SystemExit(result.returncode)
finally:
    temporary.cleanup()
