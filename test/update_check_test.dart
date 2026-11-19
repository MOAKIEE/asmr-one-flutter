import 'dart:async';
import 'dart:convert';

import 'package:asmr_one/core/api/update_client.dart';
import 'package:asmr_one/core/app_info.dart';
import 'package:asmr_one/core/models/release.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/l10n/app_localizations.dart';
import 'package:asmr_one/screens/library_screen.dart';
import 'package:asmr_one/screens/root_shell.dart';
import 'package:asmr_one/screens/settings_screen.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/state/update_state.dart';
import 'package:asmr_one/widgets/update_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client_test.dart' show TestAdapter, jsonResponse;
import 'app_navigation_test.dart' show ShellLibrary;
import 'player_state_test.dart' show TestAudio;

class _AsyncTestAdapter implements HttpClientAdapter {
  _AsyncTestAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _releaseJson({
  String tag = 'v1.3.0',
  String htmlUrl = 'https://github.com/MOAKIEE/asmr-one-flutter/releases/tag/v1.3.0',
  String body = '## 更新\n- 支持 **检查更新** 与 `arm64-v8a` 直链。',
  bool draft = false,
  List<Map<String, dynamic>>? assets,
}) => {
  'tag_name': tag,
  'name': '$tag Release',
  'html_url': htmlUrl,
  'published_at': '2026-11-19T08:00:00Z',
  'prerelease': false,
  'draft': draft,
  'body': body,
  'assets':
      assets ??
      [
        {
          'name': 'SHA256SUMS.txt',
          'size': 320,
          'browser_download_url':
              'https://github.com/MOAKIEE/asmr-one-flutter/releases/download/$tag/SHA256SUMS.txt',
        },
        {
          'name': 'app-x86_64-release.apk',
          'size': 23000000,
          'browser_download_url':
              'https://github.com/MOAKIEE/asmr-one-flutter/releases/download/$tag/app-x86_64-release.apk',
        },
        {
          'name': 'app-armeabi-v7a-release.apk',
          'size': 19000000,
          'browser_download_url':
              'https://github.com/MOAKIEE/asmr-one-flutter/releases/download/$tag/app-armeabi-v7a-release.apk',
        },
        {
          'name': 'app-release.apk',
          'size': 60000000,
          'browser_download_url':
              'https://github.com/MOAKIEE/asmr-one-flutter/releases/download/$tag/app-release.apk',
        },
        {
          'name': 'app-arm64-v8a-release.apk',
          'size': 21000000,
          'browser_download_url':
              'https://github.com/MOAKIEE/asmr-one-flutter/releases/download/$tag/app-arm64-v8a-release.apk',
        },
      ],
};

Widget _wrapApp({
  required SettingsState settings,
  required AuthState auth,
  required LibraryState library,
  required DownloadState downloads,
  required PlayerState player,
  required UpdateState updates,
  required Widget home,
  double textScale = 1.0,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsState>.value(value: settings),
      ChangeNotifierProvider<AuthState>.value(value: auth),
      ChangeNotifierProvider<LibraryState>.value(value: library),
      ChangeNotifierProvider<DownloadState>.value(value: downloads),
      ChangeNotifierProvider<PlayerState>.value(value: player),
      ChangeNotifierProvider<UpdateState>.value(value: updates),
    ],
    child: MaterialApp(
      locale: settings.locale,
      theme: settings.themeFor(Brightness.light),
      darkTheme: settings.themeFor(Brightness.dark),
      themeMode: settings.themeMode,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

void main() {
  group('AppVersion & ReleaseInfo', () {
    test('compares semantic versions with v prefix, build metadata and prerelease', () {
      expect(AppVersion.isNewer(latest: 'v1.2.1', current: '1.2.0'), isTrue);
      expect(AppVersion.isNewer(latest: 'v1.2.10', current: '1.2.2'), isTrue);
      expect(AppVersion.isNewer(latest: 'v2.0.0', current: '1.9.9'), isTrue);
      expect(AppVersion.isNewer(latest: 'v1.2.0', current: '1.2.0+3'), isFalse);
      expect(AppVersion.isNewer(latest: '1.2', current: '1.2.0'), isFalse);
      expect(AppVersion.isNewer(latest: 'v1.1.9', current: '1.2.0'), isFalse);
      expect(
        AppVersion.isNewer(latest: 'v1.3.0', current: '1.3.0-rc.1'),
        isTrue,
      );
      expect(
        AppVersion.isNewer(latest: 'v1.3.0-beta.10', current: '1.3.0-beta.2'),
        isTrue,
      );
      expect(
        AppVersion.isNewer(latest: 'v1.3.0-rc.1', current: '1.3.0-beta.9'),
        isTrue,
      );
      expect(
        AppVersion.isNewer(latest: 'v1.2.0', current: '1.3.0-beta.1'),
        isFalse,
      );
      expect(AppVersion.isNewer(latest: 'invalid', current: '1.2.0'), isFalse);
      expect(AppVersion.isNewer(latest: 'v1.3.0', current: 'bad'), isFalse);
      expect(AppVersion.normalizeLabel('v1.2.0+3'), '1.2.0');
    });

    test('sanitizes GitHub URLs and orders APK assets by recommendation', () {
      expect(
        sanitizeGitHubUrl('https://github.com/MOAKIEE/asmr-one-flutter'),
        'https://github.com/MOAKIEE/asmr-one-flutter',
      );
      expect(
        sanitizeGitHubUrl('https://objects.githubusercontent.com/file.apk'),
        'https://objects.githubusercontent.com/file.apk',
      );
      expect(sanitizeGitHubUrl('http://github.com/MOAKIEE/asmr-one-flutter'), isNull);
      expect(sanitizeGitHubUrl('javascript:alert(1)'), isNull);
      expect(sanitizeGitHubUrl('https://evil.example/github.com'), isNull);
      expect(sanitizeGitHubUrl('https://user@github.com/repo'), isNull);

      final release = ReleaseInfo.tryFromJson(
        _releaseJson(htmlUrl: 'https://evil.example/phish'),
      )!;
      expect(release.htmlUrl, AppInfo.releasesUrl);
      expect(release.apkAssets.map((a) => a.name).toList(), [
        'app-arm64-v8a-release.apk',
        'app-release.apk',
        'app-armeabi-v7a-release.apk',
        'app-x86_64-release.apk',
      ]);
      expect(release.apkAssets.first.isRecommendedApk, isTrue);
      expect(release.apkAssets[1].isRecommendedApk, isFalse);

      expect(ReleaseInfo.tryFromJson(_releaseJson(draft: true)), isNull);
    });
  });

  group('UpdateClient', () {
    test('parses latest release and sends GitHub headers', () async {
      final adapter = TestAdapter((_) => jsonResponse(_releaseJson()));
      final client = UpdateClient(adapter: adapter);

      final release = await client.fetchLatestRelease();
      expect(release, isNotNull);
      expect(release!.tagName, 'v1.3.0');
      expect(release.versionTag, 'v1.3.0');
      final request = adapter.requests.single;
      expect(request.uri.toString(), AppInfo.latestReleaseApiUrl);
      expect(request.headers['User-Agent'], AppInfo.repoName);
      expect(request.headers['Accept'], 'application/vnd.github+json');
    });

    test('treats 404 as no published release', () async {
      final adapter = TestAdapter(
        (_) => jsonResponse({'message': 'Not Found'}, statusCode: 404),
      );
      final client = UpdateClient(adapter: adapter);
      expect(await client.fetchLatestRelease(), isNull);
    });

    test('classifies rate limit, network error and invalid response', () async {
      final rateLimitAdapter = TestAdapter(
        (_) => ResponseBody.fromString(
          jsonEncode({'message': 'API rate limit exceeded'}),
          403,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            'x-ratelimit-remaining': ['0'],
          },
        ),
      );
      await expectLater(
        UpdateClient(adapter: rateLimitAdapter).fetchLatestRelease(),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.kind,
            'kind',
            UpdateErrorKind.rateLimited,
          ),
        ),
      );

      final invalidAdapter = TestAdapter((_) => jsonResponse({'foo': 'bar'}));
      await expectLater(
        UpdateClient(adapter: invalidAdapter).fetchLatestRelease(),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.kind,
            'kind',
            UpdateErrorKind.invalidResponse,
          ),
        ),
      );

      final networkAdapter = _AsyncTestAdapter(
        (options) => Future<ResponseBody>.error(
          DioException.connectionError(
            requestOptions: options,
            reason: 'offline',
          ),
        ),
      );
      await expectLater(
        UpdateClient(adapter: networkAdapter).fetchLatestRelease(),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.kind,
            'kind',
            UpdateErrorKind.network,
          ),
        ),
      );
    });
  });

  group('UpdateState', () {
    test('respects autoCheck toggle, cooldown and ignored version', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPrefs.load();
      var now = DateTime(2026, 11, 19, 10, 0);
      var tag = 'v1.3.0';
      final adapter = TestAdapter((_) => jsonResponse(_releaseJson(tag: tag)));
      final state = UpdateState(
        prefs,
        client: UpdateClient(adapter: adapter),
        versionLoader: () async => '1.2.0',
        now: () => now,
      );

      // 关闭自动检查时跳过静默检查。
      state.autoCheckUpdate = false;
      expect(await state.checkForUpdates(), UpdateCheckOutcome.skipped);
      expect(adapter.requests, isEmpty);

      // 开启后首次自动检查拉取成功。
      state.autoCheckUpdate = true;
      expect(await state.checkForUpdates(), UpdateCheckOutcome.available);
      expect(state.hasUpdate, isTrue);
      expect(state.hasUnignoredUpdate, isTrue);
      expect(state.shouldAutoPrompt, isTrue);
      expect(adapter.requests, hasLength(1));

      // 冷却期内再次静默检查跳过。
      now = now.add(const Duration(hours: 2));
      expect(await state.checkForUpdates(), UpdateCheckOutcome.skipped);
      expect(adapter.requests, hasLength(1));

      // 忽略 v1.3.0 后不再自动提示。
      await state.ignoreRelease('v1.3.0');
      expect(state.hasUpdate, isTrue);
      expect(state.hasUnignoredUpdate, isFalse);
      expect(state.shouldAutoPrompt, isFalse);

      // 超过冷却期并发布更高版本 v1.4.0 时，重新有未忽略更新。
      now = now.add(const Duration(hours: 6));
      tag = 'v1.4.0';
      expect(await state.checkForUpdates(), UpdateCheckOutcome.available);
      expect(state.hasUnignoredUpdate, isTrue);
      state.dispose();
    });

    test('deduplicates concurrent checks and keeps silent failures quiet', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPrefs.load();
      final started = Completer<void>();
      final completer = Completer<ResponseBody>();
      final adapter = _AsyncTestAdapter((_) {
        if (!started.isCompleted) started.complete();
        return completer.future;
      });
      final state = UpdateState(
        prefs,
        client: UpdateClient(adapter: adapter),
        initialVersion: '1.2.0',
      );

      final first = state.checkForUpdates();
      final second = state.checkForUpdates();
      expect(identical(first, second), isTrue);
      await started.future;
      expect(adapter.requests, hasLength(1));

      completer.completeError(
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/'),
          reason: 'offline',
        ),
      );
      expect(await first, UpdateCheckOutcome.failed);
      // 纯静默检查失败不污染为 error 态。
      expect(state.status, UpdateStatus.idle);
      state.dispose();
    });
  });

  test('new settings and update l10n keys are translated in all 3 locales', () {
    final zh = L10n.forLocale(const Locale('zh', 'CN'));
    final ja = L10n.forLocale(const Locale('ja', 'JP'));
    final en = L10n.forLocale(const Locale('en', 'US'));

    for (final key in [
      'settings.themeAndColor',
      'settings.contentAndNetwork',
      'settings.lineAutoShort',
      'settings.checkUpdate',
      'settings.checkingUpdate',
      'settings.autoCheckUpdate',
      'settings.githubRepo',
      'update.availableTitle',
      'update.foundShort',
      'update.publishedAt',
      'update.changelog',
      'update.noChangelog',
      'update.apkDownloads',
      'update.recommended',
      'update.openRelease',
      'update.openReleasesPage',
      'update.ignoreVersion',
      'update.later',
      'update.upToDate',
      'update.upToDateDetail',
      'update.errorNetwork',
      'update.errorRateLimited',
      'update.errorFailed',
    ]) {
      expect(zh(key), isNot(key), reason: 'zh missing $key');
      expect(ja(key), isNot(key), reason: 'ja missing $key');
      expect(en(key), isNot(key), reason: 'en missing $key');
      expect(en(key), isNot(zh(key)), reason: 'en same as zh for $key');
    }
  });

  testWidgets(
    'refactored SettingsScreen supports appearance/language/grid/line sheets, update checks and GitHub link',
    (tester) async {
      final launchedUrls = <String>[];
      const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlChannel, (call) async {
            final args = call.arguments as Map<Object?, Object?>?;
            if (args != null && args['url'] is String) {
              launchedUrls.add(args['url']! as String);
            }
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlChannel, null);
      });

      SharedPreferences.setMockInitialValues({
        'ui.locale': 'zh-CN',
        'ui.themeMode': 'dark',
        'ui.useCoverAccent': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final library = ShellLibrary();
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );

      var remoteTag = 'v1.2.0';
      final adapter = TestAdapter(
        (_) => jsonResponse(_releaseJson(tag: remoteTag)),
      );
      final updates = UpdateState(
        prefs,
        client: UpdateClient(adapter: adapter),
        initialVersion: '1.2.0',
      );

      await tester.pumpWidget(
        _wrapApp(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          updates: updates,
          home: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1) 外观面板修改主题模式
      await tester.tap(find.text('主题与配色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.light);
      Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
      await tester.pumpAndSettle();

      // 2) 每行列数面板修改列数
      await tester.tap(find.text('每行列数 · 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(settings.gridColumns, 3);
      expect(find.text('每行列数 · 3'), findsOneWidget);

      // 3) 滚动到关于：检查更新（已是最新版本）
      await tester.scrollUntilVisible(
        find.text('GitHub 仓库'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('当前已是最新版本（v1.2.0）'), findsOneWidget);

      // 4) 远端发布 v1.3.0 后再点检查更新，弹出更新面板并测试忽略此版本
      remoteTag = 'v1.3.0';
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsWidgets);
      expect(find.text('app-arm64-v8a-release.apk'), findsOneWidget);
      await tester.tap(find.text('前往 GitHub 下载'));
      await tester.pumpAndSettle();
      expect(
        launchedUrls,
        contains(
          'https://github.com/MOAKIEE/asmr-one-flutter/releases/tag/v1.3.0',
        ),
      );
      await tester.tap(find.text('忽略此版本'));
      await tester.pumpAndSettle();
      expect(updates.ignoredVersion, '1.3.0');

      // 5) 点击 GitHub 仓库打开正确链接
      await tester.tap(find.text('GitHub 仓库'));
      await tester.pumpAndSettle();
      expect(launchedUrls, contains(AppInfo.repoUrl));

      await tester.pumpWidget(const SizedBox());
      updates.dispose();
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'LibraryScreen shows update banner, GitHub link and clipboard fallback when launch fails',
    (tester) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = (call.arguments as Map<Object?, Object?>)['text']
                  as String?;
            }
            return null;
          });
      const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlChannel, (_) async => false);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlChannel, null);
      });

      SharedPreferences.setMockInitialValues({'ui.locale': 'zh-CN'});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final library = ShellLibrary();
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );
      final adapter = TestAdapter((_) => jsonResponse(_releaseJson()));
      final updates = UpdateState(
        prefs,
        client: UpdateClient(adapter: adapter),
        initialVersion: '1.2.0',
      );
      await tester.runAsync(() => updates.checkForUpdates(manual: true));

      await tester.pumpWidget(
        _wrapApp(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          updates: updates,
          home: const LibraryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('GitHub · ${AppInfo.repoSlug}'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.3.0'), findsOneWidget);
      expect(find.text('GitHub · ${AppInfo.repoSlug}'), findsOneWidget);

      await tester.tap(find.text('GitHub · ${AppInfo.repoSlug}'));
      await tester.pumpAndSettle();
      expect(copiedText, AppInfo.repoUrl);
      expect(find.text('已复制到剪贴板'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      updates.dispose();
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'RootShell prompts update sheet once on launch and UpdateSheet fits 360x640 at 1.35x without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'ui.locale': 'zh-CN',
        'ui.useCoverAccent': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final library = ShellLibrary();
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );
      final adapter = TestAdapter((_) => jsonResponse(_releaseJson()));
      final updates = UpdateState(
        prefs,
        client: UpdateClient(adapter: adapter),
        initialVersion: '1.2.0',
      );

      await tester.pumpWidget(
        _wrapApp(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          updates: updates,
          textScale: 1.35,
          home: const RootShell(),
        ),
      );
      await tester.pump();

      await tester.runAsync(() => updates.checkForUpdates());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(UpdateSheet), findsOneWidget);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('稍后再说'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(UpdateSheet), findsNothing);
      // 本次会话已提示过，不再重复自动弹出。
      expect(updates.shouldAutoPrompt, isFalse);

      await tester.pumpWidget(const SizedBox());
      updates.dispose();
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
