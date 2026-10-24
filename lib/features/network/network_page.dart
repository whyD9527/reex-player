import 'package:flutter/material.dart';

import '../../data/smb_accounts.dart';
import '../../smb/smb_client.dart';
import '../../smb/smb_session.dart';
import '../player/player_page.dart';

class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  static const route = '/network';

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final _store = SmbAccountStore();
  List<SmbAccount>? _accounts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _store.load();
    if (mounted) setState(() => _accounts = list);
  }

  Future<void> _add() async {
    final account = await showDialog<SmbAccount>(
      context: context,
      builder: (_) => const _AddAccountDialog(),
    );
    if (account == null) return;
    await _store.add(account);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('网络共享')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('添加 SMB'),
      ),
      body: accounts == null
          ? const Center(child: CircularProgressIndicator())
          : accounts.isEmpty
              ? const Center(child: Text('还没有网络共享\n点右下角添加 SMB 账号'))
              : ListView.separated(
                  itemCount: accounts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = accounts[i];
                    return ListTile(
                      leading: const Icon(Icons.folder_shared_outlined),
                      title: Text(a.label),
                      subtitle: Text('smb://${a.server}/${a.share}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _store.removeAt(i);
                          await _reload();
                        },
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SmbBrowserPage(account: a),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog();

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _server = TextEditingController();
  final _share = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _domain = TextEditingController();
  final _alias = TextEditingController();

  @override
  void dispose() {
    _server.dispose();
    _share.dispose();
    _user.dispose();
    _pass.dispose();
    _domain.dispose();
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加 SMB 共享'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _server, decoration: const InputDecoration(labelText: '服务器 (IP/主机名)')),
            TextField(controller: _share, decoration: const InputDecoration(labelText: '共享名')),
            TextField(controller: _user, decoration: const InputDecoration(labelText: '用户名')),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
            TextField(controller: _domain, decoration: const InputDecoration(labelText: '域 (可空)')),
            TextField(controller: _alias, decoration: const InputDecoration(labelText: '备注 (可空)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            SmbAccount(
              server: _server.text.trim(),
              share: _share.text.trim(),
              user: _user.text.trim(),
              pass: _pass.text,
              domain: _domain.text.trim(),
              alias: _alias.text.trim(),
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class SmbBrowserPage extends StatefulWidget {
  const SmbBrowserPage({super.key, required this.account, this.path = '/'});

  final SmbAccount account;
  final String path;

  @override
  State<SmbBrowserPage> createState() => _SmbBrowserPageState();
}

class _SmbBrowserPageState extends State<SmbBrowserPage> {
  late String _path = widget.path;
  late Future<List<SmbEntry>> _future = _load();

  Future<List<SmbEntry>> _load() async {
    final client = await SmbSession.client(widget.account);
    return client.list(_path);
  }

  void _reload() => setState(() => _future = _load());

  void _up() {
    if (_path == '/' || _path.isEmpty) return;
    final idx = _path.lastIndexOf('/');
    setState(() {
      _path = idx <= 0 ? '/' : _path.substring(0, idx);
      _future = _load();
    });
  }

  Future<void> _play(SmbEntry entry) async {
    final full = _path == '/' ? '/${entry.name}' : '$_path/${entry.name}';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final url = await SmbSession.urlFor(widget.account, full);
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerPage(path: url, title: entry.name)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_path == '/' ? '/${widget.account.share}' : _path),
        leading: IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed: _path == '/' ? () => Navigator.pop(context) : _up,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: FutureBuilder<List<SmbEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) return const Center(child: Text('空目录'));
          items.sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = items[i];
              return ListTile(
                leading: Icon(e.isDir ? Icons.folder_outlined : Icons.movie_outlined),
                title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: e.isDir ? null : Text('${(e.size / (1024 * 1024)).toStringAsFixed(1)} MB'),
                onTap: () {
                  if (e.isDir) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SmbBrowserPage(
                          account: widget.account,
                          path: _path == '/' ? '/${e.name}' : '$_path/${e.name}',
                        ),
                      ),
                    );
                  } else {
                    _play(e);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}