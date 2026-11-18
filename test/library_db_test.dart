import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/state/library_state.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('favorites beyond 500 survive refresh; backup merges atomically and remaps lists', () async {
    final db = await LibraryDb.open(path: inMemoryDatabasePath);
    for (var i = 1; i <= 501; i++) {
      await db.toggleFavorite(Work.fromJson({'id': i, 'title': 'Work $i'}));
    }
    expect(await db.favorites(), hasLength(501));
    final playlist = await db.createLocalPlaylist('A');
    await db.addToLocalPlaylist(playlist, Work.fromJson({'id': 501}));
    await db.saveProgress(
      hash: '501/a',
      workId: 501,
      positionMs: 4000,
      durationMs: 10000,
    );
    await db.writeDocument('downloadQueue', {
      'url': 'https://example.invalid?token=secret',
    });
    final backup = await db.exportBackup();
    expect(backup, isNot(contains('secret')));
    await db.clearFavorites();
    await db.deleteLocalPlaylist(playlist);
    await db.createLocalPlaylist('Unrelated');
    await db.importBackup(backup);
    await db.importBackup(backup);
    expect(await db.favorites(), hasLength(501));
    final lists = await db.localPlaylists();
    expect(lists, hasLength(2));
    expect(
      await db.localPlaylistWorks(lists.singleWhere((p) => p.name == 'A').id),
      hasLength(1),
    );
    final bad = jsonDecode(backup) as Map<String, dynamic>;
    bad['tables']['favorites'] = [
      {'work_id': 999, 'data': '{"id":999}', 'created_at': 1},
    ];
    bad['tables']['progress'] = [
      {'unexpected_column': 1},
    ];
    await expectLater(db.importBackup(jsonEncode(bad)), throwsA(anything));
    expect(await db.isFavorite(999), isFalse);
    await db.close();
  });

  test(
    'LibraryState.clearFavorites clears favorites in DB while preserving bookmarks, subtitles, progress and downloads',
    () async {
      final db = await LibraryDb.open(path: inMemoryDatabasePath);
      final library = LibraryState(db);
      final work1 = Work.fromJson({'id': 1, 'title': 'Work 1'});
      final work2 = Work.fromJson({'id': 2, 'title': 'Work 2'});
      await library.toggleFavorite(work1);
      await library.toggleFavorite(work2);
      await library.recordHistory(work1);
      final pid = await library.createLocalPlaylist('List');
      await library.addToLocalPlaylist(pid, work1);
      await library.saveProgress(
        hash: '1/0',
        workId: 1,
        positionMs: 9000,
        durationMs: 30000,
      );
      await library.writeDocument('bookmarks:1:1/0', [
        {'positionMs': 1000, 'note': 'Bookmark'},
      ]);
      await library.writeDocument('subtitle:1:1/0', {
        'name': 'a.lrc',
        'source': '[00:01.00]Hi',
        'offsetMs': 0,
      });
      await library.saveDownload(
        DownloadRow(
          workId: 1,
          workTitle: 'Work 1',
          hash: '1/0',
          title: '01.mp3',
          filePath: '/tmp/01.mp3',
          size: 100,
        ),
      );

      await library.clearFavorites();

      expect(library.favorites, isEmpty);
      expect(library.favoriteCount, 0);
      expect(await db.favorites(), isEmpty);
      expect(await db.history(), hasLength(1));
      expect(await db.localPlaylists(), hasLength(1));
      expect(await db.progressFor('1/0'), 9000);
      expect(await db.readDocument('bookmarks:1:1/0'), isNotNull);
      expect(await db.readDocument('subtitle:1:1/0'), isNotNull);
      expect(await db.downloads(), hasLength(1));

      library.dispose();
      await db.close();
    },
  );
}
