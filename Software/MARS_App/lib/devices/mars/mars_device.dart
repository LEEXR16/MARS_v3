/// The MARS robot over Bluetooth: parses its lines, keeps the latest state, sends commands.
/// The commands are the MARS GUI's (the MARS desktop GUI); every safety check is in the firmware,
/// which refuses what isn't allowed and says why in an I line.
library;

import 'dart:async';

import '../../core/line_device.dart';
import 'mars_protocol.dart';

class MarsDevice extends LineBleDevice {
  MarsDevice() : super('MARS');

  static const staleS = 1.0; // no D line for this long while connected -> stream stalled
  static const logLen = 80;

  MarsSample? latest;
  MarsHub? hub;
  List<double>? loads;
  final Map<String, double> params = {};
  final List<String> log = []; // newest last
  double lastD = -1e9, lastM = -1e9, lastL = -1e9;

  final _samples = StreamController<MarsSample>.broadcast();
  Stream<MarsSample> get samples => _samples.stream;

  bool get live => isConnected && hostTime() - lastD < staleS;
  bool get hubLive => isConnected && hostTime() - lastM < staleS;
  bool get loadsLive => isConnected && hostTime() - lastL < staleS;
  bool get homeSet => (params['zero_ok'] ?? 0) == 1 && (params['enc_zero_ok'] ?? 0) == 1;
  bool get motorOn => latest?.on ?? false;

  @override
  Future<void> onConnected() => send('GET');

  /// A requested disconnect leaves the motor holding (the firmware would also hold after 1 s).
  @override
  Future<void> onDisconnecting() async {
    if (motorOn) await send('HOLD');
  }

  @override
  void onLinkDown() {
    latest = null;
    hub = null;
    loads = null;
    notifyListeners();
  }

  @override
  void handleLine(String line) {
    if (line.length < 2 || line[1] != ',') {
      _log('?? $line');
      return;
    }
    final rest = line.substring(2);
    switch (line[0]) {
      case 'D':
        final s = parseD(rest, hostTime());
        if (s == null) {
          badLines++;
          return;
        }
        latest = s;
        lastD = s.t;
        _samples.add(s);
      case 'M':
        final h = parseM(rest);
        if (h != null) {
          hub = h;
          lastM = hostTime();
        }
      case 'L':
        final l = parseL(rest);
        if (l != null) {
          loads = l;
          lastL = hostTime();
        }
      case 'P':
        params.addAll(parseP(rest));
        notifyListeners();
      case 'I':
        _log(rest);
        if (rest.startsWith('FAULT')) {
          message(MsgLevel.error, rest);
        } else if (_isRefusal(rest)) {
          message(MsgLevel.warn, rest);
        }
      default:
        break; // C (CAN dump) and anything new
    }
  }

  static bool _isRefusal(String s) {
    final l = s.toLowerCase();
    return l.contains('refused') || l.contains(' needs ') || l.contains(' only ') || l.contains('not during') ||
        l.contains('unknown');
  }

  void _log(String s) {
    log.add(s);
    if (log.length > logLen) log.removeAt(0);
    notifyListeners();
  }

  // ---- Commands ----

  Future<void> command(String c) {
    _log('> $c');
    return send(c);
  }

  Future<void> enable() => command('EN');
  Future<void> disable() => command('DIS');
  Future<void> hold() => command('HOLD');
  Future<void> go(double deg) => command('GO ${deg.toStringAsFixed(1)}');
  Future<void> window() => command('WINDOW');
  Future<void> brake(bool engage) => command('BRAKE ${engage ? 1 : 0}');
  Future<void> solenoid(String name, bool on) => command('$name ${on ? 1 : 0}');
  Future<void> alpha(int percent) => command('ALPHA $percent');
  Future<void> calArm() => command('CAL ARM');
  Future<void> calLever() => command('CAL LEVER');
  Future<void> uncuff() => command('UNCUFF');
  Future<void> assist() => command('ASSIST');
  Future<void> clearFault() => command('CLEAR');
  Future<void> home() => command('HOME');
  Future<void> tare() => command('TARE');
  Future<void> setParam(String key, double v) => command('SET $key $v');

  /// Height: repeated while the button is held (the firmware stops after 400 ms without it).
  Future<void> height(int dir) => send(dir > 0 ? 'HEIGHT UP' : dir < 0 ? 'HEIGHT DOWN' : 'HEIGHT STOP');

  /// STOP: hold where the lever is now.
  void emergencyStop() {
    if (isConnected) hold();
  }

  @override
  void dispose() {
    _samples.close();
    super.dispose();
  }
}
