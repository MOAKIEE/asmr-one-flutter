import 'dart:io';

import 'package:mimori/core/api/api_client.dart';
import 'package:mimori/core/models/subtitle_matcher.dart';
import 'package:mimori/core/models/track.dart';
import 'package:mimori/core/models/work.dart';
import 'package:mimori/core/storage/app_prefs.dart';
import 'package:mimori/core/storage/library_db.dart';
import 'package:mimori/l10n/app_localizations.dart';
import 'package:mimori/screens/settings_screen.dart';
import 'package:mimori/state/auth_state.dart';
import 'package:mimori/state/download_state.dart';
import 'package:mimori/state/library_state.dart';
import 'package:mimori/state/listening_notes.dart';
import 'package:mimori/state/player_state.dart';
import 'package:mimori/state/settings_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'player_state_test.dart' show TestAudio;

class _SubtitleStorageApi extends ApiClient {
  _SubtitleStorageApi(this.tracksByWork, this.subtitlesByTitle);

  final Map<int, List<TrackNode>> tracksByWork;
  final Map<String, String> subtitlesByTitle;
  int subtitleFetches = 0;

  @override
  Future<List<TrackNode>> fetchTracks(int workId) async =>
      tracksByWork[workId] ?? const [];

  @override
  Future<String> fetchSubtitle(TrackNode node) async {
    subtitleFetches++;
    return subtitlesByTitle[node.title] ?? '[00:01.00]${node.title}';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'clearing auto subtitles preserves manual subtitles and migrates legacy offsets for recovery on reconnect while isolating alternate attachments',
    () async {
      SharedPreferences.setMockInitialValues({'ui.locale': 'zh-CN'});
      final db = await LibraryDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final library = LibraryState(db);
      addTearDown(library.dispose);
      final settings = SettingsState(await AppPrefs.load());
      addTearDown(settings.dispose);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );
      addTearDown(player.dispose);

      const autoSubNode = TrackNode(
        type: 'text',
        title: '02 Auto.lrc',
        hash: '10/sub_auto',
        mediaDownloadUrl: 'https://example.invalid/auto.lrc',
      );
      const altSubNode = TrackNode(
        type: 'text',
        title: '02 Alt.lrc',
        hash: '10/sub_alt',
        mediaDownloadUrl: 'https://example.invalid/alt.lrc',
      );
      final workTracks = [
        const TrackNode(
          type: 'audio',
          title: '01 Manual.mp3',
          hash: '10/a1',
          mediaStreamUrl: 'https://example.invalid/a1.mp3',
        ),
        const TrackNode(
          type: 'audio',
          title: '02 Auto.mp3',
          hash: '10/a2',
          mediaStreamUrl: 'https://example.invalid/a2.mp3',
        ),
        autoSubNode,
        altSubNode,
      ];
      final api = _SubtitleStorageApi(
        {10: workTracks},
        {
          '02 Auto.lrc': '[00:01.00]Auto Subtitle Body',
          '02 Alt.lrc': '[00:02.00]Alternate Subtitle Body',
        },
      );

      var offline = false;
      ListeningNotes createNotes() => ListeningNotes(
        library,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async =>
            offline ? [ConnectivityResult.none] : [ConnectivityResult.wifi],
      );

      final work = Work.fromJson({'id': 10, 'title': 'Subtitle Storage Work'});
      final flat = workTracks.expand((n) => n.flatten()).toList();
      await player.playWork(work, flat, startIndex: 0);

      // Track 1: manual subtitle with offset +450ms.
      var notes = createNotes();
      await notes.reload();
      await notes.importSubtitle('manual.lrc', '[00:01.00]Manual Body');
      await notes.setOffset(450);
      expect(notes.offsetMs, 450);

      // Track 2: simulate legacy auto-matched subtitle record with offset -750ms
      // (only inside matchedSubtitle, before subtitleOffset existed).
      final track2Key = ListeningNotes.trackKey(player.queue[1]);
      await library.writeDocument('matchedSubtitle:$track2Key', {
        'attachmentId': '10/sub_auto',
        'name': '02 Auto.lrc',
        'source': '[00:01.00]Auto Subtitle Body',
        'language': 'zh-hans',
        'ruleVersion': SubtitleMatcher.ruleVersion,
        'offsetMs': -750,
      });

      final statsBefore = await library.refreshAutoSubtitleCacheStats();
      expect(statsBefore.count, 1);
      expect(statsBefore.textBytes, '[00:01.00]Auto Subtitle Body'.length);

      // Clear auto-matched subtitles -> migrates -750ms to subtitleOffset, removes body, keeps manual subtitle.
      final removed = await library.clearAutoSubtitleCache();
      expect(removed, 1);
      expect(library.autoSubtitleCacheStats.count, 0);
      expect(library.autoSubtitleCacheStats.textBytes, 0);
      expect(await db.readDocument('matchedSubtitle:$track2Key'), isNull);
      expect(await db.readDocument('subtitleOffset:$track2Key'), {
        '10/sub_auto': -750,
      });
      notes.dispose();

      // Reopen offline:
      // - Track 1 (manual) still displays with original offset +450ms.
      // - Track 2 (auto) accurately reports offlineEmpty.
      offline = true;
      notes = createNotes();
      await notes.reload();
      expect(notes.subtitleSource, SubtitleSource.manual);
      expect(notes.cues.single.text, 'Manual Body');
      expect(notes.offsetMs, 450);

      await player.seekToIndex(1);
      await notes.reload();
      expect(notes.subtitleStatus, SubtitleStatus.offlineEmpty);
      expect(notes.cues, isEmpty);

      // Reconnect online: re-fetching original auto attachment restores calibrated offset -750ms!
      offline = false;
      await notes.retrySubtitle();
      expect(notes.subtitleStatus, SubtitleStatus.loaded);
      expect(notes.subtitleSource, SubtitleSource.auto);
      expect(notes.cues.single.text, 'Auto Subtitle Body');
      expect(notes.offsetMs, -750);

      // Switch to an alternate subtitle on the same track: uses its own offset (0, then +300ms)
      // without inheriting or clobbering the auto attachment's -750ms!
      await notes.selectWorkSubtitle(
        const SubtitleAttachment(node: altSubNode),
      );
      expect(notes.subtitleSource, SubtitleSource.manual);
      expect(notes.cues.single.text, 'Alternate Subtitle Body');
      expect(notes.offsetMs, 0);
      await notes.setOffset(300);
      expect(notes.offsetMs, 300);

      // Restoring auto subtitle returns to the original auto attachment with its preserved -750ms!
      await notes.restoreAutoSubtitle();
      expect(notes.subtitleSource, SubtitleSource.auto);
      expect(notes.cues.single.text, 'Auto Subtitle Body');
      expect(notes.offsetMs, -750);

      // Backup export & restore into a fresh empty DB preserves manual subtitle text & offset,
      // and never exports auto-matched cache records.
      final backup = await library.exportBackup();
      expect(backup, contains('Manual Body'));
      expect(backup, contains('450'));
      expect(backup, isNot(contains('Auto Subtitle Body')));

      final freshDb = await LibraryDb.open(path: inMemoryDatabasePath);
      addTearDown(freshDb.close);
      await freshDb.importBackup(backup);
      final track1Key = ListeningNotes.trackKey(player.queue[0]);
      final restoredManual = await freshDb.readDocument('subtitle:$track1Key');
      expect(restoredManual, isA<Map>());
      expect((restoredManual as Map)['source'], '[00:01.00]Manual Body');
      expect(restoredManual['offsetMs'], 450);

      notes.dispose();
    },
  );

  testWidgets(
    'SettingsScreen opens unified cache manager sheet and clears auto subtitle cache while keeping manual subtitles and offsets',
    (tester) async {
      SharedPreferences.setMockInitialValues({'ui.locale': 'zh-CN'});
      final db = await tester.runAsync(
        () => LibraryDb.open(path: inMemoryDatabasePath),
      );
      addTearDown(() async => tester.runAsync(() => db!.close()));
      final library = LibraryState(db!);
      await tester.runAsync(() async {
        await library.writeDocument('subtitle:1:1/0', {
          'name': 'manual.lrc',
          'source': '[00:01.00]Keep Me',
          'offsetMs': 250,
        });
        await library.writeDocument('matchedSubtitle:1:1/1', {
          'attachmentId': '1/sub1',
          'name': 'auto.lrc',
          'source': '[00:01.00]Auto Cache Text',
          'language': 'zh-hans',
          'ruleVersion': SubtitleMatcher.ruleVersion,
          'offsetMs': -400,
        });
      });

      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );

      await tester.pumpWidget(
        MultiProvider(
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
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('缓存管理'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('缓存管理'), findsOneWidget);

      await tester.tap(find.text('缓存管理'));
      await tester.pumpAndSettle();
      expect(find.text('图片缓存'), findsOneWidget);
      expect(find.text('在线播放缓存'), findsWidgets);
      expect(find.text('自动匹配字幕'), findsOneWidget);
      expect(find.textContaining('时间偏移'), findsOneWidget);

      // Tap the "清除" button on the 自动匹配字幕 row (3rd TextButton in sheet).
      final subtitleTile = find.ancestor(
        of: find.text('自动匹配字幕'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: subtitleTile, matching: find.byType(TextButton)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(library.autoSubtitleCacheStats.count, 0);
      expect(
        await tester.runAsync(() => db.readDocument('subtitle:1:1/0')),
        isNotNull,
      );
      expect(
        await tester.runAsync(() => db.readDocument('matchedSubtitle:1:1/1')),
        isNull,
      );
      expect(
        await tester.runAsync(() => db.readDocument('subtitleOffset:1:1/1')),
        {'1/sub1': -400},
      );

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );

  test(
    'clearAutoSubtitleCache rolls back transaction on offset write failure, preserving original matchedSubtitle and succeeding on retry',
    () async {
      SharedPreferences.setMockInitialValues({'ui.locale': 'zh-CN'});
      final tempDir = await Directory.systemTemp.createTemp(
        'subtitle_rollback_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final dbPath = p.join(tempDir.path, 'library.db');

      const autoSubNode = TrackNode(
        type: 'text',
        title: '02 Auto.lrc',
        hash: '10/sub_auto',
        mediaDownloadUrl: 'https://example.invalid/auto.lrc',
      );
      const track2 = TrackNode(
        type: 'audio',
        title: '02 Auto.mp3',
        hash: '10/a2',
        mediaStreamUrl: 'https://example.invalid/a2.mp3',
      );
      final work = Work.fromJson({'id': 10, 'title': 'Rollback Work'});
      final settings = SettingsState(await AppPrefs.load());
      addTearDown(settings.dispose);

      // 1. Seed legacy matchedSubtitle with non-zero calibrated offset + another cached record.
      var db = await LibraryDb.open(path: dbPath);
      final track2Key = '10:10/a2';
      await db.writeDocument('matchedSubtitle:$track2Key', {
        'attachmentId': '10/sub_auto',
        'name': '02 Auto.lrc',
        'source': '[00:01.00]Auto Subtitle Body',
        'language': 'zh-hans',
        'ruleVersion': SubtitleMatcher.ruleVersion,
        'offsetMs': -750,
      });
      await db.writeDocument('matchedSubtitle:10:10/a3', {
        'attachmentId': '10/sub_zero',
        'name': '03 Zero.lrc',
        'source': '[00:01.00]Zero Offset Body',
        'language': 'zh-hans',
        'ruleVersion': SubtitleMatcher.ruleVersion,
        'offsetMs': 0,
      });
      await db.close();

      // 2. Install SQLite trigger that aborts any write to subtitleOffset:*.
      var raw = await openDatabase(dbPath);
      await raw.execute('''
        CREATE TRIGGER fail_offset_write
        BEFORE INSERT ON documents
        WHEN NEW.key LIKE 'subtitleOffset:%'
        BEGIN
          SELECT RAISE(ABORT, 'disk full');
        END
      ''');
      await raw.close();

      // 3. Attempting to clear must throw and roll back, leaving matchedSubtitle intact.
      db = await LibraryDb.open(path: dbPath);
      final library = LibraryState(db);
      await library.refreshAutoSubtitleCacheStats();
      expect(library.autoSubtitleCacheStats.count, 2);

      await expectLater(
        library.clearAutoSubtitleCache(),
        throwsA(isA<DatabaseException>()),
      );

      final preserved = await db.readDocument('matchedSubtitle:$track2Key');
      expect(preserved, isA<Map>());
      expect((preserved as Map)['offsetMs'], -750);
      expect(preserved['source'], '[00:01.00]Auto Subtitle Body');
      expect(await db.readDocument('matchedSubtitle:10:10/a3'), isNotNull);
      expect(await db.readDocument('subtitleOffset:$track2Key'), isNull);
      expect(library.autoSubtitleCacheStats.count, 2);
      library.dispose();
      await db.close();

      // 4. Drop trigger and also inject a malformed JSON matchedSubtitle row to confirm
      //    FormatException still skips safely while valid migration succeeds.
      raw = await openDatabase(dbPath);
      try {
        await raw.execute('DROP TRIGGER fail_offset_write');
        await raw.insert('documents', {
          'key': 'matchedSubtitle:10:10/corrupt',
          'value': '{not-valid-json',
        });
      } finally {
        await raw.close();
      }

      db = await LibraryDb.open(path: dbPath);
      addTearDown(db.close);
      final recoveredLibrary = LibraryState(db);
      addTearDown(recoveredLibrary.dispose);
      final removed = await recoveredLibrary.clearAutoSubtitleCache();
      expect(removed, 3);
      expect(await db.readDocument('matchedSubtitle:$track2Key'), isNull);
      expect(await db.readDocument('subtitleOffset:$track2Key'), {
        '10/sub_auto': -750,
      });

      // 5. Re-matching the same attachment restores the migrated -750ms offset.
      final player = PlayerState(
        settings: settings,
        library: recoveredLibrary,
        audioPlayer: TestAudio(),
      );
      addTearDown(player.dispose);
      final flat = const [track2, autoSubNode]
          .expand((n) => n.flatten())
          .toList();
      await player.playWork(work, flat, startIndex: 0);
      final api = _SubtitleStorageApi(
        {
          10: const [track2, autoSubNode],
        },
        {'02 Auto.lrc': '[00:01.00]Auto Subtitle Body'},
      );
      final notes = ListeningNotes(
        recoveredLibrary,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async => [ConnectivityResult.wifi],
      );
      addTearDown(notes.dispose);

      await notes.reload();
      expect(notes.subtitleStatus, SubtitleStatus.loaded);
      expect(notes.subtitleSource, SubtitleSource.auto);
      expect(notes.offsetMs, -750);
    },
  );
}
