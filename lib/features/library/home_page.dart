import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/recent_store.dart';
import '../../platform/intent_channel.dart';
import '../../platform/media_library.dart';
import '../../data/smb_accounts.dart';
import '../../diagnostics.dart';
import '../../data/webdav_accounts.dart';
import '../../webdav/webdav_client.dart';
import '../../smb/smb_session.dart';
import '../network/network_page.dart';
import '../network/webdav_page.dart';
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

  Future<void> _selfTest() async {
    await Diag.log('=== selftest start ===');
    final smbAccounts = await SmbAccountStore().load();
    await Diag.log('smb accounts: ${smbAccounts.length}');
    for (final a in smbAccounts) {
      await Diag.log(
          'smb try ${a.server}/${a.share} user="${a.user}" domain="${a.domain}" passLen=${a.pass.length} codes=${a.pass.codeUnits.join(",")}');
      try {
        final client = await SmbSession.client(a);
        final entries = await client.list('/');
        await Diag.log('smb ok: ${entries.length} entries');
      } catch (e, st) {
        await Diag.log('smb FAIL: $e');
        await Diag.log('smb stack: $st');
      }
    }
    final webdav = await WebDavAccountStore().load();
    await Diag.log('webdav accounts: ${webdav.length}');
    for (final a in webdav) {
      await Diag.log('webdav try "${a.url}" user="${a.user}" passLen=${a.pass.length}');
      try {
        final result = await listWebDav(a, '/');
        await Diag.log('webdav ok: ${result.entries.length} entries url=${result.client.baseUrl}');
      } catch (e, st) {
        await Diag.log('webdav FAIL: $e');
        await Diag.log('webdav stack: $st');
      }
    }
    await Diag.log('=== selftest end ===');
  }

  Future<void> _openUri(String uri) async {
    if (uri.startsWith('reexplayer://selftest')) {
      await _selfTest();
      return;
    }
    // 诊断/自动化入口：直接打开网络页或某个 SMB 目录（设备上 adb 触摸注入不可用时用）
    if (uri.startsWith('reexplayer://network')) {
      await Navigator.of(context).pushNamed(NetworkPage.route);
      return;
    }
    if (uri.startsWith('reexplayer://webdav-browse')) {
      final q = Uri.parse(uri).queryParameters;
      final account = WebDavAccount(
        url: q['url'] ?? '',
        user: q['user'] ?? '',
        pass: q['pass'] ?? '',
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebDavBrowserPage(account: account, path: q['path'] ?? '/'),
        ),
      );
      return;
    }
    if (uri.startsWith('reexplayer://smb-browse')) {
      final q = Uri.parse(uri).queryParameters;
      final account = SmbAccount(
        server: q['server'] ?? '',
        share: q['share'] ?? '',
        user: q['user'] ?? '',
        pass: q['pass'] ?? '',
        domain: q['domain'] ?? '',
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SmbBrowserPage(account: account, path: q['path'] ?? '/'),
        ),
      );
      return;
    }
    // 诊断用：reexplayer://smb-list?server=..&share=..&user=..&pass=..&path=/
    if (uri.startsWith('reexplayer://smb-list')) {
      final q = Uri.parse(uri).queryParameters;
      try {
        final account = SmbAccount(
          server: q['server'] ?? '',
          share: q['share'] ?? '',
          user: q['user'] ?? '',
          pass: q['pass'] ?? '',
          domain: q['domain'] ?? '',
        );
        final client = await SmbSession.client(account);
        final entries = await client.list(q['path'] ?? '/');
        final shown = entries
            .take(20)
            .map((e) => e.isDir ? '${e.name}/' : '${e.name} (${e.size})')
            .join(', ');
        debugPrint('[smb] list ${entries.length} entries: $shown');
      } catch (e) {
        debugPrint('[smb] list failed: $e');
      }
      return;
    }
    if (uri.startsWith('smb://') || uri.startsWith('smb2://')) {
      final smb = SmbUrl.parse(uri);
      if (smb != null) {
        await _playSmb(smb);
        return;
      }
    }
    final path = uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
    final name = path.split(Platform.pathSeparator).last;
    await RecentStore().add(path);
    ref.invalidate(recentProvider);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerPage(path: path, title: name)),
    );
  }

  Future<void> _playSmb(SmbUrl smb) async {
    final name = smb.path.split('/').last;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final url = await SmbSession.urlFor(smb.toAccount(), smb.path);
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerPage(path: url, title: name)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      debugPrint('[smb] play failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SMB 播放失败: $e')));
    }
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
            tooltip: '网络共享',
            icon: const Icon(Icons.lan_outlined),
            onPressed: () => Navigator.of(context).pushNamed(NetworkPage.route),
          ),
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