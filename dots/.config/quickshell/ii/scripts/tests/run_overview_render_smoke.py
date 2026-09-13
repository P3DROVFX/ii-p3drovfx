"""Check overview clipping and cached backing in a synthetic offscreen Qt scene.

Uses the production shader and backing Loader. No Quickshell, IPC or desktop
capture; pixel checks only read the test scene rendered by software OpenGL.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
QT_BIN = next(p for p in (Path('/usr/lib64/qt6/bin'), Path('/usr/lib/qt6/bin'))
              if (p / 'qmltestrunner').exists())

wallpaper = (ROOT / 'modules/ii/background/wallpaper/WallpaperImage.qml').read_text()
start = wallpaper.rfind('    Loader {', 0, wallpaper.index('id: overviewBackingBlurLoader'))
end = wallpaper.index('\n    Rectangle {', start)
backing_loader = wallpaper[start:end]
backing_loader = backing_loader.replace('Appearance.colors.colLayer0', '"black"')

with tempfile.TemporaryDirectory(prefix='ii-overview-render-') as directory:
    out = Path(directory)
    (out / 'overview').mkdir()
    (out / 'shaders').mkdir()
    shutil.copy(ROOT / 'modules/ii/background/overview/OverviewRoundedMask.qml', out / 'overview')
    shader = ROOT / 'modules/ii/background/shaders/overviewRoundedMask.frag'
    subprocess.run([str(QT_BIN / 'qsb'), '--glsl', '100 es,120,150', '--hlsl', '50',
                    '--msl', '12', '-o', str(out / 'rebuilt.qsb'), str(shader)], check=True)
    shutil.copy(shader.with_suffix('.frag.qsb'), out / 'shaders')
    (out / 'tst_render.qml').write_text('''import QtQuick
import QtQuick.Effects
import QtTest
import "overview"
Rectangle {
 id: root; width:640; height:360; color:"blue"
 property real radius:40
 Rectangle { id: plane; anchors.fill:parent; color:"green"; layer.enabled:true
   layer.effect: OverviewRoundedMask { objectName:"roundedMask"; cornerRadius:root.radius }
 }
 Item { id: wallpaperImageRoot; anchors.fill:parent; visible:false
   property bool overviewAnimationVisible:true
   property bool videoEffectsDisabled:false
   property QtObject overviewController: QtObject {
     property bool isGnomeLike:true
     property bool useBackingBlur:true
     property real blurAmount:0.7
     property real dimAmount:0
   }
   Rectangle { id: overviewBackingImage; anchors.fill:parent
     color:"red"; layer.enabled:true
     layer.textureSize:Qt.size(width/4,height/4)
   }
   BACKING_LOADER
 }
 TestCase {
   name:"OverviewRender"; when:windowShown
   function init() {
     plane.visible=true; wallpaperImageRoot.visible=false; root.radius=40;
     wallpaperImageRoot.overviewAnimationVisible=true;
     wallpaperImageRoot.overviewController.isGnomeLike=true;
     wallpaperImageRoot.overviewController.dimAmount=0;
     overviewBackingImage.color="red";
   }
   function test_rounded_mask_preserves_center_and_clips_corners() {
     verify(waitForRendering(plane));
     const pixels=grabImage(root);
     compare(pixels.blue(0,0),255);
     compare(pixels.green(320,180),128);
     compare(pixels.green(320,1),128);
     const mask=findChild(root,"roundedMask");
     verify(mask!==null);
     verify(mask.source!==null);
   }
   function test_radius_can_reverse_without_rebuilding_effect() {
     const mask=findChild(root,"roundedMask");
     for(let radius of [0,80,20,0]) {
       root.radius=radius;
       verify(waitForRendering(plane));
       const pixels=grabImage(root);
       compare(pixels.green(320,180),128);
       compare(pixels.blue(0,0),radius===0?0:255);
       compare(findChild(root,"roundedMask"),mask);
     }
   }
   function test_backing_cache_stays_small_during_blur_animation() {
     plane.visible=false;wallpaperImageRoot.visible=true;
     wallpaperImageRoot.overviewController.isGnomeLike=false;
     for(let amount of [0,0.2,0.7,0.3]) {
       wallpaperImageRoot.overviewController.blurAmount=amount;
       verify(waitForRendering(wallpaperImageRoot));
       compare(overviewBackingBlurLoader.layer.textureSize,Qt.size(160,90));
       const pixels=grabImage(root);
       verify(pixels.red(320,180)>245,"Blur must preserve a uniform source");
       compare(pixels.blue(320,180),0);
     }
   }
   function test_cache_tracks_wallpaper_and_dim_changes() {
     plane.visible=false;wallpaperImageRoot.visible=true;
     wallpaperImageRoot.overviewController.isGnomeLike=false;
     verify(waitForRendering(wallpaperImageRoot));
     verify(grabImage(root).red(320,180)>245);
     overviewBackingImage.color="lime";
     verify(waitForRendering(wallpaperImageRoot));
     let pixels=grabImage(root);
     verify(pixels.green(320,180)>245,"Cached blur must follow wallpaper changes");
     compare(pixels.red(320,180),0);
     wallpaperImageRoot.overviewController.dimAmount=0.5;
     verify(waitForRendering(wallpaperImageRoot));
     pixels=grabImage(root);
     verify(pixels.green(320,180)>110 && pixels.green(320,180)<140,
       "Cached backing must still animate its dim");
   }
   function test_backing_reopens_and_keeps_edge_pixels() {
     plane.visible=false;wallpaperImageRoot.visible=true;
     wallpaperImageRoot.overviewController.isGnomeLike=false;
     for(let i=0;i<3;i++) {
       wallpaperImageRoot.overviewAnimationVisible=false;
       compare(overviewBackingBlurLoader.active,false);
       wallpaperImageRoot.overviewAnimationVisible=true;
       tryVerify(()=>overviewBackingBlurLoader.item!==null);
       verify(waitForRendering(wallpaperImageRoot));
       const pixels=grabImage(root);
       verify(pixels.red(0,0)>245,"No transparent/black border at monitor edge");
       verify(pixels.red(320,180)>245);
     }
   }
 }
}
'''.replace('BACKING_LOADER', backing_loader))
    result = subprocess.run([str(QT_BIN / 'qmltestrunner'), '-input', str(out)],
        env={**os.environ, 'QT_QPA_PLATFORM':'offscreen', 'QSG_RHI_BACKEND':'opengl',
             'QT_QUICK_BACKEND':'rhi', 'LIBGL_ALWAYS_SOFTWARE':'true'}, timeout=40)
    raise SystemExit(result.returncode)
