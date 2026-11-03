const {chromium}=require('C:/Users/Lenovo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const assert=require('assert');
const {pathToFileURL}=require('url');
const path=require('path');
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 const results=[];
 for(const [width,height] of [[1400,920],[800,1280],[412,850]]){
  const page=await browser.newPage({viewport:{width,height}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(__dirname,'assets/index.html')).href);
  const result=await page.evaluate(async()=>{
   window.Native={write:(cmd,id)=>setTimeout(()=>{nativeEvent('written',{id});nativeEvent('data',{bytes:[cmd.charCodeAt(0)]});},0)};
   nativeEvent('connected',{});
   function touch(t,oct=4){const f=[165,94,0,0,14,60,oct,t&255,t>>8,0];f.push(f.slice(2).reduce((a,b)=>a^b,0));received(f);}
   touch(0);
   const song={name:'单音、三音和弦和十二音和弦连续切换测试',bpm:120,notes:Array.from({length:64},(_,i)=>({...([0,2].includes(i%4)?{midi:[60,62,64,67][i%4]}:{midis:i%4===1?[60,64,67]:Array.from({length:12},(_,k)=>60+k)}),beats:1,...(i%3===0?{bend:-100,vibrato:100,pressure:100}:{})}))};
   startLocalFollow(song);window.scrollTo(0,220);await new Promise(r=>requestAnimationFrame(r));
   const positions=()=>['keys','visualCanvas','followHint','queue'].map(id=>document.getElementById(id).getBoundingClientRect().top).concat(window.scrollY);
   const base=positions(),durations=[],deltas=[];
   for(let i=0;i<64;i++){
    expression={bend:i%2?100:-100,vibrato:i,pressure:i,flags:i%7?7:0,time:Date.now()};
    touch(0);const begin=performance.now();touch(pitches(song.notes[i]).reduce((mask,m)=>mask|(1<<(m%12)),0));durations.push(performance.now()-begin);
    await new Promise(r=>requestAnimationFrame(r));deltas.push(Math.max(...positions().map((p,j)=>Math.abs(p-base[j]))));
    if(localFollow.index!==Math.min(63,i+1))throw Error('Local guide stalled');
   }
   return {maxPositionDelta:Math.max(...deltas),maxHandlerMs:Math.max(...durations),meanHandlerMs:durations.reduce((a,b)=>a+b)/durations.length,done:localFollow.done,scrollY:window.scrollY};
  });
  assert.equal(errors.length,0,errors.join('\n'));assert.equal(result.done,true);assert(result.maxPositionDelta<=1,'layout moved: '+JSON.stringify(result));
  await page.screenshot({path:path.join(__dirname,`instant19_${width}.png`)});
  results.push({width,height,...result});await page.close();
 }
 await browser.close();require('fs').writeFileSync(path.join(__dirname,'test_layout_results.json'),JSON.stringify({source:'Synthetic BLE replay on desktop Edge; not tablet radio timing',results},null,2));console.log(JSON.stringify(results,null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
