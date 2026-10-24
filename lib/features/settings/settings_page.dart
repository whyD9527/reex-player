import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/library_store.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const route = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const ListTile(title: Text('外观'), subtitle: Text('主题模式')),
          RadioListTile<ThemeMode>(
            value: ThemeMode.system,
            groupValue: mode,
            title: const Text('跟随系统'),
            onChanged: (v) => ref.read(themeModeProvider.notifier).state = v!,
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.light,
            groupValue: mode,
            title: const Text('浅色'),
            onChanged: (v) => ref.read(themeModeProvider.notifier).state = v!,
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.dark,
            groupValue: mode,
            title: const Text('深色'),
            onChanged: (v) => ref.read(themeModeProvider.notifier).state = v!,
          ),
          const Divider(),
          ListTile(
            title: const Text('清除播放历史'),
            subtitle: const Text('只清历史记录，不删除文件'),
            onTap: () async {
              await LibraryStore().clearHistory();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除')));
              }
            },
          ),
          const Divider(),
          const ListTile(
            title: Text('关于'),
            subtitle: Text('Reex Player 0.1.0（clean-room rewrite）'),
          ),
        ],
      ),
    );
  }
}