/// MARS data on the app side: history for the plots, stream rate, COP trail, recording.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../../core/line_device.dart';
import '../../core/recorder.dart';
import 'mars_device.dart';
import 'mars_protocol.dart';

const historyS = 30; // seconds kept for the plots
const maxSamples = historyS * 60; // D is 25 Hz on Bluetooth; headroom
const copTrailLen = 60;

const seriesKeys = ['theta', 'ref', 'tau', 'tff', 'th2', 'th3', 'th4'];

/// Fixed-size ring of doubles, oldest first.
class Ring {
  Ring(int capacity) : _d = Float64List(capacity);
  final Float64List _d;
  int _start = 0;
  int length = 0;

  void add(double v) {
    if (length < _d.length) {
      _d[(_start + length) % _d.length] = v;
      length++;
    } else {
      _d[_start] = v;
      _start = (_start + 1) % _d.length;
    }
  }

  double operator [](int i) => _d[(_start + i) % _d.length];
  double get last => this[length - 1];

  void clear() {
    _start = 0;
    length = 0;
  }
}

class MarsModel {
  MarsModel(this.device) {
    _sub = device.samples.listen(_onSample);
  }

  final MarsDevice device;
  late final StreamSubscription<MarsSample> _sub;
  CsvRecorder? recorder;

  final Ring t = Ring(maxSamples);
  final Map<String, Ring> series = {for (final k in seriesKeys) k: Ring(maxSamples)};
  final ListQueue<Offset> copTrail = ListQueue<Offset>();

  double rate = 0;
  int _rateCount = 0;
  double _rateT0 = hostTime();

  void reset() {
    t.clear();
    for (final r in series.values) {
      r.clear();
    }
    copTrail.clear();
    rate = 0;
    _rateCount = 0;
    _rateT0 = hostTime();
  }

  void _onSample(MarsSample s) {
    _rateCount++;
    if (s.t - _rateT0 >= 1.0) {
      rate = _rateCount / (s.t - _rateT0);
      _rateCount = 0;
      _rateT0 = s.t;
    }
    t.add(s.t);
    series['theta']!.add(s.theta);
    series['ref']!.add(s.on ? s.ref : double.nan);
    series['tau']!.add(s.tau);
    series['tff']!.add(s.on ? s.tff : double.nan);
    final j = s.joints;
    for (var i = 0; i < 3; i++) {
      series['th${i + 2}']!.add(s.encOk(i) ? j[i] : double.nan);
    }
    final l = device.loads;
    if (l != null && device.loadsLive) {
      final (w, x, y) = weightCop(l);
      if (w > wMinKg) {
        copTrail.add(Offset(x, y));
        while (copTrail.length > copTrailLen) {
          copTrail.removeFirst();
        }
      } else {
        copTrail.clear();
      }
    }
    recorder?.write([
      s.t.toStringAsFixed(3),
      for (final k in dFields) k == 'mode' ? s.mode : s.v[k],
      ...?l,
    ]);
  }

  /// Index of the first sample at or after [since] (binary search).
  int firstIndexAfter(double since) {
    var lo = 0, hi = t.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (t[mid] < since) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  // ---- Recording ----

  bool get recording => recorder != null;

  Future<void> startRecording() async {
    if (recorder != null) return;
    recorder = await CsvRecorder.start('session', ['app_time', ...dFields, 'kg1', 'kg2', 'kg3', 'kg4'], tag: 'MARS');
  }

  Future<void> stopRecording() async {
    final r = recorder;
    recorder = null;
    await r?.close();
  }

  void dispose() {
    _sub.cancel();
    recorder?.close();
  }
}

double? lastFinite(Ring r) {
  for (var i = r.length - 1; i >= math.max(0, r.length - 5); i--) {
    if (r[i].isFinite) return r[i];
  }
  return null;
}
