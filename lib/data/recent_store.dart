import 'package:shared_preferences/shared_preferences.dart';

/// 最近打开记录（MVP 用 SharedPreferences；后续迁移到 drift）。
class RecentStore {
  static const _key = 'recent_paths';
  static const maxItems = 20;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  Future<List<String>> add(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_key) ?? <String>[];
    items.remove(path);
    items.insert(0, path);
    final trimmed = items.take(maxItems).toList();
    await prefs.setStringList(_key, trimmed);
    return trimmed;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
