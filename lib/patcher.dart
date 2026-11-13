import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Thrown when a patch cannot be applied (the caller then downloads the full
/// APK instead).
class PatchException implements Exception {
  final String message;
  const PatchException(this.message);
  @override
  String toString() => 'PatchException: $message';
}

/// Rebuilds a new file from the old file plus a small SDM patch, so an update
/// only has to download what changed.
///
/// Patch format ("DROMPAT1", made by tool/make_patches.py from a bsdiff):
///   8  bytes  "DROMPAT1"
///   4 x int64 little endian: new size, ctrl length, diff length, extra length
///   then three zlib streams: ctrl, diff, extra
/// ctrl is a list of (add, copy, seek) int64 triples, exactly like bsdiff:
///   new[pos .. pos+add)  = diff bytes + old bytes at the old position
///   new[.. +copy)        = next bytes of extra
///   old position        += add + seek
///
/// Writes the result to [outPath] and returns its SHA-256 (lowercase hex).
Future<String> applyDromPatch(
    String oldPath, String patchPath, String outPath) async {
  final patch = await File(patchPath).readAsBytes();
  if (patch.length < 40 ||
      String.fromCharCodes(patch.sublist(0, 8)) != 'DROMPAT1') {
    throw const PatchException('not a SDM patch');
  }
  final head = ByteData.sublistView(patch);
  final newSize = head.getInt64(8, Endian.little);
  final ctrlZ = head.getInt64(16, Endian.little);
  final diffZ = head.getInt64(24, Endian.little);
  final extraZ = head.getInt64(32, Endian.little);
  if (newSize <= 0 ||
      ctrlZ < 0 ||
      diffZ < 0 ||
      extraZ < 0 ||
      40 + ctrlZ + diffZ + extraZ != patch.length) {
    throw const PatchException('patch header is damaged');
  }

  Uint8List inflate(int start, int len) {
    final out = zlib.decode(Uint8List.sublistView(patch, start, start + len));
    return out is Uint8List ? out : Uint8List.fromList(out);
  }

  final ctrl = inflate(40, ctrlZ);
  final diff = inflate(40 + ctrlZ, diffZ);
  final extra = inflate(40 + ctrlZ + diffZ, extraZ);
  if (ctrl.length % 24 != 0) throw const PatchException('control damaged');
  final cb = ByteData.sublistView(ctrl);

  // Everything below is synchronous on purpose: this runs on its own isolate,
  // and a real async file write for each of the (many thousands of) small
  // pieces of a patch made the rebuild take minutes. Output goes through one
  // big buffer instead.
  final old = File(oldPath).readAsBytesSync();
  final oldLen = old.length;
  final raf = File(outPath).openSync(mode: FileMode.write);
  try {
    final buf = Uint8List(4 << 20);
    var fill = 0;
    void flushBuf() {
      if (fill > 0) {
        raf.writeFromSync(buf, 0, fill);
        fill = 0;
      }
    }

    var oldPos = 0, newPos = 0, diffPos = 0, extraPos = 0, c = 0;
    while (newPos < newSize) {
      if (c + 24 > ctrl.length) throw const PatchException('patch too short');
      final add = cb.getInt64(c, Endian.little);
      final copy = cb.getInt64(c + 8, Endian.little);
      final seek = cb.getInt64(c + 16, Endian.little);
      c += 24;
      if (add < 0 ||
          copy < 0 ||
          newPos + add + copy > newSize ||
          diffPos + add > diff.length ||
          extraPos + copy > extra.length) {
        throw const PatchException('patch data is inconsistent');
      }
      // 1) old bytes + diff bytes
      var done = 0;
      while (done < add) {
        final n = math.min(add - done, buf.length - fill);
        final d0 = diffPos + done;
        final o0 = oldPos + done;
        for (var i = 0; i < n; i++) {
          final o = o0 + i;
          final ob = (o >= 0 && o < oldLen) ? old[o] : 0;
          buf[fill + i] = (diff[d0 + i] + ob) & 0xFF;
        }
        fill += n;
        done += n;
        if (fill == buf.length) flushBuf();
      }
      newPos += add;
      oldPos += add;
      diffPos += add;
      // 2) bytes that only exist in the new file
      var left = copy;
      var from = extraPos;
      while (left > 0) {
        final n = math.min(left, buf.length - fill);
        buf.setRange(fill, fill + n, extra, from);
        fill += n;
        from += n;
        left -= n;
        if (fill == buf.length) flushBuf();
      }
      newPos += copy;
      extraPos += copy;
      oldPos += seek;
    }
    flushBuf();
    raf.flushSync();
  } finally {
    raf.closeSync();
  }

  final out = File(outPath);
  if (await out.length() != newSize) {
    throw const PatchException('rebuilt file has the wrong size');
  }
  final digest = await sha256.bind(out.openRead()).first;
  return digest.toString();
}

/// Same as [applyDromPatch], but runs on its own isolate so the app stays
/// smooth while the new APK is rebuilt.
Future<String> applyDromPatchInBackground(
        String oldPath, String patchPath, String outPath) =>
    Isolate.run(() => applyDromPatch(oldPath, patchPath, outPath));
