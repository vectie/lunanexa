'use strict';
(() => {
  const slides = [...document.querySelectorAll('.slide')];
  const dots = [...document.querySelectorAll('.dot')];
  const play = document.querySelector('#play');
  const path = document.querySelector('#play-path');
  const full = document.querySelector('#fullscreen');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const interval = 15000;
  let index = 0, playing = !reduced.matches, timer, idle;
  function schedule() {
    clearTimeout(timer);
    if (playing && !document.hidden) timer = setTimeout(() => show(index + 1), interval);
  }
  function show(next, manual = false) {
    index = (next + slides.length) % slides.length;
    slides.forEach((slide, i) => {
      slide.classList.toggle('active', i === index);
      slide.setAttribute('aria-hidden', String(i !== index));
      slide.inert = i !== index;
      if (i === index) dots[i].setAttribute('aria-current', 'true');
      else dots[i].removeAttribute('aria-current');
    });
    if (manual) document.querySelector('#announcement').textContent = slides[index].getAttribute('aria-label');
    schedule();
  }
  function updatePlay() {
    const label = playing ? '暂停轮播' : '播放轮播';
    play.setAttribute('aria-label', label);
    play.title = `${label}（空格）`;
    path.setAttribute('d', playing ? 'M9 5v14M15 5v14' : 'm9 5 10 7-10 7Z');
    schedule();
  }
  function wake() {
    document.body.classList.remove('idle');
    clearTimeout(idle);
    if (!reduced.matches) idle = setTimeout(() => {
      if (!document.querySelector('.controls').contains(document.activeElement)) document.body.classList.add('idle');
    }, 3500);
  }
  document.querySelector('#previous').addEventListener('click', () => show(index - 1, true));
  document.querySelector('#next').addEventListener('click', () => show(index + 1, true));
  dots.forEach((dot, i) => dot.addEventListener('click', () => show(i, true)));
  play.addEventListener('click', () => { playing = !playing; updatePlay(); });
  full.addEventListener('click', async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await document.documentElement.requestFullscreen();
    } catch { document.querySelector('#announcement').textContent = '浏览器未允许全屏，可使用浏览器全屏功能。'; }
  });
  document.addEventListener('fullscreenchange', () => {
    const label = document.fullscreenElement ? '退出全屏' : '进入全屏';
    full.setAttribute('aria-label', label); full.title = `${label}（F）`;
  });
  document.addEventListener('keydown', event => {
    wake();
    if (event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.key === 'ArrowRight') { event.preventDefault(); show(index + 1, true); }
    if (event.key === 'ArrowLeft') { event.preventDefault(); show(index - 1, true); }
    if (event.code === 'Space' && event.target.tagName !== 'BUTTON') { event.preventDefault(); playing = !playing; updatePlay(); }
    if (event.key.toLowerCase() === 'f') { event.preventDefault(); full.click(); }
  });
  document.addEventListener('visibilitychange', schedule);
  document.addEventListener('pointermove', wake, {passive:true});
  document.addEventListener('pointerdown', wake, {passive:true});
  document.addEventListener('focusin', wake);
  reduced.addEventListener('change', () => { if (reduced.matches) { playing = false; updatePlay(); } wake(); });
  slides.forEach(slide => {
    const img = slide.querySelector('img');
    const fail = () => { document.querySelector('#load-error').hidden = false; playing = false; updatePlay(); wake(); };
    img.addEventListener('error', fail);
    if (img.complete && !img.naturalWidth) fail();
  });
  document.querySelector('#retry').addEventListener('click', () => location.reload());
  if (!document.fullscreenEnabled) full.hidden = true;
  updatePlay(); wake();
})();
