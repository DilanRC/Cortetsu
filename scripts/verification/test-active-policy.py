#!/usr/bin/env python3
"""Real Go/Rust consent, CAS, manual override and crash/reconnect integration.

Only two fake Hyprland UNIX sockets and a temporary HOME are used. No compositor,
system bus, network, display, GPU or user service is accessed.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]

def wait_for(predicate, label, timeout=12):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            value = predicate()
            if value:
                return value
        except (OSError, ValueError):
            pass
        time.sleep(.025)
    raise AssertionError(f"timeout waiting for {label}")

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--bundle',type=Path,default=ROOT/'dist/native');args=parser.parse_args()
    bundle=args.bundle.resolve()
    with tempfile.TemporaryDirectory(prefix='ct-policy-',dir='/tmp') as directory:
        root=Path(directory);runtime=root/'r';runtime.mkdir(mode=0o700);home=root/'h';home.mkdir()
        hypr=runtime/'hypr'/'test-one';hypr.mkdir(parents=True)
        stopping=threading.Event();connections=[];listeners=[];fullscreen=[True]
        def serve_commands():
            listener=socket.socket(socket.AF_UNIX);listeners.append(listener);listener.bind(str(hypr/'.socket.sock'));listener.listen();listener.settimeout(.2)
            while not stopping.is_set():
                try: conn,_=listener.accept()
                except socket.timeout:continue
                except OSError:return
                with conn:
                    request=conn.recv(128).decode()
                    values={'j/monitors':[{'focused':True,'disabled':False,'name':'private-monitor'}],
                            'j/workspaces':[{'id':1,'name':'private-name'}],
                            'j/activewindow':{'fullscreen':2 if fullscreen[0] else 0,'title':'PRIVATE-NEVER-RETAIN'}}
                    conn.sendall(json.dumps(values[request]).encode())
        def serve_events():
            listener=socket.socket(socket.AF_UNIX);listeners.append(listener);listener.bind(str(hypr/'.socket2.sock'));listener.listen();listener.settimeout(.2)
            while not stopping.is_set():
                try: conn,_=listener.accept()
                except socket.timeout:continue
                except OSError:return
                connections.append(conn)
                conn.sendall(b'fullscreen>>1\n')
        threading.Thread(target=serve_commands,daemon=True).start();threading.Thread(target=serve_events,daemon=True).start()
        wait_for(lambda:(hypr/'.socket2.sock').exists() and (hypr/'.socket.sock').exists(),'fake endpoints')
        env={**os.environ,'HOME':str(home),'XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(home/'config'),
             'XDG_STATE_HOME':str(home/'state'),'XDG_DATA_HOME':str(home/'data'),'XDG_CACHE_HOME':str(home/'cache'),
             'HYPRLAND_INSTANCE_SIGNATURE':'test-one','DBUS_SYSTEM_BUS_ADDRESS':f'unix:path={root}/absent-system-bus',
             'CORTETSU_DATA_ROOT':str(home/'data/cortetsu'),'CORTETSU_RUNTIME_ROOT':str(home/'config/quickshell/cortetsu')}
        for key in ('CORTETSU_INSTALL_TRANSACTION','CORTETSU_RESOURCE_ROOT','CORTETSU_MANUAL_OVERRIDE_SECONDS'):
            env.pop(key,None)
        owner=bundle/'cortetsu-notifications-rs';policy=bundle/'cortetsu-policy';descriptor=runtime/'cortetsu/bridge-test-one.json'
        state_file=home/'state/cortetsu/notification-status.json'
        def cli(*argv):
            result=subprocess.run(list(map(str,argv)),env=env,capture_output=True,text=True,timeout=10)
            assert result.returncode==0,(argv,result.stdout,result.stderr)
            return result.stdout
        def state():return json.loads(state_file.read_text()) if state_file.exists() else {'dnd':False,'revision':0}
        def start():return subprocess.Popen([str(bundle/'cortetsu-coordinator'),'--observe'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
        daemon=start()
        try:
            meta=wait_for(lambda:json.loads(descriptor.read_text()),'metadata')
            assert 0<meta['session_epoch']<=9007199254740991
            time.sleep(.65)
            assert state()['revision']==0,'mutated without explicit consent'
            cli(policy,'enable','notifications')
            wait_for(lambda:state()['dnd'] and state()['revision']==1,'verified automatic DND')
            connections[-1].sendall(b'fullscreen>>1\n')
            time.sleep(.55)
            assert state()['revision']==1,'reapplied an already satisfied state'
            cli(owner,'dnd','off')
            manual=state();assert manual['revision']==2 and manual['manual_override_until_unix_ms']>time.time()*1000
            connections[-1].sendall(b'fullscreen>>1\n')
            time.sleep(.55);assert state()==manual,'automation overrode a manual choice'
            # SIGKILL deliberately leaves metadata and a socket inode. The next
            # owner must reclaim only that dead same-UID session under its lock.
            daemon.kill();daemon.wait(timeout=5);daemon=start()
            new_meta=wait_for(lambda:(m if (m:=json.loads(descriptor.read_text()))['session_epoch']!=meta['session_epoch'] else None),'new session epoch')
            assert new_meta['socket']==meta['socket'];time.sleep(.55);assert state()==manual
            cli(policy,'disable','notifications')
            audit=home/'state/cortetsu/policy-audit/policy-decisions-v1.jsonl'
            records=[json.loads(line) for line in audit.read_text().splitlines()]
            assert [r['outcome'] for r in records]==['INTENT','APPLIED'],records
            assert 'PRIVATE' not in audit.read_text() and 'private-monitor' not in audit.read_text()
            print('PASS: real Go→Rust consent, verified CAS, no replay, manual override, private audit and crash reconnect')
        finally:
            daemon.terminate()
            try:daemon.wait(timeout=5)
            except subprocess.TimeoutExpired:daemon.kill();daemon.wait(timeout=5)
            stopping.set()
            for connection in connections:connection.close()
            for listener in listeners:listener.close()

if __name__=='__main__':main()
