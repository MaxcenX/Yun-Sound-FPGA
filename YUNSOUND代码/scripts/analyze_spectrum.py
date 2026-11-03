from pathlib import Path
import numpy as np,json,csv
p=Path(__file__).resolve().parents[1]
y=np.loadtxt(p/'sim/spectrum32.pcm.txt'); n=len(y);fs=48000
spec=np.abs(np.fft.rfft(y))/n*2
bins=np.array([64+19*i for i in range(32)])
amp=spec[bins];assert len(y)==16384 and np.min(amp)>100
for b in bins:assert spec[b]>spec[b-1]*100 and spec[b]>spec[b+1]*100
with (p/'docs/32声部测试频率.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.writer(f);w.writerow(['Voice','Frequency_Hz_nominal_48k','Phase_step','FFT_peak_amplitude'])
 for i,b in enumerate(bins):w.writerow([i,b*fs/n,int(b)<<18,float(amp[i])])
r={'sample_count':n,'fs_nominal':fs,'expected_peaks':32,'minimum_peak_amplitude':float(min(amp)),'maximum_peak_amplitude':float(max(amp)),'peak_pcm':int(np.max(np.abs(y))),'clipped_samples':int(np.sum(np.abs(y)>=32767))}
assert r['clipped_samples']==0
(p/'sim/fft_result.json').write_text(json.dumps(r,indent=2));print(json.dumps(r))
