import fs from 'node:fs';
const targets=await fetch('http://127.0.0.1:19327/json/list').then(r=>r.json());
const target=targets.find(t=>t.url==='app://-/index.html');
const ws=new WebSocket(target.webSocketDebuggerUrl);
let id=0;const pending=new Map();
ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){pending.get(m.id)?.(m);pending.delete(m.id)}};
await new Promise(r=>ws.onopen=r);
function call(method,params){return new Promise(r=>{pending.set(++id,r);ws.send(JSON.stringify({id,method,params}))})}
const expression=fs.readFileSync(process.argv[2],'utf8');console.log(JSON.stringify(await call('Runtime.evaluate',{expression,returnByValue:true})));
const shot=await call('Page.captureScreenshot',{format:'jpeg',quality:75});fs.writeFileSync('native-startup/live-main.jpg',Buffer.from(shot.result.data,'base64'));ws.close();
