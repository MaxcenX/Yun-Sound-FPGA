// Tests the actual bundled script with a simulated native bridge, not a BLE radio.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync(__dirname+'/assets/index.html','utf8');
const js=html.match(/<script>([\s\S]*)<\/script>/)[1];
class Element{constructor(){this.value='';this.textContent='';this.style={};this.children=[];this.disabled=false;this.classes=new Set();this.classList={toggle:(k,b)=>b?this.classes.add(k):this.classes.delete(k),remove:k=>this.classes.delete(k)};}append(x){this.children.push(x);}appendChild(x){this.append(x);}replaceChildren(){this.children=[];}click(){if(this.onclick)return this.onclick();}}
const els=new Map(),get=id=>{if(!els.has(id))els.set(id,new Element());return els.get(id);};get('import').parentElement=new Element();
const storage=new Map(),timers=new Set();let connected=false,writes=[],stored=[],uploading=[],expected=0,failNext=false,suppressAck=false;
const context={console,Element,Map,JSON,Number,Math,Date,Error,Promise,setInterval:()=>0,clearInterval:()=>{},setTimeout:(f,n)=>{const id=setTimeout(f,n);timers.add(id);return id;},clearTimeout:id=>{clearTimeout(id);timers.delete(id);},localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)},document:{getElementById:get,createElement:()=>new Element(),querySelectorAll:()=>[]}};
context.window=context;
const fire=(t,p)=>context.nativeEvent(t,p);
context.Native={connect:()=>{connected=true;fire('connected',{name:'JDY-23'});},disconnect:()=>{connected=false;fire('disconnected',{message:'test disconnect'});},exportScore:s=>{context.exported=s;},importScore:()=>{},write:(cmd,id)=>{
 assert(connected);writes.push(cmd);
 if(failNext){failNext=false;setTimeout(()=>fire('writeError',{id}),1);return;}
 let ack=cmd[0];if(cmd[0]==='B'){expected=parseInt(cmd.slice(1,3),16);uploading=[];}
 if(cmd[0]==='W'){const i=parseInt(cmd.slice(1,3),16),m=parseInt(cmd.slice(3,5),16),d=parseInt(cmd.slice(5,7),16),c=parseInt(cmd.slice(7,9),16);assert.equal(i,uploading.length);assert.equal((i+m+d)&255,c);uploading.push({midi:m,beats:d});ack='K';}
 if(cmd[0]==='C'){assert.equal(uploading.length,expected);stored=uploading.slice();}
 // ACK can arrive before Android's characteristic-write callback.
 if(!suppressAck)setTimeout(()=>fire('data',{bytes:[ack.charCodeAt(0)]}),1);
 setTimeout(()=>fire('written',{id}),5);
}};
vm.createContext(context);vm.runInContext(js,context);
const ev=s=>vm.runInContext(s,context),sleep=n=>new Promise(r=>setTimeout(r,n));
function frame(index,midi,touch,flags){const a=[0xa5,0x5a,1,index,14,midi,4,touch&255,touch>>8,flags];a.push(a.slice(2).reduce((a,b)=>a^b,0));return a;}
// Follow the actual multi-key telemetry through recording, editor, export and guidance.
function input(touch,octave=4){const f=[165,94,0,0,14,60,octave,touch&255,touch>>8,0];f.push(f.slice(2).reduce((a,b)=>a^b,0));fire('data',{bytes:f,arrivedAt:Date.now()});}
const plain=o=>JSON.parse(JSON.stringify(o));
const raw=notes=>({format:'acg525-performance-v1',name:'和弦测试',bpm:120,durationMs:5000,expression:[],notes});
(async()=>{
 get('connect').click();input(0);get('recStart').click();ev('recordStart-=100');
 input(145); // C4 E4 G4 at the same BLE status (bits 0,4,7).
 assert.deepEqual(plain(ev('take.notes.map(n=>n.midi)')),[60,64,67]);
 assert.equal(get('recordHeld').textContent,'当前同时按下：C4 + E4 + G4');
 assert.equal(get('recordNotes').textContent,'C4+E4+G4');
 ev('recordStart-=500');input(144); // lift C first: don't create a new score event.
 ev('recordStart-=20');input(128);ev('recordStart-=20');input(0);
 ev('recordStart-=2000');input(145);ev('recordStart-=500');input(0);
 get('recStop').click();get('recExport').click();const takeSaved=JSON.parse(context.exported);assert.equal(takeSaved.notes.length,6);
 get('recConvert').click();assert.equal(get('notes').value,'C4+E4+G4:1 C4+E4+G4:1');
 assert.equal(get('recordHeld').textContent,'当前同时按下：—');
 get('export').click();const score=JSON.parse(context.exported);assert.deepEqual(score.notes,[{midis:[60,64,67],beats:1},{midis:[60,64,67],beats:1}]);
 fire('import',{text:JSON.stringify(score)});get('openRows').click();get('applyRows').click();assert.equal(get('notes').value,'C4+E4+G4:1 C4+E4+G4:1');
 get('save').click();assert(storage.get('acg525-scores').includes('"midis":[60,64,67]'));
 // No silent reduction to the top note in a legacy hardware upload.
 const before=writes.length;await get('upload').click();assert.equal(writes.length,before);assert(get('message').textContent.includes('和弦'));
 await get('rhythm').click();assert.equal(writes.length,before);assert(get('message').textContent.includes('和弦'));
 input(0);await get('follow').click();assert.equal(get('goal').textContent,'0+4+7');
 for(const k of [0,4,7])assert(get('key'+k).classes.has('goal'));assert(!get('key1').classes.has('goal'));
 input(1);assert.equal(ev('localFollow.stepIndex'),0);input(17);assert.equal(ev('localFollow.stepIndex'),0);input(145);assert.equal(ev('localFollow.stepIndex'),1);
 input(145);assert.equal(ev('localFollow.done'),false); // holding a chord never repeats it.
 input(144);input(145);assert.equal(ev('localFollow.done'),false); // must re-articulate every member of repeated chord.
 input(0);input(145);assert.equal(ev('localFollow.done'),true);
 await get('stop').click();
 // Shared tones can be held when changing chords: CEG -> CFA.
 get('notes').value='C4+E4+G4:1 C4+F4+A4:1';input(0);await get('follow').click();input(145);assert.equal(get('goal').textContent,'0+5+9');input(1);input(33);input(545);assert.equal(ev('localFollow.done'),true);
 await get('stop').click();input(0);await get('follow').click();input(145,5);assert.equal(ev('localFollow.stepIndex'),0);input(0);input(145,4);assert.equal(ev('localFollow.stepIndex'),1);await get('stop').click();
 // Staggered status packets: 0/30/60 ms -> one chord, no release artifacts.
 context.testTake=raw([{midi:60,startMs:0,durationMs:500},{midi:64,startMs:30,durationMs:520},{midi:67,startMs:60,durationMs:510}]);
 const unchanged=JSON.stringify(context.testTake);
 assert.deepEqual(plain(ev('takeToSong(testTake).notes')),[{midis:[60,64,67],beats:1}]);assert.equal(JSON.stringify(context.testTake),unchanged);
 assert.deepEqual(plain(ev('takeToSong(testTake,0).notes.map(n=>n.midi)')),[60,64,67]);
 get('chordWindow').value='0';fire('import',{text:JSON.stringify(context.testTake)});get('recConvert').click();assert.equal(get('notes').value,'C4:1 E4:1 G4:1');get('chordWindow').value='80';get('recConvert').click();assert.equal(get('notes').value,'C4+E4+G4:1');
 // Rapid nonoverlapping notes are not merged; repeated pitch isn't deduplicated.
 context.testTake=raw([{midi:60,startMs:0,durationMs:10},{midi:64,startMs:30,durationMs:10},{midi:67,startMs:60,durationMs:10}]);assert.equal(ev('takeToSong(testTake).notes.length'),3);
 context.testTake=raw([{midi:60,startMs:0,durationMs:20},{midi:60,startMs:30,durationMs:20}]);assert.equal(ev('takeToSong(testTake).notes.length'),2);
 // Preserve full 12-key chord and its expression, with text/editor/JSON roundtrip.
 context.testTake={...raw(Array.from({length:12},(_,i)=>({midi:60+i,startMs:0,durationMs:500}))),expression:[{timeMs:0,bend:-20,vibrato:30,pressure:70}]};
 const full=plain(ev('takeToSong(testTake)'));assert.equal(full.notes[0].midis.length,12);assert.equal(full.notes[0].pressure,70);fire('import',{text:JSON.stringify(full)});get('openRows').click();get('applyRows').click();get('export').click();assert.deepEqual(JSON.parse(context.exported),full);
 input(0);await get('follow').click();input(4095);assert.equal(ev('localFollow.done'),true);await get('stop').click();
 // Invalid / ambiguous chord input is explicitly rejected.
 for(const t of ['C4+C4:1','C4+R:1','C4+E5:1','C4+E4:0','C4+E4:17']){get('notes').value=t;assert.throws(()=>ev('checkedEditor()'));}
 assert.throws(()=>ev("validate({name:'ambiguous',bpm:120,notes:[{midi:60,midis:[60,64],beats:1}]})"));
 console.log('PASS chords: real status-mask capture; raw onset/duration preservation; no rests; full chord conversion; staggered onsets and configurable grouping; no release artifacts; repeated chord and shared-tone transitions; all 12 bits; text/row/JSON/storage round trips; no unsupported firmware upload.');
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>{for(const t of timers)clearTimeout(t);});
