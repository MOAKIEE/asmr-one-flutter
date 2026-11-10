import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/screens/browse_screen.dart';
import 'package:asmr_one/screens/filter_sheet.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/state/work_feed.dart';
import 'package:asmr_one/widgets/work_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client_test.dart' show TestAdapter, jsonResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'clearing or applying filters preserves the global content restriction',
    () async {
      final adapter = TestAdapter(
        (_) => jsonResponse({'works': [], 'totalCount': 0}),
      );
      final controller = BrowseController(api: ApiClient(adapter: adapter));
      await controller.setShowNsfw(false);
      await controller.update(const WorkQuery(tags: [42], nsfw: true));
      expect(controller.query.nsfw, isFalse);
      await controller.clearFilters();
      expect(controller.query.tags, isEmpty);
      expect(controller.query.nsfw, isFalse);
      expect(
        adapter.requests.every((r) => r.queryParameters['nsfw'] == 'false'),
        isTrue,
      );
      await controller.setShowNsfw(true);
      expect(controller.query.nsfw, isNull);
      expect(
        adapter.requests.last.queryParameters.containsKey('nsfw'),
        isFalse,
      );
      controller.dispose();
    },
  );

  testWidgets(
    'an already open browse page updates when the content setting changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final adapter = TestAdapter(
        (_) => jsonResponse({'works': [], 'totalCount': 0}),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: auth),
          ],
          child: MaterialApp(
            home: BrowseScreen(api: ApiClient(adapter: adapter)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      settings.showNsfw = false;
      await tester.pumpAndSettle();
      expect(
        tester.widget<ActiveFilterBar>(find.byType(ActiveFilterBar)).query.nsfw,
        isFalse,
      );
      expect(adapter.requests.last.queryParameters['nsfw'], 'false');
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      settings.dispose();
    },
  );

  testWidgets('home rails replace their feed when the content query changes', (
    tester,
  ) async {
    final adapter = TestAdapter(
      (_) => jsonResponse({'works': [], 'totalCount': 0}),
    );
    final api = ApiClient(adapter: adapter);
    Future<void> show(bool? nsfw) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkRail(
              title: 'Test rail',
              query: WorkQuery(nsfw: nsfw),
              api: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(null);
    await show(false);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.queryParameters['nsfw'], 'false');
    await show(false);
    expect(adapter.requests, hasLength(2));
  });
}
