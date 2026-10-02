(() => {
  if (location.protocol !== 'app:' || location.hostname !== '-' || location.pathname !== '/index.html') return 'wrong-target';
  if (!document.body || !document.getElementById('root')) return 'not-ready';
  if (window.__aemeathEnhancements?.version === 5) return 'already-installed';
  window.__aemeathEnhancements?.cleanup?.();

  const gauge = document.createElement('div');
  gauge.id = 'aemeath-quota';
  gauge.setAttribute('role', 'img');
  gauge.innerHTML = '<svg viewBox="0 0 24 15" aria-hidden="true"><path class="track" d="M 1.25 13.25 A 10.75 10.75 0 0 1 22.75 13.25"/><path class="fill" d="M 1.25 13.25 A 10.75 10.75 0 0 1 22.75 13.25" pathLength="100"/></svg><span class="value">—</span><span class="label">额度</span>';
  document.body.append(gauge);

  const updateQuota = (quota) => {
    if (quota !== undefined) window.__aemeathQuota = quota;
    const value = window.__aemeathQuota?.remainingPercent;
    const valid = Date.now() - (window.__aemeathQuota?.updatedAt || 0) < 180000 && Number.isFinite(value) && value >= 0 && value <= 100;
    gauge.dataset.available = String(valid);
    gauge.style.setProperty('--quota-offset', valid ? String(100 - value) : '100');
    gauge.querySelector('.value').textContent = valid ? `${Math.round(value)}` : '—';
    const minutes = Number(window.__aemeathQuota?.windowDurationMins);
    const period = minutes === 10080 ? '7 天' : minutes === 300 ? '5 小时' :
      Number.isFinite(minutes) && minutes > 0 ? `${Math.round(minutes / 60)} 小时` : 'Codex';
    const reset = Number(window.__aemeathQuota?.resetsAt);
    const resetText = Number.isFinite(reset) && reset > 0
      ? `，${new Date(reset * 1000).toLocaleString('zh-CN', {month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'})} 重置` : '';
    gauge.setAttribute('aria-label', valid ? `${period}额度剩余 ${Math.round(value)}%${resetText}` : 'Codex 额度暂不可用');
    gauge.title = gauge.getAttribute('aria-label');
  };
  window.__aemeathQuotaUpdate = updateQuota;
  updateQuota();

  const root = document.getElementById('root');
  let frame = null;
  const paint = () => {
    frame = null;
    const w = window.innerWidth, h = window.innerHeight;
    for (const child of root.children) {
      const box = child.getBoundingClientRect();
      if (box.width > w * .65 && box.height > h * .65) child.classList.add('aemeath-shell-stage');
    }
    const topLevel = [...root.querySelectorAll('aside,nav,main,[data-app-shell-main-surface],[data-app-shell-focus-area]')];
    for (const el of topLevel) {
      const box = el.getBoundingClientRect();
      if (box.height < h * .58) continue;
      if (box.left < 80 && box.width >= 32 && box.width <= 96) el.classList.add('aemeath-icon-rail');
      else if (box.left < 125 && box.width >= 170 && box.width <= 440) el.classList.add('aemeath-sidebar');
      else if (box.left >= 170 && box.width > w * .45) el.classList.add('aemeath-main');
    }
    const account = [...root.querySelectorAll('button,[role="button"]')]
      .map(el => ({el, box: el.getBoundingClientRect()}))
      .filter(({el,box}) => box.left >= 0 && box.left < 110 && box.width >= 24 && box.width <= 72 &&
        box.height >= 24 && box.height <= 72 && box.bottom > h - 120 &&
        (/^[\p{L}]{1,3}$/u.test(el.textContent.trim()) || /account|profile|avatar|账户|账号|个人资料/i.test(el.getAttribute('aria-label') || '')))
      .sort((a,b) => b.box.bottom - a.box.bottom)[0];
    gauge.hidden = !account;
    if (account) {
      const avatar = account.el.querySelector('img')?.getBoundingClientRect() || account.box;
      const diameter = avatar.width;
      gauge.style.setProperty('--quota-size', `${diameter}px`);
      gauge.style.left = `${avatar.left}px`;
      gauge.style.bottom = `${Math.round(h - account.box.top + 54)}px`;
    }
  };
  const schedule = () => { if (frame === null) frame = requestAnimationFrame(paint); };
  const observer = new MutationObserver(schedule);
  observer.observe(root, {childList:true,subtree:true});
  window.addEventListener('resize', schedule, {passive:true});
  const timer = setInterval(() => { updateQuota(); schedule(); }, 3000);
  schedule();
  window.__aemeathEnhancements = {
    version: 5,
    paint,
    cleanup() {
      observer.disconnect();
      clearInterval(timer);
      window.removeEventListener('resize', schedule);
      if (frame !== null) cancelAnimationFrame(frame);
      gauge.remove();
      delete window.__aemeathQuotaUpdate;
    },
  };
  return 'installed';
})()
