"""Run production launcher motion bindings in Qt, without a shell or screen capture.

The window/services are inert fixtures; the bindings and query-edit function are
extracted from QML so typing during entry, hidden grids and close tails exercise
the actual policy. This checks lifecycle/coordination, not GPU frame time.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text()


def binding(text, marker):
    """Read a binding and its more-indented continuation lines."""
    lines = text.splitlines()
    i = next(i for i, line in enumerate(lines) if line.lstrip().startswith(marker))
    indent = len(lines[i]) - len(lines[i].lstrip())
    result = [lines[i].split(marker, 1)[1]]
    for line in lines[i + 1:]:
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        result.append(line)
    return "\n".join(result).strip()


def block(text, marker):
    start = text.index(marker)
    pos = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[pos] == "{") - (text[pos] == "}")
        pos += 1
    return text[start:pos]


search = source("modules/ii/overview/SearchWidget.qml")
overview = source("modules/ii/overview/Overview.qml")
wallpaper = source("modules/ii/background/wallpaper/WallpaperImage.qml")
preview = source("modules/ii/overview/OverviewWindow.qml")
classic = source("modules/ii/overview/OverviewWidget.qml")
wrapper = overview.split("id: searchWidgetWrapper", 1)[1]
grid = overview.split("id: overviewLoader", 1)[1]
backing = wallpaper.split("id: overviewBackingBlurLoader", 1)[1]
shape = wallpaper.split("id: materialShapeMaskSource", 1)[1]
content = wallpaper.split("id: wallpaperContent", 1)[1]
capture = preview.split("id: windowPreview", 1)[1]
backing_image = wallpaper.split("id: overviewBackingImage", 1)[1]
workspace_motion = classic.split("property real animProgress: 0.0", 1)[1].split("\n                            Connections {\n                                target: GlobalStates", 1)[0]
reveal = search.split("property real revealProgress:", 1)[1].split("\n                        Component {", 1)[0]

qml = '''import QtQuick
import QtTest
Item {
 id: root; width: 800; height: 600
 property bool surfaceAnimating: false
 property bool searchSurfaceOwned: false
 property bool suppressItemTransitions: true
 property bool exiting: false
 property double lastQueryEditTime: 0
 property int burstTypingThreshold: 120
 property bool isNotchMode: false
 property var toplevel: ({})
 property bool initialized: true
 property int frameRequests: 0
 QtObject { id: globalStates; property bool overviewOpen: true; property bool lockLookActive: false }
 QtObject { id: config; property var options: ({background:{windowZoomLiveCapture:true},overview:{showWindowPreviews:true}}) }
 QtObject { id: appearance; property var animation: ({elementMoveFast:{duration:120,type:Easing.Linear,bezierCurve:[]}}) }
 property real animMultiplier: 1
 Timer { id: typingSettleTimer; interval: 120 }
 Item { id: appResults; property bool staggerReveal: true; property int staggerStep: 22 }
 Item { id: wallpaperImageRoot
   property bool lockAnimationActive: false
   property bool wallpaperClipRadius: true
   property bool videoEffectsDisabled: false
   property bool overviewAnimationVisible: true
   property bool materialShapeActive: overviewController.isMaterialShape && overviewAnimationVisible
   property bool materialShapeDirectMask: overviewController.isMaterialShape && !shadowEnabled
   property bool materialShapeShadowActive: materialShapeActive && shadowEnabled
   property bool shadowEnabled: false
   property QtObject overviewController: QtObject {
     property bool isGnomeLike: true
     property bool isMaterialShape: false
     property bool active: true
     property bool useBackingBlur: true
   }
 }
 Item { id: materialShapeMaskContainer }
 Item { id: searchWidgetWrapper
   property bool isNotchMode: false
   property real slideOpacity: 0.5
   layer.enabled: WRAPPER_LAYER
 }
 Item { id: overviewLoader
   opacity: 0
   layer.enabled: GRID_LAYER
 }
 Item { id: wallpaperContent; layer.enabled: CONTENT_LAYER }
 Item { id: backingImage; width:3840; height:2160; layer.textureSize: BACKING_SIZE }
 QtObject { id: policy
   readonly property int reorderDuration: REORDER
   readonly property bool backingActive: BACKING_ACTIVE
   readonly property Item maskInput: SHAPE_SOURCE
   readonly property bool maskLive: SHAPE_LIVE
   readonly property bool previewLive: PREVIEW_LIVE
 }
 NOTE_QUERY
 Component {
   id: cascadeComponent
   Item { id: root
     property real animMultiplier: 1
     property alias pending: workspaceStaggerTimer.running
     property alias animating: workspaceStaggerAnim.running
     property alias progress: workspace.animProgress
     function start() { workspaceStaggerTimer.start(); }
     Item { id: workspace; property int cellIndex: 0; property real animProgress: 0
       WORKSPACE_MOTION
     }
   }
 }
 Component {
   id: previewComponent
   Item { id: root
     property bool initialized: true
     property QtObject toplevel: QtObject {}
     property int frames: 0
     property alias live: windowPreview.live
     property alias pending: recaptureDebounce.running
     QtObject { id: windowPreview
       property bool live: false
       property QtObject captureSource: root.toplevel
       function captureFrame() { root.frames++; }
     }
     REQUEST_RECAPTURE
     PREVIEW_VISIBILITY
     RECAPTURE_TIMER
   }
 }
 Component {
   id: delegateComponent
   Item { id: resultDelegate; property int index: 4
     property real revealProgress: REVEAL
   }
 }
 TestCase {
   name: "LauncherMotion"; when: windowShown
   function init() {
     root.surfaceAnimating=false; root.searchSurfaceOwned=false;
     root.suppressItemTransitions=true; root.lastQueryEditTime=0;
     root.exiting=false; root.visible=true;
     globalStates.overviewOpen=true; globalStates.lockLookActive=false;
     wallpaperImageRoot.overviewController.active=true;
     wallpaperImageRoot.overviewController.isMaterialShape=false;
     wallpaperImageRoot.shadowEnabled=false;
     wallpaperImageRoot.overviewAnimationVisible=true;
   }
   function test_first_key_during_open_does_not_start_reorder() {
     root.surfaceAnimating=true;
     root.noteQueryEdit();
     compare(policy.reorderDuration,0);
   }
   function test_deliberate_edit_after_open_keeps_motion() {
     root.noteQueryEdit();
     verify(policy.reorderDuration>0);
     root.noteQueryEdit();
     compare(policy.reorderDuration,0);
   }
   function test_typing_expands_without_blur_target() {
     verify(searchWidgetWrapper.layer.enabled);
     root.searchSurfaceOwned=true;
     compare(searchWidgetWrapper.layer.enabled,false);
   }
   function test_settled_search_has_no_blur_target() {
     searchWidgetWrapper.slideOpacity=1;
     compare(searchWidgetWrapper.layer.enabled,false);
     searchWidgetWrapper.slideOpacity=0.5;
   }
   function test_hidden_grid_has_no_blur_target() {
     compare(overviewLoader.layer.enabled,false);
   }
   function test_overview_does_not_add_second_wallpaper_layer() {
     compare(wallpaperContent.layer.enabled,false);
     globalStates.lockLookActive=true;
     compare(wallpaperContent.layer.enabled,true);
   }
   function test_material_shape_keeps_its_direct_source_ready_between_openings() {
     wallpaperImageRoot.overviewController.isMaterialShape=true;
     verify(wallpaperContent.layer.enabled);
     wallpaperImageRoot.overviewAnimationVisible=false;
     verify(wallpaperContent.layer.enabled);
     wallpaperImageRoot.shadowEnabled=true;
     compare(wallpaperContent.layer.enabled,false);
   }
   function test_backing_texture_is_bounded_and_stable_during_close() {
     compare(backingImage.layer.textureSize,Qt.size(960,540));
     wallpaperImageRoot.overviewController.active=false;
     compare(backingImage.layer.textureSize,Qt.size(960,540));
   }
   function test_material_mask_only_has_source_in_its_preset() {
     compare(policy.maskInput,null);
     compare(policy.maskLive,false);
     wallpaperImageRoot.overviewController.isMaterialShape=true;
     // The normal Material Shape path no longer needs the screen-sized mask.
     compare(policy.maskInput,null);
     compare(policy.maskLive,false);
     wallpaperImageRoot.shadowEnabled=true;
     compare(policy.maskInput,materialShapeMaskContainer);
     compare(policy.maskLive,true);
   }
   function test_backing_survives_close_tail() {
     wallpaperImageRoot.overviewController.active=false;
     verify(policy.backingActive);
     wallpaperImageRoot.overviewAnimationVisible=false;
     compare(policy.backingActive,false);
   }
   function test_hidden_preview_stops_live_capture() {
     root.visible=false;
     compare(policy.previewLive,false);
     root.visible=true;
     verify(policy.previewLive);
   }
   function test_new_rows_are_immediate_during_entry() {
     root.surfaceAnimating=true;
     let row=createTemporaryObject(delegateComponent,root);
     verify(row);
     compare(row.revealProgress,1);
   }
   function test_typing_finishes_pending_stagger() {
     root.suppressItemTransitions=false;
     let row=createTemporaryObject(delegateComponent,root);
     verify(row);
     root.suppressItemTransitions=true;
     compare(row.revealProgress,1);
   }
   function test_hidden_workspace_cancels_pending_cascade() {
     let tile=createTemporaryObject(cascadeComponent,root);
     tile.start();
     verify(tile.pending);
     tile.visible=false;
     compare(tile.pending,false);
     compare(tile.animating,false);
     compare(tile.progress,1);
   }
   function test_hidden_workspace_finishes_running_cascade() {
     let tile=createTemporaryObject(cascadeComponent,root);
     tile.start();
     tryCompare(tile,"animating",true);
     tile.visible=false;
     compare(tile.animating,false);
     compare(tile.progress,1);
   }
   function test_hidden_cold_workspace_does_not_animate() {
     let tile=createTemporaryObject(cascadeComponent,root,{visible:false});
     tile.start();
     tryCompare(tile,"pending",false);
     compare(tile.animating,false);
     compare(tile.progress,1);
   }
   function test_frozen_preview_refreshes_once_on_return() {
     let tile=createTemporaryObject(previewComponent,root);
     tile.visible=false;
     tile.requestRecapture();
     compare(tile.pending,false);
     tile.visible=true;
     tryCompare(tile,"frames",1);
     compare(tile.pending,false);
   }
   function test_live_preview_does_not_schedule_redundant_capture() {
     let tile=createTemporaryObject(previewComponent,root,{live:true});
     tile.requestRecapture();
     compare(tile.pending,false);
     compare(tile.frames,0);
   }
 }
}
'''
for name, value in {
    "WRAPPER_LAYER": binding(wrapper, "layer.enabled:"),
    "GRID_LAYER": binding(grid, "layer.enabled:"),
    "CONTENT_LAYER": binding(content, "layer.enabled:"),
    "BACKING_SIZE": binding(backing_image, "layer.textureSize:"),
    "REORDER": binding(search, "readonly property int reorderDuration:"),
    "BACKING_ACTIVE": binding(backing, "active:"),
    "SHAPE_SOURCE": binding(shape, "sourceItem:"),
    "SHAPE_LIVE": binding(shape, "live:"),
    "PREVIEW_LIVE": binding(capture, "live:"),
    "NOTE_QUERY": block(search, "function noteQueryEdit()"),
    "REVEAL": reveal,
    "WORKSPACE_MOTION": workspace_motion.replace("Appearance.animMultiplier", "root.animMultiplier"),
    "REQUEST_RECAPTURE": block(preview, "function requestRecapture()"),
    "PREVIEW_VISIBILITY": block(preview, "onVisibleChanged:"),
    "RECAPTURE_TIMER": block(preview[preview.index("function requestRecapture()"):], "Timer {"),
}.items():
    qml = qml.replace(name, value)
for upper in ("Appearance", "GlobalStates", "Config"):
    qml = re.sub(r"\b" + upper + r"\b", upper[0].lower() + upper[1:], qml)

runner = next((str(p) for p in (Path("/usr/lib64/qt6/bin/qmltestrunner"),
    Path("/usr/lib/qt6/bin/qmltestrunner")) if p.exists()), None) or shutil.which("qmltestrunner")
with tempfile.TemporaryDirectory(prefix="ii-launcher-motion-") as directory:
    test = Path(directory) / "tst_motion.qml"
    test.write_text(qml)
    result = subprocess.run([runner, "-input", directory],
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
        timeout=30)
    raise SystemExit(result.returncode)
