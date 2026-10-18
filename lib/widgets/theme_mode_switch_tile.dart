import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';

class ThemeModeSwitchTile extends ConsumerWidget {
  const ThemeModeSwitchTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final systemIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark =
        mode == ThemeMode.dark || (mode == ThemeMode.system && systemIsDark);
    final subtitle = switch (mode) {
      ThemeMode.dark => 'Always use dark colors',
      ThemeMode.light => 'Always use light colors',
      ThemeMode.system => 'Follow your device setting',
    };

    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      secondary: Icon(
        isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
      ),
      title: const Text('Dark mode'),
      subtitle: Text(subtitle),
      value: isDark,
      onChanged: (enabled) => ref
          .read(themeModeProvider.notifier)
          .setMode(enabled ? ThemeMode.dark : ThemeMode.light),
    );
  }
}
