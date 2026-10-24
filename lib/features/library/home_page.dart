import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/recent_store.dart';
import '../../platform/intent_channel.dart';
import '../../platform/media_library.dart';
import '../player/player_page.dart';
import '../settings/settings_page.dart';

final mediaLibraryProvider = FutureProvider<List<MediaItem>>((ref) async {
  await MediaLibrary.ensurePermission();
  return MediaLibrary.scan();
});

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
    final name = path.split(Platform.pathSeparator).last;
    await RecentStore().add(path);
    ref.invalidate(recentProvider);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerPage(path: path, title: name)),
    );
  }

  Future<void> _pickAndPlay() async {
    final path = await IntentChannel.pickVideo();
    if (path == null) return;
    await _openUri(path);
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(mediaLibraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reex Player'),
        actions: [
          IconButton(
            tooltip: '刷新媒体库',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(mediaLibraryProvider),
          ),
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
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取失败: $e')),
        data: (items) {
          if (items.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = items[i];
              return ListTile(
                leading: _VideoBadge(item: item),
                title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [item.resolution, item.sizeText].where((s) => s.isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Text(
                  _fmtDuration(item.duration),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerPage(path: item.path, title: item.name),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.movie_outlined, color: Theme.of(context).colorScheme.primary),
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
          const Text('媒体库里还没有视频'),
          const SizedBox(height: 4),
          Text('也可以点右下角直接打开文件', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}