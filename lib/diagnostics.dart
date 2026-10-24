import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 轻量诊断日志：同时写到 logcat 和 /sdcard/Android/data/<pkg>/files/diagnostics.log
/// （adb 可直接 pull，不需要 debuggable）。
class Diag {
  static File? _file;

  static Future<void> _ensure() async {
    if (_file != null) return;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      _file = File('${dir.path}/diagnostics.log');
    } catch (_) {}
  }

  static Future<void> log(String message) async {
    debugPrint('[diag] $message');
    await _ensure();
    try {
      await _file?.writeAsString(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }
}