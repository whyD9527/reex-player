import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../player/player_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  static const route = '/history';

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _store = LibraryStore();
  late Future<List<HistoryEntry>> _future = _store.history();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              await _store.clearHistory();
              setState(() => _future = _store.history());
            },
          ),
        ],
      ),
      body: FutureBuilder<List<HistoryEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <HistoryEntry>[];
          if (items.isEmpty) return const Center(child: Text('还没有播放记录'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = items[i];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(e.title.isEmpty ? e.path.split('/').last : e.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: LinearProgressIndicator(value: e.progress),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await _store.removeHistory(e.path);
                    setState(() => _future = _store.history());
                  },
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerPage(path: e.path, title: e.title),
                    ),
                  );
                  if (mounted) setState(() => _future = _store.history());
                },
              );
            },
          );
        },
      ),
    );
  }
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  static const route = '/favorites';

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final _store = LibraryStore();
  late Future<List<String>> _future = _store.favorites();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <String>[];
          if (items.isEmpty) return const Center(child: Text('还没有收藏'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final path = items[i];
              return ListTile(
                leading: const Icon(Icons.favorite, color: Colors.redAccent),
                title: Text(path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () async {
                    await _store.toggleFavorite(path);
                    setState(() => _future = _store.favorites());
                  },
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => PlayerPage(path: path)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  static const route = '/playlists';

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  final _store = LibraryStore();
  late Future<List<Playlist>> _future = _store.playlists();

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新建播放列表'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: '名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _store.createPlaylist(name);
    setState(() => _future = _store.playlists());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放列表')),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.add)),
      body: FutureBuilder<List<Playlist>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <Playlist>[];
          if (items.isEmpty) return const Center(child: Text('还没有播放列表'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = items[i];
              final count = p.paths.length;
              return ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(p.name),
                subtitle: Text('$count 个条目'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _store.deletePlaylist(p.name);
                    setState(() => _future = _store.playlists());
                  },
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => PlaylistDetailPage(playlist: p)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: playlist.paths.isEmpty
          ? const Center(child: Text('空播放列表'))
          : ListView.separated(
              itemCount: playlist.paths.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final path = playlist.paths[i];
                return ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: Text(path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => PlayerPage(path: path)),
                  ),
                );
              },
            ),
    );
  }
}
