import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.path,
    required this.title,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  final String path;
  final String title;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  Map<String, Object?> toJson() => {
        'path': path,
        'title': title,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> m) => HistoryEntry(
        path: (m['path'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        updatedAt: (m['updatedAt'] as num?)?.toInt() ?? 0,
      );

  double get progress => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);
}

class Playlist {
  const Playlist({required this.name, required this.paths});

  final String name;
  final List<String> paths;

  Map<String, Object?> toJson() => {'name': name, 'paths': paths};

  factory Playlist.fromJson(Map<String, dynamic> m) => Playlist(
        name: (m['name'] as String?) ?? '',
        paths: ((m['paths'] as List?) ?? const []).whereType<String>().toList(),
      );
}

/// 历史 / 收藏 / 播放列表（MVP 用 SharedPreferences，后续可迁 drift）。
class LibraryStore {
  static const _historyKey = 'history_v2';
  static const _favKey = 'favorites';
  static const _playlistsKey = 'playlists';

  Future<List<HistoryEntry>> history() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().map(HistoryEntry.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordPlay(String path, String title, Duration position, Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...await history()];
    list.removeWhere((e) => e.path == path);
    list.insert(
      0,
      HistoryEntry(
        path: path,
        title: title,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final trimmed = list.take(100).toList();
    await prefs.setString(_historyKey, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  Future<void> removeHistory(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...await history()];
    list.removeWhere((e) => e.path == path);
    await prefs.setString(_historyKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<List<String>> favorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favKey) ?? const [];
  }

  Future<bool> isFavorite(String path) async => (await favorites()).contains(path);

  Future<bool> toggleFavorite(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...await favorites()];
    final added = !list.contains(path);
    if (added) {
      list.insert(0, path);
    } else {
      list.remove(path);
    }
    await prefs.setStringList(_favKey, list);
    return added;
  }

  Future<List<Playlist>> playlists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().map(Playlist.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePlaylists(List<Playlist> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistsKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> createPlaylist(String name) async {
    final list = await playlists();
    if (list.any((p) => p.name == name)) return;
    await savePlaylists([...list, Playlist(name: name, paths: const [])]);
  }

  Future<void> addToPlaylist(String name, String path) async {
    final list = await playlists();
    final out = <Playlist>[];
    for (final p in list) {
      if (p.name == name) {
        final paths = [...p.paths];
        if (!paths.contains(path)) paths.add(path);
        out.add(Playlist(name: p.name, paths: paths));
      } else {
        out.add(p);
      }
    }
    await savePlaylists(out);
  }

  Future<void> deletePlaylist(String name) async {
    final list = await playlists();
    await savePlaylists(list.where((p) => p.name != name).toList());
  }
}