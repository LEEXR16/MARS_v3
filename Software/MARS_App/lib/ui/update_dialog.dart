/// "Check for updates": checks GitHub, shows what's new, downloads the APK and opens Android's
/// installer. Installing closes the app, so it refuses while a device is connected.
/// Before the installer it checks what would make Android fail with a bare "App not installed":
/// the update must be signed with the installed app's key, and MARS must be allowed to install apps
/// (asked here, once, with a button to the setting; the update goes on by itself on return).
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../core/updater.dart';
import 'theme.dart' as th;

Future<void> showUpdateDialog(BuildContext context, {required bool Function() anyConnected}) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(anyConnected: anyConnected),
    );

enum _Step { checking, upToDate, available, downloading, permission, installing, wrongKey, failed }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.anyConnected});
  final bool Function() anyConnected;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> with WidgetsBindingObserver {
  _Step _step = _Step.checking;
  AppUpdate? _update;
  File? _apk; // downloaded and checked
  String _mine = '';
  double? _progress;
  String _error = '';
  bool _downloadFailed = false; // Try again: download again rather than check again

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the "Install unknown apps" setting: go on to the installer if it was allowed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _step == _Step.permission) _openInstaller();
  }

  Future<void> _check() async {
    setState(() => _step = _Step.checking);
    _downloadFailed = false;
    try {
      _mine = await appVersionText();
      _update = await checkForUpdate();
      _step = _update == null ? _Step.upToDate : _Step.available;
    } catch (e) {
      _error = '$e';
      _step = _Step.failed;
    }
    if (mounted) setState(() {});
  }

  Future<void> _install() async {
    final u = _update!;
    setState(() {
      _step = _Step.downloading;
      _progress = 0;
    });
    try {
      final apk = await downloadUpdate(u, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      if (await sameSigner(apk) == false) {
        setState(() => _step = _Step.wrongKey);
        return;
      }
      _apk = apk;
      await _openInstaller();
    } catch (e) {
      _error = '$e';
      _downloadFailed = true;
      _step = _Step.failed;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openInstaller() async {
    final apk = _apk;
    if (apk == null) return;
    if (!await canInstallUpdates()) {
      if (mounted) setState(() => _step = _Step.permission);
      return;
    }
    if (!mounted) return;
    setState(() => _step = _Step.installing);
    try {
      await installUpdate(apk);
    } catch (e) {
      _error = '$e';
      _step = _Step.failed;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openSettings() async {
    if (await openInstallSettings() || !mounted) return;
    // no such screen on this tablet: let Android's installer ask instead
    setState(() => _step = _Step.installing);
    await installUpdate(_apk!).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final u = _update;
    final connected = widget.anyConnected();
    final close = TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'));

    final (Widget body, List<Widget> actions) = switch (_step) {
      _Step.checking => (
          const _Busy('Checking for updates…'),
          <Widget>[],
        ),
      _Step.upToDate => (
          Text('You have the latest version ($_mine).', style: _text),
          [close],
        ),
      _Step.available => (
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Version ${u!.version} (${u.build}) is available. You have $_mine.', style: _text),
            if (u.size > 0) ...[
              const SizedBox(height: 4),
              Text('Download: ${(u.size / 1e6).toStringAsFixed(1)} MB', style: th.muted),
            ],
            if (u.notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text("WHAT'S NEW", style: th.cardTitle),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(child: Text(u.notes, style: _text)),
              ),
            ],
            if (connected) ...[
              const SizedBox(height: 14),
              const Text(
                'Disconnect every device first: installing closes the app.',
                style: TextStyle(color: th.warn, fontSize: 13),
              ),
            ],
          ]),
          [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
            FilledButton(onPressed: connected ? null : _install, child: const Text('Download and install')),
          ],
        ),
      _Step.downloading => (
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              _progress == null ? 'Downloading…' : 'Downloading… ${(_progress! * 100).toStringAsFixed(0)} %',
              style: _text,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
          ]),
          <Widget>[],
        ),
      _Step.permission => (
          Text(
            'Downloaded and checked. One more step, needed only once on this tablet:\n\n'
            'Android has to allow MARS to install its updates. Tap Open setting, turn on '
            '"Allow from this source", then come back with the Back button. The update continues by itself.',
            style: _text,
          ),
          [
            close,
            FilledButton(onPressed: _openSettings, child: const Text('Open setting')),
          ],
        ),
      _Step.installing => (
          Text(
            'Downloaded and checked. Android\'s installer is open: tap Update (or Install).\n\n'
            'MARS closes while it installs. Open it again afterwards; your recordings stay.',
            style: _text,
          ),
          [
            close,
            TextButton(onPressed: _openInstaller, child: const Text('Open installer again')),
          ],
        ),
      _Step.wrongKey => (
          Text(
            'This update is signed with a different key from the MARS app on this tablet, so Android would '
            'refuse it ("App not installed").\n\n'
            'Fix, once: uninstall MARS, then install app-release.apk from '
            'github.com/$updateRepo/releases. Uninstalling deletes the recordings in '
            'Android/data/com.mars.mars_app/files/MARS: copy that folder to a PC first if you need them.',
            style: _text,
          ),
          [close],
        ),
      _Step.failed => (
          Text(_error, style: _text),
          [
            close,
            FilledButton(onPressed: _downloadFailed && !connected ? _install : _check, child: const Text('Try again')),
          ],
        ),
    };

    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.system_update_rounded, color: th.accent),
        SizedBox(width: 10),
        Text('App update', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(width: 440, child: body),
      actions: actions,
    );
  }
}

const _text = TextStyle(color: th.text, height: 1.4);

class _Busy extends StatelessWidget {
  const _Busy(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 14),
        Text(text, style: _text),
      ]);
}
