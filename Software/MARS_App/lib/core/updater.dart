/// App updates from GitHub Releases.
///
/// Each release holds app-release.apk and version.json. The app reads version.json from the
/// latest release and compares its build number with its own (pubspec `version: x.y.z+build`).
/// tools/publish_release.ps1 builds a release and uploads it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 'owner/repo' of the public GitHub repository whose Releases hold the APKs (MARS: the code
/// repository itself). Empty = updates not set up. tools/publish_release.ps1 reads it from here.
const updateRepo = 'LEEXR16/MARS_v3';

const _timeout = Duration(seconds: 30); // also the longest gap allowed in a download

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// version.json of a release.
class AppUpdate {
  AppUpdate({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.size,
    required this.sha256,
    required this.notes,
  });

  factory AppUpdate.fromJson(Map<String, dynamic> j) => AppUpdate(
        version: j['version'] as String,
        build: (j['build'] as num).toInt(),
        apkUrl: j['apk'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        sha256: (j['sha256'] as String?)?.toLowerCase() ?? '',
        notes: j['notes'] as String? ?? '',
      );

  final String version;
  final int build;
  final String apkUrl;
  final int size; // bytes, 0 = unknown
  final String sha256; // hex, '' = not checked
  final String notes;
}

/// This app's version, e.g. "1.1.0 (2)".
Future<String> appVersionText() async {
  final i = await PackageInfo.fromPlatform();
  return '${i.version} (${i.buildNumber})';
}

/// The latest release if it is newer than this app; null if this app is up to date.
Future<AppUpdate?> checkForUpdate() async {
  if (updateRepo.isEmpty) throw UpdateException('Updates are not set up yet (no GitHub repository in updater.dart).');
  final uri = Uri.parse('https://github.com/$updateRepo/releases/latest/download/version.json');
  final http.Response r;
  try {
    r = await http.get(uri).timeout(_timeout);
  } on TimeoutException {
    throw UpdateException('No answer from GitHub. Check the internet connection.');
  } on SocketException {
    throw UpdateException('No internet connection.');
  }
  if (r.statusCode == 404) throw UpdateException('No release found on GitHub ($updateRepo).');
  if (r.statusCode != 200) throw UpdateException('GitHub answered ${r.statusCode}.');
  final AppUpdate u;
  try {
    // GitHub serves it as a binary file, so decode as UTF-8 (and drop a BOM if one slipped in)
    final text = utf8.decode(r.bodyBytes).replaceFirst('﻿', '');
    u = AppUpdate.fromJson(jsonDecode(text) as Map<String, dynamic>);
  } catch (e) {
    throw UpdateException('The release\'s version.json can\'t be read: $e');
  }
  final mine = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
  return u.build > mine ? u : null;
}

/// Downloads the APK into the app's cache and checks its size and SHA-256.
/// [onProgress] gets 0..1 (or null while the size is unknown).
Future<File> downloadUpdate(AppUpdate u, void Function(double? progress) onProgress) async {
  final file = File('${(await getTemporaryDirectory()).path}/mars_update.apk');
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(u.apkUrl))).timeout(_timeout);
    if (res.statusCode != 200) throw UpdateException('Download failed: GitHub answered ${res.statusCode}.');
    final total = res.contentLength ?? u.size;
    final sink = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.stream.timeout(_timeout)) {
        sink.add(chunk);
        got += chunk.length;
        onProgress(total > 0 ? got / total : null);
      }
    } on TimeoutException {
      throw UpdateException('The download stalled. Check the internet connection and try again.');
    } finally {
      await sink.close();
    }
    if (u.size > 0 && got != u.size) throw UpdateException('The download is incomplete ($got of ${u.size} bytes).');
    if (u.sha256.isNotEmpty) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != u.sha256) throw UpdateException('The download is damaged (checksum mismatch). Try again.');
    }
    return file;
  } on SocketException {
    throw UpdateException('The internet connection dropped during the download.');
  } finally {
    client.close();
  }
}

const _installer = MethodChannel('mars/installer'); // android/.../MainActivity.kt

/// Is Android's "Install unknown apps" allowed for MARS? (Asked once per tablet.)
Future<bool> canInstallUpdates() async {
  try {
    return await _installer.invokeMethod<bool>('canInstall') ?? true;
  } catch (_) {
    return true; // can't tell: let Android's installer ask
  }
}

/// Opens the "Install unknown apps" setting for MARS. False if the tablet has no such screen.
Future<bool> openInstallSettings() async {
  try {
    return await _installer.invokeMethod<bool>('openInstallSettings') ?? false;
  } catch (_) {
    return false;
  }
}

/// Is [apk] signed with the same key as the installed app? Android refuses an update signed with
/// another key and only says "App not installed". Null = could not tell.
Future<bool?> sameSigner(File apk) async {
  try {
    final r = await _installer.invokeMapMethod<String, Object?>('signers', {'path': apk.path});
    final mine = (r?['installed'] as List?)?.cast<String>() ?? const [];
    final theirs = (r?['apk'] as List?)?.cast<String>() ?? const [];
    if (mine.isEmpty || theirs.isEmpty) return null;
    return mine.toSet().containsAll(theirs) && theirs.toSet().containsAll(mine);
  } catch (_) {
    return null;
  }
}

/// Opens Android's installer with the downloaded APK.
Future<void> installUpdate(File apk) async {
  final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
  if (r.type != ResultType.done) throw UpdateException('The installer could not be opened: ${r.message}');
}
