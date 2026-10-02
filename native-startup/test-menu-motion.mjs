// Opens and dismisses menus only; never selects an action or changes permissions.
const ts=await fetch('http://127.0.0.1:19327/json/list').then(r=>r.json());
const ws=new WebSocket(ts.find(t=>t.url==='app://-/index.html').webSocketDebuggerUrl);
let id=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){pending.get(m.id)?.(m);pending.delete(m.id)}};
await new Promise(r=>ws.onopen=r);
const call=(method,params)=>new Promise(r=>{pending.set(++id,r);ws.send(JSON.stringify({id,method,params}))});
const ev=async expression=>(await call('Runtime.evaluate',{expression,returnByValue:true})).result?.result?.value;
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const key=async k=>{await call('Input.dispatchKeyEvent',{type:'keyDown',key:k,code:k,windowsVirtualKeyCode:k==='Escape'?27:40});await call('Input.dispatchKeyEvent',{type:'keyUp',key:k,code:k,windowsVirtualKeyCode:k==='Escape'?27:40})};
const results=[];
try {
 for(const reduce of [false,true]){
  await call('Emulation.setEmulatedMedia',{features:reduce?[{name:'prefers-reduced-motion',value:'reduce'}]:[]});
  for(const label of ['添加文件等内容','更改权限']){
   await key('Escape');await wait(1250);
   const pos=await ev(`(()=>{const b=[...document.querySelectorAll('button')].find(e=>e.getAttribute('aria-label')===${JSON.stringify(label)}&&e.checkVisibility());if(!b)return null;const r=b.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
   if(!pos)throw Error('Missing trigger '+label);
   await call('Input.dispatchMouseEvent',{type:'mousePressed',...pos,button:'left',clickCount:1});await call('Input.dispatchMouseEvent',{type:'mouseReleased',...pos,button:'left',clickCount:1});await wait(40);
   const opened=await ev(`(()=>{const e=document.querySelector('[data-composer-overlay-floating-ui]:not(.aemeath-popup-exit *),[role="menu"][data-state="open"]');if(!e)return null;const r=e.getBoundingClientRect();return{durations:e.getAnimations().map(a=>a.effect.getTiming().duration),animation:getComputedStyle(e).animationName,hit:e.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2))}})()`);
   if(!opened || !opened.hit)throw Error('Menu unavailable '+label);
   if(reduce ? opened.durations.length!==0 : !opened.durations.includes(1100))throw Error('Incorrect enter timing '+JSON.stringify(opened));
   await wait(1250);await key('ArrowDown');
   const keyboard=await ev(`({role:document.activeElement.getAttribute('role'),label:document.activeElement.getAttribute('aria-label'),selectedRows:document.querySelectorAll('[data-list-navigation-item][aria-current="true"]').length})`);
   await key('Escape');await wait(30);
   const closing=await ev(`({native:document.querySelector('[role="menu"][data-state="closed"]')?getComputedStyle(document.querySelector('[role="menu"][data-state="closed"]')).animationName:null,ghost:!!document.querySelector('.aemeath-popup-exit'),ghostInteractive:document.querySelector('.aemeath-popup-exit')?.inert===false})`);
   if(reduce && closing.ghost)throw Error('Reduced-motion ghost');
   if(!reduce && label==='添加文件等内容' && !closing.ghost)throw Error('Missing custom menu exit');
   if(!reduce && label==='更改权限' && !closing.ghost)throw Error('Missing menu exit');
   await wait(1250);
   const closed=await ev(`({remaining:document.querySelectorAll('[data-composer-overlay-floating-ui],[role="menu"],.aemeath-popup-exit').length,focus:document.activeElement.getAttribute('aria-label'),focusConnected:document.activeElement.isConnected})`);
   if(closed.remaining!==0||!closed.focusConnected)throw Error('Cleanup/focus failed');
   results.push({label,reduced:reduce,opened,keyboard,closing,closed});
  }
 }
 console.log(JSON.stringify(results,null,2));
}finally{await key('Escape');await call('Emulation.setEmulatedMedia',{features:[]});ws.close()}
