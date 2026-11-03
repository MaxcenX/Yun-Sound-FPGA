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

function input(touch){const f=[165,94,0,0,14,60,4,touch&255,touch>>8,0];f.push(f.slice(2).reduce((a,b)=>a^b,0));fire('data',{bytes:f});}
(async()=>{
 get('connect').click();input(0);ev('syncGuideLed()');await sleep(20);assert(writes.includes('LFFFF;'));
 get('notes').value='C4+E4+G4:1 D4:1';get('bpm').value=120;
 await get('follow').click();await sleep(25);assert.equal(writes[writes.length-1],'L0091;');
 input(145);await sleep(25);assert.equal(writes[writes.length-1],'L0004;');
 input(0);input(4);await sleep(25);assert.equal(writes[writes.length-1],'L0000;');
 ev('ledSentAt=0;pumpGuideLed()');await sleep(25);assert.equal(writes[writes.length-1],'L0000;');
 await get('stop').click();await sleep(25);assert.equal(writes[writes.length-1],'LFFFF;');
 const n=writes.length;ev('busyUI=true;ledDesired="L0FFF;";pumpGuideLed()');await sleep(20);assert.equal(writes.length,n);ev('busyUI=false;pumpGuideLed()');await sleep(25);assert.equal(writes[writes.length-1],'L0FFF;');
 fire('disconnected',{message:'test'});const end=writes.length;ev('pumpGuideLed()');await sleep(20);assert.equal(writes.length,end);
 console.log('PASS LED release/target/chord/advance/done, refresh lease, command serialization and disconnect.');
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>{for(const t of timers)clearTimeout(t);});
