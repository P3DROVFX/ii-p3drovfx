"""Additional finite A/B runs. Uses the same recovery/sandbox supervisor."""
import run
import subprocess
run.CASES=[
 {'id':'family_upstream','path':'panelFamilies/IllogicalImpulseFamily.qml','kind':'resident','upstream':True,'productionConfig':True},
 {'id':'bar_reference','path':'modules/ii/verticalBar/VerticalBar.qml','kind':'bar'},
 {'id':'bar_active_layout','path':'modules/ii/verticalBar/VerticalBarAudit.qml','kind':'bar'},
 {'id':'media_reference','path':'modules/ii/background/Background.qml','kind':'media'},
 {'id':'media_static','path':'modules/ii/background/Background.qml','kind':'media','staticMedia':True},
 {'id':'family_fork_no_prewarm','path':'panelFamilies/IllogicalImpulseFamily.qml','kind':'resident','productionConfig':False},
]
run.DRIVER=run.DRIVER.replace('if(root.test.noPrivacy) Config.options.bar.privacyPill.enabled=false;', '''if(root.test.noPrivacy) Config.options.bar.privacyPill.enabled=false;
   if(root.test.staticMedia) {
    Config.options.background.mediaMode.backgroundAnimation.enable=false;
    Config.options.background.mediaMode.visualizerMode=0;
   }''')
_original=run.run_case
def measured(case,ignored):
 status=subprocess.run(['playerctl','--all-players','--format','{{playerName}} {{status}}','status'],capture_output=True,text=True)
 (run.BASE/(case['id']+'-mpris-state.txt')).write_text(status.stdout)
 return _original(case,[{'phase':'core','seconds':20},{'phase':'controller','seconds':20},{'phase':'open','seconds':35},{'phase':'closed','seconds':25},{'phase':'unloaded','seconds':20}])
run.run_case=measured
run.main()
