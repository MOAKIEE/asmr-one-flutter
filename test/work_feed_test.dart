import 'dart:async';

import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/l10n/app_localizations.dart';
import 'package:asmr_one/screens/work_list_screen.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/state/work_feed.dart';
import 'package:asmr_one/widgets/work_grid.dart';
import 'package:asmr_one/widgets/work_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_state_test.dart' show DownloadLibrary;
import 'player_state_test.dart' show TestAudio;

WorksPage _page(int page, List<int> ids, {required int total}) => WorksPage(
  works: [
    for (final id in ids) Work.fromJson({'id': id}),
  ],
  page: page,
  pageSize: 1,
  totalCount: total,
);

void main() {
  test('a duplicate on the last page ends pagination', () async {
    final requested = <int>[];
    final feed = WorkFeed((page, _) async {
      requested.add(page);
      return _page(page, [1], total: 2);
    }, pageSize: 1);
    addTearDown(feed.dispose);

    await feed.load();
    expect(feed.hasMore, isTrue);
    await feed.loadMore();
    await feed.loadMore();

    expect(requested, [1, 2]);
    expect(feed.items.map((work) => work.id), [1]);
    expect(feed.page, 2);
    expect(feed.totalCount, 2);
    expect(feed.hasMore, isFalse);
  });

  test(
    'an empty page ends pagination before reaching the reported total',
    () async {
      final requested = <int>[];
      final feed = WorkFeed((page, _) async {
        requested.add(page);
        return _page(page, page == 3 ? [] : [1], total: 10);
      }, pageSize: 1);
      addTearDown(feed.dispose);

      await feed.load();
      await feed.loadMore();
      expect(feed.hasMore, isTrue);
      await feed.loadMore();
      await feed.loadMore();

      expect(requested, [1, 2, 3]);
      expect(feed.items.map((work) => work.id), [1]);
      expect(feed.hasMore, isFalse);

      await feed.refresh();
      expect(feed.hasMore, isTrue);
      expect(feed.page, 1);
    },
  );

  test('a previous page response cannot end a refreshed feed', () async {
    final previousPage = Completer<WorksPage>();
    final feed = WorkFeed(
      (page, _) async =>
          page == 1 ? _page(page, [1], total: 3) : previousPage.future,
      pageSize: 1,
    );
    addTearDown(feed.dispose);

    await feed.load();
    final pending = feed.loadMore();
    await feed.refresh();
    previousPage.complete(_page(2, [], total: 3));
    await pending;

    expect(feed.page, 1);
    expect(feed.hasMore, isTrue);
  });

  test(
    'server page size and requested page size support short final pages',
    () {
      final result = WorksPage.fromJson({
        'works': [
          {'id': 25},
        ],
        'pagination': {'currentPage': 2, 'pageSize': 24, 'totalCount': 25},
      }, requestedPageSize: 50);
      expect(result.page, 2);
      expect(result.maxPage, 2);

      final fallback = WorksPage.fromJson({
        'works': [
          {'id': 25},
        ],
        'page': 2,
        'totalCount': 25,
      }, requestedPageSize: 24);
      expect(fallback.maxPage, 2);
    },
  );

  testWidgets(
    'WorkFeedView avoids empty flash before initial load and shows retry on loadMore error',
    (tester) async {
      SharedPreferences.setMockInitialValues({'ui.locale': 'zh-CN'});
      final settings = SettingsState(await AppPrefs.load());
      final library = _FeedLibrary();
      final firstPage = Completer<WorksPage>();
      var failPage2 = true;
      final feed = WorkFeed((page, pageSize) async {
        if (page == 1) return firstPage.future;
        if (failPage2) {
          failPage2 = false;
          throw ApiException('下一页加载失败');
        }
        return WorksPage(
          works: [Work.fromJson({'id': 99, 'title': 'Page 2 Item'})],
          page: 2,
          pageSize: 6,
          totalCount: 7,
        );
      }, pageSize: 6);
      final refreshFuture = feed.refresh();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<LibraryState>.value(value: library),
          ],
          child: MaterialApp(
            locale: settings.locale,
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: WorkFeedView(feed: feed)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('没有找到相关内容'), findsNothing);

      firstPage.complete(
        WorksPage(
          works: [
            for (var i = 1; i <= 6; i++)
              Work.fromJson({'id': i, 'title': 'Work $i'}),
          ],
          page: 1,
          pageSize: 6,
          totalCount: 7,
        ),
      );
      await refreshFuture;
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.text('下一页加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 Item'), findsOneWidget);
      expect(find.text('没有更多了'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      feed.dispose();
      library.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'WorkRail defers loadMore past layout and shows retry button on page 2 failure',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'ui.locale': 'zh-CN'});
      final settings = SettingsState(await AppPrefs.load());
      final library = _FeedLibrary();
      var allowPage2 = false;
      final api = _StubWorksApi((query) async {
        if (query.page == 1) {
          return WorksPage(
            works: [
              for (var i = 1; i <= 4; i++)
                Work.fromJson({'id': i, 'title': 'Rail $i'}),
            ],
            page: 1,
            pageSize: 4,
            totalCount: 5,
          );
        }
        if (!allowPage2) throw ApiException('server down');
        return WorksPage(
          works: [Work.fromJson({'id': 5, 'title': 'Rail 5'})],
          page: 2,
          pageSize: 4,
          totalCount: 5,
        );
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<LibraryState>.value(value: library),
          ],
          child: MaterialApp(
            locale: settings.locale,
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: WorkRail(
                title: 'Hot',
                query: const WorkQuery(),
                pageSize: 4,
                api: api,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(-900, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('重试'), findsOneWidget);

      allowPage2 = true;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Rail 5'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      library.dispose();
      settings.dispose();
    },
  );

  testWidgets('WorkListScreen disposes previous feed when changing sort order', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'ui.locale': 'zh-CN'});
    final settings = SettingsState(await AppPrefs.load());
    final library = _FeedLibrary();
    final player = PlayerState(
      settings: settings,
      library: library,
      audioPlayer: TestAudio(),
    );
    final pendingInitial = Completer<WorksPage>();
    var calls = 0;
    final api = _StubWorksApi((query) {
      calls++;
      if (calls == 1) return pendingInitial.future;
      return Future.value(
        WorksPage(
          works: [Work.fromJson({'id': 2, 'title': 'Fresh Sorted'})],
          page: 1,
          pageSize: 24,
          totalCount: 1,
        ),
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsState>.value(value: settings),
          ChangeNotifierProvider<LibraryState>.value(value: library),
          ChangeNotifierProvider<PlayerState>.value(value: player),
        ],
        child: MaterialApp(
          locale: settings.locale,
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: WorkListScreen(title: 'Works', api: api),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ChoiceChip).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Fresh Sorted'), findsOneWidget);

    pendingInitial.complete(
      WorksPage(
        works: [Work.fromJson({'id': 1, 'title': 'Stale Initial'})],
        page: 1,
        pageSize: 24,
        totalCount: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fresh Sorted'), findsOneWidget);
    expect(find.text('Stale Initial'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    player.dispose();
    library.dispose();
    settings.dispose();
  });
}

class _FeedLibrary extends DownloadLibrary {
  @override
  bool isFavorite(int workId) => false;

  @override
  Set<int> get downloadedWorkIds => const {};
}

class _StubWorksApi extends ApiClient {
  _StubWorksApi(this._onFetch);
  final Future<WorksPage> Function(WorkQuery query) _onFetch;

  @override
  Future<WorksPage> fetchWorks(WorkQuery query) => _onFetch(query);
}
