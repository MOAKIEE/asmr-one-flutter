import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/root_shell.dart';
import 'state/settings_state.dart';

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
    );
  }
}
