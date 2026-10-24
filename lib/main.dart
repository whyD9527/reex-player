import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // libmpv 初始化必须在 runApp 之前
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: ReexApp()));
}
