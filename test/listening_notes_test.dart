import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/listening_notes.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';

import 'player_state_test.dart' show TestAudio, TestLibrary;

class NotesLibrary extends ChangeNotifier implements LibraryState {
  final documents = <String, Object?>{};
  @override
  Future<Object?> readDocument(String key) async => documents[key];
  @override
  Future<void> writeDocument(String key, Object? value) async {
    documents[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bookmarks and subtitles persist per track and survive reopening',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: TestAudio(),
      );
      await player.playLocalFiles(Work.fromJson({'id': 1}), {'a': '/a.mp3'});
      final library = NotesLibrary();
      final notes = ListeningNotes(library, player);
      await notes.reload();
      await notes.addBookmark('a note', positionMs: 9000);
      await notes.importSubtitle('captions.lrc', '[00:01.00]Hello');
      await notes.setOffset(-500);
      notes.dispose();
      final restored = ListeningNotes(library, player);
      await restored.reload();
      expect(restored.bookmarks.single.positionMs, 9000);
      expect(restored.bookmarks.single.note, 'a note');
      expect(restored.offsetMs, -500);
      expect(restored.cues.single.text, 'Hello');
      await expectLater(
        restored.importSubtitle('bad.srt', 'invalid'),
        throwsFormatException,
      );
      expect(restored.cues.single.text, 'Hello');
      await restored.editBookmark(restored.bookmarks.single, 'updated');
      expect(restored.bookmarks.single.note, 'updated');
      await player.playLocalFiles(Work.fromJson({'id': 1}), {'b': '/b.mp3'});
      await restored.reload();
      expect(restored.bookmarks, isEmpty);
      expect(restored.cues, isEmpty);
      restored.dispose();
      library.dispose();
      player.dispose();
      settings.dispose();
    },
  );
}
