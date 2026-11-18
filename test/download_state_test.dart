import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:asmr_one/core/api/resumable_download.dart';
import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/screens/downloads_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadLibrary extends ChangeNotifier implements LibraryState {
  final rows = <DownloadRow>[];
  int _nextId = 1;
  @override
  List<DownloadRow> get downloads => rows;
  @override
  int get downloadBytes => rows.fold(0, (sum, row) => sum + row.size);
  @override
  List<Work> get favorites => const [];
  @override
  List<Work> get history => const [];
  Completer<void>? saving;
  final Map<int, Map<String, String>> pathsByWork = {};
  final Map<int, int> downloadedPathQueries = {};
  @override
  Future<Map<String, String>> downloadedPaths(int workId) async {
    downloadedPathQueries[workId] = (downloadedPathQueries[workId] ?? 0) + 1;
    return pathsByWork[workId] ?? {};
  }
  @override
  Future<void> saveDownload(DownloadRow row) async {
    if (saving != null) await saving!.future;
    rows.add(DownloadRow.fromMap({...row.toMap(), 'id': _nextId++}));
  }

  @override
  Future<List<DownloadRow>> downloadsFor(int workId) async =>
      rows.where((r) => r.workId == workId).toList();
  @override
  Future<void> refreshDownloads() async {}
  @override
  Future<void> deleteDownloads(Iterable<int> ids) async {
    rows.removeWhere((r) => ids.contains(r.id));
    notifyListeners();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<AudioTrack> tracks() => ['a', 'b']
    .map(
      (hash) => TrackNode.fromJson({
        'type': 'audio',
        'title': '$hash.mp3',
        'hash': hash,
        'mediaDownloadUrl': 'https://example.invalid/$hash',
      }).flatten().single,
    )
    .toList();

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 1000; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for download state');
}

void main() {
  test(
    'restored queue waits for Wi-Fi and preserves manually paused tasks',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'asmr-restore-download-',
      );
      final network = StreamController<List<ConnectivityResult>>.broadcast();
      final library = DownloadLibrary();
      Object? saved;
      final state = DownloadState(
        library,
        readQueue: () async => {
          'wifiOnly': true,
          'tasks': [
            for (final hash in ['a', 'b'])
              {
                'workId': 1,
                'workTitle': 'Work',
                'hash': hash,
                'title': '$hash.mp3',
                'url': 'https://example.invalid/$hash',
                'duration': 10,
                'trackIndex': 0,
                'folderLabel': '',
                'status': hash == 'a' ? 'running' : 'paused',
              },
          ],
        },
        writeQueue: (value) async {
          saved = value;
        },
        checkNetwork: () async => [ConnectivityResult.mobile],
        networkChanges: network.stream,
        workDirectory: (_) async => dir,
        downloadFile:
            ({required url, required savePath, cancelToken, onProgress}) async {
              await File(savePath).writeAsBytes([1, 2, 3]);
            },
      );
      await state.initialize();
      expect(state.waitingForWifi, isTrue);
      expect(state.tasks.first.status, DownloadStatus.queued);
      expect(library.rows, isEmpty);
      network.add([ConnectivityResult.wifi]);
      await until(() => library.rows.length == 1 && state.current == null);
      expect(state.tasks.last.status, DownloadStatus.paused);
      expect((saved as Map)['tasks'], hasLength(1));
      state.dispose();
      await network.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'clearAll cancels active and queued downloads and removes partial bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('asmr-clear-download-');
      final library = DownloadLibrary();
      final started = Completer<void>();
      final state = DownloadState(
        library,
        workDirectory: (_) async => dir,
        downloadFile:
            ({required url, required savePath, cancelToken, onProgress}) async {
              await File('$savePath.part').writeAsBytes([1]);
              started.complete();
              await cancelToken!.whenCancel;
            },
      );
      await state.enqueueWork(Work.fromJson({'id': 1}), tracks());
      await started.future;
      await state.clearAll();
      expect(library.rows, isEmpty);
      expect(state.tasks, isEmpty);
      expect(await dir.list().toList(), isEmpty);
      state.dispose();
      await dir.delete(recursive: true);
    },
  );
  testWidgets('downloaded work has play button without favorites or history', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsState(await AppPrefs.load());
    final library = DownloadLibrary();
    library.rows.add(
      DownloadRow(
        workId: 1,
        workTitle: 'Offline work',
        hash: 'a',
        title: 'a.mp3',
        filePath: '/a.mp3',
      ),
    );
    final state = DownloadState(library);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryState>.value(value: library),
          ChangeNotifierProvider<DownloadState>.value(value: state),
          ChangeNotifierProvider<SettingsState>.value(value: settings),
        ],
        child: const MaterialApp(home: DownloadsScreen()),
      ),
    );
    expect(find.text('Offline work'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    state.dispose();
    library.dispose();
  });
  test('cancelling queued B leaves running A untouched', () async {
    final dir = await Directory.systemTemp.createTemp('asmr-download-test-');
    final library = DownloadLibrary();
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final state = DownloadState(
      library,
      workDirectory: (_) async => dir,
      downloadFile:
          ({required url, required savePath, cancelToken, onProgress}) async {
            calls++;
            started.complete();
            await release.future;
            expect(cancelToken!.isCancelled, isFalse);
            await File(savePath).writeAsBytes([1, 2, 3]);
          },
    );
    await state.enqueueWork(Work.fromJson({'id': 1}), tracks());
    await started.future;
    state.cancel(state.tasks.last);
    expect(state.tasks.first.status, DownloadStatus.running);
    expect(state.tasks.last.status, DownloadStatus.cancelled);
    release.complete();
    await until(() => state.current == null);
    expect(calls, 1);
    expect(library.rows, hasLength(1));
    state.dispose();
    await dir.delete(recursive: true);
  });

  test(
    'delete waits for in-flight database write and removes all files',
    () async {
      final dir = await Directory.systemTemp.createTemp('asmr-download-test-');
      final library = DownloadLibrary()..saving = Completer<void>();
      final state = DownloadState(
        library,
        workDirectory: (_) async => dir,
        downloadFile:
            ({required url, required savePath, cancelToken, onProgress}) async {
              await File(savePath).writeAsBytes([1, 2, 3]);
            },
      );
      await state.enqueueWork(Work.fromJson({'id': 1}), tracks());
      await until(() => state.tasks.first.status == DownloadStatus.done);
      final deleting = state.deleteWorkFiles(1);
      library.saving!.complete();
      await deleting;
      expect(library.rows, isEmpty);
      expect(state.tasks, isEmpty);
      expect(await dir.list().toList(), isEmpty);
      state.dispose();
      await dir.delete(recursive: true);
    },
  );

  test('delete cancels a transfer and discards its partial file', () async {
    final dir = await Directory.systemTemp.createTemp('asmr-download-test-');
    final library = DownloadLibrary();
    final started = Completer<void>();
    final state = DownloadState(
      library,
      workDirectory: (_) async => dir,
      downloadFile:
          ({required url, required savePath, cancelToken, onProgress}) async {
            await File(savePath).writeAsBytes([1]);
            started.complete();
            await cancelToken!.whenCancel;
          },
    );
    await state.enqueueWork(Work.fromJson({'id': 1}), tracks());
    await started.future;
    await state.deleteWorkFiles(1);
    expect(library.rows, isEmpty);
    expect(state.tasks, isEmpty);
    expect(await dir.list().toList(), isEmpty);
    state.dispose();
    await dir.delete(recursive: true);
  });

  test(
    'consecutive 416 responses fail the download task with no saved file or record',
    () async {
      final dir = await Directory.systemTemp.createTemp('asmr-dl-416-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = 416;
        const body = 'Range Not Satisfiable';
        req.response.headers.contentLength = body.length;
        req.response.write(body);
        await req.response.close();
      });

      final dio = Dio();
      final library = DownloadLibrary();
      final saveName = '1_a_a.mp3';
      await File('${dir.path}/$saveName.part').writeAsString('stale');
      await File('${dir.path}/$saveName.validator').writeAsString('"v1"');

      final state = DownloadState(
        library,
        workDirectory: (_) async => dir,
        downloadFile: ({required url, required savePath, cancelToken, onProgress}) =>
            ResumableDownload(dio).download(
              url: url,
              savePath: savePath,
              cancelToken: cancelToken,
              onProgress: onProgress,
            ),
      );
      final track = TrackNode.fromJson({
        'type': 'audio',
        'title': 'a.mp3',
        'hash': '1/a',
        'mediaDownloadUrl': 'http://127.0.0.1:${server.port}/a.mp3',
      }).flatten().single;

      await state.enqueueWork(Work.fromJson({'id': 1, 'title': 'Work'}), [track]);
      await until(() => state.tasks.single.status == DownloadStatus.failed);

      expect(state.tasks.single.status, DownloadStatus.failed);
      expect(library.rows, isEmpty);
      expect(await File('${dir.path}/$saveName').exists(), isFalse);

      state.dispose();
      dio.close();
      await server.close(force: true);
      await dir.delete(recursive: true);
    },
  );

  test(
    'restore caches downloadedPaths per workId and enqueueWork preserves loop trackIndex',
    () async {
      final dir = await Directory.systemTemp.createTemp('asmr-dl-restore-');
      final library = DownloadLibrary()
        ..pathsByWork[1] = {'1/0': '${dir.path}/0.mp3'}
        ..pathsByWork[2] = {};
      final state = DownloadState(
        library,
        readQueue: () async => {
          'wifiOnly': false,
          'tasks': [
            {
              'workId': 1,
              'workTitle': 'Work 1',
              'hash': '1/0',
              'title': '0.mp3',
              'url': 'https://example.invalid/0',
              'duration': 10,
              'trackIndex': 0,
              'folderLabel': '',
              'status': 'paused',
            },
            {
              'workId': 1,
              'workTitle': 'Work 1',
              'hash': '1/1',
              'title': '1.mp3',
              'url': 'https://example.invalid/1',
              'duration': 10,
              'trackIndex': 1,
              'folderLabel': '',
              'status': 'paused',
            },
            {
              'workId': 2,
              'workTitle': 'Work 2',
              'hash': '2/0',
              'title': '2_0.mp3',
              'url': 'https://example.invalid/2_0',
              'duration': 10,
              'trackIndex': 0,
              'folderLabel': '',
              'status': 'paused',
            },
            {
              'workId': 1,
              'workTitle': 'Work 1',
              'hash': '1/2',
              'title': '2.mp3',
              'url': 'https://example.invalid/2',
              'duration': 10,
              'trackIndex': 2,
              'folderLabel': '',
              'status': 'paused',
            },
          ],
        },
        workDirectory: (_) async => dir,
        checkNetwork: () async => [ConnectivityResult.wifi],
      );

      await state.initialize();
      expect(library.downloadedPathQueries, {1: 1, 2: 1});
      expect(state.tasks.map((t) => t.hash), ['1/1', '2/0', '1/2']);

      // enqueueWork 跳过不可下载项后仍保留原始循环索引
      final mixedTracks = [
        TrackNode.fromJson({'type': 'audio', 'title': 'no_hash.mp3'}).flatten().single,
        TrackNode.fromJson({
          'type': 'audio',
          'title': 'ok.mp3',
          'hash': '3/1',
          'mediaDownloadUrl': 'https://example.invalid/3_1',
        }).flatten().single,
      ];
      final result = await state.enqueueWork(
        Work.fromJson({'id': 3, 'title': 'Work 3'}),
        mixedTracks,
      );
      expect(result.queued, 1);
      expect(result.skipped, 1);
      expect(state.tasks.last.trackIndex, 1);

      state.dispose();
      await dir.delete(recursive: true);
    },
  );
}
