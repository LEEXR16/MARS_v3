/// Base class for a device reached over BLE with a newline-separated text protocol
/// (MARS: the same lines as the Teensy's USB port, see Firmware_SOLO_v2).
///
/// It handles scanning, connecting, disconnecting, the heartbeat and line framing.
/// A device class (devices/mars/mars_device.dart) adds what the lines mean and its commands:
///   onConnected()      runs right after the link is up (e.g. ask for the parameters)
///   onDisconnecting()  runs before a requested disconnect (e.g. HOLD)
///   handleLine()       called for every complete line
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ble.dart';

enum ConnState { disconnected, scanning, connecting, connected, error }

enum MsgLevel { info, warn, error }

class DeviceMessage {
  DeviceMessage(this.level, this.text);
  final MsgLevel level;
  final String text;
}

/// Seconds since the app started; the time base for samples, plots and recordings.
final Stopwatch _clock = Stopwatch()..start();
double hostTime() => _clock.elapsedMicroseconds / 1e6;

class LineBleDevice extends ChangeNotifier {
  LineBleDevice(this.name, {this.heartbeat = 'PING', this.heartbeatInterval = const Duration(milliseconds: 200)}) {
    _transport = BleTransport(onData: _onBytes, onDisconnected: _onLinkLost);
  }

  /// Sent every [heartbeatInterval]; the firmware holds the motor when it hears nothing for 1 s.
  final String heartbeat;
  final Duration heartbeatInterval;

  /// Addresses connected anywhere in the app, so the picker can mark them as in use.
  static final Set<String> inUse = {};

  final String name;
  ConnState state = ConnState.disconnected;
  String? address;
  String deviceName = '';
  int badLines = 0;

  late final BleTransport _transport;
  final List<int> _rx = [];
  Timer? _heartbeat;
  final _messages = StreamController<DeviceMessage>.broadcast();

  Stream<DeviceMessage> get messages => _messages.stream;
  bool get isConnected => state == ConnState.connected && (_transport.isConnected || debugFakeLink);

  /// Tests only: treat the device as connected without a BLE link (sends are dropped).
  @visibleForTesting
  bool debugFakeLink = false;

  void _setState(ConnState s) {
    state = s;
    notifyListeners();
  }

  void message(MsgLevel level, String text) => _messages.add(DeviceMessage(level, text));

  // ---- Scan / connect / disconnect ----

  Future<List<ScanHit>> scan() async {
    if (state == ConnState.connecting || state == ConnState.connected) return const [];
    _setState(ConnState.scanning);
    try {
      return await scanDevices();
    } finally {
      if (state == ConnState.scanning) _setState(ConnState.disconnected);
    }
  }

  Future<void> connectTo(ScanHit hit) async {
    if (state == ConnState.connecting || state == ConnState.connected) return;
    _setState(ConnState.connecting);
    try {
      await _transport.connect(hit.device);
    } catch (e) {
      message(MsgLevel.error, 'Could not connect to ${hit.name.isEmpty ? hit.address : hit.name}: ${_short(e)}');
      _setState(ConnState.error);
      return;
    }
    address = hit.address;
    deviceName = hit.name;
    inUse.add(hit.address);
    _rx.clear();
    _setState(ConnState.connected);
    message(MsgLevel.info, 'Connected to ${hit.name.isEmpty ? hit.address : hit.name}');
    // the heartbeat starts first: it is also what makes the firmware start streaming
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => send(heartbeat));
    try {
      await onConnected();
    } catch (e) {
      message(MsgLevel.error, 'Start-up commands failed: ${_short(e)}');
    }
  }

  Future<void> disconnect() async {
    try {
      await onDisconnecting();
    } catch (_) {}
    _heartbeat?.cancel();
    try {
      await _writeChain;
      await _transport.disconnect();
    } catch (_) {}
    _forgetLink();
    _setState(ConnState.disconnected);
    onLinkDown();
  }

  void _onLinkLost() {
    _heartbeat?.cancel();
    _forgetLink();
    _setState(ConnState.disconnected);
    message(MsgLevel.error, 'Connection to $name lost (the robot holds its position)');
    onLinkDown();
  }

  void _forgetLink() {
    if (address != null) inUse.remove(address);
  }

  // ---- Sending / receiving ----

  // Writes go out one at a time, in the order they were asked for.
  Future<void> _writeChain = Future.value();

  Future<void> send(String line) {
    final msg = utf8.encode('$line\n');
    return _writeChain = _writeChain.then((_) async {
      if (!_transport.isConnected) return;
      try {
        await _transport.write(msg);
      } catch (e) {
        message(MsgLevel.warn, 'Send failed: ${_short(e)}');
      }
    });
  }

  void _onBytes(List<int> data) => feed(data);

  /// Splits bytes into lines (also used by tests to inject data).
  @visibleForTesting
  void feed(List<int> data) {
    for (final b in data) {
      if (b == 10 || b == 13) {
        if (_rx.isNotEmpty) {
          final line = utf8.decode(_rx, allowMalformed: true).trim();
          _rx.clear();
          if (line.isNotEmpty) handleLine(line);
        }
      } else if (_rx.length < 2048) {
        _rx.add(b);
      } else {
        _rx.clear(); // runaway line: resync on the next newline
        badLines++;
      }
    }
  }

  // ---- Hooks for device classes ----

  @protected
  Future<void> onConnected() async {}

  @protected
  Future<void> onDisconnecting() async {}

  /// After any disconnect (requested or lost).
  @protected
  void onLinkDown() {}

  @protected
  void handleLine(String line) {}

  @override
  void dispose() {
    _heartbeat?.cancel();
    _messages.close();
    super.dispose();
  }
}

/// Scanning is a top-level function so tests can run without Bluetooth.
Future<List<ScanHit>> Function() scanDevices = scanBle;

String _short(Object e) {
  final s = e.toString();
  return s.length > 140 ? '${s.substring(0, 140)}…' : s;
}
