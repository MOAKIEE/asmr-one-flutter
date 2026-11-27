import 'package:mimori/core/api/api_client.dart';
import 'package:mimori/core/models/work.dart';
import 'package:mimori/core/storage/app_prefs.dart';
import 'package:mimori/screens/search_screen.dart';
import 'package:mimori/state/library_state.dart';
import 'package:mimori/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_state_test.dart' show DownloadLibrary;

class SearchApi implements ApiClient {
  final keywords = <String>[];
  final nsfwFilters = <bool?>[];
  @override
  Future<WorksPage> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    WorkOrder order = WorkOrder.createDate,
    SortDirection sort = SortDirection.desc,
    List<int> tags = const [],
    double? rate,
    int? duration,
    bool? subtitle,
    bool? nsfw,
  }) async {
    keywords.add(keyword);
    nsfwFilters.add(nsfw);
    return WorksPage.empty;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'changing content preference reloads the current search without adding history',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final api = SearchApi();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(home: SearchScreen(api: api)),
        ),
      );
      await tester.enterText(find.byType(TextField), 'asmr');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      settings.showNsfw = false;
      await tester.pump();
      await tester.pump();
      expect(api.keywords, ['asmr', 'asmr']);
      expect(api.nsfwFilters, [null, false]);
      expect(settings.searchHistory, isEmpty);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  testWidgets(
    'debounce keeps focus; submit records history without a duplicate request',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final api = SearchApi();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(home: SearchScreen(api: api)),
        ),
      );
      await tester.enterText(find.byType(TextField), 'asmr');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      expect(settings.searchHistory, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
      expect(settings.searchHistory, ['asmr']);
      expect(api.keywords, ['asmr']);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets('clear cancels the pending search', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsState(await AppPrefs.load());
    final api = SearchApi();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(home: SearchScreen(api: api)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'stale');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.keywords, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('search header updates result totalCount when feed finishes loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
    final settings = SettingsState(await AppPrefs.load());
    final library = _SearchLibrary();
    final api = _PagedSearchApi();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsState>.value(value: settings),
          ChangeNotifierProvider<LibraryState>.value(value: library),
        ],
        child: MaterialApp(home: SearchScreen(api: api)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'rain');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('共 27 个结果'), findsOneWidget);
    expect(find.text('共 0 个结果'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    library.dispose();
    settings.dispose();
  });
}

class _SearchLibrary extends DownloadLibrary {
  @override
  bool isFavorite(int workId) => false;
}

class _PagedSearchApi extends SearchApi {
  @override
  Future<WorksPage> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    WorkOrder order = WorkOrder.createDate,
    SortDirection sort = SortDirection.desc,
    List<int> tags = const [],
    double? rate,
    int? duration,
    bool? subtitle,
    bool? nsfw,
  }) async {
    return WorksPage(
      works: [Work.fromJson({'id': 101, 'title': 'Rainy Night'})],
      page: 1,
      pageSize: pageSize,
      totalCount: 27,
    );
  }
}
