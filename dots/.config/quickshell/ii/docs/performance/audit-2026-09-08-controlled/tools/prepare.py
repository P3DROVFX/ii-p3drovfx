#!/usr/bin/env python3
"""Prepare a private audit copy. Does not start, stop, reload or control Quickshell."""
import argparse,ast,json,os,re,shutil,subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent

def copy_file(source,target):
    subprocess.run(['cp','--reflink=auto','-p',str(source),str(target)],check=True)
    return str(target)

def revision(path):
    return subprocess.check_output(['git','rev-parse','HEAD'],cwd=path,text=True).strip()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=Path.home()/'.config/quickshell/ii')
    parser.add_argument('--upstream',type=Path,default=Path.home()/'.config/quickshell/dots-hyprland/dots/.config/quickshell/ii')
    parser.add_argument('--output',required=True,type=Path,help='New private directory on a persistent filesystem')
    args=parser.parse_args();source=args.source.resolve();upstream=args.upstream.resolve();out=args.output.resolve();home=Path.home()
    if out.exists():parser.error('Output already exists. Choose a new directory; nothing was overwritten.')
    if not (source/'shell.qml').exists():parser.error('Source must contain shell.qml.')
    if not (upstream/'shell.qml').exists():parser.error('Upstream must contain shell.qml.')
    if out==source or source in out.parents:parser.error('Output must be outside the live source tree.')
    out.mkdir(parents=True,mode=0o700);out.chmod(0o700)
    ignore=shutil.ignore_patterns('.git','.agents','docs','tests','__pycache__')
    for name,origin in [('source',source),('upstream',upstream)]:
        shutil.copytree(origin,out/name,ignore=ignore,symlinks=True,copy_function=copy_file)
    # The reference clone may have an uninitialized shapes submodule. Copy the exact
    # pinned revision from the already-present local object, without network/package installs.
    relative='dots/.config/quickshell/ii/modules/common/widgets/shapes'
    pin=subprocess.check_output(['git','ls-tree','HEAD',relative],cwd=upstream,text=True).strip()
    # git ls-tree paths are relative to cwd unless run at repository root.
    if not pin:
        gitroot=subprocess.check_output(['git','rev-parse','--show-toplevel'],cwd=upstream,text=True).strip()
        pin=subprocess.check_output(['git','ls-tree','HEAD',relative],cwd=gitroot,text=True).strip()
    shapes=out/'upstream/modules/common/widgets/shapes';shape_revision=None
    if not (shapes/'material-shapes.js').exists():
        if not pin.startswith('160000 commit '):raise RuntimeError('Cannot resolve upstream shapes submodule. Preparation stopped; production is untouched.')
        shape_revision=pin.split()[2]
        archive=subprocess.check_output(['git','archive',shape_revision],cwd=source/'modules/common/widgets/shapes')
        shapes.mkdir(parents=True,exist_ok=True)
        subprocess.run(['tar','-x','-C',str(shapes)],input=archive,check=True)
    for name,origin in [('config',home/'.config/illogical-impulse'),('state',home/'.local/state/quickshell'),('cache',home/'.cache/quickshell')]:
        subprocess.run(['cp','-a','--reflink=auto',str(origin),str(out/('seed-'+name))],check=True)
    (out/'host-config').mkdir();config=out/'config-root';config.mkdir()
    for p in (home/'.config').iterdir():
        target=config/p.name
        if p.is_file():shutil.copy2(p,target)
        elif p.name=='illogical-impulse':target.mkdir()
        elif p.name=='qt6ct':subprocess.run(['cp','-a','--reflink=auto',str(p),str(target)],check=True)
        else:target.symlink_to(out/'host-config'/p.name)
    # Two alternative QML files exist only in the private snapshot.
    v=out/'source/modules/ii/verticalBar'
    content=(v/'VerticalBarContent.qml').read_text()
    start=content.index('    ColumnLayout { // Combined Island section')
    end=content.index('    FocusedScrollMouseArea { // Top section',start)
    pattern=r'model: (Config\.options\.bar\.layouts\.(?:left|right)|root\.(?:leftList|centerList|rightList))'
    first,n=re.subn(pattern,r'model: root.isDynamicIsland ? \1 : []',content[start:end])
    second,k=re.subn(pattern,r'model: !root.isDynamicIsland ? \1 : []',content[end:])
    if (n,k)!=(5,5):raise RuntimeError('Bar structure changed. Adapt the prototype; production is untouched.')
    (v/'VerticalBarContentAudit.qml').write_text(content[:start]+first+second)
    host=(v/'VerticalBar.qml').read_text()
    if 'VerticalBarContent {' not in host:raise RuntimeError('Bar host changed; adapt prototype.')
    (v/'VerticalBarAudit.qml').write_text(host.replace('VerticalBarContent {','VerticalBarContentAudit {'))
    runner=(HERE/'runner_template.py').read_text()
    runner=runner.replace("SRC=Path('/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii')",'SRC=Path('+repr(str(source))+')')
    runner=runner.replace("HOME_PATH=Path('/home/pedro')",'HOME_PATH=Path('+repr(str(home))+')')
    ast.parse(runner);(out/'run.py').write_text(runner)
    for name in ['proc_reader.py','build_report.py','cases.json']:shutil.copy2(HERE/name,out/name)
    meta={'source':str(source),'sourceHead':revision(source),'upstream':str(upstream),'upstreamHead':revision(upstream),'shapesRevisionRestored':shape_revision,'preparedOnly':True,'privateData':True}
    (out/'preparation.json').write_text(json.dumps(meta,indent=2)+'\n')
    print(json.dumps({'prepared':str(out),'productionTouched':False,'next':'Choose explicit case IDs from cases.json; see GUIA-DE-AUDITORIA.md.'}))

if __name__=='__main__':main()
