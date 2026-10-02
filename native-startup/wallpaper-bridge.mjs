import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawn,spawnSync} from 'node:child_process';

const root=path.dirname(fileURLToPath(import.meta.url));
const logDir=path.join(os.homedir(),'Library/Logs/AemeathStartup');
fs.mkdirSync(logDir,{recursive:true});
const lock=path.join(logDir,'bridge.lock');
const requestFile=path.join(logDir,'play-startup.request.json');
const ackFile=path.join(logDir,'play-startup.ack.json');
try {const old=JSON.parse(fs.readFileSync(lock));const command=spawnSync('/bin/ps',['-p',String(old.pid),'-o','command='],{encoding:'utf8'}).stdout || '';if(command.includes(fileURLToPath(import.meta.url)))process.exit(0);} catch {}
fs.writeFileSync(lock,JSON.stringify({pid:process.pid}));
process.on('exit',()=>{try{fs.unlinkSync(lock)}catch{}});

const theme=fs.readFileSync(path.join(root,'theme.css'),'utf8');
const motion=fs.readFileSync(path.join(root,'motion.js'),'utf8');
const enhancements=fs.readFileSync(path.join(root,'enhancements.js'),'utf8');
const picture='data:image/png;base64,'+fs.readFileSync(path.join(root,'wallpaper.png')).toString('base64');
const videoPath=path.join(root,'startup.mp4');
const voicePath=[path.join(root,'startup-voice.wav'),path.join(root,'audio/startup-voice.wav')].find(fs.existsSync);
let startupMedia;

function record(message){fs.appendFileSync(path.join(logDir,'wallpaper.log'),new Date().toISOString()+' '+message+'\n')}
function isMainCodexTarget(target){
 if(target.type!=='page')return false;
 try {const u=new URL(target.url);return u.protocol==='app:'&&u.hostname==='-'&&u.pathname==='/index.html'&&!u.searchParams.has('initialRoute')} catch {return false}
}
async function targets(){
 const response=await fetch('http://127.0.0.1:19327/json/list',{signal:AbortSignal.timeout(1500)});
 return (await response.json()).filter(isMainCodexTarget);
}
async function evaluate(target,expression,timeout=6000){
 return await new Promise((resolve,reject)=>{
  const ws=new WebSocket(target.webSocketDebuggerUrl);const timer=setTimeout(()=>{ws.close();reject(Error('timeout'))},timeout);
  ws.onopen=()=>ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression,returnByValue:true,awaitPromise:true}}));
  ws.onmessage=event=>{const data=JSON.parse(event.data);if(data.id!==1)return;clearTimeout(timer);ws.close();if(data.error||data.result?.exceptionDetails)reject(Error('evaluation-failed'));else resolve(data.result?.result?.value)};
  ws.onerror=()=>{clearTimeout(timer);reject(Error('connection-error'))};
 });
}

const wallpaperExpression=`(()=>{
 if(location.protocol!=='app:'||location.hostname!=='-'||location.pathname!=='/index.html'||new URL(location.href).searchParams.has('initialRoute'))return 'wrong-target';
 if(!document.body||!document.head)return 'not-ready';
 if(document.getElementById('aemeath-wallpaper')?.dataset.version==='27')return 'already-installed';
 document.getElementById('aemeath-wallpaper')?.remove();document.getElementById('aemeath-wallpaper-style')?.remove();
 if(!document.getElementById('aemeath-glass-filters')){
 const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.id='aemeath-glass-filters';svg.setAttribute('width','0');svg.setAttribute('height','0');svg.style.position='fixed';svg.style.pointerEvents='none';
 svg.innerHTML='<defs><filter id="aemeath-glass-refraction" x="-10%" y="-10%" width="120%" height="120%" color-interpolation-filters="sRGB"><feTurbulence type="fractalNoise" baseFrequency="0.008 0.014" numOctaves="1" seed="8" result="waves"/><feDisplacementMap in="SourceGraphic" in2="waves" scale="12" xChannelSelector="R" yChannelSelector="G"/></filter></defs>';document.body.append(svg);
 }
 const image=document.createElement('div');image.id='aemeath-wallpaper';image.dataset.version='27';
 image.style.cssText='position:fixed;inset:0;pointer-events:none;z-index:0;background:center/cover no-repeat;opacity:0.32';
 image.style.backgroundImage='url('+${JSON.stringify(picture)}+')';document.body.prepend(image);
 const style=document.createElement('style');style.id='aemeath-wallpaper-style';
 style.textContent=\`
[data-app-shell-unified-tab-strip="true"]{background:transparent!important}
.app-shell-left-panel::after{display:none!important}
[data-app-shell-main-surface]{border-left:0!important;outline:none!important;box-shadow:none!important}
[data-app-shell-header-layout],[class*="_FloatingHeader_"],[class*="_ApplicationMenuTopBar_"]{background:transparent!important;border-bottom:0!important;box-shadow:none!important}
[data-app-shell-header-layout]::before,[data-app-shell-header-layout]::after,[class*="_FloatingHeader_"]::after{background:transparent!important;box-shadow:none!important}
[data-app-shell-header-toolbar]>div{background:transparent!important}
[data-app-shell-main-content-top-fade]{background:none!important}
html,body{background:#181818!important}
#root{position:relative;z-index:1;background:transparent!important}
#root [class*="bg-token-main-surface"],#root [class*="bg-token-sidebar-surface"],#root [class*="bg-token-bg-primary"],#root [class*="bg-token-bg-secondary"]{background-color:transparent!important}
[data-app-shell-main-surface], [data-app-shell-main-surface]::before, [class*="_MainContentSurface_"], [class~="bg-surface"]{background-color:transparent!important;background-image:none!important}
[data-app-shell-focus-area="left-panel"]{background:rgba(12,10,18,.55)!important}
#root{--color-token-main-surface-primary:transparent;--color-token-main-surface-secondary:rgba(15,12,22,.55);--color-token-sidebar-surface-primary:rgba(15,12,22,.6);--color-token-bg-primary:transparent;--color-token-bg-secondary:rgba(15,12,22,.55)}
\`;
 style.textContent += ${JSON.stringify(theme)};
 document.head.append(style);return 'installed';
})()`;

function getStartupMedia(){
 if(startupMedia)return startupMedia;
 if(!fs.existsSync(videoPath))throw Error('missing-startup-video');
 startupMedia={video:'data:video/mp4;base64,'+fs.readFileSync(videoPath).toString('base64'),voice:voicePath?'data:audio/wav;base64,'+fs.readFileSync(voicePath).toString('base64'):''};
 return startupMedia;
}
function startupExpression(token,reason='',coldStart=false){
 const media=getStartupMedia();
 return `(()=>{
  if(location.protocol!=='app:'||location.hostname!=='-'||location.pathname!=='/index.html'||!document.body)return 'not-ready';
  const coldStart=${JSON.stringify(coldStart)};
  if(coldStart&&(document.readyState!=='complete'||!document.querySelector('[data-app-shell-main-surface],[data-app-shell-unified-tab-strip],[data-app-shell-focus-area]')))return 'cold-start-not-ready';
  const token=${JSON.stringify(token)};
  const active=document.getElementById('aemeath-startup-layer');
  if(active?.dataset.token===token)return window.__aemeathStartupState?.phase==='buffering'?'startup-buffering':'already-playing';
  active?.remove();
  const layer=document.createElement('div');layer.id='aemeath-startup-layer';layer.dataset.token=token;
  layer.style.cssText='position:fixed;inset:0;z-index:2147483647;overflow:hidden;background:#070c1a;opacity:1;transition:opacity 1.05s cubic-bezier(.4,0,.2,1);pointer-events:auto;isolation:isolate';
  const video=document.createElement('video');video.src=${JSON.stringify(media.video)};video.autoplay=true;video.muted=true;video.playsInline=true;video.preload='auto';
  video.style.cssText='position:absolute;inset:0;width:100%;height:100%;object-fit:cover;background:#070c1a';
  const hero=document.createElement('div');hero.style.cssText='position:absolute;inset:0;background:center/cover no-repeat;opacity:0;transition:opacity .65s cubic-bezier(.4,0,.2,1)';hero.style.backgroundImage='url('+${JSON.stringify(picture)}+')';
  const dim=document.createElement('div');dim.style.cssText='position:absolute;inset:0;background:#181818;opacity:0;transition:opacity 1.65s cubic-bezier(.4,0,.2,1)';
  const skip=document.createElement('button');skip.textContent='跳过  Esc';skip.style.cssText='position:absolute;right:20px;bottom:18px;border:0;background:rgba(12,10,18,.28);color:rgba(255,255,255,.68);padding:7px 12px;border-radius:999px;font:11px -apple-system,BlinkMacSystemFont,sans-serif;backdrop-filter:blur(16px);cursor:pointer';
  const fromPet=${JSON.stringify(reason.includes('pet'))};
  const petLink=document.createElement('div');petLink.textContent='✦ 桌宠共鸣链路 · 已连接';petLink.style.cssText='position:absolute;left:20px;bottom:18px;border:1px solid rgba(140,217,244,.32);background:rgba(12,10,18,.32);color:rgba(244,220,232,.82);padding:7px 12px;border-radius:999px;font:11px -apple-system,BlinkMacSystemFont,sans-serif;letter-spacing:1px;backdrop-filter:blur(16px);box-shadow:0 0 22px rgba(217,147,179,.12)';
  const boot=document.createElement('div');boot.textContent='✦  AEMEATH LINK / INITIALIZING';boot.style.cssText='position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);color:rgba(244,220,232,.82);font:11px ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:2.4px;text-shadow:0 0 20px rgba(140,217,244,.5);pointer-events:none';
  boot.animate([{opacity:.35,filter:'blur(.3px)'},{opacity:1,filter:'blur(0)'},{opacity:.35,filter:'blur(.3px)'}],{duration:1200,iterations:Infinity,easing:'ease-in-out'});
  const voice=${media.voice?`new Audio(${JSON.stringify(media.voice)})`:'null'};if(voice)voice.volume=.85;
  let voiceTimer,heroTimer,dimTimer,endTimer,finished=false,started=false,resolveReady;
  window.__aemeathStartupState={token,phase:'buffering',createdAt:Date.now()};
  const finish=(reason='completed')=>{if(finished)return;finished=true;clearTimeout(voiceTimer);clearTimeout(heroTimer);clearTimeout(dimTimer);clearTimeout(endTimer);if(voice)voice.pause();window.removeEventListener('keydown',onKey,true);window.__aemeathStartupState={token,phase:'fading',reason,finishedAt:Date.now()};layer.style.pointerEvents='none';layer.style.opacity='0';setTimeout(()=>{layer.remove();window.__aemeathStartupState.phase='removed'},1100)};
  const begin=()=>{if(started||finished)return;started=true;boot.remove();window.__aemeathStartupState={token,phase:'playing',startedAt:Date.now()};voiceTimer=setTimeout(()=>voice?.play().catch(()=>{}),950);heroTimer=setTimeout(()=>hero.style.opacity='1',7650);dimTimer=setTimeout(()=>dim.style.opacity='.68',8350);endTimer=setTimeout(()=>finish('completed'),9900);resolveReady?.('startup-playing')};
  skip.onclick=()=>{if(started)finish('skip-button')};layer.append(video,hero,dim,boot,skip);if(fromPet)layer.append(petLink);document.body.append(layer);
  const onKey=e=>{if(e.key==='Escape'){e.preventDefault();finish('escape')}};window.addEventListener('keydown',onKey,{capture:true});
  return new Promise(resolve=>{resolveReady=resolve;video.addEventListener('playing',begin,{once:true});video.load();video.play().then(begin).catch(()=>{});setTimeout(()=>{if(!started&&!finished)video.play().then(begin).catch(()=>{})},500)});
 })()`;
}

async function injectWallpaper(target){
 const state=await evaluate(target,"({wallpaper:document.getElementById('aemeath-wallpaper')?.dataset.version,enhancements:window.__aemeathEnhancements?.version,motion:window.__aemeathMotion?.version})");
 if(state?.wallpaper!=='27'){
  const result=await evaluate(target,wallpaperExpression);
  if(result==='installed')record('wallpaper-installed');
 }
 if(state?.enhancements!==5){
  const result=await evaluate(target,enhancements);
  if(result==='installed')record('enhancements-installed');
 }
 if(state?.motion!==8)await evaluate(target,motion);
 await evaluate(target,`window.__aemeathQuotaUpdate?.(${JSON.stringify(quota)})`);
}

async function readQuota(){
 const binary=path.join(os.homedir(),'Desktop/ChatGPT.app/Contents/Resources/codex-cli/bin/codex');
 return await new Promise(resolve=>{
  let child,done=false,buffer='';
  const finish=value=>{if(done)return;done=true;clearTimeout(timeout);child?.kill();resolve(value)};
  const timeout=setTimeout(()=>finish(null),8000);
  try{child=spawn(binary,['app-server','--stdio'],{stdio:['pipe','pipe','ignore']})}catch{return finish(null)}
  child.on('error',()=>finish(null));child.on('exit',()=>finish(null));child.stdin.on('error',()=>finish(null));
  child.stdout.setEncoding('utf8');
  child.stdout.on('data',chunk=>{
   buffer+=chunk;if(buffer.length>262144)return finish(null);
   let i;while((i=buffer.indexOf('\n'))>=0){
    const line=buffer.slice(0,i);buffer=buffer.slice(i+1);let message;
    try{message=JSON.parse(line)}catch{continue}
    if(message.id===1){child.stdin.write(JSON.stringify({method:'initialized'})+'\n');child.stdin.write(JSON.stringify({id:2,method:'account/rateLimits/read',params:{excludeResetCreditDetails:true}})+'\n')}
    else if(message.id===2){const p=(message.result?.rateLimitsByLimitId?.codex ?? message.result?.rateLimits)?.primary;const used=p?.usedPercent;return finish(Number.isFinite(used)&&used>=0&&used<=100?{
     remainingPercent:Math.round(100-used),updatedAt:Date.now(),windowDurationMins:Number(p?.windowDurationMins)||null,resetsAt:Number(p?.resetsAt)||null
    }:null)}
   }
  });
  child.stdin.write(JSON.stringify({id:1,method:'initialize',params:{clientInfo:{name:'codex-aemeath-skin',version:'1.0'}}})+'\n');
 });
}

let quota=null,quotaUpdatedAt=0,quotaBusy=false;
async function quotaTick(){
 if(quotaBusy || Date.now()-quotaUpdatedAt<60000)return;
 quotaBusy=true;
 try { quota=await readQuota(); quotaUpdatedAt=Date.now(); } finally { quotaBusy=false; }
 record(quota?`quota-refresh remaining=${quota.remainingPercent}`:'quota-refresh-unavailable');
}

let failures=0;
let wallpaperBusy=false;
async function wallpaperTick(){
 if(wallpaperBusy)return;wallpaperBusy=true;
 try{for(const target of await targets())await injectWallpaper(target);failures=0}
 catch{failures++;if(failures===3)record('waiting-for-Codex-debug-interface')}
 finally{wallpaperBusy=false}
}

let startupBusy=false;
const refreshedTokens=new Map();
async function startupTick(){
 if(startupBusy||!fs.existsSync(requestFile))return;startupBusy=true;
 try{
  const request=JSON.parse(fs.readFileSync(requestFile,'utf8'));
  if(!request.token)throw Error('invalid-request');
  for(const target of await targets()){
   if(request.refresh===true){
    if(!refreshedTokens.has(request.token)){
     refreshedTokens.set(request.token,Date.now());
     await evaluate(target,"location.reload(); 'reloading'").catch(()=>{});
     record('codex-page-reloaded token='+request.token);
     break;
    }
    if(Date.now()-refreshedTokens.get(request.token)<1000)break;
   }
   await injectWallpaper(target);
   const result=await evaluate(target,startupExpression(request.token,request.reason,request.coldStart===true),12000);
   if(result==='startup-playing'||result==='already-playing'){
    fs.writeFileSync(ackFile,JSON.stringify({token:request.token,at:Date.now()}));
    try{fs.unlinkSync(requestFile)}catch{}
    refreshedTokens.delete(request.token);
    record('startup-injected token='+request.token);
    break;
   }
  }
 }catch(error){if(String(error).includes('missing-startup-video'))record('startup-error '+error)}
 finally{startupBusy=false}
}

void quotaTick();await wallpaperTick();await startupTick();
setInterval(wallpaperTick,3000);
setInterval(startupTick,150);
setInterval(quotaTick,15000);
