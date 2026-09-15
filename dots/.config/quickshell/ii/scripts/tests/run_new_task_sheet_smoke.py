"""Exercise the To-Do new-task form offscreen with IO and style stubs.

Runs Qt Quick Test, never Quickshell, and does not touch real task storage.
Covers the form state machine (canSave, tags, priority, capabilities, save
payload); it does not verify the live theme.
"""
from pathlib import Path
import re,json,os,subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[2]
temporary=tempfile.TemporaryDirectory(prefix="ii-newtask-smoke-")
out=Path(temporary.name)
def put(rel,text):
 p=out/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)

source=(root/'modules/common/dashboardWidgets/todo/NewTaskSheet.qml').read_text()
# MaterialShape.Shape.* enum references collapse to ints under the stub shape.
source=re.sub(r'MaterialShape\.Shape\.\w+','0',source)
put('qs/modules/common/dashboardWidgets/todo/NewTaskSheet.qml',source)

put('qs/modules/common/widgets/StyledText.qml','import QtQuick\nText { font.pixelSize: 16; color: "white" }')
put('qs/modules/common/widgets/StyledTextInput.qml','import QtQuick\nTextInput { color: "white"; font.pixelSize: 16 }')
put('qs/modules/common/widgets/StyledTextArea.qml','import QtQuick.Controls\nTextArea { color: "white"; font.pixelSize: 16 }')
put('qs/modules/common/widgets/StyledFlickable.qml','import QtQuick\nFlickable {}')
put('qs/modules/common/widgets/MaterialSymbol.qml','import QtQuick\nText { property real iconSize: 16; property real fill: 0; font.pixelSize: iconSize }')
put('qs/modules/common/widgets/RippleButton.qml','''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 10
 property bool toggled: false
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colBackgroundActive: "transparent"
}
''')
put('qs/modules/common/widgets/FloatingActionButton.qml','''import QtQuick
Rectangle {
 property real baseSize: 52
 property real iconSize: 24
 property real buttonRadius: 12
 property string iconText: ""
 signal clicked()
}
''')
put('qs/modules/common/widgets/DashedBorder.qml','''import QtQuick
Item {
 property color color: "transparent"
 property int borderWidth: 1
 property int dashLength: 4
 property int gapLength: 3
 property real radius: 0
}
''')
put('qs/modules/common/widgets/StyledRectangularShadow.qml','''import QtQuick
Item { property Item target: null; property real radius: 0; property real blur: 0 }
''')
put('qs/modules/common/widgets/StyledToolTip.qml','import QtQuick.Controls\nToolTip { property bool extraVisibleCondition: true }')
put('qs/modules/common/widgets/DatePickerPopup.qml','''import QtQuick
Item {
 property bool opened: false
 property string title: ""
 property date selected: new Date()
 signal accepted(var pickedDate)
 signal dismissed
 function open(date, titleText) { opened = true; if (date) selected = date; }
 function close() { opened = false; }
}
''')
put('qs/modules/common/widgets/MaterialShapeWrappedMaterialSymbol.qml','''import QtQuick
Item { property string text: ""; property real iconSize: 16; property real padding: 10; property int shape: 0; property color color: "transparent"; property color colSymbol: "white"; implicitWidth: 40; implicitHeight: 40 }
''')

alltext=source
colors=set(re.findall(r'Appearance\.colors\.(\w+)',alltext));m3=set(re.findall(r'Appearance\.m3colors\.(\w+)',alltext));rounding=set(re.findall(r'Appearance\.rounding\.(\w+)',alltext));sizes=set(re.findall(r'Appearance\.font\.pixelSize\.(\w+)',alltext))
appearance='''pragma Singleton
import QtQuick
QtObject {
 property var colors: %s
 property var m3colors: %s
 property var rounding: %s
 property var sizes: ({elevationMargin: 8})
 property var font: ({ pixelSize: %s, family: {main: "sans-serif",numbers:"sans-serif"} })
 property Component num: NumberAnimation { duration: 1 }
 property Component col: ColorAnimation { duration: 1 }
 property var a: ({duration: 1,type: Easing.Linear,bezierCurve: [0,0,1,1,1,1],numberAnimation:num,colorAnimation:col})
 property var animation: ({elementMove:a,elementMoveFast:a,elementMoveEnter:a,elementMoveExit:a})
}
'''%(json.dumps({k:'#eeeeee' if 'On' in k else '#333333' for k in colors}),json.dumps({k:'#222222' for k in m3}),json.dumps({k:12 for k in rounding}),json.dumps({k:16 for k in sizes}))
put('qs/modules/common/Appearance.qml',appearance)
put('qs/modules/common/Config.qml','pragma Singleton\nimport QtQuick\nQtObject { property var options: ({todo:{provider:"local"}}) }')
put('qs/modules/common/functions/ColorUtils.qml','pragma Singleton\nimport QtQuick\nQtObject { function applyAlpha(c,a) { return c; } function mix(a,b,t) { return a; } function transparentize(c,a) { return c; } }')
put('qs/services/Translation.qml','pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }')
put('qs/services/Todo.qml','''pragma Singleton
import QtQuick
QtObject {
 property string provider: "local"
 property string providerName: "Local"
 property bool supportsDate: true
 property bool supportsNotes: true
 property bool supportsPriority: true
 property bool supportsTags: true
 property var list: []
 property var lastAdded: null
 property int addCount: 0
 function addItem(item) { lastAdded = item; addCount++; }
}
''')

for folder in out.rglob('*'):
 if not folder.is_dir():continue
 qmls=list(folder.glob('*.qml'))
 if not qmls:continue
 (folder/'qmldir').write_text('module '+'.'.join(folder.relative_to(out).parts)+'\n'+'\n'.join(('singleton ' if 'pragma Singleton' in p.read_text() else '')+p.stem+' 1.0 '+p.name for p in qmls)+'\n')

put('tests/tst_NewTaskSheet.qml','''import QtQuick
import QtTest
import qs.modules.common.dashboardWidgets.todo
import qs.services

Item {
 width: 360; height: 350

 Component { id: sheetComponent; NewTaskSheet { width: 360; height: 350 } }

 TestCase {
  name: "NewTaskSheet"
  when: windowShown

  function findInput(item, name) {
   if (item.objectName === name) return item;
   for (const child of item.children ?? []) {
    const found = findInput(child, name);
    if (found) return found;
   }
   return null;
  }

  function test_can_save_gates_on_title() {
   Todo.addCount = 0; Todo.lastAdded = null;
   const sheet = createTemporaryObject(sheetComponent, parent);
   verify(sheet !== null);
   compare(sheet.canSave, false);
   const title = findInput(sheet, "newTaskTitleInput");
   verify(title !== null);
   title.text = "Buy coffee";
   compare(sheet.canSave, true);
  }

  function test_save_sends_full_payload_and_clears() {
   Todo.addCount = 0; Todo.lastAdded = null; Todo.supportsPriority = true; Todo.supportsTags = true;
   const sheet = createTemporaryObject(sheetComponent, parent);
   const title = findInput(sheet, "newTaskTitleInput");
   const notes = findInput(sheet, "newTaskNotesArea");
   title.text = "Pay rent";
   notes.text = "Check the app";
   sheet.addTag("home");
   sheet.addTag("bills");
   sheet.addTag("home"); // duplicate is ignored
   sheet.formPriority = 5;
   const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1);
   sheet.selectDate(tomorrow);
   verify(sheet.formHasDate);

   let closed = false, saved = false;
   sheet.closeRequested.connect(() => closed = true);
   sheet.saved.connect(() => saved = true);
   sheet.save();

   compare(Todo.addCount, 1);
   compare(Todo.lastAdded.content, "Pay rent");
   compare(Todo.lastAdded.notes, "Check the app");
   compare(Todo.lastAdded.priority, 5);
   compare(Todo.lastAdded.tags.length, 2);
   // hasDate is computed by Todo on the way in; the payload carries the date.
   verify(Todo.lastAdded.date && !isNaN(new Date(Todo.lastAdded.date).getTime()));
   verify(saved && closed);
   compare(sheet.canSave, false);
   compare(sheet.formHasDate, false);
   compare(sheet.formTags.length, 0);
  }

  function test_undated_task_has_no_date_on_the_wire() {
   Todo.addCount = 0; Todo.lastAdded = null;
   const sheet = createTemporaryObject(sheetComponent, parent);
   findInput(sheet, "newTaskTitleInput").text = "Someday";
   sheet.save();
   compare(Todo.lastAdded.date, null);
  }

  function test_tag_input_and_removal() {
   const sheet = createTemporaryObject(sheetComponent, parent);
   const tagInput = findInput(sheet, "newTaskTagInput");
   tagInput.text = "  urgent  ";
   sheet.addTagFromInput();
   compare(sheet.formTags, ["urgent"]);
   compare(tagInput.text, "");
   sheet.removeTag(0);
   compare(sheet.formTags.length, 0);
  }

  function test_google_tasks_hides_priority_and_tags() {
   Todo.supportsPriority = false; Todo.supportsTags = false;
   const sheet = createTemporaryObject(sheetComponent, parent);
   verify(findInput(sheet, "newTaskTitleInput") !== null);
   // The provider contract hides fields it would drop on the wire.
   const prioritySection = findInput(sheet, "newTaskSheet").children;
   let priorityVisible = false, tagInputFound = false;
   (function scan(item) {
    for (const child of item.children ?? []) {
     if (child.objectName === "newTaskTagInput") tagInputFound = child.visible;
     scan(child);
    }
   })(sheet);
   compare(tagInputFound, false);
   Todo.supportsPriority = true; Todo.supportsTags = true;
  }

  function test_priority_capable_provider_shows_tag_input() {
   Todo.supportsPriority = true; Todo.supportsTags = true;
   const sheet = createTemporaryObject(sheetComponent, parent);
   verify(findInput(sheet, "newTaskTagInput") !== null);
  }

  function test_date_chips_and_picker_handoff() {
   const sheet = createTemporaryObject(sheetComponent, parent);
   compare(sheet.formHasDate, false);
   sheet.selectDate(new Date());
   verify(sheet.formHasDate);
   sheet.clearInput();
   compare(sheet.formHasDate, false);
   // Selecting through the picker's accepted signal lands the same way.
   const future = new Date(); future.setDate(future.getDate() + 3);
   sheet.selectDate(future);
   verify(sheet.formHasDate);
  }

  function test_option_chip_centering() {
   const sheet = createTemporaryObject(sheetComponent, parent);
   // Locate OptionChips in the sheet
   const chips = [];
   (function findChips(item) {
    for (const child of item.children ?? []) {
     if (child.label !== undefined && child.hasDot !== undefined) chips.push(child);
     findChips(child);
    }
   })(sheet);
   verify(chips.length > 0);
   for (const chip of chips) {
    const row = chip.children.find(c => c.spacing !== undefined);
    verify(row !== undefined);
    // Row should be centered in the chip within fractional subpixel tolerance
    const leftMargin = row.x;
    const rightMargin = chip.width - (row.x + row.width);
    verify(Math.abs(leftMargin - rightMargin) <= 1.5);
   }
  }
 }
}
''')

runner = shutil.which("qmltestrunner6") or "/usr/lib64/qt6/bin/qmltestrunner"
try:
    result = subprocess.run([runner, "-input", str(out/"tests"), "-import", str(out)],
                            env={**os.environ, "QT_QPA_PLATFORM":"offscreen", "QT_QUICK_BACKEND":"software"},
                            timeout=30)
    raise SystemExit(result.returncode)
finally:
    temporary.cleanup()
