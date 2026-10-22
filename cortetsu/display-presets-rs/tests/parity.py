#!/usr/bin/env python3
"""Compare original Python and opt-in Rust presets CLI in private isolated homes."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parents[3]
old = repo / "cortetsu/bin/cortetsu-display-presets"
new = repo / "cortetsu/display-presets-rs/target/release/cortetsu-display-presets-rs"

def invoke(binary, args, env):
    process = subprocess.run([str(binary),*args],cwd=repo,env=env,encoding="utf8",capture_output=True,timeout=20)
    try: doc=json.loads(process.stdout)
    except Exception as e: raise AssertionError((binary, args, process.stdout, process.stderr)) from e
    return process.returncode,doc

def simulate():
    with tempfile.TemporaryDirectory(prefix="cortetsu-presets-") as home:
        home=Path(home)
        python_home=home/"python";rust_home=home/"rust"
        planner=home/"cortetsu-display-plan"
        planner.write_text('#!/usr/bin/env python3\nimport json,sys\nx=json.loads(sys.argv[2]);print(json.dumps({"ok":True,"candidate":x}))\n')
        planner.chmod(0o755)
        python_dir=home/"pybin";python_dir.mkdir()
        pycopy=python_dir/"cortetsu-display-presets";pycopy.write_bytes(old.read_bytes());pycopy.chmod(0o755)
        (python_dir/"cortetsu-display-plan").symlink_to(planner)
        pyenv=os.environ.copy();pyenv["HOME"]=str(python_home)
        rsenv=os.environ.copy();rsenv["HOME"]=str(rust_home);rsenv["CORTETSU_DISPLAY_PLANNER"]=str(planner)
        cases=[
            ["list"],["get","--name","Missing"],["delete","--name","Missing"],
            ["save","--name","Example","--candidate",'{"outputs":[]}'],
            ["get","--name","Example"],["list"],
            ["delete","--name","Example"],["get","--name","Example"],
            ["save","--name","unsafe/name","--candidate","{}"],
        ]
        for args in cases:
            a,one=invoke(pycopy,args,pyenv)
            b,two=invoke(new,args,rsenv)
            if 'preset' in one and isinstance(one['preset'],dict):one.get('preset',{}).pop('saved_at',None)
            if 'preset' in two and isinstance(two['preset'],dict):two.get('preset',{}).pop('saved_at',None)
            if args == ["list"]:
                one['config']='<home>/display-presets.json'
                two['config']='<home>/display-presets.json'
                for val in one.get('presets',[]):val.pop('saved_at',None)
                for val in two.get('presets',[]):val.pop('saved_at',None)
            if (a,one)!=(b,two):raise AssertionError(f"{args}: Python={a,one}, Rust={b,two}")
        for home_dir in (python_home,rust_home):
            path=home_dir/".config/cortetsu/display-presets.json"
            content=json.loads(path.read_text())
            assert content["version"]==1
        print("PASS: Rust/Python display presets parity, isolated HOME")
if __name__=="__main__":simulate()
