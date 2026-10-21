/// MARS tablet app: a welcome screen, then the MARS tab (the machine interface over Bluetooth).
/// The Android counterpart of the desktop GUI (the MARS desktop GUI), built like the DYNABO app.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/line_device.dart';
import 'core/updater.dart';
import 'ui/device_tab.dart';
import 'ui/game_screen.dart';
import 'ui/tabs/mars_tab.dart';
import 'ui/theme.dart' as th;
import 'ui/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  // Default logging prints every notification (25 per second)
  FlutterBluePlus.setLogLevel(LogLevel.warning, color: false);
  runApp(MarsApp(controllers: [MarsController()]));
}

class MarsApp extends StatelessWidget {
  const MarsApp({super.key, required this.controllers});
  final List<DeviceController> controllers;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MARS',
      debugShowCheckedModeBanner: false,
      theme: th.buildTheme(),
      home: Shell(controllers: controllers),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.controllers});
  final List<DeviceController> controllers;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int? _index; // null = welcome screen
  late final List<Widget> _tabs = [for (final c in widget.controllers) c.buildTab()];
  final List<StreamSubscription<DeviceMessage>> _subs = [];
  late final Timer _timer;
  bool _wakelock = false;
  bool _stoppedInBackground = false;
  String _version = '';

  List<DeviceController> get _ctls => widget.controllers;
  bool get _anyConnected => _ctls.any((c) => c.isConnected);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    appVersionText().then((v) {
      if (mounted) setState(() => _version = v);
    }).catchError((_) {}); // no version info in tests
    for (final c in _ctls) {
      _subs.add(c.messages.listen(_showMessage));
    }
    // Tab dots and the screen wakelock at 2 Hz
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final any = _anyConnected;
      if (any != _wakelock) {
        _wakelock = any;
        WakelockPlus.toggle(enable: any).ignore(); // screen stays on while the robot is connected
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app hides the HOLD button, so the robot holds when the app goes to the background.
    // (If the app is killed, the heartbeat stops and the firmware holds after 1 s.)
    if (state == AppLifecycleState.paused && _anyConnected) {
      _holdAll(silent: true);
      _stoppedInBackground = true;
    } else if (state == AppLifecycleState.resumed && _stoppedInBackground) {
      _stoppedInBackground = false;
      _showMessage(DeviceMessage(MsgLevel.warn, 'The robot was put on HOLD while the app was in the background'));
    } else if (state == AppLifecycleState.detached) {
      for (final c in _ctls) {
        c.shutdown();
      }
    }
  }

  void _holdAll({bool silent = false}) {
    for (final c in _ctls) {
      c.emergencyStop();
    }
    if (!silent) _showMessage(DeviceMessage(MsgLevel.warn, 'HOLD sent: the robot holds where it is'));
  }

  /// A keyboard's Esc holds the robot, as on the desktop.
  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) _holdAll();
    return false;
  }

  void _showMessage(DeviceMessage m) {
    if (!mounted) return;
    final color = switch (m.level) {
      MsgLevel.info => th.accent,
      MsgLevel.warn => th.warn,
      MsgLevel.error => th.err,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        width: 560,
        duration: Duration(seconds: m.level == MsgLevel.info ? 2 : 4),
        content: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(m.text)),
        ]),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return PopScope(
      // Back on a device tab goes to the welcome screen; on the welcome screen it leaves the app
      canPop: index == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = null);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            if (index != null) ...[
              _topBar(index),
              const Divider(height: 1, thickness: 1, color: th.border),
            ],
            // the tabs stay alive behind the welcome screen, so their state and plots carry on
            Expanded(child: IndexedStack(index: index == null ? 0 : index + 1, children: [_welcome(), ..._tabs])),
          ]),
        ),
      ),
    );
  }

  Widget _logo(double size) => Text(
        'MARS',
        style: TextStyle(
          fontFamily: th.titleFont,
          fontSize: size,
          fontWeight: FontWeight.w300,
          letterSpacing: size * 0.45,
          color: th.text,
        ),
      );

  Widget _holdAllButton() => SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            foregroundColor: th.err,
            backgroundColor: th.errStrong.withValues(alpha: 0.12),
            side: const BorderSide(color: th.errStrong),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          onPressed: _anyConnected ? _holdAll : null,
          icon: const Icon(Icons.pan_tool, size: 18),
          label: const Text('HOLD ALL'),
        ),
      );

  // ---- Welcome screen ----

  Widget _welcome() {
    return Stack(children: [
      const Positioned.fill(child: CustomPaint(painter: _MarsHorizon())),
      Row(children: [
        const Spacer(flex: 9),
        Expanded(
          flex: 11,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 56, 24, 48),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _logo(64),
                const SizedBox(height: 4),
                const Text('MOTORISED ARM-SUPPORT ROBOT  ·  v3.1',
                    style: TextStyle(color: th.textMuted, fontSize: 13, letterSpacing: 3, fontFamily: th.titleFont)),
                const SizedBox(height: 34),
                Wrap(spacing: 16, runSpacing: 16, alignment: WrapAlignment.center, children: [
                  for (var i = 0; i < _ctls.length; i++) _deviceCard(i),
                  for (final c in _ctls.whereType<MarsController>()) _gameCard(c),
                ]),
              ]),
            ),
          ),
        ),
      ]),
      // a robot left connected can still be stopped from here
      Positioned(top: 6, right: 12, child: _holdAllButton()),
      Positioned(
        left: 0,
        right: 0,
        bottom: 8,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_version.isNotEmpty) Text('Version $_version', style: th.faint),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: () => showUpdateDialog(context, anyConnected: () => _anyConnected),
            icon: const Icon(Icons.system_update_rounded, size: 16),
            label: const Text('Check for updates'),
          ),
        ]),
      ),
    ]);
  }

  Widget _deviceCard(int i) {
    final c = _ctls[i];
    final (status, color) = c.isConnected ? ('Connected', c.statusColor) : ('Not connected', th.idle);
    return SizedBox(
      width: 300,
      height: 216,
      child: Material(
        color: th.card.withValues(alpha: 0.92),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.isConnected ? th.accent.withValues(alpha: 0.7) : th.borderHi),
        ),
        child: InkWell(
          onTap: () => setState(() => _index = i),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('MACHINE',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300, letterSpacing: 7, fontFamily: th.titleFont)),
              const Text('INTERFACE',
                  style: TextStyle(fontSize: 14, letterSpacing: 6, color: th.accent, fontFamily: th.titleFont)),
              const SizedBox(height: 8),
              Text(c.description, style: th.muted),
              const Spacer(),
              Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(status, style: const TextStyle(color: th.textMuted, fontSize: 12)),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: th.textMuted),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  /// VOID WING, steered by the arm in the robot (or by touch without it).
  Widget _gameCard(MarsController c) {
    return SizedBox(
      width: 300,
      height: 216,
      child: Material(
        color: th.card.withValues(alpha: 0.92),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: th.borderHi),
        ),
        child: InkWell(
          onTap: () => openGame(context, c),
          child: const Padding(
            padding: EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('VOID WING',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300, letterSpacing: 7, fontFamily: th.titleFont)),
              ),
              Text('GAME', style: TextStyle(fontSize: 14, letterSpacing: 6, color: th.gold, fontFamily: th.titleFont)),
              SizedBox(height: 8),
              Text('Fly the Ranger with your arm', style: th.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
              Spacer(),
              Row(children: [
                Icon(Icons.sports_esports_rounded, size: 16, color: th.textMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Connect the robot first to steer with the arm',
                      style: TextStyle(color: th.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- Inside a device: tab bar ----

  Widget _topBar(int index) {
    return Container(
      height: 52,
      color: th.bg,
      padding: const EdgeInsets.only(left: 6, right: 12),
      child: Row(children: [
        IconButton(
          tooltip: 'Home',
          onPressed: () => setState(() => _index = null),
          icon: const Icon(Icons.home_rounded, color: th.textMuted),
        ),
        const SizedBox(width: 4),
        _logo(20),
        const SizedBox(width: 22),
        for (var i = 0; i < _ctls.length; i++) _tabButton(i, i == index),
        const Spacer(),
        _holdAllButton(),
      ]),
    );
  }

  Widget _tabButton(int i, bool selected) {
    final c = _ctls[i];
    return InkWell(
      onTap: () => setState(() => _index = i),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? th.accent : Colors.transparent, width: 2)),
        ),
        child: Row(children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: c.statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 9),
          Text(
            c.name,
            style: TextStyle(
              color: selected ? th.text : th.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ]),
      ),
    );
  }
}

/// The welcome screen's backdrop: dark sky, a few stars and the rim of Mars, as the GUI's home screen.
class _MarsHorizon extends CustomPainter {
  const _MarsHorizon();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = th.bg);
    final rnd = math.Random(7);
    for (var i = 0; i < 140; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height * 0.8);
      canvas.drawCircle(p, rnd.nextDouble() * 1.1 + 0.3,
          Paint()..color = th.text.withValues(alpha: rnd.nextDouble() * 0.5 + 0.1));
    }
    // the planet: a large disc whose rim crosses the lower left
    final r = size.height * 1.15;
    final c = Offset(size.width * 0.18, size.height + r * 0.55);
    canvas.drawCircle(
        c,
        r * 1.04,
        Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFFF2A254).withValues(alpha: 0.28),
            const Color(0xFFF2A254).withValues(alpha: 0.0),
          ], stops: const [0.93, 1.0])
              .createShader(Rect.fromCircle(center: c, radius: r * 1.04)));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.3, -0.75),
            radius: 0.9,
            colors: const [Color(0xFFC86A35), Color(0xFF7A3418), Color(0xFF2A1208)],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)));
  }

  @override
  bool shouldRepaint(_MarsHorizon old) => false;
}
