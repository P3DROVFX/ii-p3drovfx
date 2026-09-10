"""Exercise the real Material Shape effect in an offscreen Qt scene.

No desktop capture, Quickshell instance or IPC. Mesa renders the synthetic scene
so shader compilation, Canvas lifecycle and uniform updates are checked together.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
QT_BIN = next(p for p in (Path('/usr/lib64/qt6/bin'), Path('/usr/lib/qt6/bin'))
              if (p / 'qmltestrunner').exists())

with tempfile.TemporaryDirectory(prefix='ii-material-mask-') as directory:
    out = Path(directory)
    widgets = out / 'qs/modules/common/widgets'
    shapes = widgets / 'shapes'
    shapes.mkdir(parents=True)
    (widgets / 'qmldir').write_text('module qs.modules.common.widgets\nMaterialShape 1.0 MaterialShape.qml\n')
    (shapes / 'qmldir').write_text('module qs.modules.common.widgets.shapes\nShapeCanvas 1.0 ShapeCanvas.qml\n')
    shutil.copy(ROOT / 'modules/common/widgets/MaterialShape.qml', widgets)
    shutil.copy(ROOT / 'modules/common/widgets/shapes/ShapeCanvas.qml', shapes)
    for name in ('shapes', 'geometry', 'graphics', 'material-shapes.js'):
        (shapes / name).symlink_to(ROOT / 'modules/common/widgets/shapes' / name)
    (out / 'overview').mkdir()
    (out / 'shaders').mkdir()
    shutil.copy(ROOT / 'modules/ii/background/overview/OverviewMaterialMask.qml', out / 'overview')
    shader = ROOT / 'modules/ii/background/shaders/overviewMaterialMask.frag'
    compiled = out / 'shaders/overviewMaterialMask.frag.qsb'
    subprocess.run([str(QT_BIN / 'qsb'), '--glsl', '100 es,120,150', '--hlsl', '50',
                    '--msl', '12', '-o', str(compiled), str(shader)], check=True)
    # Test the shipped package as well as rebuilding the source.
    shutil.copy(shader.with_suffix('.frag.qsb'), compiled)
    (out / 'tst_mask.qml').write_text('''import QtQuick
import QtTest
import "overview"
Rectangle {
 id: root; width:640; height:360; color:"blue"
 QtObject { id: maskController
   property real maskTargetDiameter: 240
   property real maskScale: 1
   property real maskRotation: 0
   property string currentMaterialShape: "Flower"
 }
 Rectangle { id: content; width:640; height:360; color:"red"; visible:false; layer.enabled:true }
 OverviewMaterialMask { id: effect; anchors.fill:parent; controller:maskController; source:content }
 Rectangle { id: layeredPlane; width:320; height:180; color:"green"
   layer.enabled:false
   layer.effect:OverviewMaterialMask { objectName:"layerMask"; controller:maskController }
 }
 SignalSpy { id: paintSpy; target:effect.maskSource.sourceItem; signalName:"painted" }
 Item { id: legacyShape
   width:maskController.maskTargetDiameter; height:width; anchors.centerIn:parent
   transform: [
     Scale { origin.x:legacyShape.width/2; origin.y:legacyShape.height/2;
       xScale:maskController.maskScale; yScale:maskController.maskScale },
     Rotation { origin.x:legacyShape.width/2; origin.y:legacyShape.height/2; angle:maskController.maskRotation }
   ]
 }
 TestCase {
   name:"OverviewMaterialMask"; when:windowShown
   function initTestCase() {
     verify(waitForRendering(effect));
     verify(effect.controller!==null);
     compare(effect.visible,true);
     compare(effect.width,640);
     tryCompare(effect,"status",ShaderEffect.Compiled);
     tryCompare(effect.maskSource.sourceItem,"progress",1);
   }
   function test_source_is_small_static_silhouette() {
     compare(effect.maskSource.sourceItem.width,maskController.maskTargetDiameter);
     compare(effect.maskSource.sourceItem.height,maskController.maskTargetDiameter);
     compare(effect.maskSource.sourceItem.animation.duration,0);
     compare(effect.maskSource.hideSource,true);
   }
   function test_layer_effect_receives_source_and_is_released() {
     maskController.maskScale=1;maskController.maskRotation=0;
     effect.visible=false;
     layeredPlane.layer.enabled=true;
     verify(waitForRendering(layeredPlane));
     const mask=findChild(root,"layerMask");
     verify(mask!==null);
     verify(mask.source!==null);
     compare(mask.screenExtent,Qt.vector2d(320,180));
     verify(mask.visible,"layer effect must be visible");
     // Read only this synthetic offscreen scene, never the desktop/window system.
     const pixels=grabImage(root);
     compare(pixels.blue(0,0),255,"Shape must cut the layer corner");
     verify(pixels.green(160,90)>0,"Layer source must survive at the center");
     layeredPlane.layer.enabled=false;
     tryVerify(()=>findChild(root,"layerMask")===null);
     effect.visible=true;
   }
   function test_shape_change_finishes_morph_immediately() {
     maskController.currentMaterialShape="Heart";
     tryCompare(effect.maskSource.sourceItem,"progress",1);
     verify(waitForRendering(effect));
     maskController.currentMaterialShape="Cookie7Sided";
     tryCompare(effect.maskSource.sourceItem,"progress",1);
     verify(waitForRendering(effect));
     compare(effect.status,ShaderEffect.Compiled);
   }
   function test_animation_uniforms_do_not_repaint_canvas() {
     // Allow the previous shape change to paint, then observe only motion.
     wait(80);
     paintSpy.clear();
     for(let i=0;i<15;i++) {
       maskController.maskScale=4-i*0.2;
       maskController.maskRotation=-18+i;
       wait(16);
     }
     compare(paintSpy.count,0,"Transform-only frames must not repaint Canvas");
     fuzzyCompare(effect.maskExtent,240*maskController.maskScale,0.001);
     compare(effect.maskSource.sourceItem.width,240);
   }
   function test_rotation_and_aspect_use_screen_pixel_space() {
     maskController.maskRotation=90;
     fuzzyCompare(effect.rotationVector.x,0,0.00001);
     fuzzyCompare(effect.rotationVector.y,1,0.00001);
     compare(effect.screenExtent,Qt.vector2d(640,360));
     root.width=360;root.height=640;
     compare(effect.screenExtent,Qt.vector2d(360,640));
     compare(effect.maskSource.sourceItem.width,240);
     root.width=640;root.height=360;
   }
   function test_repeated_shape_switches_stay_ready() {
     for(let shape of ["Flower","Cookie9Sided","Cookie12Sided","Cookie7Sided",
       "Cookie6Sided","SoftBurst","Burst","Sunny","VerySunny","Puffy",
       "Clover4Leaf","Clover8Leaf","Boom","SoftBoom","Bun","Gem","ClamShell","Heart"]) {
       const previous=maskController.currentMaterialShape;
       maskController.currentMaterialShape=shape;
       tryCompare(effect.maskSource.sourceItem,"progress",1);
       if(previous!==shape) verify(waitForRendering(effect));
       compare(effect.status,ShaderEffect.Compiled);
     }
   }
   function test_inverse_sampling_matches_existing_qml_transforms() {
     for(let extent of [[640,360],[360,640],[1280,360]]) {
       root.width=extent[0];root.height=extent[1];
       for(let scale of [0.1,1.15,4,9]) for(let angle of [-22,0,18]) {
         maskController.maskScale=scale;maskController.maskRotation=angle;
         const c=effect.rotationVector.x, s=effect.rotationVector.y;
         for(let point of [[0,0],[0.2,0.7],[0.5,0.5],[1,1]]) {
           const screen=legacyShape.mapToItem(root,point[0]*240,point[1]*240);
           const px=screen.x-root.width/2, py=screen.y-root.height/2;
           // Same inverse transform used in overviewMaterialMask.frag.
           fuzzyCompare((c*px+s*py)/effect.maskExtent+0.5,point[0],0.00001);
           fuzzyCompare((-s*px+c*py)/effect.maskExtent+0.5,point[1],0.00001);
         }
       }
     }
     root.width=640;root.height=360;
   }
 }
}
''')
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QSG_RHI_BACKEND': 'opengl', 'QT_QUICK_BACKEND': 'rhi',
           'LIBGL_ALWAYS_SOFTWARE': 'true'}
    result = subprocess.run([str(QT_BIN / 'qmltestrunner'), '-import', str(out),
                             '-input', str(out)], env=env, timeout=40)
    raise SystemExit(result.returncode)
