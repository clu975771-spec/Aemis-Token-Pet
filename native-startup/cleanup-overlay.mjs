const targets=await fetch('http://127.0.0.1:19327/json/list').then(r=>r.json());
for(const t of targets.filter(t=>t.url.startsWith('app://-/index.html'))){
 await new Promise((resolve,reject)=>{const ws=new WebSocket(t.webSocketDebuggerUrl);ws.onopen=()=>ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:"document.getElementById('aemeath-startup-layer')?.remove();if(window.__aemeathStartupState)window.__aemeathStartupState.phase='removed';",returnByValue:true}}));ws.onmessage=()=>{ws.close();resolve()};ws.onerror=reject});
}
