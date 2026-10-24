import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/recent_store.dart';
import '../../platform/intent_channel.dart';
import '../player/player_page.dart';
import '../settings/settings_page.dart';

final recentProvider = FutureProvider<List<String>>((ref) async {
  return RecentStore().load();
});

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    IntentChannel.setHandler(_openUri);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uri = await IntentChannel.initialUri();
      if (uri != null && mounted) await _openUri(uri);
    });
  }

  Future<void> _openUri(String uri) async {
    final path = uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
    await RecentStore().add(path);
    ref.invalidate(recentProvider);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerPage(path: path)),
    );
  }

  Future<void> _pickAndPlay() async {
    final path = await IntentChannel.pickVideo();
    if (path == null) return;
    await _openUri(path);
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reex Player'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).pushNamed(SettingsPage.route),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndPlay,
        icon: const Icon(Icons.folder_open),
        label: const Text('打开视频'),
      ),
      body: recent.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取失败: $e')),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final path = items[i];
              final name = path.split(Platform.pathSeparator).last;
              return ListTile(
                leading: const Icon(Icons.movie_outlined),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_outline, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          const Text('还没有播放记录'),
          const SizedBox(height: 4),
          Text('点右下角打开一个视频文件', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
