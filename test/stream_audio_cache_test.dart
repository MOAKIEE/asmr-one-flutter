import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mimori/core/api/api_client.dart';
import 'package:mimori/core/models/track.dart';
import 'package:mimori/core/models/work.dart';
import 'package:mimori/core/storage/app_prefs.dart';
import 'package:mimori/core/storage/stream_audio_cache.dart';
import 'package:mimori/state/auth_state.dart';
import 'package:mimori/state/player_state.dart';
import 'package:mimori/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client_test.dart' show TestAdapter, jsonResponse;
import 'player_state_test.dart' show TestAudio, TestLibrary;

/// 支持 Range 请求并记录传输字节数的本地模拟音频服务器。
class _MockAudioServer {
  _MockAudioServer(this.payload);

  final Uint8List payload;
  late HttpServer _server;
  int requestCount = 0;
  int bytesServed = 0;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/track.mp3');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      requestCount++;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
      if (range != null && range.startsWith('bytes=')) {
        final parts = range.substring('bytes='.length).split('-');
        final start = int.parse(parts[0]);
        final end = parts.length > 1 && parts[1].isNotEmpty
            ? int.parse(parts[1])
            : payload.length - 1;
        final slice = payload.sublist(start, end + 1);
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${payload.length}',
        );
        req.response.contentLength = slice.length;
        bytesServed += slice.length;
        req.response.add(slice);
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.ok;
      req.response.contentLength = payload.length;
      bytesServed += payload.length;
      req.response.add(payload);
      await req.response.close();
    });
  }

  void resetCounts() {
    requestCount = 0;
    bytesServed = 0;
  }

  Future<void> close() => _server.close(force: true);
}

Future<Uint8List> _readAll(Uri uri, {String? range}) async {
  if (uri.scheme == 'file') {
    return File(uri.toFilePath()).readAsBytes();
  }
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    final chunks = <int>[];
    await for (final c in res) {
      chunks.addAll(c);
    }
    return Uint8List.fromList(chunks);
  } finally {
    client.close(force: true);
  }
}

class _DownloadableLibrary extends TestLibrary {
  final Map<String, String> localPaths = {};

  @override
  Future<Map<String, String>> downloadedPaths(int workId) async => localPaths;
}

class _GatedSetSourcesAudio extends TestAudio {
  Completer<void>? _entered;
  Completer<void>? _release;

  void gateNextSetSources(Completer<void> entered, Completer<void> release) {
    _entered = entered;
    _release = release;
  }

  @override
  Future<Duration?> setAudioSources(
    List<ja.AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ja.ShuffleOrder? shuffleOrder,
  }) async {
    final entered = _entered;
    final release = _release;
    _entered = null;
    _release = null;
    if (entered != null && !entered.isCompleted) {
      entered.complete();
    }
    if (release != null) {
      await release.future;
    }
    return super.setAudioSources(
      sources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
  }
}

Future<({int statusCode, String? contentRange, Uint8List body})> _readRangeRaw(
  Uri uri,
  String range,
) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    final chunks = <int>[];
    await for (final c in res) {
      chunks.addAll(c);
    }
    return (
      statusCode: res.statusCode,
      contentRange: res.headers.value(HttpHeaders.contentRangeHeader),
      body: Uint8List.fromList(chunks),
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    // Allow loopback HttpClient requests to the local mock server in tests.
    HttpOverrides.global = null;
  });

  test(
    'controlled replay experiment: cache off transfers 2x payload while cache on transfers 0 upstream bytes on replay',
    () async {
      final payload = Uint8List.fromList(
        List.generate(256 * 1024, (i) => (i * 31) & 0xff),
      );
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-stream-exp-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);
      const key = AudioCacheKey(
        accountScope: 'guest',
        workId: 100,
        trackId: '100/0',
        lowQuality: false,
      );

      // Baseline (cache OFF): play twice directly from upstream.
      server.resetCounts();
      final offPlay1 = await _readAll(server.uri);
      final offFirstBytes = server.bytesServed;
      final offPlay2 = await _readAll(server.uri);
      final offReplayBytes = server.bytesServed - offFirstBytes;
      expect(offPlay1, payload);
      expect(offPlay2, payload);
      expect(offFirstBytes, payload.length);
      expect(offReplayBytes, payload.length);

      // Experiment (cache ON): clear cache, then play twice through cache.
      await cache.clearAll(includeActive: true);
      server.resetCounts();
      cache.resetMetrics();

      final firstUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: server.uri,
      );
      expect(firstUri, isNotNull);
      expect(firstUri!.scheme, 'http'); // proxy stream-and-cache on miss
      final onPlay1 = await _readAll(firstUri);
      final onFirstBytes = server.bytesServed;
      expect(onPlay1, payload);
      expect(onFirstBytes, payload.length);
      expect(await cache.refreshStats(), payload.length);

      // Replay: stays on loopback proxy URI and serves local complete file with 0 upstream bytes!
      final secondUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: server.uri,
      );
      expect(secondUri, isNotNull);
      expect(secondUri!.scheme, 'http');
      expect(secondUri.host, '127.0.0.1');
      final onPlay2 = await _readAll(secondUri);
      final onReplayBytes = server.bytesServed - onFirstBytes;
      expect(onPlay2, payload);
      expect(onReplayBytes, 0);
      expect(cache.cacheHitBytes, payload.length);
    },
  );

  test(
    'seeking into an uncached Range passes through 206 without marking partial data complete',
    () async {
      final payload = Uint8List.fromList(
        List.generate(64 * 1024, (i) => i & 0xff),
      );
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-stream-seek-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);
      const key = AudioCacheKey(
        accountScope: 'uid:u1',
        workId: 200,
        trackId: '200/0',
        lowQuality: false,
      );

      final proxyUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: server.uri,
      );
      expect(proxyUri, isNotNull);

      // Seek to middle of uncached track.
      final midSlice = await _readAll(proxyUri!, range: 'bytes=32768-40959');
      expect(midSlice, payload.sublist(32768, 40960));
      expect(await cache.lookupComplete(key), isNull);
    },
  );

  test(
    'cache isolates account scope and quality, survives token refresh, and evicts oldest idle LRU entry first',
    () async {
      final payload = Uint8List.fromList(List.filled(60 * 1024, 7));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-stream-lru-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      var clock = DateTime(2026, 1, 1, 10, 0);
      final cache = StreamAudioCache(
        directoryProvider: () async => dir,
        maxBytes: 100 * 1024, // 100 KB limit; two 60 KB files exceed it.
        now: () => clock,
      );
      addTearDown(cache.dispose);

      // Account scope invariance across token refreshes.
      final scopeBeforeRefresh = StreamAudioCache.accountScopeFor(
        hasToken: true,
        userId: 'user-42',
        userName: 'alice',
      );
      final scopeAfterRefresh = StreamAudioCache.accountScopeFor(
        hasToken: true,
        userId: 'user-42',
        userName: 'alice',
      );
      final guestScope = StreamAudioCache.accountScopeFor(hasToken: false);
      expect(scopeBeforeRefresh, isNotNull);
      expect(scopeBeforeRefresh, scopeAfterRefresh);
      expect(scopeBeforeRefresh, isNot(guestScope));

      final highKey = AudioCacheKey(
        accountScope: scopeBeforeRefresh!,
        workId: 1,
        trackId: '1/0',
        lowQuality: false,
      );
      final lowKey = AudioCacheKey(
        accountScope: scopeBeforeRefresh,
        workId: 1,
        trackId: '1/0',
        lowQuality: true,
      );
      final guestKey = AudioCacheKey(
        accountScope: guestScope!,
        workId: 1,
        trackId: '1/0',
        lowQuality: false,
      );

      // Populate highKey (60 KB) at t=0.
      final uri1 = await cache.resolvePlayableUri(
        key: highKey,
        remoteUri: server.uri,
      );
      await _readAll(uri1!);
      expect(await cache.lookupComplete(highKey), isNotNull);
      // Low quality & guest must NOT hit highKey.
      expect(await cache.lookupComplete(lowKey), isNull);
      expect(await cache.lookupComplete(guestKey), isNull);

      // Populate lowKey (60 KB) at t=10m -> total 120 KB > 100 KB -> highKey (older) evicted, lowKey (newer) kept!
      clock = clock.add(const Duration(minutes: 10));
      final uri2 = await cache.resolvePlayableUri(
        key: lowKey,
        remoteUri: server.uri,
      );
      await _readAll(uri2!);
      expect(await cache.lookupComplete(highKey), isNull);
      expect(await cache.lookupComplete(lowKey), isNotNull);
      expect(cache.cachedBytes, 60 * 1024);

      // Mark lowKey active, then add guestKey (60 KB) at t=20m:
      // lowKey is active so it must be skipped during eviction until released!
      cache.markActive(lowKey.id);
      clock = clock.add(const Duration(minutes: 10));
      final uri3 = await cache.resolvePlayableUri(
        key: guestKey,
        remoteUri: server.uri,
      );
      await _readAll(uri3!);
      expect(await cache.lookupComplete(lowKey), isNotNull);
      expect(await cache.lookupComplete(guestKey), isNotNull);

      // Release lowKey -> deferred LRU eviction drops older lowKey and retains newer guestKey.
      cache.releaseActive(lowKey.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await cache.lookupComplete(lowKey), isNull);
      expect(await cache.lookupComplete(guestKey), isNotNull);
      expect(cache.cachedBytes, 60 * 1024);
    },
  );

  test(
    'PlayerState prioritizes downloaded files over cache, falls back on cache failure, and clearing cache keeps downloads playable offline',
    () async {
      SharedPreferences.setMockInitialValues({
        'player.streamCache': true,
        'player.lowQuality': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final dlDir = await Directory.systemTemp.createTemp('asmr-dl-');
      final cacheDir = await Directory.systemTemp.createTemp('asmr-cache-');
      addTearDown(() async {
        if (await dlDir.exists()) await dlDir.delete(recursive: true);
        if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
      });

      final downloadedFile = await File(
        p.join(dlDir.path, '01.mp3'),
      ).writeAsBytes(List.filled(1024, 1));
      final library = _DownloadableLibrary()
        ..localPaths['50/0'] = downloadedFile.path;
      final cache = StreamAudioCache(directoryProvider: () async => cacheDir);
      addTearDown(cache.dispose);
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(player.dispose);
      addTearDown(settings.dispose);

      final work = Work.fromJson({'id': 50, 'title': 'Mixed Work'});
      final downloadedTrack = TrackNode.fromJson({
        'type': 'audio',
        'hash': '50/0',
        'title': '01.mp3',
        'mediaStreamUrl': 'https://cdn.example/50_0.mp3',
      }).flatten().single;
      final onlineTrack = TrackNode.fromJson({
        'type': 'audio',
        'hash': '50/1',
        'title': '02.mp3',
        'mediaStreamUrl': 'https://cdn.example/50_1.mp3',
      }).flatten().single;

      await player.playWork(work, [downloadedTrack, onlineTrack]);
      final sources = audio.sources.cast<ja.UriAudioSource>();
      // Track 0 uses downloaded file directly (no stream cache occupied).
      expect(sources[0].uri.scheme, 'file');
      expect(sources[0].uri.toFilePath(), downloadedFile.path);
      // Track 1 uses local stream cache proxy.
      expect(sources[1].uri.host, '127.0.0.1');

      // Clearing temporary stream cache never deletes downloaded files.
      await player.stop();
      await cache.clearAll();
      expect(await downloadedFile.exists(), isTrue);
      expect(
        await player.playLocalFiles(work, {'50/0': downloadedFile.path}),
        isTrue,
      );

      // Broken cache directory gracefully falls back to direct remote streaming.
      final brokenCache = StreamAudioCache(
        directoryProvider: () => Future.error(const FileSystemException('full')),
      );
      addTearDown(brokenCache.dispose);
      final fallbackAudio = TestAudio();
      final fallbackPlayer = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: fallbackAudio,
        audioCache: brokenCache,
        accountScope: () => 'guest',
      );
      addTearDown(fallbackPlayer.dispose);

      await fallbackPlayer.playSingle(work, onlineTrack);
      final fallbackUri =
          (fallbackAudio.sources.single as ja.UriAudioSource).uri;
      expect(fallbackUri.toString(), 'https://cdn.example/50_1.mp3');
    },
  );

  test(
    'Android manifest enables cleartext network security config strictly for 127.0.0.1',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final config = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();

      expect(
        manifest,
        contains('android:networkSecurityConfig="@xml/network_security_config"'),
      );
      expect(config, contains('cleartextTrafficPermitted="false"'));
      expect(config, contains('cleartextTrafficPermitted="true"'));
      expect(config, contains('<domain includeSubdomains="false">127.0.0.1</domain>'));
    },
  );

  test(
    'cold start skips cache when identity is pending and isolates restored queue per persisted account across token refresh',
    () async {
      final payload = Uint8List.fromList(List.generate(8192, (i) => i & 0xff));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-cold-scope-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      Map<String, Object?> savedSession() => {
        'playerSession': {
          'index': 0,
          'position': 0,
          'shuffle': false,
          'loop': 0,
        },
        'playerQueue': [
          {
            'workId': 77,
            'workTitle': 'Cold Work',
            'title': '01.mp3',
            'hash': '77/0',
            'url': server.uri.toString(),
            'coverUrl': '',
          },
        ],
      };

      // 1. Legacy token without persisted accountScope -> pending identity -> skips cache (direct remote URL).
      SharedPreferences.setMockInitialValues({
        'auth.token': 'legacy-token',
        'player.streamCache': true,
      });
      final legacyPrefs = await AppPrefs.load();
      final legacySettings = SettingsState(legacyPrefs);
      final legacyAuth = AuthState(legacyPrefs);
      expect(legacyAuth.cacheAccountScope, isNull);
      final legacyAudio = TestAudio();
      final legacyPlayer = PlayerState(
        settings: legacySettings,
        library: TestLibrary(),
        audioPlayer: legacyAudio,
        audioCache: cache,
        accountScope: () => legacyAuth.cacheAccountScope,
        readSession: (_) async => savedSession(),
      );
      await legacyPlayer.restoreSession();
      expect(
        (legacyAudio.sources.single as ja.UriAudioSource).uri,
        server.uri,
      );
      legacyPlayer.dispose();
      legacyAuth.dispose();
      legacySettings.dispose();

      // 2. Account A logs in, caches track 77/0, then cold-starts with refreshed token -> hits Account A's file.
      final api = ApiClient(
        adapter: TestAdapter((request) {
          if (request.method == 'POST' && request.uri.path == '/api/auth/me') {
            final name = (request.data as Map)['name'] as String;
            return jsonResponse({'token': 'tok-$name'});
          }
          final authHeader = request.headers['Authorization'] as String? ?? '';
          if (authHeader.contains('tok-alice')) {
            return jsonResponse({
              'user': {'loggedIn': true, 'id': 'u-alice', 'name': 'alice'},
            });
          }
          return jsonResponse({
            'user': {'loggedIn': true, 'id': 'u-bob', 'name': 'bob'},
          });
        }),
      );

      SharedPreferences.setMockInitialValues({'player.streamCache': true});
      final prefsA = await AppPrefs.load();
      final authA = AuthState(prefsA, api: api);
      expect(await authA.login('alice', 'pass123'), isTrue);
      expect(prefsA.accountScope, 'uid:u-alice');
      final keyA = const AudioCacheKey(
        accountScope: 'uid:u-alice',
        workId: 77,
        trackId: '77/0',
        lowQuality: false,
      );
      final proxyA = await cache.resolvePlayableUri(
        key: keyA,
        remoteUri: server.uri,
      );
      await _readAll(proxyA!);
      authA.dispose();

      // Cold start Account A with a refreshed token (before bootstrap runs): still hits Account A's cache!
      SharedPreferences.setMockInitialValues({
        'auth.token': 'refreshed-tok-alice',
        'auth.accountScope': 'uid:u-alice',
        'player.streamCache': true,
      });
      final coldPrefsA = await AppPrefs.load();
      final coldSettingsA = SettingsState(coldPrefsA);
      final coldAuthA = AuthState(coldPrefsA);
      final coldAudioA = TestAudio();
      final coldPlayerA = PlayerState(
        settings: coldSettingsA,
        library: TestLibrary(),
        audioPlayer: coldAudioA,
        audioCache: cache,
        accountScope: () => coldAuthA.cacheAccountScope,
        readSession: (_) async => savedSession(),
      );
      await coldPlayerA.restoreSession();
      final uriA = (coldAudioA.sources.single as ja.UriAudioSource).uri;
      expect(uriA.scheme, 'http');
      expect(uriA.host, '127.0.0.1');
      server.resetCounts();
      expect(await _readAll(uriA), payload);
      expect(server.requestCount, 0);
      expect(server.bytesServed, 0);
      coldPlayerA.dispose();
      coldAuthA.dispose();
      coldSettingsA.dispose();

      // 3. Cold start Account B -> must NOT hit Account A's file (gets proxy for uid:u-bob and hits upstream).
      SharedPreferences.setMockInitialValues({
        'auth.token': 'tok-bob',
        'auth.accountScope': 'uid:u-bob',
        'player.streamCache': true,
      });
      final coldPrefsB = await AppPrefs.load();
      final coldSettingsB = SettingsState(coldPrefsB);
      final coldAuthB = AuthState(coldPrefsB);
      final coldAudioB = TestAudio();
      final coldPlayerB = PlayerState(
        settings: coldSettingsB,
        library: TestLibrary(),
        audioPlayer: coldAudioB,
        audioCache: cache,
        accountScope: () => coldAuthB.cacheAccountScope,
        readSession: (_) async => savedSession(),
      );
      await coldPlayerB.restoreSession();
      final uriB = (coldAudioB.sources.single as ja.UriAudioSource).uri;
      expect(uriB.scheme, 'http');
      expect(uriB.host, '127.0.0.1');
      server.resetCounts();
      expect(await _readAll(uriB), payload);
      expect(server.requestCount, 1);
      expect(server.bytesServed, payload.length);
      coldPlayerB.dispose();
      coldAuthB.dispose();
      coldSettingsB.dispose();
    },
  );

  test(
    '257-track queue keeps first track route alive across jumps and releases old routes when queue is replaced',
    () async {
      final payload = Uint8List.fromList(List.generate(2048, (i) => i & 0xff));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-long-queue-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({
        'player.streamCache': true,
        'player.autoPlayNext': true,
      });
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(() {
        player.dispose();
        settings.dispose();
      });

      final tracks = [
        for (var i = 0; i < 257; i++)
          TrackNode.fromJson({
            'type': 'audio',
            'hash': '900/$i',
            'title': 'Track $i.mp3',
            'mediaStreamUrl': server.uri.toString(),
          }).flatten().single,
      ];
      await player.playWork(Work.fromJson({'id': 900, 'title': 'Long'}), tracks);
      final sources = audio.sources.cast<ja.UriAudioSource>();
      expect(sources, hasLength(257));
      expect(cache.activeRouteCount, 257);

      final firstUri = sources[0].uri;
      final lastUri = sources[256].uri;
      // Fetch track 0, jump to track 256, return to track 0: all 3 succeed!
      expect(await _readAll(firstUri), payload);
      await player.seekToIndex(256);
      expect(await _readAll(lastUri), payload);
      await player.seekToIndex(0);
      expect(await _readAll(firstUri), payload);

      // Replace queue with a single-track work -> old 257 routes are released and return 404.
      await player.playWork(
        Work.fromJson({'id': 901, 'title': 'Replacement'}),
        [
          TrackNode.fromJson({
            'type': 'audio',
            'hash': '901/0',
            'title': 'Single.mp3',
            'mediaStreamUrl': server.uri.toString(),
          }).flatten().single,
        ],
      );
      expect(cache.activeRouteCount, 1);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final staleReq = await client.getUrl(lastUri);
      final staleRes = await staleReq.close();
      expect(staleRes.statusCode, HttpStatus.notFound);
      await staleRes.drain<void>();
    },
  );

  test(
    'only currently playing track is marked active so finished tracks evict under budget and failed setAudioSources leaks no refs',
    () async {
      final payload = Uint8List.fromList(List.filled(60 * 1024, 3));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-active-scope-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      var clock = DateTime(2026, 2, 1, 12, 0);
      final cache = StreamAudioCache(
        directoryProvider: () async => dir,
        maxBytes: 100 * 1024, // fits 1 track (60 KB), not 2 (120 KB)
        now: () => clock,
      );
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({
        'player.streamCache': true,
        'player.autoPlayNext': true,
      });
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(() {
        player.dispose();
        settings.dispose();
      });

      final tracks = [
        for (var i = 0; i < 3; i++)
          TrackNode.fromJson({
            'type': 'audio',
            'hash': '800/$i',
            'title': '0$i.mp3',
            'mediaStreamUrl': server.uri.toString(),
          }).flatten().single,
      ];
      await player.playWork(Work.fromJson({'id': 800, 'title': 'Album'}), tracks);
      final sources = audio.sources.cast<ja.UriAudioSource>();

      // Track 0 plays and caches (60 KB).
      await _readAll(sources[0].uri);
      const key0 = AudioCacheKey(
        accountScope: 'guest',
        workId: 800,
        trackId: '800/0',
        lowQuality: false,
      );
      const key1 = AudioCacheKey(
        accountScope: 'guest',
        workId: 800,
        trackId: '800/1',
        lowQuality: false,
      );
      expect(cache.isActive(key0.id), isTrue);
      expect(cache.isActive(key1.id), isFalse);

      // Advance to track 1 -> track 0 is released and evicted once track 1 caches!
      clock = clock.add(const Duration(minutes: 5));
      await player.seekToIndex(1);
      await Future<void>.delayed(Duration.zero);
      expect(cache.isActive(key0.id), isFalse);
      expect(cache.isActive(key1.id), isTrue);
      await _readAll(sources[1].uri);
      expect(await cache.lookupComplete(key0), isNull);
      expect(await cache.lookupComplete(key1), isNotNull);
      expect(cache.cachedBytes, 60 * 1024);

      // Simulate setAudioSources failure on a fresh player -> zero leaked active refs, manual clear deletes track 1.
      await player.stop();
      final failingAudio = TestAudio()..failLoading = true;
      final failingPlayer = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: failingAudio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(failingPlayer.dispose);
      final res = await failingPlayer.playWork(
        Work.fromJson({'id': 800, 'title': 'Album'}),
        tracks,
        startIndex: 1,
      );
      expect(res.queued, 0);
      expect(cache.isActive(key1.id), isFalse);
      expect(await cache.clearAll(), 0);
      expect(cache.cachedBytes, 0);
    },
  );

  test(
    'concurrent requests for the same uncached track keep both streams intact and commit one reusable cache file',
    () async {
      final chunkA = Uint8List.fromList(List.filled(16 * 1024, 0xAA));
      final chunkB = Uint8List.fromList(List.filled(16 * 1024, 0xBB));
      final expected = Uint8List.fromList([...chunkA, ...chunkB]);

      final releaseFirst = Completer<void>();
      final firstHalfSent = Completer<void>();
      final secondHalfStarted = Completer<void>();
      var upstreamHits = 0;

      final gatedServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => gatedServer.close(force: true));
      gatedServer.listen((req) async {
        final hit = ++upstreamHits;
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
        req.response.contentLength = expected.length;
        req.response.add(chunkA);
        await req.response.flush();
        if (hit == 1) {
          firstHalfSent.complete();
          await releaseFirst.future;
        } else {
          secondHalfStarted.complete();
        }
        req.response.add(chunkB);
        await req.response.close();
      });

      final dir = await Directory.systemTemp.createTemp('asmr-concurrent-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      const key = AudioCacheKey(
        accountScope: 'guest',
        workId: 555,
        trackId: '555/0',
        lowQuality: false,
      );
      final upstreamUri = Uri.parse(
        'http://127.0.0.1:${gatedServer.port}/track.mp3',
      );
      final proxyUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: upstreamUri,
      );

      // Start request 1 (holds writer lock) and pause after first chunk.
      final f1 = _readAll(proxyUri!);
      await firstHalfSent.future;

      // Start request 2 while request 1 is still writing; request 2 finishes FIRST (pass-through).
      final f2 = _readAll(proxyUri);
      await secondHalfStarted.future;
      final bytes2 = await f2;
      expect(bytes2, expected);

      // Now let request 1 finish and commit.
      releaseFirst.complete();
      final bytes1 = await f1;
      expect(bytes1, expected);

      // Cache file is intact and next replay hits local cache via proxy with 0 upstream requests!
      final hitsBeforeReplay = upstreamHits;
      final replayUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: upstreamUri,
      );
      expect(replayUri?.scheme, 'http');
      expect(replayUri?.host, '127.0.0.1');
      expect(await _readAll(replayUri!), expected);
      expect(upstreamHits, hitsBeforeReplay);
    },
  );

  test(
    'queued cached track falls back to upstream after manual cache clear or LRU eviction without PathNotFoundException',
    () async {
      final payload1 = Uint8List.fromList(List.filled(60 * 1024, 0x11));
      final payload2 = Uint8List.fromList(List.filled(60 * 1024, 0x22));
      final server1 = _MockAudioServer(payload1);
      final server2 = _MockAudioServer(payload2);
      await server1.start();
      await server2.start();
      addTearDown(server1.close);
      addTearDown(server2.close);

      final dir = await Directory.systemTemp.createTemp('asmr-queue-evict-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      var clock = DateTime(2026, 3, 1, 10, 0);
      final cache = StreamAudioCache(
        directoryProvider: () async => dir,
        maxBytes: 100 * 1024, // fits 1 track (60 KB), evicts older when 2nd caches
        now: () => clock,
      );
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({
        'player.streamCache': true,
        'player.autoPlayNext': true,
      });
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(() {
        player.dispose();
        settings.dispose();
      });

      final tracks = [
        TrackNode.fromJson({
          'type': 'audio',
          'hash': '600/0',
          'title': '01.mp3',
          'mediaStreamUrl': server1.uri.toString(),
        }).flatten().single,
        TrackNode.fromJson({
          'type': 'audio',
          'hash': '600/1',
          'title': '02.mp3',
          'mediaStreamUrl': server2.uri.toString(),
        }).flatten().single,
      ];
      const key2 = AudioCacheKey(
        accountScope: 'guest',
        workId: 600,
        trackId: '600/1',
        lowQuality: false,
      );

      // --- Scenario A: Manual clear deletes pre-cached Track 2 while playing Track 1 ---
      final preUriA = await cache.resolvePlayableUri(
        key: key2,
        remoteUri: server2.uri,
      );
      await _readAll(preUriA!);
      expect(await cache.lookupComplete(key2), isNotNull);

      await player.playWork(Work.fromJson({'id': 600, 'title': 'Queue Clear'}), tracks);
      final sourcesA = audio.sources.cast<ja.UriAudioSource>();
      expect(sourcesA[1].uri.scheme, 'http');
      expect(sourcesA[1].uri.host, '127.0.0.1');

      // While Track 1 is active, user manually clears stream cache -> deletes Track 2's file.
      await cache.clearAll();
      expect(await cache.lookupComplete(key2), isNull);

      // Switching to Track 2 seamlessly streams from upstream instead of throwing PathNotFoundException!
      server2.resetCounts();
      await player.seekToIndex(1);
      expect(await _readAll(sourcesA[1].uri), payload2);
      expect(server2.requestCount, 1);
      expect(await cache.lookupComplete(key2), isNotNull);

      // --- Scenario B: LRU eviction deletes pre-cached Track 2 while Track 1 caches ---
      await player.stop();
      await cache.clearAll(includeActive: true);
      clock = DateTime(2026, 3, 1, 11, 0);

      // Pre-cache Track 2 at t=0.
      final preUriB = await cache.resolvePlayableUri(
        key: key2,
        remoteUri: server2.uri,
      );
      await _readAll(preUriB!);
      expect(await cache.lookupComplete(key2), isNotNull);

      // Build queue starting at Track 1; Track 1 plays and caches at t=+10m -> evicts idle Track 2!
      await player.playWork(Work.fromJson({'id': 600, 'title': 'Queue LRU'}), tracks);
      final sourcesB = audio.sources.cast<ja.UriAudioSource>();
      clock = clock.add(const Duration(minutes: 10));
      expect(await _readAll(sourcesB[0].uri), payload1);
      expect(await cache.lookupComplete(key2), isNull);

      // Switch to Track 2 -> seamlessly falls back to upstream and plays full payload2!
      server2.resetCounts();
      await player.seekToIndex(1);
      expect(await _readAll(sourcesB[1].uri), payload2);
      expect(server2.requestCount, 1);
    },
  );

  test(
    'server-confirmed anonymous session clears persisted uid:A cache scope and stops using old cache, while offline startup keeps it',
    () async {
      final cachedPayload = Uint8List.fromList(List.filled(4096, 0xAA));
      final freshPayload = Uint8List.fromList(List.filled(4096, 0xBB));
      final server = _MockAudioServer(freshPayload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-anon-scope-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      // Pre-populate uid:A's cache with cachedPayload so we can tell cache hit vs upstream.
      final seedServer = _MockAudioServer(cachedPayload);
      await seedServer.start();
      addTearDown(seedServer.close);
      const keyA = AudioCacheKey(
        accountScope: 'uid:A',
        workId: 88,
        trackId: '88/0',
        lowQuality: false,
      );
      final seedProxy = await cache.resolvePlayableUri(
        key: keyA,
        remoteUri: seedServer.uri,
      );
      await _readAll(seedProxy!);
      expect(await cache.lookupComplete(keyA), isNotNull);

      Map<String, Object?> savedSession() => {
        'playerSession': {
          'index': 0,
          'position': 0,
          'shuffle': false,
          'loop': 0,
        },
        'playerQueue': [
          {
            'workId': 88,
            'workTitle': 'Session Work',
            'title': '01.mp3',
            'hash': '88/0',
            'url': server.uri.toString(),
            'coverUrl': '',
          },
        ],
      };

      // 1. Offline cold start: fetchSession fails -> keeps uid:A offline cache!
      SharedPreferences.setMockInitialValues({
        'auth.token': 'stale-token',
        'auth.accountScope': 'uid:A',
        'player.streamCache': true,
      });
      final offlinePrefs = await AppPrefs.load();
      final offlineSettings = SettingsState(offlinePrefs);
      late PlayerState offlinePlayer;
      final offlineApi = ApiClient(
        adapter: TestAdapter((_) => throw const SocketException('offline')),
      );
      final offlineAuth = AuthState(
        offlinePrefs,
        api: offlineApi,
        onTokenChanged: () => offlinePlayer.refreshTokens(),
      );
      final offlineAudio = TestAudio();
      offlinePlayer = PlayerState(
        settings: offlineSettings,
        library: TestLibrary(),
        audioPlayer: offlineAudio,
        api: offlineApi,
        audioCache: cache,
        accountScope: () => offlineAuth.cacheAccountScope,
        readSession: (_) async => savedSession(),
      );
      await offlinePlayer.restoreSession();
      await offlineAuth.bootstrap();
      expect(offlineAuth.cacheAccountScope, 'uid:A');
      server.resetCounts();
      final offlineUri = (offlineAudio.sources.single as ja.UriAudioSource).uri;
      expect(await _readAll(offlineUri), cachedPayload);
      expect(server.requestCount, 0);
      offlinePlayer.dispose();
      offlineAuth.dispose();
      offlineSettings.dispose();

      // 2. Online cold start where server returns loggedIn=false with authEnabled=true:
      //    clears uid:A and reconfigures player queue away from uid:A cache!
      SharedPreferences.setMockInitialValues({
        'auth.token': 'stale-token',
        'auth.accountScope': 'uid:A',
        'player.streamCache': true,
      });
      final anonPrefs = await AppPrefs.load();
      final anonSettings = SettingsState(anonPrefs);
      late PlayerState anonPlayer;
      final anonApi = ApiClient(
        adapter: TestAdapter((request) {
          return jsonResponse({
            'auth': true,
            'reg': true,
            'user': {'loggedIn': false},
          });
        }),
      );
      final anonAuth = AuthState(
        anonPrefs,
        api: anonApi,
        onTokenChanged: () => anonPlayer.refreshTokens(),
      );
      final anonAudio = TestAudio();
      anonPlayer = PlayerState(
        settings: anonSettings,
        library: TestLibrary(),
        audioPlayer: anonAudio,
        api: anonApi,
        audioCache: cache,
        accountScope: () => anonAuth.cacheAccountScope,
        readSession: (_) async => savedSession(),
      );
      await anonPlayer.restoreSession();
      final oldProxyUri = (anonAudio.sources.single as ja.UriAudioSource).uri;
      expect(oldProxyUri.host, '127.0.0.1');

      await anonAuth.bootstrap();
      expect(anonAuth.cacheAccountScope, isNull);
      expect(anonPrefs.accountScope, isNull);

      // Reconfigured source no longer uses uid:A cache; reads fresh upstream payload.
      final newUri = (anonAudio.sources.single as ja.UriAudioSource).uri;
      expect(newUri, server.uri);
      server.resetCounts();
      expect(await _readAll(newUri), freshPayload);
      expect(server.requestCount, 1);

      // Old uid:A proxy route is revoked (404).
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final staleReq = await client.getUrl(oldProxyUri);
      final staleRes = await staleReq.close();
      expect(staleRes.statusCode, HttpStatus.notFound);
      await staleRes.drain<void>();

      anonPlayer.dispose();
      anonAuth.dispose();
      anonSettings.dispose();
    },
  );

  test(
    'disabling stream cache then logging out revokes old account A CDN proxy routes and stops writing to account A cache',
    () async {
      final payload = Uint8List.fromList(List.generate(8192, (i) => i & 0xff));
      final cdnServer = _MockAudioServer(payload);
      await cdnServer.start();
      addTearDown(cdnServer.close);

      final dir = await Directory.systemTemp.createTemp('asmr-disable-logout-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({
        'auth.token': 'tok-a',
        'auth.accountScope': 'uid:A',
        'player.streamCache': true,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      late PlayerState player;
      final api = ApiClient()..attachPrefs(prefs);
      final auth = AuthState(
        prefs,
        api: api,
        onTokenChanged: () => player.refreshTokens(),
      );
      final audio = TestAudio();
      player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        api: api,
        audioCache: cache,
        accountScope: () => auth.cacheAccountScope,
      );
      addTearDown(() {
        player.dispose();
        auth.dispose();
        settings.dispose();
      });

      final tracks = [
        TrackNode.fromJson({
          'type': 'audio',
          'hash': '99/0',
          'title': '01.mp3',
          'mediaStreamUrl': cdnServer.uri.toString(),
        }).flatten().single,
        TrackNode.fromJson({
          'type': 'audio',
          'hash': '99/1',
          'title': '02.mp3',
          'mediaStreamUrl': cdnServer.uri.toString(),
        }).flatten().single,
      ];
      await player.playWork(Work.fromJson({'id': 99, 'title': 'CDN Work'}), tracks);
      final oldSources = audio.sources.cast<ja.UriAudioSource>();
      final oldProxy0 = oldSources[0].uri;
      expect(oldProxy0.host, '127.0.0.1');
      expect(cache.activeRouteCount, 2);

      // Disable stream cache, then immediately log out Account A.
      settings.streamCacheEnabled = false;
      await auth.logout();

      // Existing queue is rebuilt to direct CDN URLs and old Account A proxy routes are revoked.
      expect(cache.activeRouteCount, 0);
      final updatedSources = audio.sources.cast<ja.UriAudioSource>();
      expect(updatedSources, hasLength(2));
      expect(updatedSources[0].uri, cdnServer.uri);
      expect(updatedSources[1].uri, cdnServer.uri);

      // Reading all tracks from the existing queue still plays online from CDN...
      expect(await _readAll(updatedSources[0].uri), payload);
      expect(await _readAll(updatedSources[1].uri), payload);

      // ...and ZERO files are written to Account A's cache directory!
      const keyA0 = AudioCacheKey(
        accountScope: 'uid:A',
        workId: 99,
        trackId: '99/0',
        lowQuality: false,
      );
      const keyA1 = AudioCacheKey(
        accountScope: 'uid:A',
        workId: 99,
        trackId: '99/1',
        lowQuality: false,
      );
      expect(await cache.lookupComplete(keyA0), isNull);
      expect(await cache.lookupComplete(keyA1), isNull);
      expect(await cache.refreshStats(), 0);
      expect(dir.listSync(), isEmpty);

      // Stale proxy URI returns 404 even if referenced directly.
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final staleReq = await client.getUrl(oldProxy0);
      final staleRes = await staleReq.close();
      expect(staleRes.statusCode, HttpStatus.notFound);
      await staleRes.drain<void>();
    },
  );

  test(
    'disabling cache and logging out while first proxy route is still being created cancels pending route and writes 0 files to account A',
    () async {
      final payload = Uint8List.fromList(List.generate(4096, (i) => i & 0xff));
      final cdnServer = _MockAudioServer(payload);
      await cdnServer.start();
      addTearDown(cdnServer.close);

      final dir = await Directory.systemTemp.createTemp('asmr-inflight-logout-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final dirRequested = Completer<void>();
      final allowDir = Completer<void>();
      var gatedOnce = false;
      final cache = StreamAudioCache(
        directoryProvider: () async {
          if (!gatedOnce) {
            gatedOnce = true;
            dirRequested.complete();
            await allowDir.future;
          }
          return dir;
        },
      );
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({
        'auth.token': 'tok-a',
        'auth.accountScope': 'uid:A',
        'player.streamCache': true,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      late PlayerState player;
      final api = ApiClient()..attachPrefs(prefs);
      final auth = AuthState(
        prefs,
        api: api,
        onTokenChanged: () => player.refreshTokens(),
      );
      final audio = TestAudio();
      player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        api: api,
        audioCache: cache,
        accountScope: () => auth.cacheAccountScope,
      );
      addTearDown(() {
        player.dispose();
        auth.dispose();
        settings.dispose();
      });

      final track = TrackNode.fromJson({
        'type': 'audio',
        'hash': '105/0',
        'title': '01.mp3',
        'mediaStreamUrl': cdnServer.uri.toString(),
      }).flatten().single;

      // Start playWork: pauses mid-route creation BEFORE setAudioSources is called.
      final playFuture = player.playWork(
        Work.fromJson({'id': 105, 'title': 'Inflight Work'}),
        [track],
      );
      await dirRequested.future;
      expect(audio.sources, isEmpty);

      // Disable cache and log out Account A before route creation finishes.
      settings.streamCacheEnabled = false;
      await auth.logout();

      // Let the original route creation resume and finish.
      allowDir.complete();
      final playResult = await playFuture;
      await Future<void>.delayed(Duration.zero);

      // First-play request must succeed and start playback on the direct CDN URL, with 0 writes to Account A.
      expect(playResult.queued, 1);
      expect(playResult.unplayable, 0);
      expect(player.playing, isTrue);
      expect(cache.activeRouteCount, 0);
      expect(audio.sources, hasLength(1));
      final installedUri = (audio.sources.single as ja.UriAudioSource).uri;
      expect(installedUri, cdnServer.uri);
      expect(await _readAll(installedUri), payload);
      expect(await cache.refreshStats(), 0);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'rapidly toggling stream cache preserves active playback while explicit pause during reload keeps player paused',
    () async {
      final payload = Uint8List.fromList(List.filled(4096, 0x55));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-rapid-toggle-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({'player.streamCache': true});
      final settings = SettingsState(await AppPrefs.load());
      final audio = _GatedSetSourcesAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(() {
        player.dispose();
        settings.dispose();
      });

      final track = TrackNode.fromJson({
        'type': 'audio',
        'hash': '106/0',
        'title': '01.mp3',
        'mediaStreamUrl': server.uri.toString(),
      }).flatten().single;
      await player.playWork(Work.fromJson({'id': 106, 'title': 'Toggle Work'}), [
        track,
      ]);
      expect(player.playing, isTrue);
      audio.position = const Duration(seconds: 15);

      // 1. Rapid OFF then ON while reload #1 is paused after stop(): must keep playing!
      final entered1 = Completer<void>();
      final release1 = Completer<void>();
      audio.gateNextSetSources(entered1, release1);

      settings.streamCacheEnabled = false;
      await entered1.future;
      // stop() inside reload #1 has already flipped raw playing to false.
      expect(audio.playing, isFalse);

      // Quickly turn cache back ON before reload #1 finishes.
      settings.streamCacheEnabled = true;
      release1.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(player.playing, isTrue);
      expect(audio.position, const Duration(seconds: 15));
      expect((audio.sources.single as ja.UriAudioSource).uri.host, '127.0.0.1');

      // 2. Explicit user pause during reload: must stay paused once reload finishes!
      final entered2 = Completer<void>();
      final release2 = Completer<void>();
      audio.gateNextSetSources(entered2, release2);

      settings.streamCacheEnabled = false;
      await entered2.future;
      await player.pause();
      release2.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(player.playing, isFalse);
      expect((audio.sources.single as ja.UriAudioSource).uri, server.uri);
    },
  );

  test(
    'cached local proxy serves suffix Range bytes=-N as well as open-ended and explicit ranges',
    () async {
      final payload = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-suffix-range-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      const key = AudioCacheKey(
        accountScope: 'guest',
        workId: 107,
        trackId: '107/0',
        lowQuality: false,
      );
      final proxyUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: server.uri,
      );
      // Warm cache completely.
      expect(await _readAll(proxyUri!), payload);
      expect(await cache.lookupComplete(key), isNotNull);
      server.resetCounts();

      // Suffix range bytes=-2 -> last 2 bytes [70, 80], Content-Range: bytes 6-7/8.
      final suffix2 = await _readRangeRaw(proxyUri, 'bytes=-2');
      expect(suffix2.statusCode, HttpStatus.partialContent);
      expect(suffix2.contentRange, 'bytes 6-7/8');
      expect(suffix2.body, [70, 80]);

      // Suffix range larger than file length -> full file bytes 0-7/8.
      final suffixLarge = await _readRangeRaw(proxyUri, 'bytes=-20');
      expect(suffixLarge.statusCode, HttpStatus.partialContent);
      expect(suffixLarge.contentRange, 'bytes 0-7/8');
      expect(suffixLarge.body, payload);

      // Invalid zero suffix -> 416 Range Not Satisfiable.
      final suffixZero = await _readRangeRaw(proxyUri, 'bytes=-0');
      expect(suffixZero.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(suffixZero.contentRange, 'bytes */8');

      // Open-ended range bytes=0- -> full file bytes 0-7/8.
      final openStart = await _readRangeRaw(proxyUri, 'bytes=0-');
      expect(openStart.statusCode, HttpStatus.partialContent);
      expect(openStart.contentRange, 'bytes 0-7/8');
      expect(openStart.body, payload);

      // Explicit range bytes=2-4 -> [30, 40, 50], Content-Range: bytes 2-4/8.
      final explicit = await _readRangeRaw(proxyUri, 'bytes=2-4');
      expect(explicit.statusCode, HttpStatus.partialContent);
      expect(explicit.contentRange, 'bytes 2-4/8');
      expect(explicit.body, [30, 40, 50]);

      // All served from local cache with 0 upstream requests.
      expect(server.requestCount, 0);
    },
  );

  test(
    'seeking twice during source reload preserves final target position and latest play/pause state in both playing and paused modes',
    () async {
      final payload = Uint8List.fromList(List.filled(4096, 0x33));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-reload-seek-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({'player.streamCache': true});
      final settings = SettingsState(await AppPrefs.load());
      final audio = _GatedSetSourcesAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(() {
        player.dispose();
        settings.dispose();
      });

      final track = TrackNode.fromJson({
        'type': 'audio',
        'hash': '108/0',
        'title': '01.mp3',
        'mediaStreamUrl': server.uri.toString(),
      }).flatten().single;
      await player.playWork(Work.fromJson({'id': 108, 'title': 'Seek Work'}), [
        track,
      ]);
      expect(player.playing, isTrue);

      // 1. Playing at 15s -> toggle cache -> seek twice (25s -> 36s) and stay playing.
      audio.position = const Duration(seconds: 15);
      final entered1 = Completer<void>();
      final release1 = Completer<void>();
      audio.gateNextSetSources(entered1, release1);

      settings.streamCacheEnabled = false;
      await entered1.future;
      await player.seek(const Duration(seconds: 25));
      await player.seek(const Duration(seconds: 36));
      release1.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(player.playing, isTrue);
      expect(audio.position, const Duration(seconds: 36));

      // 2. Playing at 15s -> toggle cache -> seek twice (28s -> 41s) and pause during reload.
      audio.position = const Duration(seconds: 15);
      final entered2 = Completer<void>();
      final release2 = Completer<void>();
      audio.gateNextSetSources(entered2, release2);

      settings.streamCacheEnabled = true;
      await entered2.future;
      await player.seek(const Duration(seconds: 28));
      await player.seek(const Duration(seconds: 41));
      await player.pause();
      release2.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(player.playing, isFalse);
      expect(audio.position, const Duration(seconds: 41));

      // 3. Paused at 15s -> toggle cache -> seek twice (22s -> 44s) -> stays paused at 44s.
      audio.position = const Duration(seconds: 15);
      final entered3 = Completer<void>();
      final release3 = Completer<void>();
      audio.gateNextSetSources(entered3, release3);

      settings.streamCacheEnabled = false;
      await entered3.future;
      await player.seek(const Duration(seconds: 22));
      await player.seek(const Duration(seconds: 44));
      release3.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(player.playing, isFalse);
      expect(audio.position, const Duration(seconds: 44));

      // 4. Paused at 15s -> toggle cache -> seek twice (20s -> 48s) and resume via toggle().
      audio.position = const Duration(seconds: 15);
      final entered4 = Completer<void>();
      final release4 = Completer<void>();
      audio.gateNextSetSources(entered4, release4);

      settings.streamCacheEnabled = true;
      await entered4.future;
      await player.seek(const Duration(seconds: 20));
      await player.seek(const Duration(seconds: 48));
      await player.toggle();
      release4.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(player.playing, isTrue);
      expect(audio.position, const Duration(seconds: 48));
    },
  );
}
