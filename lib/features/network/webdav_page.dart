import 'package:flutter/material.dart';

import '../../data/webdav_accounts.dart';
import '../../webdav/webdav_client.dart';
import '../player/player_page.dart';

class WebDavPage extends StatefulWidget {
  const WebDavPage({super.key});

  static const route = '/webdav';

  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  final _store = WebDavAccountStore();
  List<WebDavAccount>? _accounts;

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
    final a = await showDialog<WebDavAccount>(
      context: context,
      builder: (_) => const _AddWebDavDialog(),
    );
    if (a == null) return;
    await _store.add(a);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('添加 WebDAV'),
      ),
      body: accounts == null
          ? const Center(child: CircularProgressIndicator())
          : accounts.isEmpty
              ? const Center(child: Text('还没有 WebDAV 账号'))
              : ListView.separated(
                  itemCount: accounts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = accounts[i];
                    return ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(a.label),
                      subtitle: Text(a.url),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _store.removeAt(i);
                          await _reload();
                        },
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WebDavBrowserPage(account: a),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AddWebDavDialog extends StatefulWidget {
  const _AddWebDavDialog();

  @override
  State<_AddWebDavDialog> createState() => _AddWebDavDialogState();
}

class _AddWebDavDialogState extends State<_AddWebDavDialog> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _alias = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加 WebDAV'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: '地址',
                hintText: 'http://192.168.1.9:8081',
              ),
            ),
            TextField(controller: _user, decoration: const InputDecoration(labelText: '用户名')),
            TextField(
              controller: _pass,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true,
            ),
            TextField(controller: _alias, decoration: const InputDecoration(labelText: '备注 (可空)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            WebDavAccount(
              url: _url.text.trim(),
              user: _user.text.trim(),
              pass: _pass.text,
              alias: _alias.text.trim(),
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class WebDavBrowserPage extends StatefulWidget {
  const WebDavBrowserPage({super.key, required this.account, this.path = '/'});

  final WebDavAccount account;
  final String path;

  @override
  State<WebDavBrowserPage> createState() => _WebDavBrowserPageState();
}

class _WebDavBrowserPageState extends State<WebDavBrowserPage> {
  late String _path;
  late Future<List<WebDavEntry>> _future;
  late final WebDavClient _client = WebDavClient(
    baseUrl: widget.account.url,
    user: widget.account.user,
    pass: widget.account.pass,
  );

  @override
  void initState() {
    super.initState();
    _path = widget.path;
    _future = _client.list(_path);
  }

  void _reload() => setState(() => _future = _client.list(_path));

  Future<void> _play(WebDavEntry e) async {
    final url = _client.playUrl(e.href);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerPage(path: url, title: e.name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_path == '/' ? widget.account.url : _path),
        leading: IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed: _path == '/' ? () => Navigator.pop(context) : () {
            final idx = _path.endsWith('/')
                ? _path.substring(0, _path.length - 1).lastIndexOf('/')
                : _path.lastIndexOf('/');
            setState(() {
              _path = idx <= 0 ? '/' : _path.substring(0, idx);
              _future = _client.list(_path);
            });
          },
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _reload)],
      ),
      body: FutureBuilder<List<WebDavEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 12),
                    Text('${snap.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _reload, child: const Text('重试')),
                  ],
                ),
              ),
            );
          }
          final items = [...?snap.data];
          items.sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
          if (items.isEmpty) return const Center(child: Text('空目录'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = items[i];
              return ListTile(
                leading: Icon(e.isDir ? Icons.folder_outlined : Icons.movie_outlined),
                title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: e.isDir ? null : Text(e.sizeText),
                onTap: () {
                  if (e.isDir) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => WebDavBrowserPage(
                          account: widget.account,
                          path: e.href,
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