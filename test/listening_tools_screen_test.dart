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

  testWidgets(
    'long multiline subtitles wrap naturally at 1.35x text scale without overflow',
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
        Work.fromJson({'id': 2, 'title': 'Multiline work'}),
        {'track1': '/track1.mp3'},
      );
      final library = NotesLibrary();
      const longCue =
          '第一行很长的台词用来验证不会再被固定高度裁切\n'
          '第二行继续延续对话内容以确保多行折行完整展示\n'
          '第三行在放大字体倍数时依然可以完整阅读\n'
          '第四行也不再被 maxLines 截断或触发溢出警告';
      library.documents['subtitle:2:track1'] = {
        'name': 'long.vtt',
        'source': 'WEBVTT\n\n00:00:01.000 --> 00:00:08.000\n$longCue',
        'offsetMs': 0,
      };
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerState>.value(value: player),
            ChangeNotifierProvider<LibraryState>.value(value: library),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.35),
              ),
              child: child!,
            ),
            home: const ListeningToolsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final textWidget = tester.widget<Text>(find.text(longCue));
      expect(textWidget.maxLines, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
      library.dispose();
      settings.dispose();
    },
  );
}
