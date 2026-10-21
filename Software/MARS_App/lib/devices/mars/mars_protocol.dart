/// MARS text protocol (Firmware_SOLO_v2, same lines as USB; see the MARS desktop GUI's mars_gui.py).
///
/// Robot -> app:
///   D,ms,mode,fault,theta,vel,tau,cur,temp,err,alpha%,alphaSet%,tff,kp,ref,cal,th2,th3,th4,enc,fb   25 Hz on BLE
///   M,ms,relayMask,seq,height,1,service,motorFb,raw1,raw2,raw3,encMask                             10 Hz on BLE
///   L,ms,kg1,kg2,kg3,kg4                                                                           10 Hz on BLE
///   P,key=value,...   parameters (on connect, GET and after changes)
///   I,text            messages
/// App -> robot: one command per line (EN, DIS, HOLD, GO 90, WINDOW, BRAKE 0, ...), PING every 200 ms.
library;

import 'dart:math' as math;

/// Telemetry D-line fields, in firmware order.
const dFields = ['ms', 'mode', 'fault', 'theta', 'vel', 'tau', 'cur', 'temp', 'err', 'alpha', 'alpha_set', 'tff', 'kp',
  'ref', 'cal', 'th2', 'th3', 'th4', 'enc', 'fb'];

/// M-line fields.
const mFields = ['ms', 'relays', 'seq', 'height', 'slave', 'service', 'mfb', 'raw1', 'raw2', 'raw3', 'encm'];

// Relay bits of the M line (brake ON = released)
const rBrake = 0, rCfg = 1, rRight = 2, rLeft = 3, rHDown = 4, rHUp = 5;

const faultBits = {
  1: 'GUI LINK', 2: 'CAN LOST', 4: 'ANGLE', 8: 'TORQUE', 16: 'SPEED', 32: 'TEMP', 64: 'MOTOR ERR', 128: 'P RANGE',
  256: 'ENCODERS',
};

const seqNames = {1: 'ENABLING · WAIT MOTOR POWER', 2: 'ENABLING · HOLD', 3: 'DISABLING · BRAKE', 4: 'DISABLING'};

const jointNames = ['E1 shoulder', 'E2 elbow', 'E3 cuff'];

/// Load cells: LC1 front-left, LC2 front-right, LC3 back-left, LC4 back-right.
/// Half the cell spacing in mm (placeholders until measured, as mars_config.json loadcell).
const bHalfMm = 150.0, lHalfMm = 150.0, wMinKg = 1.0;

/// Kinematics (the MARS desktop GUI's kinematics.py), mm.
const j2X = 55.0, j2Z = 75.0, r1 = 480.0, r2 = 300.0;

/// One telemetry sample (D line). t = app time (s) when it arrived.
class MarsSample {
  MarsSample(this.t, this.v, this.mode);

  final double t;
  final Map<String, double> v;
  final String mode;

  double get theta => v['theta']!;
  double get ref => v['ref']!;
  double get tau => v['tau']!;
  double get tff => v['tff']!;
  double get vel => v['vel']!;
  int get fault => v['fault']!.toInt();
  int get enc => v['enc']!.toInt();
  int get cal => v['cal']!.toInt();
  bool get motorFb => v['fb']! != 0;
  bool get encLinked => enc & 8 != 0;
  bool encOk(int i) => enc & (1 << i) != 0;
  bool encWarn(int i) => (enc >> 4) & (1 << i) != 0;
  bool get allEncOk => enc & 15 == 15;
  List<double> get joints => [v['th2']!, v['th3']!, v['th4']!];
  bool get on => mode != 'OFF';
}

/// Hub state (M line).
class MarsHub {
  MarsHub(this.v);
  final Map<String, int> v;

  int get relays => v['relays']!;
  bool relay(int bit) => relays & (1 << bit) != 0;
  bool get brakeEngaged => !relay(rBrake);
  int get height => v['height']!;
  int get seq => v['seq']!;
  bool get service => v['service']! != 0;
  bool get motorPowered => v['mfb']! != 0;
  int raw(int i) => v['raw${i + 1}']!;
  bool encOk(int i) => v['encm']! & (1 << i) != 0;
}

MarsSample? parseD(String rest, double t) {
  final parts = rest.split(',');
  if (parts.length != dFields.length) return null;
  final v = <String, double>{};
  String mode = '';
  for (var i = 0; i < parts.length; i++) {
    if (dFields[i] == 'mode') {
      mode = parts[i];
      continue;
    }
    final x = double.tryParse(parts[i]);
    if (x == null) return null;
    v[dFields[i]] = x;
  }
  return MarsSample(t, v, mode);
}

MarsHub? parseM(String rest) {
  final parts = rest.split(',');
  if (parts.length != mFields.length) return null;
  final v = <String, int>{};
  for (var i = 0; i < parts.length; i++) {
    final x = int.tryParse(parts[i]);
    if (x == null) return null;
    v[mFields[i]] = x;
  }
  return MarsHub(v);
}

/// L line -> kg of the 4 cells.
List<double>? parseL(String rest) {
  final parts = rest.split(',');
  if (parts.length != 5) return null;
  final kg = [for (final p in parts.skip(1)) double.tryParse(p)];
  if (kg.any((k) => k == null)) return null;
  return [for (final k in kg) k!];
}

/// P line -> key/value pairs (numbers; NaN for non-numbers).
Map<String, double> parseP(String rest) {
  final out = <String, double>{};
  for (final kv in rest.split(',')) {
    final i = kv.indexOf('=');
    if (i <= 0) continue;
    out[kv.substring(0, i)] = double.tryParse(kv.substring(i + 1)) ?? double.nan;
  }
  return out;
}

/// Cuff position in the world frame (mm), as fk() in the desktop GUI's kinematics.py:
/// z = motor axis, x = down in the start pose; theta1 turns the robot plane about z.
List<double> cuffMm(double t1Deg, double t2Deg, double t3Deg) {
  double r(double d) => d * math.pi / 180;
  final a2 = r(t2Deg), a23 = r(t2Deg + t3Deg);
  final xp = j2X + r1 * math.cos(a2) + r2 * math.cos(a23); // in-plane "down"
  final zp = j2Z + r1 * math.sin(a2) + r2 * math.sin(a23); // along the motor axis
  final t1 = r(t1Deg);
  return [xp * math.cos(t1), xp * math.sin(t1), zp];
}

/// What the game reads: the same JSON the desktop GUI sends it over UDP, plus a sequence number.
Map<String, Object> gameInput(MarsSample s, int seq) {
  final j = s.joints;
  final c = cuffMm(s.theta, j[0], j[1]);
  double r1d(double v) => (v * 10).roundToDouble() / 10;
  return {
    'seq': seq,
    't': s.v['ms']! / 1000,
    'th1': s.theta,
    'th2': j[0],
    'th3': j[1],
    'th4': j[2],
    'cuff_mm': [r1d(c[0]), r1d(c[1]), r1d(c[2])],
    'mode': s.mode,
    'enc_ok': s.allEncOk,
  };
}

/// Weight (kg) and COP (mm, x + right towards LC2/LC4, y + front towards LC1/LC2), as LC_Weight_COP.
(double, double, double) weightCop(List<double> f) {
  final w = f[0] + f[1] + f[2] + f[3];
  if (w <= wMinKg) return (w, 0, 0);
  final x = ((f[1] + f[3]) - (f[0] + f[2])) / w * bHalfMm;
  final y = ((f[0] + f[1]) - (f[2] + f[3])) / w * lHalfMm;
  return (w, x, y);
}

String faultText(int fault, int err) {
  final names = [for (final e in faultBits.entries) if (fault & e.key != 0) e.value];
  if (err != 0) names.add('MOTOR CODE $err');
  return names.join(' · ');
}
