/// VOID WING on the tablet: the Godot web export (assets/web/game/, from Software/VoidWing) in a
/// full-screen WebView, the way DYNABO runs its game.
///   app -> game:  window.marsInput = the desktop GUI's UDP JSON (th1..th4, cuff_mm, mode, enc_ok) + seq
///   game -> app:  MarsGame.postMessage(JSON)  {type: 'session', ...} = logs to save, {type: 'exit'}
/// The game only reads the robot; it never commands it. HOLD stays on screen the whole time.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/asset_server.dart';
import '../core/line_device.dart';
import '../core/recorder.dart';
import '../devices/mars/mars_protocol.dart';
import 'tabs/mars_tab.dart';
import 'theme.dart' as th;
import 'web_page.dart';

Future<void> openGame(BuildContext context, MarsController ctl) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameScreen(ctl: ctl)));

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.ctl});
  final MarsController ctl;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final LocalWebPage _page =
      LocalWebPage(path: 'game/index.html', channel: 'MarsGame', background: Colors.black, onMessage: _onMessage);
  StreamSubscription<MarsSample>? _sub;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _sub = widget.ctl.device.samples.listen((s) => _page.setGlobal('marsInput', gameInput(s, ++_seq)));
  }

  @override
  void dispose() {
    _sub?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    AssetServer.instance.releaseCache(); // the ~40 MB engine
    super.dispose();
  }

  void _onMessage(String text) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'exit':
        if (mounted) Navigator.of(context).maybePop();
      case 'session':
        _saveSession(msg);
    }
  }

  /// The game's session files, as on the desktop: sessions.csv (one row per session) and the
  /// 10 Hz trace, in Android/data/com.mars.mars_app/files/MARS/game/.
  Future<void> _saveSession(Map<String, dynamic> msg) async {
    try {
      final dir = await recordingsFolder('game');
      final summary = File('${dir.path}/sessions.csv');
      final isNew = !await summary.exists();
      await summary.writeAsString('${isNew ? '${msg['summary_header']}\n' : ''}${msg['summary_row']}\n',
          mode: FileMode.append);
      await File('${dir.path}/session_${msg['stamp']}.csv').writeAsString(msg['trace'] as String);
      widget.ctl.device.message(MsgLevel.info, 'Game session saved: MARS/game/session_${msg['stamp']}.csv');
    } catch (e) {
      widget.ctl.device.message(MsgLevel.error, 'Could not save the game session: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.ctl.device;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: _page.build()),
        Positioned(
          top: 10,
          left: 10,
          child: ListenableBuilder(
            listenable: d,
            builder: (context, _) => Row(children: [
              _overlayButton(Icons.close_rounded, 'EXIT', th.textMuted, () => Navigator.of(context).maybePop()),
              const SizedBox(width: 8),
              if (d.isConnected) _overlayButton(Icons.pan_tool, 'HOLD', th.err, d.hold),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _overlayButton(IconData icon, String label, Color color, VoidCallback onTap) => SizedBox(
        height: 36,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundColor: color,
            backgroundColor: Colors.black.withValues(alpha: 0.55),
            side: BorderSide(color: color.withValues(alpha: 0.7)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 12),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      );
}
