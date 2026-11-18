import 'dart:io';

import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/l10n/app_localizations.dart';
import 'package:asmr_one/screens/library_lists.dart';
import 'package:asmr_one/screens/settings_screen.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_state_test.dart' show TestAudio;

class _FakeLibraryState extends ChangeNotifier implements LibraryState {
  List<Work> _favorites = [
    Work.fromJson({'id': 101, 'title': 'Favorite One'}),
    Work.fromJson({'id': 102, 'title': 'Favorite Two'}),
  ];
  final List<Work> _history = [
    Work.fromJson({'id': 101, 'title': 'Favorite One'}),
  ];
  final List<LocalPlaylistRow> _localPlaylists = [
    LocalPlaylistRow(
      id: 1,
      name: 'My List',
      createdAt: DateTime(2026),
      worksCount: 1,
    ),
  ];
  final List<DownloadRow> _downloads = [];
  final Map<String, Object?> documents = {
    'bookmarks:101:101/0': [
      {'positionMs': 5000, 'note': 'Keep this note'},
    ],
    'subtitle:101:101/0': {
      'name': 'sub.lrc',
      'source': '[00:01.00]Hello',
      'offsetMs': 0,
    },
  };
  final Map<String, int> progress = {'101/0': 15000};
  int toggleCalls = 0;
  int clearFavoritesCalls = 0;

  @override
  List<Work> get favorites => _favorites;
  @override
  List<Work> get history => _history;
  @override
  List<LocalPlaylistRow> get localPlaylists => _localPlaylists;
  @override
  List<DownloadRow> get downloads => _downloads;
  @override
  int get favoriteCount => _favorites.length;
  @override
  bool isFavorite(int workId) => _favorites.any((w) => w.id == workId);
  @override
  int get downloadBytes => _downloads.fold(0, (s, d) => s + d.size);
  @override
  Set<int> get downloadedWorkIds => _downloads.map((d) => d.workId).toSet();
  @override
  bool get hasDownloads => _downloads.isNotEmpty;

  @override
  Future<Object?> readDocument(String key) async => documents[key];

  @override
  Future<void> writeDocument(String key, Object? value) async {
    if (value == null) {
      documents.remove(key);
    } else {
      documents[key] = value;
    }
  }

  @override
  Future<bool> toggleFavorite(Work work) async {
    toggleCalls++;
    return false;
  }

  @override
  Future<void> clearFavorites() async {
    clearFavoritesCalls++;
    _favorites = const [];
    notifyListeners();
  }

  @override
  Future<void> deleteDownload(int id) async {
    _downloads.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  @override
  Future<Map<String, String>> downloadedPaths(int workId) async => {};

  @override
  Future<int> progressFor(String hash) async => progress[hash] ?? 0;

  @override
  Future<void> saveProgress({
    required String hash,
    required int workId,
    required int positionMs,
    required int durationMs,
  }) async {
    progress[hash] = positionMs;
  }

  @override
  Future<void> clearAllLocalData() async {
    _favorites = const [];
    _history.clear();
    _localPlaylists.clear();
    progress.clear();
    documents.clear();
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap({
  required SettingsState settings,
  required AuthState auth,
  required LibraryState library,
  required DownloadState downloads,
  required PlayerState player,
  required Widget home,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsState>.value(value: settings),
      ChangeNotifierProvider<AuthState>.value(value: auth),
      ChangeNotifierProvider<LibraryState>.value(value: library),
      ChangeNotifierProvider<DownloadState>.value(value: downloads),
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
      home: home,
    ),
  );
}

void main() {
  test('clear data and clear favorites strings are translated in all 3 locales', () {
    final zh = L10n.forLocale(const Locale('zh', 'CN'));
    final ja = L10n.forLocale(const Locale('ja', 'JP'));
    final en = L10n.forLocale(const Locale('en', 'US'));

    for (final key in [
      'settings.clearDataConfirm',
      'library.clearFavorites',
      'library.clearFavoritesConfirm',
    ]) {
      expect(zh(key), isNot(key));
      expect(ja(key), isNot(key));
      expect(ja(key), isNot(zh(key)));
      expect(en(key), isNot(key));
      expect(en(key), isNot(zh(key)));
    }
    expect(zh('library.clearFavorites'), contains('清空全部收藏'));
    expect(zh('library.clearFavoritesConfirm'), contains('清空全部收藏'));
    expect(zh('settings.clearDataConfirm'), contains('书签'));
    expect(zh('settings.clearDataConfirm'), contains('字幕'));
    expect(zh('settings.clearDataConfirm'), contains('收听进度'));
    expect(zh('settings.clearDataConfirm'), contains('搜索历史'));
    expect(zh('settings.clearDataConfirm'), contains('音频文件'));
  });

  testWidgets(
    'favorites clear dialog handles cancel and batch confirm while preserving other data',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ui.locale': 'zh-CN',
        'ui.useCoverAccent': false,
      });
      final dir = Directory.systemTemp.createTempSync('asmr-fav-clear-');
      final audioFile = File('${dir.path}/01.mp3')..writeAsStringSync('audio');
      final library = _FakeLibraryState();
      library._downloads.add(
        DownloadRow(
          id: 1,
          workId: 101,
          workTitle: 'Favorite One',
          hash: '101/0',
          title: '01.mp3',
          filePath: audioFile.path,
          size: 5,
        ),
      );
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      await settings.addSearchHistory('asmr');
      final auth = AuthState(prefs);
      final downloads = DownloadState(library, workDirectory: (_) async => dir);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      await tester.pumpWidget(
        _wrap(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: const FavoritesScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 取消：收藏与其余本地数据保持不变
      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('清空全部收藏'), findsOneWidget);
      expect(find.textContaining('清空全部收藏'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(library.favorites, hasLength(2));

      // 确认：只批量清空收藏，其余内容保留
      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(library.clearFavoritesCalls, 1);
      expect(library.toggleCalls, 0);
      expect(library.favorites, isEmpty);
      expect(library.history, hasLength(1));
      expect(library.localPlaylists, hasLength(1));
      expect(library.progress['101/0'], 15000);
      expect(library.documents.containsKey('bookmarks:101:101/0'), isTrue);
      expect(library.documents.containsKey('subtitle:101:101/0'), isTrue);
      expect(library.downloads, hasLength(1));
      expect(audioFile.existsSync(), isTrue);
      expect(settings.searchHistory, ['asmr']);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'settings clear data dialog lists all deleted items and clears them on confirm',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ui.locale': 'zh-CN',
        'ui.useCoverAccent': false,
      });
      final dir = Directory.systemTemp.createTempSync('asmr-settings-clear-');
      final audioFile = File('${dir.path}/01.mp3')..writeAsStringSync('audio');
      final library = _FakeLibraryState();
      library._downloads.add(
        DownloadRow(
          id: 1,
          workId: 101,
          workTitle: 'Favorite One',
          hash: '101/0',
          title: '01.mp3',
          filePath: audioFile.path,
          size: 5,
        ),
      );
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      await settings.addSearchHistory('asmr');
      final auth = AuthState(prefs);
      final downloads = DownloadState(library, workDirectory: (_) async => dir);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      await tester.pumpWidget(
        _wrap(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('清除本地数据'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // 先点取消，全部内容保留
      await tester.tap(find.text('清除本地数据'));
      await tester.pumpAndSettle();
      expect(find.textContaining('书签'), findsWidgets);
      expect(find.textContaining('字幕'), findsWidgets);
      expect(find.textContaining('收听进度'), findsWidgets);
      expect(find.textContaining('音频文件'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(library.favorites, hasLength(2));
      expect(library.documents.containsKey('bookmarks:101:101/0'), isTrue);
      expect(library.documents.containsKey('subtitle:101:101/0'), isTrue);
      expect(library.progress['101/0'], 15000);
      expect(library.downloads, hasLength(1));
      expect(audioFile.existsSync(), isTrue);
      expect(settings.searchHistory, ['asmr']);

      // 再次点击并确认，全部清除
      await tester.tap(find.text('清除本地数据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      for (var i = 0; i < 10 && library.favorites.isNotEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();

      expect(library.favorites, isEmpty);
      expect(library.history, isEmpty);
      expect(library.localPlaylists, isEmpty);
      expect(library.progress, isEmpty);
      expect(library.documents, isEmpty);
      expect(library.downloads, isEmpty);
      expect(audioFile.existsSync(), isFalse);
      expect(settings.searchHistory, isEmpty);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );
}
