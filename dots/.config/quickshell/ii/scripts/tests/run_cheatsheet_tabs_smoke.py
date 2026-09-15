"""Exercise the actual cheatsheet tab controller/loaders in Qt, without Quickshell.

Only the window chrome, persistence IO and tab contents are replaced. The
selection block, ToolbarTabBar controller and SwipeView come from production.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


with tempfile.TemporaryDirectory(prefix="ii-tabs-smoke-") as directory:
    out = Path(directory)
    def put(name, text):
        if name == "tst_tabs.qml":
            text = text.replace("GlobalStates", "globalStates").replace("Persistent", "persistent")
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    source = (ROOT / "modules/ii/cheatsheet/Cheatsheet.qml").read_text()
    selection = source.split("property int selectedTab:", 1)[1].split("\n            anchors {", 1)[0]
    selection = "property int selectedTab:" + selection
    bar = block(source, "ToolbarTabBar {")
    swipe = block(source, "SwipeView {")
    toolbar = (ROOT / "modules/common/widgets/ToolbarTabBar.qml").read_text()
    controller = toolbar.split("Item {", 1)[1].split("    Layout.alignment:", 1)[0]
    put("ToolbarTabBar.qml", "import QtQuick\nItem {" + controller + "\n property bool showShortcutHints: false\n}")
    shutil.copy(ROOT / "modules/common/widgets/RetainedLoader.qml", out / "RetainedLoader.qml")
    put("TabBuilds.js", ".pragma library\nvar counts = ({});\nfunction record(name) { counts[name] = (counts[name] || 0) + 1; }\nfunction reset() { counts = ({}); }\n")
    for page in ["CheatsheetTimetable.qml", "CheatsheetKeybinds.qml", "CheatsheetPeriodicTable.qml",
                 "CheatsheetAminoAcids.qml", "commands/CheatsheetCommands.qml", "CheatsheetWorkspaces.qml",
                 "CheatsheetEmail.qml", "CheatsheetTypingTest.qml"]:
        put(page, 'import QtQuick\nimport "' + ('../' if '/' in page else '') + 'TabBuilds.js" as TabBuilds\nItem { property Item keyNavTarget: null; property string pageName: ' + json.dumps(page) + '; implicitWidth: 800; implicitHeight: 500; Component.onCompleted: TabBuilds.record(pageName) }')
    put("tst_tabs.qml", '''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "TabBuilds.js" as TabBuilds
import QtTest
Item {
 id: root; width: 1200; height: 700
 property bool activeState: true
 property bool cachePrepared: false
 property var tabButtonList: [
  {id:"timetable",icon:"calendar_month"}, {id:"keybinds",icon:"keyboard"},
  {id:"commands",icon:"terminal"}, {id:"workspaces",icon:"dashboard"},
  {id:"email",icon:"mail"}, {id:"typingTest",icon:"speed"}]
 function indexOfTab(id) {return tabButtonList.findIndex(t=>t.id===id);}
 QtObject {id: GlobalStates; property bool cheatsheetOpen: true}
 QtObject {id: Persistent; property QtObject states: QtObject {
  property QtObject cheatsheet: QtObject {property int tabIndex: 1}
 }}
 Item {id: cheatsheetBackground; property bool ctrlPressed: false}
 Component {
  id: frameComponent
  RetainedLoader {
   width: 1200; height: 700; requested: true; retainFor: 60
   sourceComponent: Item {
    id: cheatsheetRoot
    property var screen: ({width:1600,height:900})
    property alias view: swipeView
    property alias bar: tabBar
    ''' + selection + '''
    ColumnLayout {
     anchors.fill: parent
     ''' + bar + "\n" + swipe + '''
    }
   }
  }
 }
 TestCase {
  name: "CheatsheetTabs"; when: windowShown
  function init() { root.activeState=true; root.cachePrepared=false; TabBuilds.reset(); }
  function assertOnlySelectedLoaded(sheet,index) {
   tryCompare(sheet.view.itemAt(index),"status",Loader.Ready);
   for(let i=0;i<sheet.view.count;i++) {
    compare(sheet.view.itemAt(i).active,i===index);
    if(i!==index) compare(sheet.view.itemAt(i).item,null,"Only the selected tab may remain loaded");
   }
  }
  function test_last_tab_is_the_only_hidden_cache_data() {
   return [0,1,2,3,4,5].map(i=>({tag:String(i),saved:i}));
  }
  function test_last_tab_is_the_only_hidden_cache(data) {
   root.activeState=false; root.cachePrepared=true;
   Persistent.states.cheatsheet.tabIndex=data.saved;
   const frame=createTemporaryObject(frameComponent,root);
   tryCompare(frame,"status",Loader.Ready);
   const sheet=frame.item;
   tryCompare(sheet.view,"selectionReady",true);
   assertOnlySelectedLoaded(sheet,data.saved);
   tryCompare(sheet,"pageReady",true);
   compare(sheet.view.currentIndex,data.saved);
   compare(Object.keys(TabBuilds.counts).length,1,"Prewarm must not construct any other tab, even transiently");
   const tab=sheet.view.currentItem;
   const cached=tab.item;
   verify(!tab.visible); verify(!tab.enabled);
   for(let i=0;i<5;i++) {
    root.activeState=true;
    tryCompare(tab,"visible",true);
    root.activeState=false;
    assertOnlySelectedLoaded(sheet,data.saved);
    compare(tab.item,cached,"Reuse the same last tab across reopening");
   }
   compare(TabBuilds.counts[cached.pageName],1);
   root.cachePrepared=false;
   for(let i=0;i<sheet.view.count;i++) tryCompare(sheet.view.itemAt(i),"item",null);
  }
  function test_switching_tabs_replaces_the_cache() {
   root.cachePrepared=true;
   Persistent.states.cheatsheet.tabIndex=1;
   const frame=createTemporaryObject(frameComponent,root);
   tryCompare(frame,"status",Loader.Ready);
   const sheet=frame.item;
   tryCompare(sheet.view,"selectionReady",true);
   for(const index of [1,2,4,0,5,3,2]) {
    sheet.bar.setCurrentIndex(index);
    assertOnlySelectedLoaded(sheet,index);
   }
   const commands=sheet.view.currentItem.item;
   compare(commands.pageName,"commands/CheatsheetCommands.qml");
   root.activeState=false;
   assertOnlySelectedLoaded(sheet,2);
   compare(sheet.view.currentItem.item,commands);
   root.activeState=true;
   compare(sheet.view.currentItem.item,commands);
   compare(Persistent.states.cheatsheet.tabIndex,2);
  }
  function test_saved_tab_survives_asynchronous_creation_data() {
   return [0,1,2,3,4,5].map(i=>({tag:String(i),saved:i}));
  }
  function test_saved_tab_survives_asynchronous_creation(data) {
   Persistent.states.cheatsheet.tabIndex=data.saved;
   const frame=createTemporaryObject(frameComponent,root);
   tryCompare(frame,"status",Loader.Ready);
   const sheet=frame.item; wait(150);
   compare(Persistent.states.cheatsheet.tabIndex,data.saved);
   compare(sheet.bar.currentIndex,data.saved);
   compare(sheet.view.currentIndex,data.saved);
   verify(sheet.view.currentItem !== null);
   tryCompare(sheet.view.currentItem,"status",Loader.Ready);
   compare(sheet.view.currentItem.item.pageName,["CheatsheetTimetable.qml","CheatsheetKeybinds.qml","commands/CheatsheetCommands.qml","CheatsheetWorkspaces.qml","CheatsheetEmail.qml","CheatsheetTypingTest.qml"][data.saved]);
  }
  function test_toolbar_swipe_and_external_requests_agree() {
   Persistent.states.cheatsheet.tabIndex=1;
   const frame=createTemporaryObject(frameComponent,root);
   tryCompare(frame,"status",Loader.Ready);
   const sheet=frame.item; tryCompare(sheet.view,"selectionReady",true);
   for(const index of [4,0,5,1,3,2]) {
    sheet.bar.setCurrentIndex(index);
    tryCompare(sheet.view,"currentIndex",index);
    compare(Persistent.states.cheatsheet.tabIndex,index);
    compare(sheet.bar.currentIndex,index);
    tryCompare(sheet.view.currentItem,"status",Loader.Ready);
    verify(sheet.view.currentItem.item !== null);
   }
   sheet.view.setCurrentIndex(1);
   compare(Persistent.states.cheatsheet.tabIndex,1);
   Persistent.states.cheatsheet.tabIndex=3;
   tryCompare(sheet.view,"currentIndex",3); compare(sheet.bar.currentIndex,3);
  }
  function test_reopen_and_expiry_keep_the_selected_tab() {
   Persistent.states.cheatsheet.tabIndex=1;
   const frame=createTemporaryObject(frameComponent,root);
   tryCompare(frame,"status",Loader.Ready);
   const sheet=frame.item;
   for(let i=0;i<5;i++) {
    root.activeState=false; frame.requested=false; wait(5);
    root.activeState=true; frame.requested=true; wait(5);
    compare(frame.item,sheet);
    compare(sheet.view.currentIndex,1); compare(Persistent.states.cheatsheet.tabIndex,1);
    tryCompare(sheet.view.currentItem,"status",Loader.Ready);
    verify(sheet.view.currentItem.visible);
   }
   frame.requested=false; tryCompare(frame,"item",null,500);
   frame.requested=true; tryCompare(frame,"status",Loader.Ready);
   compare(Persistent.states.cheatsheet.tabIndex,1);
   tryCompare(frame.item.view,"currentIndex",1);
   tryCompare(frame.item.view.currentItem,"status",Loader.Ready);
  }
 }
}
''')
    result = subprocess.run([shutil.which("qmltestrunner6") or "/usr/lib64/qt6/bin/qmltestrunner",
                             "-input", str(out)], env={**os.environ, "QT_QPA_PLATFORM": "offscreen",
                             "QT_QUICK_BACKEND": "software"}, timeout=30)
    raise SystemExit(result.returncode)
