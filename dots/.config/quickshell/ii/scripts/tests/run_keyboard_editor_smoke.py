"""Exercise the actual keyboard page/editor offscreen with IO and style stubs.

Runs Qt Quick Test, never Quickshell, and does not take screenshots or use HID.
This covers component state/interaction; it does not verify the live theme.
"""
from pathlib import Path
import re,json,os,subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[2]
temporary=tempfile.TemporaryDirectory(prefix="ii-keyboard-smoke-")
out=Path(temporary.name)
def put(rel,text):
 p=out/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
actual=['modules/ii/cheatsheet/CheatsheetKeyboardPage.qml','modules/ii/cheatsheet/CheatsheetKeybindEditorSidebar.qml','modules/common/widgets/KeyboardDiagram.qml','modules/common/widgets/KeyboardKey.qml','modules/common/functions/KeyboardMap.js']
alltext='\n'.join((root/p).read_text() for p in actual)
actual += ['modules/ii/cheatsheet/DeferredKeybindEditor.qml', 'modules/ii/cheatsheet/KeybindPageNavigation.qml', 'modules/common/widgets/RetainedLoader.qml']
for p in actual:
 content=(Path(os.environ['II_KEYBOARD_PAGE_SOURCE']).read_text() if p.endswith('/CheatsheetKeyboardPage.qml') and os.environ.get('II_KEYBOARD_PAGE_SOURCE') else (root/p).read_text())
 put('qs/'+p,content.replace('MaterialShape.Shape.Cookie9Sided', '0'))
s=(root/'modules/ii/overview/typing/TypingKeyboardLayouts.qml').read_text().replace('import Quickshell','').replace('Singleton {','QtObject {')
put('qs/modules/ii/overview/typing/TypingKeyboardLayouts.qml',s)
put('qs/modules/common/widgets/StyledText.qml','import QtQuick\nText { font.pixelSize: 16; color: "white" }')
put('qs/modules/common/widgets/StyledTextInput.qml','import QtQuick\nTextInput { color: "white"; font.pixelSize: 16 }')
put('qs/modules/common/widgets/MaterialSymbol.qml','import QtQuick\nText { property real iconSize: 16; property real fill: 0; font.pixelSize: iconSize }')
put('qs/modules/common/widgets/RippleButton.qml','''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 10
 property bool toggled: false
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colBackgroundActive: "transparent"
 property color colBackgroundToggled: "transparent"
 property color colBackgroundToggledHover: "transparent"
 property color colBackgroundToggledActive: "transparent"
}
''')
put('qs/modules/common/widgets/RippleButtonWithIcon.qml','''import QtQuick
RippleButton {
 property string materialIcon: ""
 property real mainTextWeight: 400
 property bool materialIconFill: false
 property real iconPixelSize: 16
 property real textPixelSize: 16
 property string mainText: "Button text"
 property bool centerContent: true
 property color colText: "white"
 property real contentImplicitWidth: 80
 text: mainText
 implicitWidth: mainText.length ? mainText.length*8+32 : 40
}
''')
put('qs/modules/common/widgets/StyledToolTip.qml','import QtQuick.Controls\nToolTip { property bool extraVisibleCondition: true }')
put('qs/modules/common/widgets/StyledFlickable.qml','import QtQuick\nFlickable {}')
put('qs/modules/common/widgets/StyledComboBox.qml','import QtQuick.Controls\nComboBox {}')
put('qs/modules/common/widgets/MaterialShape.qml','pragma Singleton\nimport QtQuick\nQtObject { property var shapes: ({Cookie9Sided:0}) }')
put('qs/modules/common/widgets/MaterialShapeWrappedMaterialSymbol.qml','''import QtQuick
Item { property string text: ""; property real iconSize: 16; property real padding: 10; property int shape: 0; property color color: "transparent"; property color colSymbol: "white"; implicitWidth: 40; implicitHeight: 40 }
''')
put('qs/modules/ii/cheatsheet/KeybindShortcutSequence.qml','''import QtQuick
Item { property string shortcutText: ""; property string keys: ""; property real pixelSize: 16; property bool compact: false; property real maximumWidth: 100; property color colBackground: "transparent"; property color colText: "white"; property string text: "" }
''')
for name,body in {'Translation':'function tr(s) { return s; }','ColorUtils':'function transparentize(c,a) { return c; }','KeybindTokenizer':'function keyEventToString(e) { return e.text; }'}.items():
 put('qs/modules/common/functions/'+name+'.qml','pragma Singleton\nimport QtQuick\nQtObject { '+body+' }')
colors=set(re.findall(r'Appearance.colors.(\w+)',alltext));m3=set(re.findall(r'Appearance.m3colors.(\w+)',alltext));rounding=set(re.findall(r'Appearance.rounding.(\w+)',alltext));sizes=set(re.findall(r'Appearance.font.pixelSize.(\w+)',alltext))
appearance='''pragma Singleton
import QtQuick
QtObject {
 property var colors: %s
 property var m3colors: %s
 property var rounding: %s
 property var font: ({ pixelSize: %s, family: {main: "sans-serif",title:"sans-serif",monospace:"monospace",iconNerd:"monospace"} })
 property Component num: NumberAnimation { duration: 1 }
 property Component col: ColorAnimation { duration: 1 }
 property var a: ({duration: 1,type: Easing.Linear,bezierCurve: [0,0,1,1,1,1],numberAnimation:num,colorAnimation:col})
 property var animation: ({elementMove:a,elementMoveFast:a,elementMoveEnter:a,elementMoveExit:a})
}
'''%(json.dumps({k:'#eeeeee' if 'On' in k else '#333333' for k in colors}),json.dumps({k:'#222222' for k in m3}),json.dumps({k:12 for k in rounding}),json.dumps({k:16 for k in sizes}))
put('qs/modules/common/Appearance.qml',appearance)
put('qs/modules/common/Config.qml','pragma Singleton\nimport QtQuick\nQtObject { property var options: ({cheatsheet:{},appearance:{transparency:{enable:false}}}) }')
put('qs/services/VialKeyboard.qml','''pragma Singleton
import QtQuick
QtObject { property bool loading: false; property var snapshot: ({}); signal readFinished(bool success); function refresh() {} }
''')
put('qs/services/KeybindsService.qml','''pragma Singleton
import QtQuick
QtObject {
 property int revision: 0
 property bool writable: true
 property bool detectingSystemKeyboard: false
 property var pages: []
 property var lastEdit: null
 function pageById(id) { return pages.find(p=>p.id===id) || null; }
 function detectConflicts() { return []; }
 function updateKeyboardKey(id,l,i,label,icon,description) { lastEdit={id:id,l:l,i:i,label:label,icon:icon}; return true; }
 function setKeyboardMap(id,board) { const p=JSON.parse(JSON.stringify(pages)); p.find(x=>x.id===id).keyboard=board; pages=p; revision++; return true; }
 function updatePage() {return true;}
 signal operationFinished(bool success, string message, string pageId)
}
''')
for folder in out.rglob('*'):
 if not folder.is_dir():continue
 qmls=list(folder.glob('*.qml'))
 if not qmls:continue
 (folder/'qmldir').write_text('module '+'.'.join(folder.relative_to(out).parts)+'\n'+'\n'.join(('singleton ' if 'pragma Singleton' in p.read_text() else '')+p.stem+' 1.0 '+p.name for p in qmls)+'\n')
put('tests/tst_keyboard.qml','''import QtQuick
import QtTest
import qs.modules.ii.cheatsheet
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.overview.typing
import "../qs/modules/common/functions/KeyboardMap.js" as KeyboardMap
Item {
 width: 1200; height: 700
 Component { id: pageComponent; CheatsheetKeyboardPage { width:1200; height:700; pageId:"test" } }
 Component { id: navigationComponent; KeybindPageNavigation {} }
 Component {
  id: retainedComponent
  RetainedLoader {
   retainFor: 60
   property int constructions: 0
   sourceComponent: Item { Component.onCompleted: parent.constructions++ }
  }
 }
 TestCase {
  name: "KeyboardEditor"; when: windowShown
  function countVisualItems(item) {
   let count=1;
   for(const child of item.children ?? []) count+=countVisualItems(child);
   return count;
  }
  function test_editor_is_deferred_until_requested() {
   KeybindsService.pages=[{id:"test",name:"QWERTY",kind:"keyboard",keyboard:KeyboardMap.manual(TypingKeyboardLayouts.rowsFor("qwerty"),"qwerty")}];
   const start=Date.now();
   const page=createTemporaryObject(pageComponent,parent); verify(page !== null);
   warn("Keyboard consultation: "+countVisualItems(page)+" visual objects, "+(Date.now()-start)+" ms construction (offscreen/stub styles)");
   verify(findChild(page,"keyboardEditor") === null,"The editor must not be constructed during consultation");
   findChild(page,"keyboardDiagram").keyClicked(0); wait(10);
   verify(findChild(page,"keyboardEditor") !== null);
   findChild(page,"keyboardEditor").close();
   tryVerify(()=>findChild(page,"keyboardEditor") === null,1000,"A closed editor must leave the permanent cache");
   findChild(page,"keyboardDiagram").keyClicked(1); wait(10);
   verify(findChild(page,"keyboardEditor") !== null);
   compare(findChild(page,"keyboardEditor").keyboardIndex,1);
  }
  function test_reopen_reuses_tree_and_idle_expiry_releases_it() {
   const cache=createTemporaryObject(retainedComponent,parent); verify(cache !== null);
   compare(cache.item,null); compare(cache.constructions,0);
   cache.requested=true; tryCompare(cache,"status",Loader.Ready);
   const first=cache.item; compare(cache.constructions,1);
   for(let i=0;i<30;i++) {
    cache.requested=false; cache.requested=true;
    wait(1);
    compare(cache.item,first); compare(cache.constructions,1);
   }
   wait(80); compare(cache.item,first); // A cancelled expiry cannot destroy an open page.
   cache.requested=false; tryCompare(cache,"item",null,500);
   cache.requested=true; tryCompare(cache,"status",Loader.Ready);
   compare(cache.constructions,2);
  }
  function test_initial_open_is_retained_too() {
   const cache=createTemporaryObject(retainedComponent,parent,{requested:true});
   tryCompare(cache,"status",Loader.Ready);
   const first=cache.item; cache.requested=false; wait(10);
   compare(cache.item,first); cache.requested=true;
   compare(cache.constructions,1);
  }
  function test_page_and_group_shortcuts_follow_rail_order() {
   const nav=createTemporaryObject(navigationComponent,parent,{
    groups:[[""],["kitty","vscode"],["corne","abnt2"],[]],currentPageId:"kitty"
   });
   nav.pageRequested.connect(function(id) { nav.currentPageId=id; });
   nav.forceActiveFocus(); keyClick(Qt.Key_Down); compare(nav.currentPageId,"vscode");
   keyClick(Qt.Key_Down); compare(nav.currentPageId,"corne");
   keyClick(Qt.Key_Down,Qt.ControlModifier); compare(nav.currentPageId,"");
   keyClick(Qt.Key_Up,Qt.ControlModifier); compare(nav.currentPageId,"corne");
   keyClick(Qt.Key_Up); compare(nav.currentPageId,"vscode");
   nav.enabled=false; keyClick(Qt.Key_Down); compare(nav.currentPageId,"vscode");
   nav.enabled=true; nav.groups=[[""],[],["corne"]]; nav.currentPageId="";
   keyClick(Qt.Key_Down,Qt.ControlModifier); compare(nav.currentPageId,"corne");
   nav.visible=false; keyClick(Qt.Key_Up); compare(nav.currentPageId,"corne");
  }
  function test_page_navigation_does_not_conflict_with_layers_or_editing() {
   const board=KeyboardMap.manual(TypingKeyboardLayouts.rowsFor("qwerty"),"qwerty");
   board.layers.push(KeyboardMap.copy(board.layers[0]));
   KeybindsService.pages=[{id:"test",name:"Keyboard",kind:"keyboard",keyboard:board}];
   const page=createTemporaryObject(pageComponent,parent);
   const nav=createTemporaryObject(navigationComponent,page,{groups:[[""],["app"],["test"]],currentPageId:"test"});
   nav.enabled=Qt.binding(()=>!page.navigationLocked);
   nav.pageRequested.connect(function(id) { nav.currentPageId=id; });
   page.forceActiveFocus(); keyClick(Qt.Key_Right); compare(page.activeLayer,1); compare(nav.currentPageId,"test");
   keyClick(Qt.Key_Up); compare(nav.currentPageId,"app"); compare(page.activeLayer,1);
   findChild(page,"keyboardDiagram").keyClicked(0); wait(10);
   verify(!nav.enabled); keyClick(Qt.Key_Down); compare(nav.currentPageId,"app");
   findChild(page,"keyboardEditor").close(); wait(20);
   findChild(page,"keyboardName").forceActiveFocus(); verify(!nav.enabled);
  }
  function test_layer_shortcuts_and_text_focus() {
   const board=KeyboardMap.manual(TypingKeyboardLayouts.rowsFor("qwerty"),"qwerty");
   for(let i=1;i<6;i++)board.layers.push(KeyboardMap.copy(board.layers[0]));
   KeybindsService.pages=[{id:"test",name:"Keyboard",kind:"keyboard",keyboard:board}];
   const page=createTemporaryObject(pageComponent,parent); verify(page !== null); wait(20);
   page.forceActiveFocus(); verify(page.layerShortcutsEnabled);
   keyClick(Qt.Key_Right); compare(page.activeLayer,1);
   keyClick(Qt.Key_5); compare(page.activeLayer,5);
   keyClick(Qt.Key_Right); compare(page.activeLayer,0);
   keyClick(Qt.Key_Left); compare(page.activeLayer,5);
   keyClick(Qt.Key_9); compare(page.activeLayer,5);
   keyClick(Qt.Key_1,Qt.ControlModifier); compare(page.activeLayer,5);
   keyClick(Qt.Key_0); compare(page.activeLayer,0);
   page.tabActive=false; keyClick(Qt.Key_Right); compare(page.activeLayer,0);
   page.tabActive=true;
   const presets=findChild(page,"presetPicker"); presets.popup.open(); wait(10);
   verify(!page.layerShortcutsEnabled); keyClick(Qt.Key_Right); compare(page.activeLayer,0);
   presets.popup.close(); page.forceActiveFocus();
   const name=findChild(page,"keyboardName"); name.forceActiveFocus();
   verify(!page.layerShortcutsEnabled); keyClick(Qt.Key_3); compare(page.activeLayer,0);
   verify(name.text.includes("3"));
   page.forceActiveFocus();
   const diagram=findChild(page,"keyboardDiagram"); diagram.keyClicked(1); wait(10);
   verify(!page.layerShortcutsEnabled); keyClick(Qt.Key_4); compare(page.activeLayer,0);
   const editor=findChild(page,"keyboardEditor"); editor.close(); wait(30);
   page.forceActiveFocus(); keyClick(Qt.Key_2); compare(page.activeLayer,2);
   compare(findChild(page,"zoomOut").mainText,"");
  }
  function test_fast_layer_switch_and_reopen() {
   const board=KeyboardMap.manual(TypingKeyboardLayouts.rowsFor("qwerty"),"qwerty");
   for(let i=1;i<6;i++)board.layers.push(KeyboardMap.copy(board.layers[0]));
   KeybindsService.pages=[{id:"test",name:"Keyboard",kind:"keyboard",keyboard:board}];
   const page=createTemporaryObject(pageComponent,parent); verify(page !== null); wait(20);
   const diagram=findChild(page,"keyboardDiagram");
   for(let layer=0;layer<6;layer++) {
    page.selectLayer(layer); diagram.keyClicked(1); wait(5);
    const editor=findChild(page,"keyboardEditor");
    compare(editor.keyboardLayer,layer); verify(editor.isOpen);
    editor.close(); wait(5);
   }
  }
  function test_key_edit_and_layer_switch() {
   KeybindsService.pages=[{id:"test",name:"QWERTY",kind:"keyboard",keyboard:KeyboardMap.manual(TypingKeyboardLayouts.rowsFor("qwerty"),"qwerty")}];
   const page=createTemporaryObject(pageComponent,parent); verify(page !== null);
   wait(20);
   const diagram=findChild(page,"keyboardDiagram"); verify(diagram !== null);
   compare(diagram.keys.length,76); diagram.keyClicked(1); wait(20);
   const editor=findChild(page,"keyboardEditor"); verify(editor.isOpen); compare(editor.keyboardIndex,1);
   editor.iconValue="code"; editor.saveForm(); wait(20);
   compare(KeybindsService.lastEdit.icon,"code"); compare(KeybindsService.lastEdit.l,0);
   page.addLayer(); compare(page.activeLayer,1); compare(page.board.layers.length,2);
   page.selectLayer(0); compare(page.activeLayer,0);
   page.width=740; wait(20); verify(diagram.unit>=42); verify(diagram.width>0);
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
