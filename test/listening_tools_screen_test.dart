import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/screens/listening_tools_screen.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';

import 'listening_notes_test.dart' show NotesLibrary;
import 'player_state_test.dart' show TestAudio, TestLibrary;

void main() {
  testWidgets(
    'small-screen subtitle and bookmark controls work without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
      );
      await player.playLocalFiles(
        Work.fromJson({'id': 1, 'title': 'Test work'}),
        {'a': '/a.mp3'},
      );
      final library = NotesLibrary();
      library.documents['subtitle:1:a'] = {
        'name': 'sample.lrc',
        'source': '[00:01.00]A quiet evening\n[00:03.00]Time to rest',
        'offsetMs': 0,
      };
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerState>.value(value: player),
            ChangeNotifierProvider<LibraryState>.value(value: library),
          ],
          child: MaterialApp(
            home: RepaintBoundary(
              key: boundary,
              child: const ListeningToolsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Time to rest'), findsOneWidget);
      await tester.tap(find.text('Time to rest'));
      await tester.pumpAndSettle();
      expect(audio.position, const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      if (Platform.environment['ASMR_QA_DIR'] case final String directory) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/listening-tools.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('书签'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标记当前时间'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Favorite moment');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('Favorite moment'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
      library.dispose();
      settings.dispose();
    },
  );
}
