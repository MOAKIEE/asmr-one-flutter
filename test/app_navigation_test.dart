import 'dart:async';

import 'package:asmr_one/app.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/screens/player_screen.dart';
import 'package:asmr_one/screens/playlist_screen.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_state_test.dart' show DownloadLibrary;
import 'player_state_test.dart' show TestAudio, TestLibrary;

class ShellLibrary extends DownloadLibrary {
  @override
  int get favoriteCount => 0;
  @override
  List<LocalPlaylistRow> get localPlaylists => [];
  @override
  bool isFavorite(int workId) => false;
}

class ShellPlayer extends PlayerState {
  ShellPlayer(SettingsState settings)
    : super(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: TestAudio(),
      );

  @override
  PlayItem? get currentItem {
    final item = super.currentItem;
    return item == null
        ? null
        : PlayItem(
            workId: item.workId,
            workTitle: item.workTitle,
            title: item.title,
            url: item.url,
            coverUrl: '',
          );
  }
}

void main() {
  testWidgets('playback preserves navigation, route controls and dialogs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'ui.useCoverAccent': false,
      'ui.locale': 'zh',
    });
    final prefs = await AppPrefs.load();
    final settings = SettingsState(prefs);
    final auth = AuthState(prefs);
    final library = ShellLibrary();
    final downloads = DownloadState(library);
    final player = ShellPlayer(settings);
    await player.playLocalFiles(
      Work.fromJson({'id': 1, 'title': 'Test work'}),
      {'a': '/a.mp3'},
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
        child: const AsmrOneApp(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(MiniPlayer), findsOneWidget);
    final navigation = find.byType(NavigationBar);
    expect(
      tester.getRect(find.byType(MiniPlayer)).bottom,
      lessThanOrEqualTo(tester.getRect(navigation).top),
    );
    for (var i = 1; i < 4; i++) {
      final rect = tester.getRect(navigation);
      await tester.tapAt(
        Offset(rect.left + rect.width * (i + 0.5) / 4, rect.center.dy),
      );
      await tester.pump();
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, i);
    }
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const PlaylistListScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(MiniPlayer), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TextField), findsWidgets);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.text('Test work'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(MiniPlayer), findsNothing);
    expect(tester.takeException(), isNull);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MiniPlayer), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.byType(MiniPlayer), findsNothing);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
    downloads.dispose();
    library.dispose();
    auth.dispose();
    settings.dispose();
    // Drain the HTTP error responses produced by the widget-test binding.
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(tester.takeException(), isNull);
  });
}
