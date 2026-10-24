import 'package:shared_preferences/shared_preferences.dart';

/// 播放进度（MVP 用 SharedPreferences；后续迁移 drift）。
class HistoryStore {
  static const _prefix = 'pos:';

  Future<Duration> position(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$_prefix$path') ?? 0;
    return Duration(milliseconds: ms);
  }

  Future<void> save(String path, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix$path', position.inMilliseconds);
  }

  Future<void> clear(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$path');
  }
}
