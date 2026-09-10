"""Exercise the To-Do TaskList offscreen with service and style stubs.

Runs Qt Quick Test, never Quickshell, and does not touch real task storage.
Covers the reduced inter-item spacing and the priority container/on-color
mapping (0 keeps the legacy surface; 1/3/5 take primary/tertiary/error
pairs); it does not verify the live theme.
"""
from pathlib import Path
import re,json,os,subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[2]
temporary=tempfile.TemporaryDirectory(prefix="ii-tasklist-smoke-")
out=Path(temporary.name)
def put(rel,text):
 p=out/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)

source=(root/'modules/common/dashboardWidgets/todo/TaskList.qml').read_text()
put('qs/modules/common/dashboardWidgets/todo/TaskList.qml',source)
# The real list view carries the spacing under test; only its scrollbar is stubbed.
put('qs/modules/common/widgets/StyledListView.qml',(root/'modules/common/widgets/StyledListView.qml').read_text())
put('qs/modules/common/widgets/StyledScrollBar.qml','import QtQuick\nimport QtQuick.Controls\nScrollBar {}')
put('Quickshell/ScriptModel.qml','''import QtQuick
ListModel {
 property var values: []
 function sync() { clear(); for (const v of values) append({modelData: v}); }
 onValuesChanged: sync()
 Component.onCompleted: if (count === 0) sync()
}
''')
put('Quickshell/qmldir','module Quickshell\nScriptModel 1.0 ScriptModel.qml\n')
put('qs/modules/common/animations/SidebarGroupAnimation.qml','import QtQuick\nNumberAnimation { property var animationSpec; duration: 1 }')
put('qs/modules/common/widgets/StyledText.qml','import QtQuick\nText { font.pixelSize: 16; color: "white" }')
put('qs/modules/common/widgets/MaterialSymbol.qml','import QtQuick\nText { property real iconSize: 16; font.pixelSize: iconSize }')
put('qs/modules/common/widgets/RippleButton.qml','''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 10
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colBackgroundActive: "transparent"
}
''')
put('qs/modules/common/widgets/StyledToolTip.qml','import QtQuick.Controls\nToolTip { property bool extraVisibleCondition: true }')
put('qs/modules/common/widgets/TodoItemActionButton.qml',(root/'modules/common/dashboardWidgets/todo/TodoItemActionButton.qml').read_text())

alltext=source+(root/'modules/common/widgets/StyledListView.qml').read_text()
colors=set(re.findall(r'Appearance\.colors\.(\w+)',alltext));m3=set(re.findall(r'Appearance\.m3colors\.(\w+)',alltext));rounding=set(re.findall(r'Appearance\.rounding\.(\w+)',alltext));sizes=set(re.findall(r'Appearance\.font\.pixelSize\.(\w+)',alltext))
palette={'colLayer2':'#222222','colSurfaceContainerHigh':'#333333','colError':'#d32f2f','colErrorHover':'#c62828','colOnError':'#ffffff','colTertiaryContainer':'#00ff00','colTertiaryContainerHover':'#00ee00','colSecondaryContainer':'#888888','colSecondaryContainerHover':'#777777','colOnSecondaryContainer':'#111100','colOnSurface':'#111111','colOnSurfaceVariant':'#555555','colOnTertiaryContainer':'#000000','colPrimary':'#0000cc','colOnLayer1':'#444444','colTertiary':'#00cc00'}
m3palette={'m3error':'#ff0000','m3outline':'#999999','m3surfaceContainerHighest':'#444444','m3onTertiaryContainer':'#003300','m3tertiaryContainer':'#00ff00'}
appearance='''pragma Singleton
import QtQuick
QtObject {
 property var colors: %s
 property var m3colors: %s
 property var rounding: %s
 property real animMultiplier: 1.0
 property var animationCurves: ({expressiveDefaultSpatial: [0.4, 0, 0.2, 1]})
 property var sizes: ({elevationMargin: 8})
 property var font: ({ pixelSize: %s, family: {main: "sans-serif",numbers:"sans-serif"} })
 property Component num: NumberAnimation { duration: 1 }
 property Component col: ColorAnimation { duration: 1 }
 property var a: ({duration: 1,type: Easing.Linear,bezierCurve: [0,0,1,1,1,1],numberAnimation:num,colorAnimation:col})
 property var animation: ({scroll:a,elementMove:a,elementMoveFast:a,elementMoveEnter:a})
}
'''%(json.dumps({k:palette.get(k,'#123456') for k in colors}),json.dumps({k:m3palette.get(k,'#654321') for k in m3}),json.dumps({k:12 for k in rounding}),json.dumps({k:16 for k in sizes}))
put('qs/modules/common/Appearance.qml',appearance)
put('qs/modules/common/Config.qml','''pragma Singleton
import QtQuick
QtObject {
 property bool ready: true
  property QtObject options: QtObject {
  property QtObject sidebar: QtObject { property bool dashboardEntranceAnimations: false }
  property QtObject appearance: QtObject { property bool settingsPerformanceMode: false }
  property QtObject interactions: QtObject {
   property QtObject scrolling: QtObject {
    property real touchpadScrollFactor: 100
    property real mouseScrollFactor: 50
    property real mouseScrollDeltaThreshold: 120
   }
  }
 }
}
''')
put('qs/modules/common/functions/ColorUtils.qml','pragma Singleton\nimport QtQuick\nQtObject { function applyAlpha(c,a) { var col = Qt.color(c); return Qt.rgba(col.r, col.g, col.b, a); } function mix(a,b,t) { return a; } function transparentize(c,a) { return c; } }')
put('qs/services/Translation.qml','pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }')
put('qs/services/Todo.qml','''pragma Singleton
import QtQuick
QtObject {
 function markDone(t) {}
 function markUnfinished(t) {}
 function deleteItem(t) {}
}
''')

for folder in out.rglob('*'):
 if not folder.is_dir():continue
 qmls=list(folder.glob('*.qml'))
 if not qmls:continue
 (folder/'qmldir').write_text('module '+'.'.join(folder.relative_to(out).parts)+'\n'+'\n'.join(('singleton ' if 'pragma Singleton' in p.read_text() else '')+p.stem+' 1.0 '+p.name for p in qmls)+'\n')

put('tests/tst_TaskList.qml','''import QtQuick
import QtTest
import qs.modules.common.dashboardWidgets.todo

Item {
 width: 360; height: 600

 Component {
  id: listComponent
  TaskList {
   width: 360; height: 600
   taskList: [
    {content: "No priority", done: false, priority: 0, tags: [], hasDate: false, date: null, notes: ""},
    {content: "Low", done: false, priority: 1, tags: [], hasDate: false, date: null, notes: ""},
    {content: "Medium", done: false, priority: 3, tags: [], hasDate: false, date: null, notes: ""},
    {content: "High", done: false, priority: 5, tags: [], hasDate: true, date: new Date(), notes: ""}
   ]
  }
 }

 function delegates(item) {
  const found = [];
  (function scan(node) {
   if (node.taskPriority !== undefined && node.modelData !== undefined) found.push(node);
   for (const child of node.children ?? []) scan(child);
  })(item);
  return found.sort((a, b) => a.y - b.y);
 }

 TestCase {
  name: "TaskList"
  when: windowShown

  function waitForRows(view) {
   let rows = [];
   for (let i = 0; i < 40 && rows.length !== 4; ++i) { wait(25); rows = delegates(view); }
   return rows;
  }

  function test_spacing_is_reduced() {
   const view = createTemporaryObject(listComponent, parent);
   verify(view !== null);
   compare(view.todoListItemSpacing, 2);
   const rows = waitForRows(view);
   compare(rows.length, 4);
   // Real geometry: each row starts exactly one spacing after the previous ends.
   compare(rows[1].y, rows[0].y + rows[0].height + 2);
   compare(rows[2].y, rows[1].y + rows[1].height + 2);
   compare(rows[3].y, rows[2].y + rows[2].height + 2);
  }

  function test_priority_container_mapping() {
   const view = createTemporaryObject(listComponent, parent);
   const rows = waitForRows(view);
   compare(rows.length, 4);
   const byPriority = {};
   for (const row of rows) byPriority[row.modelData.priority] = row;
   compare(String(byPriority[0].priorityContainer), "#222222");
   compare(String(byPriority[1].priorityContainer), "#888888");
   compare(String(byPriority[3].priorityContainer), "#00ff00");
   compare(String(byPriority[5].priorityContainer), "#d32f2f");
  }

  function test_priority_on_color_mapping() {
   const view = createTemporaryObject(listComponent, parent);
   const rows = waitForRows(view);
   compare(rows.length, 4);
   const byPriority = {};
   for (const row of rows) byPriority[row.modelData.priority] = row;
   compare(String(byPriority[0].priorityOnContainer), "#111111");
   compare(String(byPriority[1].priorityOnContainer), "#111100");
   compare(String(byPriority[3].priorityOnContainer), "#000000");
   compare(String(byPriority[5].priorityOnContainer), "#ffffff");
  }
 }
}
''')

runner = shutil.which("qmltestrunner6") or "/usr/lib64/qt6/bin/qmltestrunner"
try:
    result = subprocess.run([runner, "-input", str(out/"tests"), "-import", str(out)],
                            env={**os.environ, "QT_QPA_PLATFORM":"offscreen", "QT_QUICK_BACKEND":"software", "QT_QUICK_CONTROLS_STYLE":"Basic"},
                            timeout=60, capture_output=True, text=True)
    print(result.stdout, end=''); print(result.stderr, end='')
    raise SystemExit(result.returncode)
finally:
    temporary.cleanup()
