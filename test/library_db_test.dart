import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/core/models/work.dart';

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
}
