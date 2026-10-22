#!/usr/bin/env python3
"""Development-only differential tests; the installed platform never calls Python."""
from __future__ import annotations
import argparse, importlib.util, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path
REPO=Path(__file__).resolve().parents[3]

def load(name,path):
    archived=REPO/'tests/reference/python-runtime'/path.relative_to(REPO)
    if archived.is_file():path=archived
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec);sys.modules[name]=mod;spec.loader.exec_module(mod);return mod

def native(binary,command,*args,env=None):
    p=subprocess.run([str(binary),command,*map(str,args)],text=True,capture_output=True,env=env)
    assert p.returncode==0,(command,p.stdout,p.stderr)
    return p.stdout

def compare_tree(a,b):
    left={str(p.relative_to(a)):p.read_bytes() for p in a.rglob('*') if p.is_file()}
    right={str(p.relative_to(b)):p.read_bytes() for p in b.rglob('*') if p.is_file()}
    assert left.keys()==right.keys(),(left.keys()-right.keys(),right.keys()-left.keys())
    for p in left: assert left[p]==right[p],p

def main():
    parser=argparse.ArgumentParser();parser.add_argument('binary',type=Path);args=parser.parse_args();binary=args.binary.resolve()
    norm=load('normal_shell',REPO/'cortetsu/bin/normalize-shell-24.py')
    content=load('normal_content',REPO/'cortetsu/bin/normalize-contentwindow-overview-24.py')
    bottom=load('migrate_bottom',REPO/'cortetsu/bin/migrate-bottom-hub-from-main.py')
    check=load('check_bottom',REPO/'cortetsu/bin/check-bottom-hub-target.py')
    prefs=load('migrate_prefs',REPO/'core/migrate_config.py')
    wire=load('wire_sad',REPO/'scripts/features/wire_sad_shell.py')
    cases=0
    with tempfile.TemporaryDirectory(prefix='cortetsu-platform-parity-') as tmp:
        root=Path(tmp)
        for watch in ('true','false'):
            old=root/f'shell-old-{watch}';new=root/f'shell-new-{watch}';old.mkdir();new.mkdir()
            text=f'ShellRoot {{\n    settings.watchFiles: {watch}\n    Background {{}}\n    Shortcuts {{}}\n}}\n'
            for p in (old,new):(p/'shell.qml').write_text(text)
            norm.normalize(old);native(binary,'normalize-shell-24',new);compare_tree(old,new)
            norm.normalize(old);native(binary,'normalize-shell-24',new);compare_tree(old,new);cases+=2
        old=root/'content-old';new=root/'content-new'
        text='\n'.join(['StyledWindow {',content.LAYER_UPSTREAM,content.KEYBOARD_UPSTREAM,content.MASK_UPSTREAM,'    onHasFullscreenChanged: {','        panels.popouts.close();','    }','    HyprlandFocusGrab {','        active: {','            const conf = root.contentItem.Config;','            return false;','        }','        windows: [root]','        onCleared: {','            panels.popouts.hasCurrent = false;','        }','    }',content.SCRIM_UPSTREAM,'}'])+'\n'
        for p in (old,new):(p/'modules/drawers').mkdir(parents=True);(p/'modules/drawers/ContentWindow.qml').write_text(text)
        content.normalize(old);native(binary,'normalize-contentwindow-overview-24',new);compare_tree(old,new)
        content.normalize(old);native(binary,'normalize-contentwindow-overview-24',new);compare_tree(old,new);cases+=2
        old=root/'bottom-old';new=root/'bottom-new'
        shutil.copytree(REPO/'cortetsu/base',old);shutil.copytree(REPO/'cortetsu/base',new)
        for name in ('shell','shortcuts','panels','sidebar','utilities','bar','popout_wrapper','popout_clip','interactions'):getattr(bottom,'migrate_'+name)(old)
        native(binary,'migrate-bottom-hub-from-main',new);compare_tree(old,new);cases+=1
        for rel,fn in check.CHECKS.items():
            p=old/rel
            if p.is_file():
                expected=0 if fn(old,p.read_text()) else 1
                actual=subprocess.run([str(binary),'check-bottom-hub-target',str(old),rel],capture_output=True).returncode
                assert actual==expected,(rel,expected,actual);cases+=1
        # The canonical fixed-function fixture contains no live session access.
        import ast
        fixture_source=ast.parse((REPO/'scripts/features/test-wire-sad-shell.py').read_text())
        fixture_fn=next(n for n in fixture_source.body if isinstance(n,ast.FunctionDef) and n.name=='fixture')
        ns={'Path':Path};exec(compile(ast.Module(body=[fixture_fn],type_ignores=[]),'<fixture>','exec'),ns)
        for features in (('display',),('display','wallpaper')):
            live=root/('wire-'+str(len(features)));user=root/(live.name+'.lua');ns['fixture'](live,user)
            expected,changed=wire.wire_all(live,user,features);old=root/(live.name+'-old');new=root/(live.name+'-new')
            wire.write_staged(expected,old)
            actual=json.loads(native(binary,'wire_sad_shell','--live',live,'--usercfg',user,'--stage',new,'--features',','.join(features)))
            assert actual=={'ok':True,'changed':changed};compare_tree(old,new);cases+=1
        configs=[{}, {'launcher':{'favouriteApps':['steam',7],'hiddenApps':['qt6ct'],'actions':[{'name':'Open','command':['open']},7],'actionPrefix':'/','enableDangerousActions':False,'useFuzzy':{'apps':False,'wallpapers':False},'vimKeybinds':False},'paths':{'wallpaperDir':'~/Wallpapers'},'services':{'smartScheme':False,'useTwelveHourClock':True,'useFahrenheit':True,'useFahrenheitPerformance':True,'weatherLocation':'9.9,-84.1','audioIncrement':0.05,'brightnessIncrement':0.2,'maxVolume':1.5,'visualiserBars':48,'defaultPlayer':'VLC','playerAliases':[{'from':'vlc','to':'VLC'}]},'utilities':{'toasts':{'audioOutputChanged':False,'audioInputChanged':False,'nowPlaying':True},'vpn':{'provider':[{'id':'office','name':'wireguard','displayName':'Office','interface':'wg-office','connectCmd':['wg-quick','up','wg-office',9],'disconnectCmd':['wg-quick','down','wg-office']}],'selectedProvider':'office','enabled':True}},'notifs':{'expire':False,'fullscreen':'off','defaultExpireTimeout':7000,'fullscreenExpireTimeout':3000,'actionOnClick':True},'bar':{'workspaces':{'shown':6},'tray':{'hiddenIcons':['nm-applet',None]}},'general':{'apps':{'terminal':['foot',9]}}}, {'bar':{'workspaces':{'shown':'100'}}}, {'services':{'maxVolume':'bad','visualiserBars':3.5,'audioIncrement':False},'notifs':{'fullscreen':0}}]
        for i,cfg in enumerate(configs):
            h=root/f'prefs-{i}';legacy=h/'.config/caelestia/shell.json';legacy.parent.mkdir(parents=True);legacy.write_text(json.dumps(cfg))
            expected=prefs.payload_from_legacy(legacy)
            env={**os.environ,'HOME':str(h),'XDG_CONFIG_HOME':str(h/'.config'),'XDG_DATA_HOME':str(h/'.local/share'),'XDG_STATE_HOME':str(h/'.local/state')}
            native(binary,'migrate_config',env=env)
            actual=json.loads((h/'.config/cortetsu/preferences.json').read_text())
            assert actual==expected,(i,{k:(expected[k],actual[k]) for k in expected if expected[k]!=actual[k]});cases+=1
    print(f'PASS: {cases} native platform parity cases')
if __name__=='__main__':main()
