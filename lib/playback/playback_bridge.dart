import 'package:flutter/services.dart';

/// 与原生前台播放服务/媒体通知通信。
class PlaybackBridge {
  static const _ch = MethodChannel('reex_player/playback');

  /// 通知栏/锁屏/蓝牙发来的控制命令：play / pause / stop / back / forward / seek:ms
  static void Function(String command)? onCommand;

  static bool _inited = false;

  static void init() {
    if (_inited) return;
    _inited = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'command') {
        onCommand?.call((call.arguments as String?) ?? '');
      }
      return null;
    });
  }

  static Future<void> start({required String title, required Duration duration}) async {
    try {
      await _ch.invokeMethod('start', {
        'title': title,
        'duration': duration.inMilliseconds,
      });
    } catch (_) {}
  }

  static Future<void> update({
    required String title,
    required Duration position,
    required Duration duration,
    required bool playing,
  }) async {
    try {
      await _ch.invokeMethod('update', {
        'title': title,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'playing': playing,
      });
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  static Future<void> keepScreenOn(bool on) async {
    try {
      await _ch.invokeMethod('keepScreenOn', on);
    } catch (_) {}
  }

  static Future<void> setVolume(double v) async {
    try {
      await _ch.invokeMethod('setVolume', v.clamp(0.0, 1.0));
    } catch (_) {}
  }

  static Future<void> setBrightness(double v) async {
    try {
      await _ch.invokeMethod('setBrightness', v.clamp(0.01, 1.0));
    } catch (_) {}
  }
}
