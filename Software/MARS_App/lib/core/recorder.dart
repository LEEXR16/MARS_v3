/// CSV recording, one folder per device: `<app files>/MARS/<device>/`.
///
/// On Android that is `Android/data/com.mars.mars_app/files/MARS/<device>/`, which a PC
/// sees over USB. Files are flushed every second, so a crash loses at most 1 s.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A top-level variable so tests can record into a temporary folder.
Future<Directory> Function(String deviceName) recordingsFolder = _recordingsFolder;

Future<Directory> _recordingsFolder(String deviceName) async {
  final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/MARS/$deviceName');
  await dir.create(recursive: true);
  return dir;
}

class CsvRecorder {
  CsvRecorder._(this.file, this._raf);

  static const flushEvery = Duration(seconds: 1);

  final File file;
  final RandomAccessFile _raf;
  final StringBuffer _buf = StringBuffer();
  final Stopwatch _elapsed = Stopwatch()..start();
  Duration _lastFlush = Duration.zero;
  int rows = 0;
  bool _closed = false;

  /// [deviceName] may be a sub-path ('RR/game'); the file is named `<tag>_<time>.csv` (tag: the device name).
  static Future<CsvRecorder> start(String deviceName, List<String> header, {String? tag}) async {
    final dir = await recordingsFolder(deviceName);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final file = File('${dir.path}/${tag ?? deviceName}_$ts.csv');
    final r = CsvRecorder._(file, await file.open(mode: FileMode.write));
    r._buf.writeln(header.join(','));
    r._flush();
    return r;
  }

  String get fileName => file.uri.pathSegments.last;
  Duration get elapsed => _elapsed.elapsed;

  void write(List<Object?> row) {
    if (_closed) return;
    _buf.writeln(row.map((v) => v ?? '').join(','));
    rows++;
    if (_elapsed.elapsed - _lastFlush >= flushEvery) _flush();
  }

  // Rows are collected and written to the file once a second (about 10 KB at 50 packets/s).
  void _flush() {
    _lastFlush = _elapsed.elapsed;
    if (_buf.isEmpty) return;
    _raf.writeStringSync(_buf.toString());
    _buf.clear();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _flush();
    await _raf.close();
  }
}
