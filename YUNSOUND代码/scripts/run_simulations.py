"""Run digital tests with an existing Icarus installation; no download/install.

python scripts/run_simulations.py --icarus-bin C:/iverilog/bin
Use --test tb_synth128 for one bench.
Sources and vvp outputs are staged under an ASCII TEMP directory for Windows.
"""
from pathlib import Path
import argparse, os, shutil, subprocess, tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--icarus-bin', required=True)
parser.add_argument('--test')
parser.add_argument('--mode', type=int, default=0)
parser.add_argument('--timbre', type=int, default=0)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
bin_dir = Path(args.icarus_bin).resolve()
iverilog = bin_dir / ('iverilog.exe' if os.name == 'nt' else 'iverilog')
vvp = bin_dir / ('vvp.exe' if os.name == 'nt' else 'vvp')
if not iverilog.is_file() or not vvp.is_file():
    raise SystemExit('Icarus iverilog/vvp not found in --icarus-bin')
stage = Path(tempfile.mkdtemp(prefix='acg525_sim_'))
for folder in ['rtl','tb']:
    shutil.copytree(root/folder,stage/folder)
(root/'sim').mkdir(exist_ok=True)
benches = [stage/'tb'/f'{args.test}.v'] if args.test else [stage/'tb'/(n+'.v') for n in ['tb_synth128','tb_testmode128','tb_effects','tb_latency128','tb_reader_latency','tb_visual_telemetry','tb_hd_uart','tb_score_ble','tb_led595','tb_split_integration']]
models = sorted((stage/'tb').glob('*_model.v'))
for bench in benches:
    name = bench.stem
    if name=='tb_mix_headroom':
        modes = [args.timbre] if args.test else [0,2]
        selector = 'TIMBRE'
    else:
        modes = [args.mode] if args.test else ([0,1,2,3] if name=='tb_ads_audio' else [0])
        selector = 'MODE'
    compiled = stage/f'{name}.vvp'
    command = [str(iverilog),'-g2012','-s',name,'-o',str(compiled)]
    command += [str(f) for f in sorted((stage/'rtl').glob('*.v'))] + [str(bench)] + [str(f) for f in models]
    build = subprocess.run(command,cwd=bin_dir,capture_output=True,text=True)
    if build.returncode:
        print(build.stdout+build.stderr)
        raise SystemExit(f'Compile failed: {name}')
    for mode in modes:
        print(f'RUN {name} mode={mode}',flush=True)
        suffix = f'_mode{mode}' if name=='tb_ads_audio' else (f'_timbre{mode}' if name=='tb_mix_headroom' else '')
        log_path=root/'sim'/f'{name}{suffix}.log'
        with log_path.open('w',encoding='utf-8') as log:
            log.write(build.stdout+build.stderr);log.flush()
            run = subprocess.run([str(vvp),'-i',str(compiled),f'+{selector}={mode}'],cwd=root.parent,stdout=log,stderr=subprocess.STDOUT,text=True,timeout=1200)
        text=log_path.read_text(encoding='utf-8')
        if run.returncode or 'FAIL' in text or 'PASS' not in text:
            print(text)
            raise SystemExit(f'Test failed: {name} mode={mode}')
        print('\n'.join(line for line in text.splitlines() if not line.startswith('TRACE')),flush=True)
    if name=='tb_spectrum32':
        shutil.copy2(stage/'spectrum32.pcm.txt',root/'sim/spectrum32.pcm.txt')
print(f'PASS all selected tests. Reproduction directory: {stage}')
