"""Real typing preview/diagram/legend in Qt offscreen; no Quickshell, IPC or HID.

Only platform services and basic widget chrome are substituted. The mapping,
color utilities, theme reactivity and QML interaction/layout are real code.
"""
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="ii-typing-fingers-") as directory:
    out = Path(directory)
    def put(name, content):
        path = out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    sources = ["modules/ii/overview/typing/" + name for name in (
        "TypingKeyboardPreview.qml", "TypingKeyboardLayouts.qml", "TypingFingerPalette.qml",
        "TypingFingerHands.qml", "TypingFingers.js")]
    sources += ["modules/common/widgets/KeyboardDiagram.qml", "modules/common/widgets/KeyboardKey.qml",
                "modules/common/functions/KeyboardMap.js", "modules/common/functions/ColorUtils.qml"]
    alltext = "\n".join((ROOT / p).read_text() for p in sources)
    for name in sources:
        content = (ROOT / name).read_text().replace("import Quickshell\n", "import QtQuick\n").replace("Singleton {", "QtObject {")
        if name.endswith("TypingFingerHands.qml"):
            content = content.replace("id: finger", 'id: finger\n                        objectName: "fingerIndicator" + modelData')
        put("qs/" + name, content)
    widgets = {
        "StyledText": 'import QtQuick\nText { font.pixelSize: 16; color: "white" }',
        "MaterialSymbol": 'import QtQuick\nText { property real iconSize: 16; font.pixelSize: iconSize }',
        "StyledSwitch": 'import QtQuick.Controls\nSwitch {}',
        "StyledFlickable": 'import QtQuick\nFlickable {}',
        "StyledComboBox": 'import QtQuick.Controls\nComboBox {}',
        "StyledToolTip": 'import QtQuick.Controls\nToolTip {property bool extraVisibleCondition: true}',
        "RippleButton": '''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 8
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colRipple: "transparent"
 background: Rectangle {color: parent.colBackground}
}
''',
    }
    for name, body in widgets.items(): put("qs/modules/common/widgets/" + name + ".qml", body)
    put("qs/services/Translation.qml", 'pragma Singleton\nimport QtQuick\nQtObject {function tr(s) {return s;}}')
    original_appearance = (ROOT / "modules/common/Appearance.qml").read_text()
    m3 = dict(re.findall(r'property color (\w+): "(#[0-9a-fA-F]+)"', original_appearance))
    color_names = set(re.findall(r'Appearance.colors.(\w+)', alltext))
    colors = {name: m3.get("m3" + name[3:4].lower() + name[4:], "#444444") for name in color_names}
    # The two values below resolve their indirect Appearance bindings in the shell.
    colors["colOnSurface"] = m3["m3onSurface"]
    put("qs/modules/common/Appearance.qml", '''pragma Singleton
import QtQuick
QtObject {
 property var colors: %s
 property var m3colors: %s
 property var rounding: ({full:999, verysmall:6})
 property var font: ({family:{monospace:"monospace"},pixelSize:{small:15,smaller:13,large:19,huge:22}})
 property var sizes: ({elevationMargin:10})
 property var animation: ({elementMoveFast:{duration:0,type:0,bezierCurve:[]}})
}
''' % (json.dumps(colors), json.dumps(m3)))
    put("qs/modules/common/Config.qml", '''pragma Singleton
import QtQuick
QtObject {
 property QtObject options: QtObject {
  property QtObject search: QtObject {
   property QtObject typingTest: QtObject {
    property QtObject keyboard: QtObject {
     property string layout: "qwerty"
     property bool fingerGuide: false
     property bool highlightNextKey: true
     property list<string> fingerAssignments: []
    }
   }
  }
 }
}
''')
    corne = json.loads((ROOT / "docs/keyboards/corne-v4.1/cheatsheet-current.json").read_text())["page"]["keyboard"]
    put("qs/services/VialKeyboard.qml", '''pragma Singleton
import QtQuick
QtObject {
 property var snapshot: %s
 property string name: "Corne"
 property bool ready: true
 property bool loading: false
 property var keys: snapshot.keys
 property var layers: snapshot.layers
 property int activeLayer: 0
 property int layerCount: layers.length
 property real unitWidth: snapshot.width
 property real unitHeight: snapshot.height
 property var activeLabels: layers[activeLayer] || []
 function setLayer(layer) {activeLayer=layer;}
 function ensureLoaded() {}
}
''' % json.dumps(corne))
    for folder in list(out.rglob("*")):
        if not folder.is_dir(): continue
        qmls = list(folder.glob("*.qml"))
        if qmls:
            put(str(folder.relative_to(out) / "qmldir"), "module " + ".".join(folder.relative_to(out).parts) + "\n" +
                "\n".join(("singleton " if "pragma Singleton" in p.read_text() else "") + p.stem + " 1.0 " + p.name for p in qmls))
    put("tests/tst_fingers.qml", '''import QtQuick
import QtTest
import qs.modules.ii.overview.typing
import qs.modules.common
import qs.modules.common.functions
import qs.services
Item {
 width: 800; height: 800
 TextInput {id: sink; width:1; height:1}
 Component { id: preview; TypingKeyboardPreview {maxWidth:440; onRequestInputFocus:sink.forceActiveFocus()} }
 TestCase {
  name: "TypingFingers"; when: windowShown
  function init() {
   failOnWarning(/.*/);
   Config.options.search.typingTest.keyboard.fingerGuide=false;
   Config.options.search.typingTest.keyboard.fingerAssignments=[];
   VialKeyboard.activeLayer=0;
   VialKeyboard.ready=true;
  }
  function test_settings_preference_and_input_focus() {
   const p=createTemporaryObject(preview,parent,{nextChar:"a"}); verify(p!==null); wait(10);
   const diagram=findChild(p,"typingKeyboardDiagram"); compare(diagram.keyHints.length,0);
   sink.forceActiveFocus();
   compare(findChild(p,"fingerGuideToggle"),null);
   Config.options.search.typingTest.keyboard.fingerGuide=true; wait(10);
   verify(p.fingerGuide); verify(sink.activeFocus);
   compare(p.nextFingers[0],-5); compare(p.nextHint,"Left little finger");
   compare(diagram.keyHints.length,p.keys.length);
   verify(p.implicitHeight>0 && p.implicitHeight<400);
   p.flash("A"); compare(p.pressedChar,"a"); wait(140); compare(p.pressedChar,"");
   p.highlightNext=false; compare(p.nextFingers.length,0);
   Config.options.search.typingTest.keyboard.fingerGuide=false; wait(10); verify(!p.fingerGuide);
   compare(diagram.keyHints.length,0); verify(sink.activeFocus);
  }
  function test_vial_layers_assignment_and_reopen() {
   Config.options.search.typingTest.keyboard.fingerGuide=true;
   let p=createTemporaryObject(preview,parent,{layoutId:"vial",nextChar:"a"}); verify(p!==null); wait(10);
   compare(p.assignedFingers.length,46); compare(p.nextFingers[0],-5);
   const original=JSON.stringify(p.assignedFingers);
   mouseClick(findChild(p,"editFingersButton")); verify(p.editingFingers);
   const diagram=findChild(p,"typingKeyboardDiagram"); diagram.keyClicked(0);
   compare(p.selectedKey,0);
   const choice=findChild(p,"fingerAssignmentChoice"); choice.activated(p.fingerChoices.indexOf(-2));
   compare(p.assignedFingers[0],-2); verify(sink.activeFocus);
   VialKeyboard.setLayer(2); compare(p.assignedFingers[0],-2);
   p.nextChar="á"; compare(p.nextFingers[0],-5);
   const saved=Config.options.search.typingTest.keyboard.fingerAssignments;
   compare(saved.length,1); verify(saved[0].indexOf("vial%3A")===0);
   p.destroy(); wait(10);
   p=createTemporaryObject(preview,parent,{layoutId:"vial"}); wait(10);
   compare(p.assignedFingers[0],-2);
   p.layoutId="colemak"; compare(p.assignedFingers[0],-5); compare(p.selectedKey,-1);
   p.layoutId="vial"; compare(p.assignedFingers[0],-2);
  }
  function test_all_layouts_widths_and_missing_characters() {
   Config.options.search.typingTest.keyboard.fingerGuide=true;
   for (const layout of ["qwerty","qwertz","azerty","colemak","dvorak","vial"]) {
    const p=createTemporaryObject(preview,parent,{layoutId:layout,nextChar:"🙂",maxWidth:360,maxHeight:240}); wait(5);
    verify(p!==null); verify(p.implicitWidth<=360); compare(p.nextFingers.length,0);
    compare(p.nextHint,"Next character is not mapped on this layer");
    const diagram=findChild(p,"typingKeyboardDiagram"); verify(diagram.width<=360.01);
    const first=findChild(p,"fingerIndicator-5"), last=findChild(p,"fingerIndicator5");
    verify(first!==null && last!==null);
    const left=first.mapToItem(p,0,0).x, right=last.mapToItem(p,last.width,0).x;
    verify(Math.abs((left+right)/2-p.width/2)<1,"Finger legend must be centered: "+left+".."+right+" in "+p.width);
    verify(p.implicitHeight<=240.01,"Preview height: "+p.implicitHeight+"; board: "+diagram.height);
    p.editingFingers=true; wait(5); verify(p.implicitHeight<=240.01,"Editor height: "+p.implicitHeight+"; board: "+diagram.height+"; info: "+findChild(p,"typingFingerInfo").height);
    p.destroy(); wait(5);
   }
   VialKeyboard.ready=false;
   const absent=createTemporaryObject(preview,parent,{layoutId:"vial"}); wait(5);
   verify(!findChild(absent,"typingKeyboardDiagram").visible);
  }
  function test_palette_contrast_and_theme_change() {
   for(const id of [1,2,3,4,5]) verify(ColorUtils.contrastRatio(TypingFingerPalette.ink(id),TypingFingerPalette.fill(id))>=4.5);
   const previous=TypingFingerPalette.fill(2);
   const colors=Object.assign({},Appearance.colors,{colPrimaryContainer:"#ead8ff",colOnSurface:"#201a24",colOnPrimaryContainer:"#201a24",colOnPrimary:"#ffffff"});
   Appearance.colors=colors;
   verify(TypingFingerPalette.fill(2)!==previous);
   for(const id of [1,2,3,4,5]) verify(ColorUtils.contrastRatio(TypingFingerPalette.ink(id),TypingFingerPalette.fill(id))>=4.5);
  }
  function test_larger_keyboard_with_information_beside_it() {
   for(const layout of ["qwerty","vial"]) {
    for(const availableWidth of [900,1600]) {
     Config.options.search.typingTest.keyboard.fingerGuide=false;
     const p=createTemporaryObject(preview,parent,{layoutId:layout,maxWidth:availableWidth,maxHeight:300,nextChar:"a"}); wait(10);
     const ordinaryUnit=p.unit;
     Config.options.search.typingTest.keyboard.fingerGuide=true; wait(10);
     verify(p.sideBySide); verify(p.unit>ordinaryUnit*1.2,"Guide key unit: "+p.unit+"; ordinary: "+ordinaryUnit);
     const diagram=findChild(p,"typingKeyboardDiagram"), info=findChild(p,"typingFingerInfo");
     // The bindings update synchronously; GridLayout positions children on
     // the next polish pass after the settings preference changes.
     tryVerify(()=>info.mapToItem(p,0,0).x>diagram.mapToItem(p,diagram.width,0).x,1000);
     verify(diagram.labelSize>15);
     const boardRight=diagram.mapToItem(p,diagram.width,0).x, infoLeft=info.mapToItem(p,0,0).x;
     verify(infoLeft>boardRight,"Information must be beside the keyboard: "+layout+" / "+availableWidth+"; board right="+boardRight+"; info left="+infoLeft+"; info width="+info.width+"; preview="+p.width+"; columns="+info.parent.columns+"; grid height="+info.parent.height+"; info y="+info.y+"; info visible="+info.visible);
     verify(infoLeft+info.width<=p.width+1); verify(p.width<=availableWidth);
     verify(p.implicitHeight<=300.01,"Preview exceeded the height available below the words");
     const first=findChild(p,"fingerIndicator-5"), last=findChild(p,"fingerIndicator5");
     if(availableWidth===1600) {
      const left=first.mapToItem(info,0,0).x, right=last.mapToItem(info,last.width,0).x;
      verify(Math.abs((left+right)/2-info.width/2)<1,"Hands must stay centered in the sidebar");
     } else {
      verify(last.mapToItem(info,0,0).y>first.mapToItem(info,0,0).y,"Compact sidebar stacks the hands");
     }
     const oldUnit=p.unit, oldHeight=p.implicitHeight;
     p.nextChar="🙂"; wait(5); compare(p.unit,oldUnit); compare(p.implicitHeight,oldHeight);
     p.editingFingers=true; wait(5); compare(p.unit,oldUnit); verify(p.implicitHeight<=300.01);
     const choice=findChild(p,"fingerAssignmentChoice"); verify(choice.mapToItem(p,0,0).x>boardRight);
     if(layout==="vial") verify(findChild(p,"typingLayerControls").mapToItem(p,0,0).x>boardRight);
     p.destroy(); wait(5);
    }
   }
  }
 }
}
''')
    result = subprocess.run(["/usr/lib64/qt6/bin/qmltestrunner", "-input", str(out / "tests"), "-import", str(out)],
                            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                            timeout=30, capture_output=True, text=True)
    print(result.stdout, end="")
    print(result.stderr, end="")
    if re.search(r"ReferenceError|TypeError|Binding loop|Unable to assign|is not defined", result.stdout + result.stderr):
        raise SystemExit(1)
    raise SystemExit(result.returncode)
