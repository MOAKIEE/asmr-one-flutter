import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/screens/search_screen.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchApi implements ApiClient {
  final keywords = <String>[];
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
    return WorksPage.empty;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
}
