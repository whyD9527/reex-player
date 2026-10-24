import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/library/home_page.dart';
import 'features/settings/settings_page.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class ReexApp extends ConsumerWidget {
  const ReexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final seed = const Color(0xFF4F6BED);
    return MaterialApp(
      title: 'Reex Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      themeMode: mode,
      home: const HomePage(),
      routes: {
        SettingsPage.route: (_) => const SettingsPage(),
      },
    );
  }
}
