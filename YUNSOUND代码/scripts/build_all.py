"""Rebuild the 128-oscillator instrument in an ASCII temporary directory.
python scripts/build_all.py [instrument]
Set GOWIN_SH if gw_sh.exe is installed elsewhere. Run builds sequentially.
"""
from pathlib import Path
import subprocess, shutil, os, json, re, sys, time, tempfile

project = Path(__file__).resolve().parents[1]
build = Path(tempfile.mkdtemp(prefix='acg525_build_'))
tool = os.environ.get('GOWIN_SH', r'C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe')
for folder in ['rtl','constraints']:
    shutil.copytree(project/folder,build/folder)
for script in project.glob('build_*.tcl'):
    shutil.copy2(script,build/script.name)
variants = ['instrument']
selected = sys.argv[1:] or variants
if any(v not in variants for v in selected):
    raise SystemExit('Choose variants: ' + ' '.join(variants))
for variant in selected:
    print('BUILD ' + variant, flush=True)
    dest = project/'reports'/variant
    dest.mkdir(parents=True,exist_ok=True)
    started = time.time()
    with (dest/'build.log').open('w',encoding='utf-8') as log:
        result = subprocess.run([tool,f'build_{variant}.tcl'],cwd=build,stdout=log,stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(f'{variant}: build failed; see reports/{variant}/build.log')
    fs = build/'impl/pnr/project.fs'
    if not fs.is_file() or fs.stat().st_mtime < started-2:
        raise SystemExit(f'{variant}: no fresh bitstream produced')
    for folder in ['impl/pnr','impl/gwsynthesis']:
        for f in (build/folder).iterdir():
            if f.suffix in ['.html','.txt','.log']:
                shutil.copy2(f,dest/f.name)
    plain = re.sub(r'\s+',' ',re.sub('<[^>]+>',' ',(dest/'project_tr_content.html').read_text(errors='replace')))
    setup = re.search(r'Numbers of Setup Violated Endpoints\s+(\d+)',plain)
    hold = re.search(r'Numbers of Hold Violated Endpoints\s+(\d+)',plain)
    if not setup or not hold or int(setup[1]) or int(hold[1]):
        raise SystemExit(f'{variant}: timing failed; bitstream not promoted to release root')
    destination=project/f'ads_{variant}.fs'
    if destination.exists(): destination.chmod(0o666)
    shutil.copy2(fs,destination)
    destination.chmod(0o666)
    summary = {'variant':variant,'exit_code':0,'setup_violations':0,'hold_violations':0,'elapsed_s':round(time.time()-started,1),'bytes':fs.stat().st_size}
    (dest/'summary.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(summary),flush=True)
print(f'PASS. Build intermediates retained in {build}')
