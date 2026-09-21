import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/root_shell.dart';
import 'state/player_state.dart';
import 'state/settings_state.dart';
import 'widgets/mini_player.dart';

/// 应用根组件。
class AsmrOneApp extends StatelessWidget {
  const AsmrOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();

    return MaterialApp(
      title: 'ASMR One',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: settings.themeFor(Brightness.light),
      darkTheme: settings.themeFor(Brightness.dark),
      locale: settings.locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootShell(),
      // 迷你播放器浮在所有路由之上，保证切页时音乐控制不中断。
      builder: (context, child) {
        return _PlayerOverlay(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

class _PlayerOverlay extends StatelessWidget {
  const _PlayerOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visible = context.select<PlayerState, bool>((p) => p.hasQueue);

    return Stack(
      children: [
        child,
        if (visible)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
      ],
    );
  }
}
