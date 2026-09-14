/* Scoranger 0.8 redesign options — shared behaviour.
   1. Icon sprite (SF Symbols are not available in a web page; these stand in
      for the glyphs the app already uses, one per idea).
   2. Pseudo-engraving: a deterministic canvas drawing of staves, barlines and
      noteheads so the score reads as a score in every mockup. It is a stand-in
      for Verovio's output, never a claim about the notation.
   3. Frame scaling so a 1194pt iPad fits the document column. */

(function () {
  const SPRITE = `
<svg xmlns="http://www.w3.org/2000/svg" style="display:none">
  <symbol id="i-menu" viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/></symbol>
  <symbol id="i-share" viewBox="0 0 24 24"><path d="M12 15V4m0 0L8 8m4-4 4 4M5 12v7a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-7"/></symbol>
  <symbol id="i-plus" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></symbol>
  <symbol id="i-x" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></symbol>
  <symbol id="i-back" viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></symbol>
  <symbol id="i-chev" viewBox="0 0 24 24"><path d="M9 5l7 7-7 7"/></symbol>
  <symbol id="i-down" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></symbol>
  <symbol id="i-up" viewBox="0 0 24 24"><path d="M6 15l6-6 6 6"/></symbol>
  <symbol id="i-play" viewBox="0 0 24 24"><path d="M7 5v14l11-7z" fill="currentColor" stroke="none"/></symbol>
  <symbol id="i-pause" viewBox="0 0 24 24"><path d="M8 5v14M16 5v14" stroke-width="2.4"/></symbol>
  <symbol id="i-start" viewBox="0 0 24 24"><path d="M6 5v14M19 6l-10 6 10 6z" fill="currentColor"/></symbol>
  <symbol id="i-prev" viewBox="0 0 24 24"><path d="M6 5v14M18 6l-9 6 9 6"/></symbol>
  <symbol id="i-next" viewBox="0 0 24 24"><path d="M18 5v14M6 6l9 6-9 6"/></symbol>
  <symbol id="i-metro" viewBox="0 0 24 24"><path d="M9 4h6l3 16H6zM12 17 17 7"/></symbol>
  <symbol id="i-mixer" viewBox="0 0 24 24"><path d="M6 4v16M12 4v16M18 4v16M4 14h4M10 8h4M16 12h4"/></symbol>
  <symbol id="i-gear" viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/></symbol>
  <symbol id="i-search" viewBox="0 0 24 24"><circle cx="11" cy="11" r="6"/><path d="m20 20-4.5-4.5"/></symbol>
  <symbol id="i-pencil" viewBox="0 0 24 24"><path d="M4 20l4-1L19 8l-3-3L5 16zM14 7l3 3"/></symbol>
  <symbol id="i-chat" viewBox="0 0 24 24"><path d="M4 5h16v11H9l-5 4z"/></symbol>
  <symbol id="i-page" viewBox="0 0 24 24"><path d="M7 3h7l4 4v14H7zM14 3v4h4"/></symbol>
  <symbol id="i-spread" viewBox="0 0 24 24"><path d="M3 5h8v14H3zM13 5h8v14h-8z"/></symbol>
  <symbol id="i-cont" viewBox="0 0 24 24"><path d="M3 12h18M6 8l-3 4 3 4M18 8l3 4-3 4"/></symbol>
  <symbol id="i-people" viewBox="0 0 24 24"><circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 19c0-3 2.7-5 6-5s6 2 6 5M15 18c0-2 1.5-3.5 4-3.5 1 0 2 .3 2.5.8"/></symbol>
  <symbol id="i-check" viewBox="0 0 24 24"><path d="m5 12 5 5L20 7"/></symbol>
  <symbol id="i-import" viewBox="0 0 24 24"><path d="M12 4v11m0 0-4-4m4 4 4-4M5 19h14"/></symbol>
  <symbol id="i-more" viewBox="0 0 24 24"><circle cx="5" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.6" fill="currentColor" stroke="none"/></symbol>
  <symbol id="i-sort" viewBox="0 0 24 24"><path d="M8 4v16m0 0-3-3m3 3 3-3M16 20V4m0 0-3 3m3-3 3 3"/></symbol>
  <symbol id="i-filter" viewBox="0 0 24 24"><path d="M4 6h16M7 12h10M10 18h4"/></symbol>
  <symbol id="i-edit" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><path d="m8.5 12 2.5 2.5 4.5-5"/></symbol>
  <symbol id="i-dup" viewBox="0 0 24 24"><path d="M8 8h11v11H8zM5 16V5h11"/></symbol>
  <symbol id="i-move" viewBox="0 0 24 24"><path d="M4 7h16M4 7l3-3M4 7l3 3M20 17H4m16 0-3-3m3 3-3 3"/></symbol>
  <symbol id="i-info" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8v.5"/></symbol>
  <symbol id="i-trash" viewBox="0 0 24 24"><path d="M5 7h14M9 7V4h6v3M7 7l1 13h8l1-13"/></symbol>
  <symbol id="i-perf" viewBox="0 0 24 24"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></symbol>
  <symbol id="i-link" viewBox="0 0 24 24"><path d="M10 14a4 4 0 0 1 0-5.7l2.3-2.3a4 4 0 0 1 5.7 5.7L17 12.7M14 10a4 4 0 0 1 0 5.7l-2.3 2.3a4 4 0 0 1-5.7-5.7L7 11.3"/></symbol>
  <symbol id="i-book" viewBox="0 0 24 24"><path d="M4 5h6a2 2 0 0 1 2 2v13a2 2 0 0 0-2-2H4zM20 5h-6a2 2 0 0 0-2 2v13a2 2 0 0 1 2-2h6z"/></symbol>
  <symbol id="i-loop" viewBox="0 0 24 24"><path d="M17 4l3 3-3 3M7 20l-3-3 3-3M4 17h11a5 5 0 0 0 5-5M20 7H9a5 5 0 0 0-5 5"/></symbol>
  <symbol id="i-sync" viewBox="0 0 24 24"><path d="M20 12a8 8 0 0 1-14 5.3M4 12a8 8 0 0 1 14-5.3M18 3v4h-4M6 21v-4h4"/></symbol>
</svg>`;
  document.body.insertAdjacentHTML('afterbegin', SPRITE);

  // ---- deterministic pseudo-engraving ----
  function rng(seed) { let s = seed >>> 0 || 1; return () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296; }

  function drawScore(cv) {
    const W = cv.clientWidth || parseInt(cv.getAttribute('width')) || 400;
    const H = cv.clientHeight || parseInt(cv.getAttribute('height')) || 500;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    cv.width = W * dpr; cv.height = H * dpr;
    const c = cv.getContext('2d'); c.scale(dpr, dpr);
    const d = cv.dataset;
    const staves = +d.staves || 4, continuous = 'continuous' in d, seed = +d.seed || 7;
    const title = d.title || '', parts = (d.parts || 'Violin I,Violin II,Viola,Cello').split(',');
    const r = rng(seed);
    const ink = '#1A1917';
    c.fillStyle = d.bg || '#FFFFFF'; c.fillRect(0, 0, W, H);
    const gap = continuous ? 6 : (+d.gap || 4.5);          // staff line spacing
    const staffH = gap * 4;
    const staveGap = continuous ? 40 : gap * 7;               // between staves in a system
    const sysH = staves * staffH + (staves - 1) * staveGap;
    const margin = continuous ? 24 : Math.round(W * 0.09);
    let y0 = continuous ? Math.round((H - sysH) / 2) : Math.round(H * 0.11);
    const x0 = margin + (continuous ? 60 : 34), x1 = W - margin;
    if (!continuous && title) {
      c.fillStyle = ink; c.font = `${Math.max(11, W * 0.034)}px Georgia, "Times New Roman", serif`; c.textAlign = 'center';
      c.fillText(title, W / 2, y0 - staffH * 1.6);
      c.textAlign = 'left';
    }
    const systems = continuous ? 1 : Math.max(1, Math.floor((H - y0 - H * 0.05) / (sysH + staffH * 3.2)));
    const bars = continuous ? Math.max(6, Math.round((x1 - x0) / 120)) : (+d.bars || 5);
    for (let s = 0; s < systems; s++) {
      const sy = y0 + s * (sysH + staffH * 3.2);
      // staves
      c.strokeStyle = ink; c.lineWidth = 0.6;
      for (let st = 0; st < staves; st++) {
        const ty = sy + st * (staffH + staveGap);
        for (let l = 0; l < 5; l++) { const ly = ty + l * gap; c.beginPath(); c.moveTo(x0, ly + .5); c.lineTo(x1, ly + .5); c.stroke(); }
        // clef stand-in: a stylised curl for treble, a comma with two dots for bass/alto
        c.lineWidth = gap * 0.35;
        c.beginPath();
        if (st < staves - 1) { c.moveTo(x0 + gap * 1.2, ty + gap * 4.6); c.bezierCurveTo(x0 + gap * 3.2, ty + gap * 3, x0 + gap * 1.2, ty - gap * .2, x0 + gap * 1.6, ty + gap * 1.6); c.bezierCurveTo(x0 + gap * 2.2, ty + gap * 3.5, x0 + gap * .4, ty + gap * 2.6, x0 + gap * 1.4, ty + gap * 2.2); }
        else { c.moveTo(x0 + gap * 1.1, ty + gap * 3.4); c.bezierCurveTo(x0 + gap * 1.5, ty + gap * .5, x0 + gap * 3.2, ty + gap * .8, x0 + gap * 2.6, ty + gap * 2.2); c.fillStyle = ink; c.beginPath(); c.arc(x0 + gap * 3.1, ty + gap * 1.1, gap * .28, 0, 7); c.fill(); c.beginPath(); c.arc(x0 + gap * 3.1, ty + gap * 2.1, gap * .28, 0, 7); c.fill(); }
        c.stroke();
        // part label on the first system
        if ((s === 0 || continuous) && parts[st]) { c.fillStyle = ink; c.font = `${Math.max(7, gap * 1.9)}px Georgia, serif`; c.textAlign = 'right'; c.fillText(parts[st], x0 - 6, ty + gap * 2.6); c.textAlign = 'left'; }
      }
      // system bracket
      c.lineWidth = 1.6; c.beginPath(); c.moveTo(x0 + .8, sy); c.lineTo(x0 + .8, sy + sysH); c.stroke();
      // barlines
      c.lineWidth = 0.8;
      const bw = (x1 - x0 - gap * 6) / bars;
      for (let b = 0; b <= bars; b++) {
        const bx = x0 + gap * 6 + b * bw; c.beginPath(); c.moveTo(Math.round(bx) + .5, sy); c.lineTo(Math.round(bx) + .5, sy + sysH); c.stroke();
        if (continuous && b < bars && (b % 4 === 0)) { c.fillStyle = ink; c.font = `${gap * 1.5}px Georgia, serif`; c.fillText(String(b + 1 + (+d.barStart || 0)), bx + 2, sy - gap * .8); }
      }
      // notes
      for (let st = 0; st < staves; st++) {
        const ty = sy + st * (staffH + staveGap);
        for (let b = 0; b < bars; b++) {
          const bx = x0 + gap * 6 + b * bw;
          const n = st === staves - 1 ? 1 + Math.floor(r() * 3) : 2 + Math.floor(r() * 5);
          let prevPos = 4 + Math.floor(r() * 4);
          for (let k = 0; k < n; k++) {
            const nx = bx + bw * (0.12 + (k + .5) / n * 0.82);
            prevPos = Math.max(-2, Math.min(10, prevPos + Math.floor(r() * 5) - 2));
            const ny = ty + prevPos * gap / 2;
            const whole = r() < 0.12;
            c.fillStyle = ink; c.strokeStyle = ink;
            c.save(); c.translate(nx, ny); c.rotate(-0.35); c.beginPath(); c.ellipse(0, 0, gap * .62, gap * .43, 0, 0, 7); whole ? (c.lineWidth = gap * .28, c.stroke()) : c.fill(); c.restore();
            if (!whole) { const up = prevPos > 4; c.lineWidth = 0.9; c.beginPath(); c.moveTo(nx + (up ? gap * .58 : -gap * .58), ny); c.lineTo(nx + (up ? gap * .58 : -gap * .58), ny + (up ? -1 : 1) * gap * 3.3); c.stroke();
              if (k + 1 < n && r() < 0.55) { const nnx = bx + bw * (0.12 + (k + 1.5) / n * 0.82); c.lineWidth = gap * .5; c.beginPath(); c.moveTo(nx + (up ? gap * .58 : -gap * .58), ny + (up ? -1 : 1) * gap * 3.3); c.lineTo(nnx + (up ? gap * .58 : -gap * .58), ny + (up ? -1 : 1) * gap * 3.1); c.stroke(); } }
            if (prevPos < 0 || prevPos > 8) { c.lineWidth = .6; const ly = ty + Math.round(prevPos / 2) * gap; c.beginPath(); c.moveTo(nx - gap, ly + .5); c.lineTo(nx + gap, ly + .5); c.stroke(); }
          }
          // an occasional dynamic
          if (st === 0 && r() < 0.25) { c.fillStyle = ink; c.font = `italic bold ${gap * 1.8}px Georgia, serif`; c.fillText(['mf', 'p', 'f', 'mp'][Math.floor(r() * 4)], bx + bw * .3, ty + staffH + gap * 2.4); }
        }
      }
      // bar number at system start
      if (!continuous && s > 0) { c.fillStyle = ink; c.font = `${gap * 1.6}px Georgia, serif`; c.fillText(String(1 + s * bars), x0 + gap * 6, sy - gap * .9); }
    }
    if (!continuous && 'pageno' in d) { c.fillStyle = ink; c.font = `${gap * 2}px Georgia, serif`; c.textAlign = 'center'; c.fillText(d.pageno, W / 2, H - gap * 3); }
  }

  function fit() {
    document.querySelectorAll('.frame').forEach(f => {
      const w = f.clientWidth; if (!w) return;
      const ipad = f.querySelector('.ipad'); if (!ipad) return;
      const nat = ipad.classList.contains('phone') ? 393 : 1194;
      f.style.setProperty('--z', Math.min(1, w / nat).toFixed(3));
    });
  }
  function drawAll() { document.querySelectorAll('canvas.engraving').forEach(drawScore); }
  function run() { fit(); drawAll(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(drawAll);
  window.addEventListener('resize', () => { fit(); });
})();
