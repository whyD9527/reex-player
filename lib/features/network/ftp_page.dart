import 'package:flutter/material.dart';

import '../../data/ftp_accounts.dart';
import '../../ftp/ftp_client.dart';
import '../player/player_page.dart';

class FtpPage extends StatefulWidget {
  const FtpPage({super.key});

  static const route = '/ftp';

  @override
  State<FtpPage> createState() => _FtpPageState();
}

class _FtpPageState extends State<FtpPage> {
  final _store = FtpAccountStore();
  List<FtpAccount>? _accounts;

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
    final a = await showDialog<FtpAccount>(
      context: context,
      builder: (_) => const _AddFtpDialog(),
    );
    if (a == null) return;
    await _store.add(a);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('FTP')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('添加 FTP'),
      ),
      body: accounts == null
          ? const Center(child: CircularProgressIndicator())
          : accounts.isEmpty
              ? const Center(child: Text('还没有 FTP 账号'))
              : ListView.separated(
                  itemCount: accounts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = accounts[i];
                    return ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: Text(a.label),
                      subtitle: Text(a.host),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _store.removeAt(i);
                          await _reload();
                        },
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => FtpBrowserPage(account: a)),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AddFtpDialog extends StatefulWidget {
  const _AddFtpDialog();

  @override
  State<_AddFtpDialog> createState() => _AddFtpDialogState();
}

class _AddFtpDialogState extends State<_AddFtpDialog> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '21');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _alias = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加 FTP'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _host, decoration: const InputDecoration(labelText: '主机')),
            TextField(controller: _port, decoration: const InputDecoration(labelText: '端口'), keyboardType: TextInputType.number),
            TextField(controller: _user, decoration: const InputDecoration(labelText: '用户名')),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
            TextField(controller: _alias, decoration: const InputDecoration(labelText: '备注 (可空)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            FtpAccount(
              host: _host.text.trim(),
              port: int.tryParse(_port.text.trim()) ?? 21,
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

class FtpBrowserPage extends StatefulWidget {
  const FtpBrowserPage({super.key, required this.account, this.path = '/'});

  final FtpAccount account;
  final String path;

  @override
  State<FtpBrowserPage> createState() => _FtpBrowserPageState();
}

class _FtpBrowserPageState extends State<FtpBrowserPage> {
  late String _path;
  late Future<List<FtpEntry>> _future;
  late final FtpSession _session = FtpSession(widget.account);

  @override
  void initState() {
    super.initState();
    _path = widget.path;
    _future = _session.list(_path);
  }

  void _reload() => setState(() => _future = _session.list(_path));

  Future<void> _play(FtpEntry e) async {
    final remote = _path == '/' ? '/' + e.name : _path + '/' + e.name;
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('下载 ' + e.name),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => LinearProgressIndicator(value: v > 0 ? v : null),
        ),
      ),
    );
    try {
      final local = await _session.download(remote, e.name, (p) => progress.value = p);
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerPage(path: local, title: e.name)),
      );
    } catch (err) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_path == '/' ? widget.account.host : _path),
        leading: IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed: _path == '/'
              ? () => Navigator.pop(context)
              : () {
                  final idx = _path.lastIndexOf('/');
                  setState(() {
                    _path = idx <= 0 ? '/' : _path.substring(0, idx);
                    _future = _session.list(_path);
                  });
                },
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _reload)],
      ),
      body: FutureBuilder<List<FtpEntry>>(
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
                    Text('$snap.error', textAlign: TextAlign.center),
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
                    setState(() {
                      _path = _path == '/' ? '/' + e.name : _path + '/' + e.name;
                      _future = _session.list(_path);
                    });
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
