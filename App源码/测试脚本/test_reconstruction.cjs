const {chromium}=require('C:/Users/Lenovo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const {pathToFileURL}=require('url'),path=require('path'),assert=require('assert');
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true});try{
const page=await browser.newPage({viewport:{width:1280,height:1100}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.goto(pathToFileURL(path.join(__dirname,'assets/index.html')).href);
const result=await page.evaluate(()=>{
 const raw=Array.from({length:128},(_,i)=>Math.round(90*Math.sin(2*Math.PI*4*i/127))),saved=JSON.stringify(raw),curve=reconstructWave(raw);
 for(let i=0;i<raw.length;i++)if(curve[8*i]!==raw[i])throw Error('Original samples changed');
 if(saved!==JSON.stringify(raw)||curve.some(x=>!Number.isFinite(x)))throw Error('Invalid interpolation');
 let er=0,el=0,points=0;for(let i=32;i<curve.length-32;i++){const x=i/8,a=Math.floor(x),f=x-a,ref=90*Math.sin(2*Math.PI*4*x/127);er+=(curve[i]-ref)**2;el+=(raw[a]*(1-f)+raw[a+1]*f-ref)**2;points++;}
 const fit=fitFundamental(raw),chord=fitFundamental(raw.map((v,i)=>v+60*Math.sin(2*Math.PI*7*i/127)));
 if(!fit||Math.abs(fit.cycles-4)>.02||chord!==null||fitFundamental(Array(128).fill(0))!==null)throw Error('Misleading sine fit');
 $('lightMode').checked=false;$('smoothWave').checked=true;$('waveMethod').value='lanczos';$('sineOverlay').checked=true;$('showSamples').checked=true;
 visualPage=0;visual={version:3,stride:2,wave:raw.slice().reverse(),xy:[],bands:[],time:Date.now()};drawVisual();
 const packetRaw=raw.map(x=>x<0?x+256:x);
 for(let part=0;part<8;part++){const f=[165,93,4,0,5,part,0x52,...packetRaw.slice(part*16,part*16+16)];f.push(f.slice(2).reduce((a,b)=>a^b,0));received(f);}
 if(!visual||visual.version!==4||visual.scale!==5||visual.stride!==2||visual.wave.some((x,i)=>x!==raw[i]/32))throw Error('V4 scale decode');
 return {rmse:Math.sqrt(er/points),linearRmse:Math.sqrt(el/points),fitCycles:fit.cycles,fitScore:fit.score,info:$('graphInfo').textContent};});
assert(result.rmse<result.linearRmse);assert.deepEqual(errors,[]);await page.locator('#visualCanvas').screenshot({path:path.join(__dirname,'wave_reconstruction22.png')});console.log('PASS reconstruction',result);
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exit(1);});
