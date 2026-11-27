import 'dart:io';
import 'dart:ui' as ui;

import 'package:mimori/core/models/track.dart';
import 'package:mimori/core/models/work.dart';
import 'package:mimori/core/storage/app_prefs.dart';
import 'package:mimori/screens/listening_tools_screen.dart';
import 'package:mimori/screens/player_screen.dart';
import 'package:mimori/state/library_state.dart';
import 'package:mimori/state/listening_notes.dart';
import 'package:mimori/state/player_state.dart';
import 'package:mimori/state/settings_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'listening_notes_test.dart' show NotesLibrary;
import 'player_state_test.dart' show TestAudio, TestLibrary;

void main() {
  testWidgets(
    'small-screen listening tools subtitle settings, offset, restore auto, and bookmark controls work without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
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
      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        checkNetwork: () async => [ConnectivityResult.none],
      );
      await notes.reload();

      final boundary = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<PlayerState>.value(value: player),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<ListeningNotes>.value(value: notes),
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

      // Subtitle settings tab shows file name, source, offset controls, restore auto, and replace expander.
      // No duplicate cue list in ListeningToolsScreen.
      expect(find.text('收听工具'), findsOneWidget);
      expect(find.text('字幕设置'), findsOneWidget);
      expect(find.text('sample.lrc'), findsOneWidget);
      expect(find.text('恢复自动匹配'), findsOneWidget);
      expect(find.text('更换字幕'), findsOneWidget);
      expect(find.text('Time to rest'), findsNothing);

      // Adjust offset by +0.5s.
      await tester.tap(find.byTooltip('+0.5s'));
      await tester.pumpAndSettle();
      expect(notes.offsetMs, 500);
      expect(find.text('+0.5s'), findsOneWidget);
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

      // Switch to Bookmarks tab and create a bookmark.
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
      notes.dispose();
      player.dispose();
      library.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'long multiline subtitles wrap naturally in PlayerScreen at 1.35x text scale without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
      );
      await player.playWork(
        Work.fromJson({'id': 2, 'title': 'Multiline work'}),
        [
          const AudioTrack(
            node: TrackNode(
              type: 'audio',
              title: 'track1.mp3',
              hash: 'track1',
              mediaStreamUrl: 'https://example.invalid/track1.mp3',
            ),
          ),
        ],
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
      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        checkNetwork: () async => [ConnectivityResult.none],
      );
      await notes.reload();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<PlayerState>.value(value: player),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<ListeningNotes>.value(value: notes),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.35),
              ),
              child: child!,
            ),
            home: const PlayerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap toggle button to show subtitles in place.
      await tester.tap(find.byKey(const ValueKey('player-stage-toggle')));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text(longCue));
      expect(textWidget.maxLines, isNull);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      notes.dispose();
      player.dispose();
      library.dispose();
      settings.dispose();
    },
  );
}
