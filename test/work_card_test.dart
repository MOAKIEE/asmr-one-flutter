import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/theme/app_theme.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/widgets/work_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigation_test.dart' show ShellLibrary;

void main() {
  testWidgets('work list grows to fit a two-line title with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsState(await AppPrefs.load());
    final library = ShellLibrary();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider<LibraryState>.value(value: library),
        ],
        child: MaterialApp(
          theme: AppTheme.build(
            brightness: Brightness.light,
            seed: AppTheme.accentChoices.first,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                WorkListTile(
                  work: Work.fromJson({
                    'id': 1,
                    'title': 'A long work title that wraps onto two lines',
                    'name': 'Test circle',
                    'rate_average_2dp': 4.8,
                    'dl_count': 1234,
                    'price': 1980,
                    'duration': 3600,
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(WorkListTile)).height, greaterThan(108));
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    library.dispose();
  });
}
