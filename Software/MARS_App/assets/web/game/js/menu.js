// Screens (menu.gd): start (session setup), arm calibration, pause and session results. DOM in
// index.html, black and white, big enough to tap.
import { NEUTRAL_S, RANGE_S } from './input.js';

const $ = (id) => document.getElementById(id);
export const MINUTES = [1, 2, 3, 5, 8, 10, 15, 20, 30];

export class Menu {
  constructor(game) {
    this.game = game;
    this.screens = { start: $('start'), calib: $('calib'), pause: $('pause'), results: $('results') };
    const tap = (el, fn) => el.addEventListener('click', (e) => { e.stopPropagation(); game.sfx.unlock(); game.sfx.play('click'); fn(); });
    tap($('launch'), () => game.launch());
    for (const b of document.querySelectorAll('[data-time]')) tap(b, () => this.stepTime(+b.dataset.time));
    for (const b of document.querySelectorAll('[data-input]')) tap(b, () => { game.settings.input = b.dataset.input; game.saveSettings(); this.refresh(); });
    for (const b of document.querySelectorAll('[data-diff]')) tap(b, () => { game.settings.difficulty = +b.dataset.diff; game.saveSettings(); this.refresh(); });
    tap($('calBtn'), () => game.beginCalibration());
    tap($('calGo'), () => game.robot.beginCalibration());
    tap($('flipX'), () => { game.robot.cal.inv_x = !game.robot.cal.inv_x; game.robot.save(); });
    tap($('flipY'), () => { game.robot.cal.inv_y = !game.robot.cal.inv_y; game.robot.save(); });
    tap($('calDone'), () => game.endCalibration());
    tap($('resume'), () => game.resume());
    tap($('endSession'), () => game.finishSession());
    tap($('again'), () => game.launch());
    tap($('toMenu'), () => game.toMenu());
    tap($('pauseBtn'), () => game.pauseGame('PAUSED'));
    this.calBox = $('calBox');
  }

  show(which) {
    for (const [k, el] of Object.entries(this.screens)) el.classList.toggle('on', k === which);
    $('pauseBtn').style.display = which === '' && this.game.state === 'play' ? 'block' : 'none';
    if (which === 'start') this.refresh();
  }

  stepTime(d) {
    const s = this.game.settings;
    let i = MINUTES.indexOf(s.minutes);
    i = Math.max(0, Math.min(MINUTES.length - 1, (i >= 0 ? i : 3) + d));
    s.minutes = MINUTES[i];
    this.game.saveSettings();
    this.refresh();
  }

  refresh() {
    const s = this.game.settings;
    $('time').textContent = `${String(s.minutes).padStart(2, '0')}:00`;
    for (const b of document.querySelectorAll('[data-input]')) b.classList.toggle('sel', b.dataset.input === s.input);
    for (const b of document.querySelectorAll('[data-diff]')) b.classList.toggle('sel', +b.dataset.diff === s.difficulty);
    const rows = s.input === 'robot'
      ? [['ARM UP / DOWN', 'Climb / dive  ·  lift the lever'], ['ARM LEFT / RIGHT', 'Turn  ·  sweep the hand'],
        ['REACH OUT', 'Faster'], ['TARGET IN SIGHTS', 'Guns fire by themselves'],
        ['HOLD IT STEADY', 'Missile locks and launches'], ['II (TOP RIGHT)', 'Pause']]
      : [['DRAG', 'Steer the ship (anywhere on the screen)'], ['TARGET IN SIGHTS', 'Guns fire by themselves'],
        ['HOLD IT STEADY', 'Missile locks and launches'], ['II (TOP RIGHT)', 'Pause']];
    $('controls').innerHTML = rows.map(([k, v]) => `<b>${k}</b><span>${v}</span>`).join('');
  }

  update() {
    const g = this.game, r = g.robot;
    if (this.screens.start.classList.contains('on')) {
      const link = $('link');
      if (r.live()) {
        link.textContent = `LIVE   LIFT ${r.raw.y.toFixed(0)}°   ${r.mode()}   ${r.encOk() ? 'ENC OK' : 'ENC OFF (LIFT ONLY)'}`;
        link.style.color = r.encOk() ? '#fff' : 'rgba(255,255,255,.75)';
      } else {
        link.textContent = 'NO DATA   (connect the robot in the app)';
        link.style.color = g.settings.input === 'robot' ? '#fff' : 'rgba(255,255,255,.5)';
      }
      $('calBtn').textContent = r.cal.done ? 'RECALIBRATE ARM' : 'CALIBRATE ARM';
    }
    if (this.screens.calib.classList.contains('on')) this._updateCalib();
  }

  _updateCalib() {
    const r = this.game.robot;
    $('calBar').style.width = `${Math.min(1, r.calProgress()) * 100}%`;
    $('calGo').disabled = r.calState === 1 || r.calState === 2;
    const msg = $('calMsg');
    if (!r.live()) msg.textContent = 'No robot data. Connect the robot in the MARS app (MARS tab), then come back here.';
    else if (r.calState === 0) msg.textContent = 'Sit comfortably with the arm in the cuff. Press START, relax for 3 seconds, then move the arm around as far as is comfortable: up, down, left, right, and reach out.';
    else if (r.calState === 1) msg.textContent = `RELAX  ·  hold your neutral position  (${Math.ceil(NEUTRAL_S - r.calT)} s)`;
    else if (r.calState === 2) msg.textContent = `MOVE  ·  up, down, left, right, reach out  (${Math.ceil(RANGE_S - r.calT)} s)`;
    else msg.textContent = 'Done. The dot should follow your hand: test it below. Use FLIP if a direction is reversed, then press DONE.';
    this._drawCalBox();
  }

  _drawCalBox() {
    const r = this.game.robot, cv = this.calBox;
    const u = Math.min(window.innerHeight / 100, window.innerWidth * 0.0062);
    const w = 80 * u, h = 30 * u, dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (cv.width !== Math.round(w * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); cv.style.width = w + 'px'; cv.style.height = h + 'px'; }
    const g = cv.getContext('2d');
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, w, h);
    const bs = h - 2 * u, bx = (w - bs) / 2 - 12 * u, by = u;
    g.fillStyle = 'rgba(255,255,255,.05)'; g.fillRect(bx, by, bs, bs);
    g.strokeStyle = 'rgba(255,255,255,.25)'; g.lineWidth = 1; g.strokeRect(bx + 0.5, by + 0.5, bs, bs);
    const cx = bx + bs / 2, cy = by + bs / 2;
    g.strokeStyle = 'rgba(255,255,255,.12)';
    g.beginPath(); g.moveTo(bx, cy); g.lineTo(bx + bs, cy); g.moveTo(cx, by); g.lineTo(cx, by + bs); g.stroke();
    g.fillStyle = r.live() ? 'rgba(255,255,255,.9)' : '#fff';
    g.beginPath(); g.arc(cx + r.aim.x * bs * 0.46, cy - r.aim.y * bs * 0.46, 1.1 * u, 0, Math.PI * 2); g.fill();
    const x = bx + bs + 4 * u;
    g.font = `600 ${Math.round(1.7 * u)}px Montserrat, sans-serif`;
    g.fillStyle = 'rgba(255,255,255,.55)';
    g.fillText('LIVE', x, by + 3 * u);
    g.fillStyle = '#fff';
    [`lift  ${r.raw.y.toFixed(1)}°`, `side  ${r.raw.x.toFixed(0)} mm`, `reach  ${r.raw.z.toFixed(0)} mm`]
      .forEach((s, i) => g.fillText(s, x, by + (6 + i * 2.6) * u));
    g.fillStyle = 'rgba(255,255,255,.62)';
    g.fillText(`lift ${r.cal.y_lo.toFixed(0)}° … ${r.cal.y_hi.toFixed(0)}°`, x, by + 16 * u);
    g.fillText(`side ${r.cal.x_lo.toFixed(0)} … ${r.cal.x_hi.toFixed(0)} mm`, x, by + 18.6 * u);
  }

  showResults(title, sub, tiles, note) {
    $('resTitle').textContent = title;
    $('resSub').textContent = sub;
    $('resNote').textContent = note;
    $('tiles').innerHTML = tiles.map(([k, v]) => `<div><b>${v}</b><span>${k}</span></div>`).join('');
    this.show('results');
  }

  setPauseTitle(t) { $('pauseTitle').textContent = t; }
}
