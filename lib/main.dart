import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/storage/app_prefs.dart';
import 'core/storage/library_db.dart';
import 'core/storage/stream_audio_cache.dart';
import 'state/auth_state.dart';
import 'state/download_state.dart';
import 'state/library_state.dart';
import 'state/listening_notes.dart';
import 'state/player_state.dart';
import 'state/settings_state.dart';
import 'state/update_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 后台播放（通知栏控制）必须在使用 AudioPlayer 之前完成初始化。
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.moakiee.mimori.channel.audio',
    androidNotificationChannelName: 'Mimori 播放',
    androidNotificationChannelDescription: '显示当前播放的音频与播放控制',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    androidNotificationIcon: 'mipmap/ic_launcher',
    fastForwardInterval: const Duration(seconds: 15),
    rewindInterval: const Duration(seconds: 15),
  );

  final prefs = await AppPrefs.load();
  runApp(StorageBootstrap(prefs: prefs));
}

/// A failed disk database must never silently become temporary storage.
class StorageBootstrap extends StatefulWidget {
  const StorageBootstrap({super.key, required this.prefs});
  final AppPrefs prefs;
  @override
  State<StorageBootstrap> createState() => _StorageBootstrapState();
}

class _StorageBootstrapState extends State<StorageBootstrap> {
  late Future<LibraryDb> _opening = LibraryDb.open();
  @override
  Widget build(BuildContext context) => FutureBuilder<LibraryDb>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return BootstrapApp(prefs: widget.prefs, db: snapshot.data!);
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('无法打开本地资料库。请检查剩余存储空间后重试，现有数据不会被清除。'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => setState(() {
                            _opening = LibraryDb.open();
                          }),
                          child: const Text('重试'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      );
    },
  );
}

/// 装配依赖并交给 [MimoriApp]。
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key, required this.prefs, required this.db});

  final AppPrefs prefs;
  final LibraryDb db;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late final SettingsState _settings;
  late final AuthState _auth;
  late final LibraryState _library;
  late final StreamAudioCache _audioCache;
  late final PlayerState _player;
  late final ListeningNotes _notes;
  late final DownloadState _downloads;
  late final UpdateState _updates;

  @override
  void initState() {
    super.initState();
    _settings = SettingsState(widget.prefs);
    _library = LibraryState(widget.db);
    _audioCache = StreamAudioCache();
    _player = PlayerState(
      settings: _settings,
      library: _library,
      audioCache: _audioCache,
      accountScope: () => _auth.cacheAccountScope,
      readSession: _library.readDocuments,
      writeSession: _library.writeDocuments,
    );
    _notes = ListeningNotes(_library, _player, settings: _settings);
    _auth = AuthState(widget.prefs, onTokenChanged: _player.refreshTokens);
    _downloads = DownloadState(
      _library,
      readQueue: () => _library.readDocument('downloadQueue'),
      writeQueue: (value) => _library.writeDocument('downloadQueue', value),
    );
    _updates = UpdateState(widget.prefs);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _library.refresh();
    unawaited(_audioCache.refreshStats());
    await _player.restoreSession();
    await _downloads.initialize();
    await _updates.initVersion();
    // 校验本地令牌；网络异常时保持离线可用。
    await _auth.bootstrap();
    // 静默检查更新，不阻塞首屏且离线可用。
    unawaited(_updates.checkForUpdates());
  }

  @override
  void dispose() {
    _updates.dispose();
    _downloads.dispose();
    _notes.dispose();
    _player.dispose();
    unawaited(_audioCache.dispose());
    _library.dispose();
    _auth.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsState>.value(value: _settings),
        ChangeNotifierProvider<AuthState>.value(value: _auth),
        ChangeNotifierProvider<LibraryState>.value(value: _library),
        ChangeNotifierProvider<StreamAudioCache>.value(value: _audioCache),
        ChangeNotifierProvider<PlayerState>.value(value: _player),
        ChangeNotifierProvider<ListeningNotes>.value(value: _notes),
        ChangeNotifierProvider<DownloadState>.value(value: _downloads),
        ChangeNotifierProvider<UpdateState>.value(value: _updates),
      ],
      child: const MimoriApp(),
    );
  }
}
