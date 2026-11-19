import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/theme/app_theme.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/widgets/common.dart';
import 'package:asmr_one/widgets/work_card.dart';
import 'package:asmr_one/widgets/work_grid.dart';
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
                .copyWith(textScaler: const TextScaler.linear(1.5)),
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

  testWidgets(
    '4-column work grid and 1-column skeleton avoid overflow with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final library = ShellLibrary();
      final work = Work.fromJson({
        'id': 1,
        'title': '超长作品标题测试换行与角标自适应',
        'name': 'Test Circle Very Long Name',
        'nsfw': true,
        'has_subtitle': true,
        'rate_average_2dp': 4.9,
        'dl_count': 199800,
        'price': 0,
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider<LibraryState>.value(value: library),
          ],
          child: MaterialApp(
            theme: AppTheme.build(
              brightness: Brightness.dark,
              seed: AppTheme.accentChoices.first,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: StaticWorkGrid(
                      works: [work, work, work, work],
                      columns: 4,
                    ),
                  ),
                  const SizedBox(
                    height: 160,
                    child: SingleChildScrollView(
                      child: GridSkeleton(columns: 1, count: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final heroes = find.descendant(
        of: find.byType(StaticWorkGrid),
        matching: find.byType(Hero),
      );
      expect(
        tester.widgetList<Hero>(heroes).map((hero) => hero.tag).toSet(),
        hasLength(4),
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      expect(heroes, findsNothing);
      expect(tester.getSize(find.byType(GridSkeleton)).height, lessThan(520));
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      library.dispose();
    },
  );
}
