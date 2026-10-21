/// BLE scan and transport for the FSC-BT986 module in transparent ("throughput") mode (same module as DYNABO).
///
/// The module passes bytes straight through: its UART (the Teensy's Serial5) <-> BLE.
///   Service FFF0, notify FFF1 (module -> tablet), write FFF2 (tablet -> module)
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final serviceUuid = Guid('fff0');
final notifyCharUuid = Guid('fff1');
final writeCharUuid = Guid('fff2');

class ScanHit {
  ScanHit(this.name, this.address, this.rssi, this.hasService, this.device);

  final String name;
  final String address;
  final int? rssi;
  final bool hasService; // advertises the FFF0 transparent-UART service
  final BluetoothDevice device;
}

/// Waits for the adapter to report its state and asks Android to switch it on if it's off.
Future<void> ensureBluetoothOn() async {
  if (!await FlutterBluePlus.isSupported) {
    throw StateError('This tablet has no Bluetooth LE');
  }
  var state = await FlutterBluePlus.adapterState
      .where((s) => s != BluetoothAdapterState.unknown)
      .first
      .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
  if (state == BluetoothAdapterState.on) return;
  try {
    await FlutterBluePlus.turnOn(timeout: 15);
  } catch (_) {
    throw StateError('Bluetooth is off. Switch it on and scan again.');
  }
}

/// All nearby BLE devices, FFF0 devices first, then by signal strength.
Future<List<ScanHit>> scanBle({Duration timeout = const Duration(seconds: 5)}) async {
  await ensureBluetoothOn();
  if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
  final hits = <String, ScanHit>{};
  final sub = FlutterBluePlus.onScanResults.listen((results) {
    for (final r in results) {
      final adv = r.advertisementData;
      final id = r.device.remoteId.str;
      hits[id] = ScanHit(
        adv.advName.isNotEmpty ? adv.advName : r.device.platformName,
        id,
        r.rssi,
        adv.serviceUuids.contains(serviceUuid),
        r.device,
      );
    }
  });
  try {
    await FlutterBluePlus.startScan(timeout: timeout);
    await FlutterBluePlus.isScanning.where((s) => !s).first;
  } finally {
    await sub.cancel();
  }
  final list = hits.values.toList()
    ..sort((a, b) {
      if (a.hasService != b.hasService) return a.hasService ? -1 : 1;
      return (b.rssi ?? -999).compareTo(a.rssi ?? -999);
    });
  return list;
}

/// One BLE connection.
class BleTransport {
  BleTransport({required this.onData, required this.onDisconnected});

  final void Function(List<int> data) onData;
  final void Function() onDisconnected;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _tx;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _connected = false;
  bool _closing = false;

  bool get isConnected => _connected;

  Future<void> connect(BluetoothDevice device) async {
    _closing = false;
    await device.connect(timeout: const Duration(seconds: 15)); // also asks for MTU 512
    _device = device;
    try {
      final services = await device.discoverServices();
      final svc = services.where((s) => s.uuid == serviceUuid).firstOrNull;
      final rx = svc?.characteristics.where((c) => c.uuid == notifyCharUuid).firstOrNull;
      final tx = svc?.characteristics.where((c) => c.uuid == writeCharUuid).firstOrNull;
      if (rx == null || tx == null) {
        throw StateError('Not a MARS module: no FFF0/FFF1/FFF2 service');
      }
      _tx = tx;
      _dataSub = rx.onValueReceived.listen(onData);
      device.cancelWhenDisconnected(_dataSub!);
      await rx.setNotifyValue(true);
    } catch (_) {
      await device.disconnect();
      _device = null;
      rethrow;
    }
    _connected = true;
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && _connected) {
        _connected = false;
        _connSub?.cancel();
        if (!_closing) onDisconnected(); // only report links that dropped, not our own disconnect
      }
    });
  }

  Future<void> disconnect() async {
    _closing = true;
    _connected = false;
    await _connSub?.cancel();
    await _dataSub?.cancel();
    _connSub = null;
    _dataSub = null;
    try {
      await _device?.disconnect();
    } finally {
      _device = null;
      _tx = null;
    }
  }

  Future<void> write(List<int> data) async {
    final tx = _tx;
    if (!_connected || tx == null) return;
    await tx.write(data, withoutResponse: tx.properties.writeWithoutResponse);
  }
}
