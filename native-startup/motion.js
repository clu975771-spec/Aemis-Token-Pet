(() => {
  if (location.protocol !== 'app:' || location.hostname !== '-' || location.pathname !== '/index.html') return 'wrong-target';
  if (!document.getElementById('root')) return 'not-ready';
  if (window.__aemeathMotion?.version === 8) return 'already-installed';
  window.__aemeathMotion?.cleanup();
  const root = document.getElementById('root');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const ease = 'cubic-bezier(0.42, 0, 0.25, 1)'; // gradual acceleration, long settling tail
  const selector = '[data-app-shell-tab-panel-controller="right"][data-tab-id^="file:"]';
  let pane = null, frame = null, rect = null, raf = 0, composer = null, thread = null;
  let prepared = null;
  const animations = new Set(), ghosts = new Set();
  const stats = {previewIn:0, previewOut:0, composerIn:0, popupIn:0, popupOut:0};
  const visible = el => el && el.checkVisibility({checkVisibilityCSS:true}) && el.getBoundingClientRect().width > 0;
  function animate(el, keys, duration, done, easing = ease) {
    if (reduced.matches) { done?.(); return; }
    const a = el.animate(keys, {duration, easing});
    animations.add(a);
    a.finished.catch(() => {}).finally(() => { animations.delete(a); done?.(); });
  }
  function snapshot() {
    if (!pane || !rect || reduced.matches) return null;
    const clone = pane.cloneNode(true);
    // Frozen frames only: a closing visual must not create a second media player.
    const originals = [...pane.querySelectorAll('video')];
    clone.querySelectorAll('video').forEach((v, i) => {
      const source = originals[i], canvas = document.createElement('canvas');
      canvas.className = v.className;
      canvas.width = source?.videoWidth || 1; canvas.height = source?.videoHeight || 1;
      canvas.style.objectFit = 'contain';
      try { if (source?.readyState >= 2) canvas.getContext('2d').drawImage(source,0,0,canvas.width,canvas.height); } catch {}
      v.replaceWith(canvas);
    });
    clone.querySelectorAll('audio,iframe,script').forEach(e => e.remove());
    clone.querySelectorAll('[id]').forEach(e => e.removeAttribute('id'));
    clone.removeAttribute('id');
    return {clone, rect: frame?.isConnected ? frame.getBoundingClientRect() : rect};
  }
  function exitPane(old) {
    if (!old || reduced.matches) return;
    const ghost = document.createElement('div');
    ghost.className = 'aemeath-preview-exit';
    ghost.setAttribute('aria-hidden','true'); ghost.inert = true;
    const r = old.rect;
    ghost.style.cssText = `position:fixed;left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;pointer-events:none;z-index:90;overflow:hidden;display:flex;flex-direction:column;`;
    ghost.append(old.clone); root.append(ghost); ghosts.add(ghost);
    stats.previewOut++;
    animate(ghost,[{transform:'translateX(0)',opacity:1},{transform:'translateX(100%)',opacity:0}],1400,()=>{ghost.remove();ghosts.delete(ghost)});
  }
  const resize = new ResizeObserver(() => { if (frame?.isConnected) rect = frame.getBoundingClientRect(); });
  function update() {
    raf = 0;
    const next = [...root.querySelectorAll(selector)].find(visible) || null;
    const nextFrame = next?.closest('[data-app-shell-pane-frame]') || null;
    if (nextFrame !== frame) {
      if (frame && !nextFrame) exitPane(prepared || snapshot());
      resize.disconnect();
      pane = next; frame = nextFrame; prepared = null;
      if (frame) {
        rect = frame.getBoundingClientRect(); resize.observe(frame);
        stats.previewIn++;
        animate(frame,[{transform:'translateX(100%)',opacity:.35},{transform:'translateX(0)',opacity:1}],2200);
      }
    } else { pane = next; prepared = null; }
    const nextComposer = [...root.querySelectorAll('[data-codex-composer-root] [class*="_ComposerLayoutRoot_"]')].find(visible) || null;
    const nextThread = [...new Set([...root.querySelectorAll('[data-app-action-sidebar-thread-selected="true"]')].map(e=>e.getAttribute('data-app-action-sidebar-thread-id')))].join('|') || 'new-chat';
    if (nextComposer && (nextComposer !== composer || nextThread !== thread)) {
      stats.composerIn++;
      animate(nextComposer,[{transform:'translateY(42px)',opacity:0},{transform:'translateY(0)',opacity:1}],2000);
    }
    composer = nextComposer; thread = nextThread;
  }
  const schedule = () => { if (!raf) raf = requestAnimationFrame(update); };
  // Capture before React unmounts a close target. Never delay or replay the click.
  const prepareClose = e => {
    const button = e.target.closest?.('button');
    if ((button && /关闭.*标签页|close.*tab/i.test(button.getAttribute('aria-label') || '')) || (e.type === 'keydown' && (e.key === 'Escape' || ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'w')))) prepared = snapshot();
  };
  const observer = new MutationObserver(schedule);
  observer.observe(root,{childList:true,subtree:true,attributes:true,attributeFilter:['data-app-action-sidebar-thread-selected','data-tab-id','hidden']});
  document.addEventListener('pointerdown',prepareClose,true);
  document.addEventListener('click',prepareClose,true);
  document.addEventListener('keydown',prepareClose,true);
  // Composer attachment/suggestion shell is a custom portal, not a Radix menu.
  // Observe only its mount/unmount, never animate updates to its contents.
  const popupSelector = '[data-composer-overlay-floating-ui="true"],[role="menu"][data-state="open"]';
  const popups = new Map();
  let popupRAF = 0;
  const popupSnapshot = el => {
    const r = el.getBoundingClientRect(), clone = el.cloneNode(true);
    clone.querySelectorAll('[id]').forEach(n=>n.removeAttribute('id'));
    clone.removeAttribute('id'); clone.removeAttribute('data-state'); clone.style.animation='none';
    clone.querySelectorAll('video,audio,iframe,script').forEach(n=>n.remove());
    return {clone, rect:r};
  };
  const popupResize = new ResizeObserver(entries => {
    for (const {target} of entries) if (popups.has(target)) popups.set(target,popupSnapshot(target));
  });
  function updatePopups() {
    popupRAF = 0;
    for (const [el, snap] of popups) if (!el.isConnected) {
      popupResize.unobserve(el); popups.delete(el);
      if (!reduced.matches && snap.rect.width > 0) {
        const g = document.createElement('div'), r = snap.rect;
        g.className = 'aemeath-popup-exit'; g.inert = true; g.setAttribute('aria-hidden','true');
        g.style.cssText = `position:fixed;left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;z-index:60;pointer-events:none;`;
        g.append(snap.clone);document.body.append(g);ghosts.add(g);stats.popupOut++;
        animate(g,[{opacity:1,transform:'translateY(0)'},{opacity:0,transform:'translateY(4px)'}],800,()=>{g.remove();ghosts.delete(g)});
      }
    }
    for (const el of document.querySelectorAll(popupSelector)) {
      if (el.closest('.aemeath-popup-exit') || popups.has(el) || !visible(el)) continue;
      popups.set(el,popupSnapshot(el));popupResize.observe(el);stats.popupIn++;
      if(el.getAttribute('role') !== 'menu') animate(el,[{opacity:0,transform:'translateY(14px)'},{opacity:1,transform:'translateY(0)'}],1100,()=>{if(el.isConnected&&popups.has(el))popups.set(el,popupSnapshot(el))});
    }
  }
  const popupObserver = new MutationObserver(records => {
    const changed = [...popups.keys()].some(el=>!el.isConnected) || records.some(r=>(r.type==='attributes' && r.target.matches(popupSelector)) || [...r.addedNodes].some(n=>n.nodeType===1 && !n.closest('.aemeath-popup-exit') && (n.matches(popupSelector)||n.querySelector(popupSelector))));
    if (changed && !popupRAF) popupRAF=requestAnimationFrame(updatePopups);
  });
  popupObserver.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['data-state']});
  const preparePopupClose = e => { if (e.type === 'keydown' && !['Escape','Enter','Tab'].includes(e.key)) return; if (!reduced.matches) for (const el of popups.keys()) if(el.isConnected)popups.set(el,popupSnapshot(el)); };
  document.addEventListener('pointerdown',preparePopupClose,true);
  document.addEventListener('keydown',preparePopupClose,true);
  updatePopups();
  const reduceChanged = () => { if (reduced.matches) { animations.forEach(a=>a.cancel()); ghosts.forEach(g=>g.remove()); ghosts.clear(); } };
  reduced.addEventListener('change',reduceChanged);
  schedule();
  window.__aemeathMotion = {version:8,stats,cleanup(){popupObserver.disconnect();popupResize.disconnect();if(popupRAF)cancelAnimationFrame(popupRAF);document.removeEventListener('pointerdown',preparePopupClose,true);document.removeEventListener('keydown',preparePopupClose,true);observer.disconnect();resize.disconnect();if(raf)cancelAnimationFrame(raf);animations.forEach(a=>a.cancel());ghosts.forEach(g=>g.remove());document.removeEventListener('pointerdown',prepareClose,true);document.removeEventListener('click',prepareClose,true);document.removeEventListener('keydown',prepareClose,true);reduced.removeEventListener('change',reduceChanged);}};
  return 'installed';
})()
