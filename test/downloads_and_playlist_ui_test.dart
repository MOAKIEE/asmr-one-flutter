import 'package:asmr_one/core/models/playlist.dart';
import 'package:asmr_one/core/models/user.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/screens/downloads_screen.dart';
import 'package:asmr_one/screens/playlist_screen.dart';
import 'package:asmr_one/screens/settings_screen.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_state_test.dart' show DownloadLibrary;
import 'player_state_test.dart' show TestAudio;

class _UiLibrary extends DownloadLibrary {
  final List<LocalPlaylistRow> _local = [];

  @override
  List<LocalPlaylistRow> get localPlaylists => List.unmodifiable(_local);

  @override
  Future<int> createLocalPlaylist(String name) async {
    final row = LocalPlaylistRow(
      id: _local.length + 1,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      worksCount: 0,
    );
    _local.add(row);
    notifyListeners();
    return row.id;
  }

  @override
  bool isFavorite(int workId) => false;
}

class _SignedAuth extends AuthState {
  _SignedAuth(super.prefs);

  @override
  bool get hasToken => true;

  @override
  AppUser get user => const AppUser(loggedIn: true, name: 'moakiee', group: 'user');

  @override
  List<Playlist> get playlists => const [];

  @override
  Future<void> loadPlaylists({bool force = false}) async {}
}

void main() {
  testWidgets(
    'downloads screen separates paused vs failed tasks, provides fallback error and cancel button',
    (tester) async {
      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final library = _UiLibrary();
      final downloads = DownloadState(
        library,
        checkNetwork: () async => [ConnectivityResult.wifi],
        readQueue: () async => {
          'wifiOnly': false,
          'tasks': [
            {
              'workId': 1,
              'workTitle': 'Work A',
              'hash': 'h_paused',
              'title': '01 Paused.mp3',
              'url': 'https://example.invalid/1.mp3',
              'duration': 60,
              'trackIndex': 0,
              'folderLabel': '',
              'status': 'paused',
            },
            {
              'workId': 2,
              'workTitle': 'Work B',
              'hash': 'h_failed',
              'title': '02 Failed.mp3',
              'url': 'https://example.invalid/2.mp3',
              'duration': 60,
              'trackIndex': 0,
              'folderLabel': '',
              'status': 'failed',
            },
          ],
        },
      );
      await downloads.initialize();
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<DownloadState>.value(value: downloads),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: const MaterialApp(home: DownloadsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已暂停'), findsAtLeastNWidgets(2));
      expect(find.text('下载失败'), findsAtLeastNWidgets(2));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      expect(
        downloads.tasks.where((t) => t.status == DownloadStatus.paused),
        isEmpty,
      );

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'signed-in user can choose local playlist target and settings shows gridColumns & signed-in label',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = _SignedAuth(prefs);
      final library = _UiLibrary();
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
          child: const MaterialApp(home: PlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('保存位置'), findsOneWidget);
      expect(find.text('云端列表'), findsOneWidget);
      expect(find.text('本地列表'), findsWidgets);

      await tester.tap(find.text('本地列表').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My Local Picks');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      expect(library.localPlaylists.map((e) => e.name), ['My Local Picks']);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<AuthState>.value(value: auth),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<DownloadState>.value(value: downloads),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('每行列数 · 2'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('当前账号：moakiee'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('当前账号：moakiee'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );
}
