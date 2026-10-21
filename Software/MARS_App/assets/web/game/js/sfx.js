// Sound, synthesised with WebAudio (no audio files): lasers, explosions, lock tones, shield hits,
// alarm and the engine hum. Audio starts on the first tap (browsers require a user gesture).
export class Sfx {
  constructor(listenerPos) {
    this.listenerPos = listenerPos; // () => THREE.Vector3
    this.ctx = null;
    this.master = null;
    this.noise = null;
    this.engine = null;
    this.last = {};
  }

  unlock() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = new AC();
    this.ctx = ctx;
    this.master = ctx.createGain();
    this.master.gain.value = 0.55;
    const comp = ctx.createDynamicsCompressor();
    this.master.connect(comp);
    comp.connect(ctx.destination);
    const len = ctx.sampleRate * 2;
    this.noise = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    // engine: filtered noise + a low hum
    const src = ctx.createBufferSource();
    src.buffer = this.noise;
    src.loop = true;
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 300;
    const hum = ctx.createOscillator();
    hum.type = 'sawtooth';
    hum.frequency.value = 48;
    const humF = ctx.createBiquadFilter();
    humF.type = 'lowpass';
    humF.frequency.value = 160;
    const g = ctx.createGain();
    g.gain.value = 0;
    src.connect(f); f.connect(g);
    hum.connect(humF); humF.connect(g);
    g.connect(this.master);
    src.start(); hum.start();
    this.engine = { g, f, hum };
  }

  setEngine(on, speed01, boosting) {
    if (!this.engine) return;
    const t = this.ctx.currentTime;
    this.engine.g.gain.setTargetAtTime(on ? 0.08 + 0.06 * speed01 + (boosting ? 0.05 : 0) : 0, t, 0.2);
    this.engine.f.frequency.setTargetAtTime(220 + 500 * speed01 + (boosting ? 400 : 0), t, 0.2);
    this.engine.hum.frequency.setTargetAtTime(42 + 30 * speed01, t, 0.3);
  }

  _env(gain, t, a, d) {
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(1, t + a);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + a + d);
  }

  _tone(type, f0, f1, dur, vol, at = 0) {
    const c = this.ctx, t = c.currentTime + at;
    const o = c.createOscillator(), g = c.createGain(), v = c.createGain();
    o.type = type;
    o.frequency.setValueAtTime(f0, t);
    o.frequency.exponentialRampToValueAtTime(Math.max(f1, 1), t + dur);
    v.gain.value = vol;
    this._env(g, t, 0.004, dur);
    o.connect(g); g.connect(v); v.connect(this.master);
    o.start(t); o.stop(t + dur + 0.05);
  }

  _noise(dur, vol, fType, f0, f1, q = 1) {
    const c = this.ctx, t = c.currentTime;
    const s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain(), v = c.createGain();
    s.buffer = this.noise;
    f.type = fType;
    f.Q.value = q;
    f.frequency.setValueAtTime(f0, t);
    f.frequency.exponentialRampToValueAtTime(Math.max(f1, 1), t + dur);
    v.gain.value = vol;
    this._env(g, t, 0.005, dur);
    s.connect(f); f.connect(g); g.connect(v); v.connect(this.master);
    s.start(t, Math.random()); s.stop(t + dur + 0.05);
  }

  play(name, vol = 1) {
    if (!this.ctx || vol < 0.02) return;
    // the same sound at most every 30 ms (bursts of hits would just get louder)
    const now = this.ctx.currentTime;
    if (this.last[name] && now - this.last[name] < 0.03) return;
    this.last[name] = now;
    switch (name) {
      case 'laser': this._tone('square', 1500, 260, 0.09, 0.05 * vol); this._noise(0.05, 0.03 * vol, 'highpass', 4000, 2000); break;
      case 'elaser': this._tone('sawtooth', 900, 180, 0.12, 0.05 * vol); break;
      case 'missile': this._noise(0.6, 0.18 * vol, 'bandpass', 900, 3000, 0.8); break;
      case 'boom': this._noise(0.9, 0.5 * vol, 'lowpass', 1400, 60); this._tone('sine', 90, 30, 0.6, 0.35 * vol); break;
      case 'bigboom': this._noise(2.2, 0.8 * vol, 'lowpass', 900, 30); this._tone('sine', 60, 22, 1.8, 0.6 * vol); break;
      case 'hit': this._noise(0.25, 0.35 * vol, 'lowpass', 2500, 200); this._tone('square', 120, 60, 0.2, 0.12 * vol); break;
      case 'shield': this._tone('sine', 700, 1400, 0.18, 0.12 * vol); this._noise(0.15, 0.08 * vol, 'bandpass', 3000, 6000, 3); break;
      case 'beep': this._tone('sine', 1320, 1320, 0.05, 0.05 * vol); break;
      case 'locked': this._tone('square', 1760, 1760, 0.08, 0.06 * vol); this._tone('square', 2200, 2200, 0.12, 0.06 * vol, 0.09); break;
      case 'alarm': for (let i = 0; i < 3; i++) this._tone('sawtooth', 660, 440, 0.32, 0.08 * vol, i * 0.4); break;
      case 'click': this._tone('sine', 900, 600, 0.04, 0.06 * vol); break;
    }
  }

  /// quieter with distance from the player
  playAt(name, pos) {
    const d = pos.distanceTo(this.listenerPos());
    this.play(name, Math.min(1, 140 / Math.max(d, 1)));
  }
}
