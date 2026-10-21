/// MARS interface: the tablet version of the MARS GUI's machine interface (the MARS desktop GUI).
///
///   header  connection, stream rate, mode, faults, brake, home
///   left    readouts: motor theta1, encoders, solenoids and power, load cells (kg, COP)
///   centre  the robot (3D CAD model, or the lever dial + arm plane), theta1 and torque plots
///   right   HOLD, then CONTROL / ASSIST / SETUP, and the robot's messages
///
/// Same rules as the desktop GUI: the firmware does every safety check and refuses what isn't
/// allowed (the reply shows as a message); the app only greys out what can't work right now.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/line_device.dart';
import '../../core/recorder.dart';
import '../../devices/mars/mars_device.dart';
import '../../devices/mars/mars_model.dart';
import '../../devices/mars/mars_protocol.dart';
import '../connect_dialog.dart';
import '../device_tab.dart';
import '../game_screen.dart';
import '../plots.dart';
import '../robot_view.dart';
import '../theme.dart' as th;
import '../web_page.dart';
import '../widgets.dart';

const _plotHz = 20; // plot repaint rate
const _valuesEvery = 2; // readouts rebuild every 2nd plot tick (10 Hz)
const expectedNames = ['MARS', 'FSC', 'BT986'];

class MarsController implements DeviceController {
  MarsController() {
    model = MarsModel(device);
  }

  final MarsDevice device = MarsDevice();
  late final MarsModel model;

  @override
  String get name => 'MARS';
  @override
  String get description => 'Arm-support robot · v3.1';
  @override
  bool get isConnected => device.isConnected;
  @override
  Stream<DeviceMessage> get messages => device.messages;

  @override
  Color get statusColor {
    final st = device.state;
    if (st == ConnState.error) return th.err;
    if (st != ConnState.connected) {
      return st == ConnState.connecting || st == ConnState.scanning ? th.warn : th.idle;
    }
    final s = device.latest;
    if (!device.live || (s != null && s.fault != 0)) return th.warn;
    return th.ok;
  }

  @override
  void emergencyStop() => device.emergencyStop();

  @override
  Future<void> shutdown() async {
    await model.stopRecording();
    if (device.isConnected) await device.disconnect(); // HOLD first
  }

  @override
  Widget buildTab() => MarsTab(ctl: this);
}

class MarsTab extends StatefulWidget {
  const MarsTab({super.key, required this.ctl});
  final MarsController ctl;

  @override
  State<MarsTab> createState() => _MarsTabState();
}

enum _Page { control, assist, setup }

class _MarsTabState extends State<MarsTab> {
  MarsDevice get device => widget.ctl.device;
  MarsModel get model => widget.ctl.model;

  final _plotTick = ValueNotifier<int>(0);
  late final Timer _timer;
  int _tick = 0;
  ConnState _lastState = ConnState.disconnected;

  _Page _page = _Page.control;
  bool _show3d = true; // the CAD model (assets/web/robot3d), else the 2D dial + arm plane
  late final LocalWebPage _robot3d = LocalWebPage(path: 'robot3d/index.html', channel: 'MarsView');
  double _goDeg = 90;
  double _alpha = 100;
  double _kpCenter = 5;
  bool _recBusy = false;
  String? _recFolder;
  final _cmdCtl = TextEditingController();
  final Map<String, Timer> _debounce = {};

  /// Sliders send only the value the finger stops at (200 ms quiet), not every step over BLE.
  void _later(String key, VoidCallback f) {
    _debounce[key]?.cancel();
    _debounce[key] = Timer(const Duration(milliseconds: 200), f);
  }

  @override
  void initState() {
    super.initState();
    _lastState = device.state;
    device.addListener(_onDevice);
    _timer = Timer.periodic(const Duration(milliseconds: 1000 ~/ _plotHz), (_) {
      _plotTick.value++;
      if (++_tick % _valuesEvery == 0 && mounted) {
        setState(() {});
        if (_show3d) _feed3d();
      }
    });
    recordingsFolder('session').then((d) {
      if (mounted) setState(() => _recFolder = d.path);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _timer.cancel();
    device.removeListener(_onDevice);
    _plotTick.dispose();
    _cmdCtl.dispose();
    for (final t in _debounce.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _onDevice() {
    final st = device.state;
    if (st != _lastState) {
      if (st == ConnState.connected) {
        model.reset();
      } else if (model.recording) {
        model.stopRecording();
      }
      _lastState = st;
    }
    final kc = device.params['kp_center'];
    if (kc != null && kc.isFinite) _kpCenter = kc.clamp(0, 20).toDouble();
    if (mounted) setState(() {});
  }

  /// The 3D page eases the joints towards these, so 10 updates a second look smooth.
  void _feed3d() {
    final s = device.latest;
    _robot3d.setGlobal('marsState', {
      'live': device.live,
      'theta1': s?.theta ?? 0,
      'enc': s?.joints ?? [0, 0, 0],
      'encOk': [for (var i = 0; i < 3; i++) s?.encOk(i) ?? false],
      'mode': s?.mode ?? '',
    });
  }

  // ---- State shortcuts ----

  MarsSample? get _s => device.live ? device.latest : null;
  MarsHub? get _hub => device.hubLive ? device.hub : null;
  bool get _live => _s != null;
  bool get _on => _s?.on ?? false;
  bool get _faultFree => (_s?.fault ?? 1) == 0;
  bool get _braked => _hub?.brakeEngaged ?? true;

  // ---- Layout ----

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 1180;
      return Column(children: [
        DeviceHeader(
          title: 'MARS',
          subtitle: 'Arm support · machine interface',
          device: device,
          expectedNames: expectedNames,
          pills: _pills(),
          extra: OutlinedButton.icon(
            onPressed: () => openGame(context, widget.ctl),
            icon: const Icon(Icons.sports_esports_rounded, size: 18),
            label: const Text('GAME'),
          ),
        ),
        hline,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: narrow ? 250 : 290, child: _left()),
              const SizedBox(width: 10),
              Expanded(child: _centre()),
              const SizedBox(width: 10),
              SizedBox(width: narrow ? 300 : 330, child: _right()),
            ]),
          ),
        ),
      ]);
    });
  }

  List<Widget> _pills() {
    final s = _s;
    final pills = <Widget>[];
    if (!device.isConnected) return pills;
    pills.add(StatusPill(_live ? '${model.rate.toStringAsFixed(0)} Hz' : 'NO DATA', _live ? th.Level.ok : th.Level.warn));
    if (s != null) {
      final mode = s.mode;
      final cal = {1: ' · MEASURING LEVER', 2: ' · MEASURING ARM'}[s.cal] ?? '';
      pills.add(StatusPill('MODE $mode$cal',
          mode == 'OFF' ? th.Level.idle : (mode == 'ASSIST' || mode == 'WINDOW') ? th.Level.gold : th.Level.info));
      final f = faultText(s.fault, s.v['err']!.toInt());
      pills.add(StatusPill(f.isEmpty ? 'NO FAULT' : '⚠ $f', f.isEmpty ? th.Level.ok : th.Level.error));
    }
    final h = _hub;
    if (h != null) {
      pills.add(StatusPill(h.brakeEngaged ? 'BRAKE ON' : 'BRAKE RELEASED', h.brakeEngaged ? th.Level.gold : th.Level.info));
    }
    if (device.params.isNotEmpty) {
      pills.add(StatusPill(device.homeSet ? 'HOME ✓' : 'HOME NOT SET', device.homeSet ? th.Level.ok : th.Level.warn));
    }
    return pills;
  }

  // ---- Left: readouts ----

  Widget _left() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _motorCard(),
        const SizedBox(height: 10),
        _encoderCard(),
        const SizedBox(height: 10),
        _powerCard(),
        const SizedBox(height: 10),
        _loadCard(),
      ]),
    );
  }

  String _f(double? v, [int dec = 1]) => v == null || !v.isFinite ? '--' : v.toStringAsFixed(dec);

  Widget _motorCard() {
    final s = _s;
    return DCard(
      title: 'Motor θ1',
      online: device.isConnected ? _live : null,
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(s == null ? '--' : '${s.theta.toStringAsFixed(1)}°',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: th.accent, fontFamily: th.mono)),
          const Spacer(),
          Text(s?.mode ?? '', style: th.cardTitle.copyWith(color: _on ? th.gold : th.textMuted)),
        ]),
        const SizedBox(height: 6),
        ValueRow('Target', s != null && s.on ? _f(s.ref) : '--', unit: '°', valueColor: th.gold),
        ValueRow('Speed', _f(s?.vel), unit: '°/s'),
        ValueRow('Torque', _f(s?.tau, 2), unit: 'Nm'),
        ValueRow('Feedforward', _f(s?.tff, 2), unit: 'Nm'),
        ValueRow('Current', _f(s?.v['cur'], 2), unit: 'A'),
        ValueRow('Temperature', _f(s?.v['temp'], 0), unit: '°C',
            valueColor: (s?.v['temp'] ?? 0) > 70 ? th.err : null),
        ValueRow('Stiffness kp', _f(s?.v['kp'], 0)),
        ValueRow('Support α', s == null ? '--' : '${(s.v['alpha']! / 100).toStringAsFixed(2)} → '
            '${(s.v['alpha_set']! / 100).toStringAsFixed(2)}', valueColor: th.gold),
      ]),
    );
  }

  Widget _encoderCard() {
    final s = _s;
    final hub = _hub;
    return DCard(
      title: 'Encoders',
      online: device.isConnected ? _live && (s?.encLinked ?? false) : null,
      child: Column(children: [
        for (var i = 0; i < 3; i++)
          ValueRow(
            jointNames[i],
            s != null && s.encOk(i) ? '${s.joints[i].toStringAsFixed(1)}°' : '--',
            dot: s == null ? th.idle : !s.encOk(i) ? th.err : s.encWarn(i) ? th.gold : th.ok,
          ),
        if (s != null && [0, 1, 2].any(s.encWarn)) const Hint('Gold = magnet gap: the angle is fine, fix the gap'),
        if (hub != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Hint('raw ${hub.raw(0)} · ${hub.raw(1)} · ${hub.raw(2)}'),
          ),
      ]),
    );
  }

  Widget _powerCard() {
    final h = _hub;
    String onOff(int bit) => h == null ? '--' : (h.relay(bit) ? 'ON' : 'off');
    return DCard(
      title: 'Solenoids & power',
      online: device.isConnected ? h != null : null,
      child: Column(children: [
        ValueRow('Brake', h == null ? '--' : (h.brakeEngaged ? 'ENGAGED' : 'released'),
            dot: h == null ? th.idle : (h.brakeEngaged ? th.gold : th.accent)),
        ValueRow('Motor power', h == null ? '--' : (h.motorPowered ? 'ON' : 'off'),
            dot: h == null ? th.idle : (h.motorPowered ? th.ok : th.idle)),
        ValueRow('Config', onOff(rCfg)),
        ValueRow('Left', onOff(rLeft)),
        ValueRow('Right', onOff(rRight)),
        ValueRow('Height', h == null ? '--' : const {1: '▲ up', -1: '▼ down'}[h.height] ?? 'stopped'),
        if (h != null && h.seq != 0) Hint(seqNames[h.seq] ?? 'sequence'),
        if (h != null && h.service) const Hint('⚠ SERVICE MODE'),
      ]),
    );
  }

  Widget _loadCard() {
    final l = device.loadsLive ? device.loads : null;
    final (w, x, y) = l == null ? (0.0, 0.0, 0.0) : weightCop(l);
    return DCard(
      title: 'Load cells',
      online: device.isConnected ? l != null : null,
      trailing: Text(l == null ? '' : '${w.toStringAsFixed(1)} kg', style: th.valueStyle.copyWith(color: th.accent)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: ValueRow('LC1 FL', _f(l?[0], 2), unit: 'kg')),
          const SizedBox(width: 12),
          Expanded(child: ValueRow('LC2 FR', _f(l?[1], 2), unit: 'kg')),
        ]),
        Row(children: [
          Expanded(child: ValueRow('LC3 BL', _f(l?[2], 2), unit: 'kg')),
          const SizedBox(width: 12),
          Expanded(child: ValueRow('LC4 BR', _f(l?[3], 2), unit: 'kg')),
        ]),
        const SizedBox(height: 6),
        SizedBox(height: 150, child: CopPlot(model: model, tick: _plotTick)),
        if (l != null && w > wMinKg) Hint('COP x ${x.toStringAsFixed(0)} · y ${y.toStringAsFixed(0)} mm', center: true),
      ]),
    );
  }

  // ---- Centre: robot and plots ----

  Widget _centre() {
    final online = device.isConnected ? _live : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        flex: 5,
        child: DCard(
          title: _show3d ? 'Robot · live 3D' : 'Robot · live',
          online: online,
          expand: true,
          trailing: SmallIconButton(
            _show3d ? Icons.timeline_rounded : Icons.view_in_ar_rounded,
            tooltip: _show3d ? 'Lever dial and arm plane' : '3D model',
            onPressed: () => setState(() => _show3d = !_show3d),
          ),
          // both stay alive, so switching back doesn't reload the 3D model
          child: IndexedStack(index: _show3d ? 0 : 1, children: [
            _robot3d.build(),
            RobotView(device: device, tick: _plotTick),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        flex: 4,
        child: TimePlot(
          title: 'Lever angle θ1',
          model: model,
          tick: _plotTick,
          online: online,
          minSpan: 6,
          series: const [
            PlotSeries('theta', 'angle', th.accent),
            PlotSeries('ref', 'target', th.gold, dashed: true),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        flex: 4,
        child: TimePlot(
          title: 'Torque',
          model: model,
          tick: _plotTick,
          online: online,
          unit: ' Nm',
          minSpan: 2,
          series: const [
            PlotSeries('tau', 'measured', th.accent),
            PlotSeries('tff', 'feedforward', th.gold, dashed: true),
          ],
        ),
      ),
    ]);
  }

  // ---- Right: controls ----

  Widget _right() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _holdButton(),
      const SizedBox(height: 10),
      SegmentedButton<_Page>(
        segments: const [
          ButtonSegment(value: _Page.control, label: Text('CONTROL')),
          ButtonSegment(value: _Page.assist, label: Text('ASSIST')),
          ButtonSegment(value: _Page.setup, label: Text('SETUP')),
        ],
        selected: {_page},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _page = v.first),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: SingleChildScrollView(
          child: switch (_page) {
            _Page.control => _controlPage(),
            _Page.assist => _assistPage(),
            _Page.setup => _setupPage(),
          },
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(height: 132, child: _messagesCard()),
    ]);
  }

  Widget _holdButton() => SizedBox(
        height: 60,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: th.err,
            backgroundColor: th.errStrong.withValues(alpha: 0.14),
            side: const BorderSide(color: th.errStrong, width: 1.5),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 18),
          ),
          onPressed: device.isConnected ? device.hold : null,
          icon: const Icon(Icons.pan_tool, size: 22),
          label: const Text('HOLD'),
        ),
      );

  Widget _section(String title, List<Widget> children) => DCard(
        title: title,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _gap() => const SizedBox(height: 8);

  Widget _controlPage() {
    final live = _live;
    final h = _hub;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('Motor', [
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: live && !_on && !_braked ? device.enable : null,
              child: const Text('Enable'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: live && _on ? device.disable : null, child: const Text('Disable'))),
        ]),
        if (live && !_on && _braked) const Padding(padding: EdgeInsets.only(top: 6), child: Hint('Release the brake to give the motor power, then Enable')),
        _gap(),
        SliderRow(
          label: 'Go to',
          min: 0,
          max: 120,
          decimals: 0,
          suffix: '°',
          value: _goDeg,
          onChanged: (v) => setState(() => _goDeg = v),
        ),
        OutlinedButton(
          onPressed: live && _on && _faultFree ? () => device.go(_goDeg) : null,
          child: Text('Go ${_goDeg.toStringAsFixed(0)}°'),
        ),
        _gap(),
        FilledButton(
          onPressed: live && _s?.mode == 'HOLD' && _faultFree ? device.window : null,
          child: const Text('Start window  60–120°'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Hint('From HOLD: the lever moves freely in the window and springs back slowly to 90°.'),
        ),
      ]),
      _gap(),
      _section('Brake', [
        _ToggleButton(
          label: h == null ? 'Brake --' : (h.brakeEngaged ? 'Engaged · tap to release' : 'Released · tap to engage'),
          on: h != null && !h.brakeEngaged,
          onPressed: h == null ? null : () => _toggleBrake(h),
        ),
      ]),
      _gap(),
      _section('Solenoids', [
        Row(children: [
          for (final (label, cmd, bit) in const [('Config', 'CFG', rCfg), ('Left', 'LEFT', rLeft), ('Right', 'RIGHT', rRight)]) ...[
            Expanded(
              child: _ToggleButton(
                label: label,
                on: h?.relay(bit) ?? false,
                onPressed: h == null ? null : () => device.solenoid(cmd, !h.relay(bit)),
              ),
            ),
            if (bit != rRight) const SizedBox(width: 6),
          ],
        ]),
      ]),
      _gap(),
      _section('Height · hold to move', [
        Row(children: [
          Expanded(child: _RepeatButton(label: '▲  Up', enabled: h != null, onRepeat: () => device.height(1), onStop: () => device.height(0))),
          const SizedBox(width: 8),
          Expanded(child: _RepeatButton(label: '▼  Down', enabled: h != null, onRepeat: () => device.height(-1), onStop: () => device.height(0))),
        ]),
      ]),
    ]);
  }

  Future<void> _toggleBrake(MarsHub h) async {
    if (h.brakeEngaged && !_on) {
      final ok = await _confirm(
        'Release the brake?',
        'Releasing the brake powers the motor, but the motor holds nothing until you press Enable.\n\n'
            'Support the lever, then press Enable straight away.',
        'Release',
      );
      if (!ok) return;
    }
    device.brake(!h.brakeEngaged);
  }

  Widget _assistPage() {
    final p = device.params;
    final s = _s;
    final model = (p['g_ok'] ?? 0) == 1
        ? ('τg FITTED', th.Level.ok)
        : (p['lever_ok'] ?? 0) == 1
            ? ('τg SINGLE HOLD', th.Level.gold)
            : ('τg NONE', th.Level.error);
    final armOk = (p['arm_ok'] ?? 0) == 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('Robot model', [
        Row(children: [StatusPill(model.$1, model.$2), const Spacer()]),
        const SizedBox(height: 6),
        Hint((p['lever_ok'] ?? 0) == 1 ? 'Lever torque at 90°: ${_f(p['a_lever'], 2)} Nm' : 'Measure the lever in SETUP first'),
      ]),
      _gap(),
      _section('Cuff', [
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _live && s?.mode == 'HOLD' && _faultFree ? _armAttached : null,
              child: const Text('Arm attached'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _live && s?.mode != 'ASSIST' && s?.mode != 'WINDOW' ? device.uncuff : null,
              child: const Text('Arm removed'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Hint(armOk ? 'Arm torque at 90°: ${_f(p['a_arm'], 2)} Nm' : 'No arm measured'),
      ]),
      _gap(),
      _section('Support α  ·  0 none · 1 full arm weight', [
        SliderRow(
          label: 'α',
          min: 0,
          max: 100,
          decimals: 0,
          suffix: ' %',
          value: _alpha,
          enabled: _live,
          onChanged: (v) {
            setState(() => _alpha = v);
            _later('alpha', () => device.alpha(_alpha.round()));
          },
        ),
        Hint(s == null ? '' : 'actual ${(s.v['alpha']! / 100).toStringAsFixed(2)} → set ${(s.v['alpha_set']! / 100).toStringAsFixed(2)}'),
        _gap(),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _live && s?.mode == 'HOLD' && _faultFree && armOk
                  ? () async {
                      await device.alpha(_alpha.round());
                      await device.assist();
                    }
                  : null,
              child: const Text('Start assist'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: _on ? device.hold : null, child: const Text('Stop → hold'))),
        ]),
      ]),
    ]);
  }

  Future<void> _armAttached() async {
    if (await _confirm('Arm attached', 'Is the arm strapped into the cuff and relaxed?\n\nThe motor measures its weight for 2 s.', 'Measure')) {
      device.calArm();
    }
  }

  Widget _setupPage() {
    final s = _s;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('Faults', [
        OutlinedButton(onPressed: _live && !_faultFree ? device.clearFault : null, child: const Text('Clear fault')),
      ]),
      _gap(),
      _section('Home (once)', [
        Row(children: [
          StatusPill(device.homeSet ? 'HOME ✓' : 'NOT SET', device.homeSet ? th.Level.ok : th.Level.warn),
          const Spacer(),
        ]),
        _gap(),
        OutlinedButton(onPressed: _live && !_on ? _setHome : null, child: const Text('Set home…')),
        const Hint('Motor OFF, every link hanging straight down. Only after remounting an encoder or magnet.'),
      ]),
      _gap(),
      _section('Calibration', [
        OutlinedButton(
          onPressed: _live && s?.mode == 'HOLD' && _faultFree && s!.theta > 30 ? _measureLever : null,
          child: const Text('Measure lever (no arm)'),
        ),
        const Hint('HOLD at about 90° with nothing in the cuff: the robot arm\'s own weight torque.'),
        _gap(),
        OutlinedButton(
          onPressed: _live && !_on && device.loadsLive ? _tare : null,
          child: const Text('Tare load cells'),
        ),
      ]),
      _gap(),
      _section('Window spring', [
        SliderRow(
          label: 'Spring back kp',
          min: 0,
          max: 20,
          decimals: 1,
          value: _kpCenter,
          enabled: _live,
          onChanged: (v) {
            setState(() => _kpCenter = v);
            _later('kp_center', () => device.setParam('kp_center', _kpCenter));
          },
        ),
        const Hint('Weak = slow return to 90°. Saved until the robot restarts.'),
      ]),
      _gap(),
      _section('Recording', [
        _ToggleButton(
          label: model.recording ? '■ Stop · ${model.recorder!.rows} rows' : '● Record',
          on: model.recording,
          onPressed: _recBusy || (!model.recording && !_live) ? null : _toggleRecording,
        ),
        if (model.recording) Hint(model.recorder!.fileName),
        if (_recFolder != null) Hint('Folder: $_recFolder'),
      ]),
      _gap(),
      _section('Command', [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _cmdCtl,
              style: th.valueStyle,
              decoration: const InputDecoration(hintText: 'GET · SET kp_hold 120'),
              onSubmitted: (_) => _sendRaw(),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: device.isConnected ? _sendRaw : null, child: const Text('Send')),
        ]),
      ]),
    ]);
  }

  void _sendRaw() {
    final c = _cmdCtl.text.trim();
    if (c.isEmpty) return;
    device.command(c);
    _cmdCtl.clear();
  }

  Future<void> _setHome() async {
    final s = _s;
    if (s == null) return;
    if (!s.allEncOk) {
      final missing = [for (var i = 0; i < 3; i++) if (!s.encOk(i)) jointNames[i]].join(', ');
      await _confirm('Set home', 'The encoders cannot be zeroed: ${s.encLinked ? 'no reading from $missing' : 'no encoder data'}.\n\n'
          'Fix that first.', 'OK', cancel: false);
      return;
    }
    if (await _confirm(
        'Set home',
        'Is every link hanging straight down (plumb line / jig)?\n\n'
            'This replaces the stored zero of the motor and all three encoders.',
        'Set home')) {
      device.home();
    }
  }

  Future<void> _measureLever() async {
    if (await _confirm('Measure lever', 'Nothing in the cuff, lever holding at about 90°?\n\nThe motor measures for 2 s.', 'Measure')) {
      device.calLever();
    }
  }

  Future<void> _tare() async {
    if (await _confirm('Tare load cells', 'Nobody on the platform? The robot pauses for about 0.3 s.', 'Tare')) {
      device.tare();
    }
  }

  Future<void> _toggleRecording() async {
    setState(() => _recBusy = true);
    try {
      if (model.recording) {
        await model.stopRecording();
      } else {
        await model.startRecording();
      }
    } catch (e) {
      device.message(MsgLevel.error, 'Recording failed: $e');
    } finally {
      if (mounted) setState(() => _recBusy = false);
    }
  }

  Widget _messagesCard() {
    final lines = device.log.reversed.take(6).toList();
    return DCard(
      title: 'Messages',
      expand: true,
      child: lines.isEmpty
          ? const Center(child: Hint('Robot messages appear here'))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final l in lines)
                  Text(l,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: th.valueStyle.copyWith(
                          fontSize: 11.5,
                          color: l.startsWith('FAULT')
                              ? th.err
                              : l.startsWith('>')
                                  ? th.textFaint
                                  : th.textMuted)),
              ],
            ),
    );
  }

  Future<bool> _confirm(String title, String text, String ok, {bool cancel = true}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Text(text, style: th.muted)),
        actions: [
          if (cancel) TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return (r ?? false) && cancel;
  }
}

/// On/off button: gold when on (as the MARS GUI's toggles).
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.label, required this.on, required this.onPressed});
  final String label;
  final bool on;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: on
            ? OutlinedButton.styleFrom(
                backgroundColor: th.gold,
                foregroundColor: const Color(0xFF1A1007),
                side: const BorderSide(color: th.gold),
              )
            : null,
        onPressed: onPressed,
        child: Text(label, overflow: TextOverflow.ellipsis),
      );
}

/// Press and hold: [onRepeat] now and every 150 ms while held, [onStop] on release (dead-man).
class _RepeatButton extends StatefulWidget {
  const _RepeatButton({required this.label, required this.enabled, required this.onRepeat, required this.onStop});
  final String label;
  final bool enabled;
  final VoidCallback onRepeat;
  final VoidCallback onStop;

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _t;

  void _start() {
    if (!widget.enabled || _t != null) return;
    widget.onRepeat();
    _t = Timer.periodic(const Duration(milliseconds: 150), (_) => widget.onRepeat());
    setState(() {});
  }

  void _stop() {
    if (_t == null) return;
    _t!.cancel();
    _t = null;
    widget.onStop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _t?.cancel();
    if (_t != null) widget.onStop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: _ToggleButton(label: widget.label, on: _t != null, onPressed: widget.enabled ? () {} : null),
      );
}
