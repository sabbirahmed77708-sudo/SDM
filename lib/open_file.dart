import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

import 'l10n.dart';
import 'link_intake.dart' show rootNavigatorKey;

/// Opens a finished download with the phone's own app for that file type.
/// When it cannot be opened, says why instead of doing nothing.
Future<void> openDownloaded(String path) async {
  void say(String text) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(tr(text)),
    ));
  }

  if (!File(path).existsSync()) {
    say('File not found. It may have been deleted or moved.');
    return;
  }
  await _allowMedia(path);
  try {
    // Tell Android exactly what the file is (video/..., audio/...): a clear
    // type makes it offer the phone's video / music player. If that is
    // refused, ask again with "any type" so the "Open with" list appears.
    final mime = _mimeFor(path);
    var r = await OpenFilex.open(path, type: mime);
    if (r.type != ResultType.done &&
        r.type != ResultType.permissionDenied &&
        r.type != ResultType.fileNotFound &&
        mime != null) {
      r = await OpenFilex.open(path, type: '*/*');
    }
    switch (r.type) {
      case ResultType.done:
        break;
      case ResultType.noAppToOpen:
        say('No app on this phone can open this file.');
      case ResultType.permissionDenied:
        say('Allow access to files and media in the phone settings to open this file.');
      case ResultType.fileNotFound:
        say('File not found. It may have been deleted or moved.');
      case ResultType.error:
        say('Could not open this file.');
    }
  } catch (_) {
    say('Could not open this file.');
  }
}

String? _mimeFor(String path) {
  final dot = path.lastIndexOf('.');
  final e = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  const m = {
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    'mov': 'video/quicktime',
    '3gp': 'video/3gpp',
    'flv': 'video/x-flv',
    'ts': 'video/mp2t',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/x-wav',
    'flac': 'audio/flac',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'apk': 'application/vnd.android.package-archive',
  };
  return m[e];
}

/// Android 13+ asks for media access before another app may show a video,
/// song or picture from shared storage.
Future<void> _allowMedia(String path) async {
  final dot = path.lastIndexOf('.');
  final e = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  Permission? p;
  if (const ['mp4', 'mkv', 'webm', 'avi', 'mov', '3gp', 'ts', 'flv', 'm4v']
      .contains(e)) {
    p = Permission.videos;
  } else if (const ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus']
      .contains(e)) {
    p = Permission.audio;
  } else if (const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(e)) {
    p = Permission.photos;
  }
  if (p == null) return;
  try {
    if (!await p.isGranted) await p.request();
  } catch (_) {}
}
