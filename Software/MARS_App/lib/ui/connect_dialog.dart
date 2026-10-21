/// Scan for BLE devices and pick one for a tab.
///
/// Only devices with the FSC-BT986 service (FFF0) or a name the tab expects are listed, unless
/// "Show all devices" is ticked. Devices already connected in another tab are marked and can't be picked.
library;

import 'package:flutter/material.dart';

import '../core/ble.dart';
import '../core/line_device.dart';
import 'theme.dart' as th;
import 'widgets.dart';

Future<void> showConnectDialog(BuildContext context, LineBleDevice device, List<String> expectedNames) {
  return showDialog<void>(
    context: context,
    builder: (_) => ConnectDialog(device: device, expectedNames: expectedNames),
  );
}

String _bars(int? rssi) {
  if (rssi == null) return '';
  final n = rssi > -60 ? 4 : rssi > -70 ? 3 : rssi > -80 ? 2 : 1;
  return '${'▂▄▆█'.substring(0, n)}${'▁' * (4 - n)}  $rssi dBm';
}

class ConnectDialog extends StatefulWidget {
  const ConnectDialog({super.key, required this.device, required this.expectedNames});

  final LineBleDevice device;
  final List<String> expectedNames;

  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  List<ScanHit> _results = const [];
  bool _scanning = false;
  bool _showAll = false;
  String? _error;
  String? _selected;

  late final List<String> _expected = widget.expectedNames.map((n) => n.toLowerCase()).toList();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _results = const [];
      _selected = null;
    });
    List<ScanHit> results = const [];
    String? error;
    try {
      results = await widget.device.scan();
    } catch (e) {
      error = 'Scan failed: ${e.toString().replaceFirst('Bad state: ', '')}';
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _results = results;
      _error = error;
      final shown = _shown();
      final first = shown.where((r) => !LineBleDevice.inUse.contains(r.address)).firstOrNull;
      _selected = first?.address;
    });
  }

  bool _matches(ScanHit r) {
    final name = r.name.toLowerCase();
    return r.hasService || _expected.any((e) => name.startsWith(e));
  }

  List<ScanHit> _shown() => [for (final r in _results) if (_showAll || _matches(r)) r];

  void _connect(ScanHit r) {
    Navigator.pop(context);
    widget.device.connectTo(r);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown();
    final hidden = _results.length - shown.length;
    final selected = shown.where((r) => r.address == _selected).firstOrNull;

    Widget listArea;
    if (_scanning) {
      listArea = const Center(child: Text('Scanning…', style: th.muted));
    } else if (_error != null) {
      listArea = Center(child: Text(_error!, style: const TextStyle(color: th.err), textAlign: TextAlign.center));
    } else if (shown.isEmpty) {
      listArea = Center(
        child: Text(
          'No MARS module found. Is the robot powered and in range?'
          '${hidden > 0 ? '\n$hidden other device(s) hidden: tick "Show all devices".' : ''}',
          style: th.muted,
          textAlign: TextAlign.center,
        ),
      );
    } else {
      listArea = ListView.separated(
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, i) {
          final r = shown[i];
          final inUse = LineBleDevice.inUse.contains(r.address);
          final isSel = r.address == _selected;
          return Material(
            color: isSel ? th.accent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: inUse ? null : () => setState(() => _selected = r.address),
              onDoubleTap: inUse ? null : () => _connect(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    r.name.isEmpty ? 'Unknown' : r.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: inUse ? th.textFaint : th.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${r.address}    ${_bars(r.rssi)}${inUse ? '    (connected in another tab)' : ''}',
                    style: th.faint.copyWith(fontSize: 12, fontFamily: th.mono),
                  ),
                ]),
              ),
            ),
          );
        },
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Connect ${widget.device.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Nearby MARS modules (FSC-BT986). Tap one, then Connect.', style: th.muted),
            const SizedBox(height: 10),
            SizedBox(height: 3, child: _scanning ? const LinearProgressIndicator() : null),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: th.bg,
                  border: Border.all(color: th.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: listArea,
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Checkbox(value: _showAll, onChanged: (v) => setState(() => _showAll = v ?? false)),
              GestureDetector(
                onTap: () => setState(() => _showAll = !_showAll),
                child: const Text('Show all devices', style: th.muted),
              ),
              const Spacer(),
              OutlinedButton(onPressed: _scanning ? null : _scan, child: const Text('Rescan')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: selected == null ? null : () => _connect(selected),
                child: const Text('Connect'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Header of a device tab: name, subtitle, status pills, connection pill and Connect button.
class DeviceHeader extends StatelessWidget {
  const DeviceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.device,
    this.expectedNames = const [],
    this.pills = const [],
    this.extra,
  });

  final String title;
  final String subtitle;
  final LineBleDevice? device;
  final List<String> expectedNames;
  final List<Widget> pills;
  final Widget? extra;

  static const _connText = {
    ConnState.disconnected: ('Disconnected', th.Level.idle),
    ConnState.scanning: ('Scanning…', th.Level.info),
    ConnState.connecting: ('Connecting…', th.Level.warn),
    ConnState.connected: ('Connected', th.Level.ok),
    ConnState.error: ('Connection failed', th.Level.error),
  };

  @override
  Widget build(BuildContext context) {
    final d = device;
    Widget? conn;
    if (d != null) {
      var (text, level) = _connText[d.state]!;
      if (d.state == ConnState.connected && d.deviceName.isNotEmpty) text = 'Connected · ${d.deviceName}';
      final connected = d.state == ConnState.connected;
      final busy = d.state == ConnState.scanning || d.state == ConnState.connecting;
      void onPressed() => connected ? d.disconnect() : showConnectDialog(context, d, expectedNames);
      conn = Row(mainAxisSize: MainAxisSize.min, children: [
        StatusPill(text, level),
        const SizedBox(width: 12),
        SizedBox(
          width: 136,
          child: connected
              ? OutlinedButton(onPressed: onPressed, child: const Text('Disconnect'))
              : FilledButton(onPressed: busy ? null : onPressed, child: const Text('Connect')),
        ),
      ]);
    }
    return Container(
      color: th.panel,
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Row(children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: th.muted.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final p in pills) ...[p, const SizedBox(width: 8)],
            ]),
          ),
        ),
        if (extra != null) ...[extra!, const SizedBox(width: 12)],
        ?conn,
      ]),
    );
  }
}
