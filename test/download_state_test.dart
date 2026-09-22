import 'dart:async';
import 'dart:io';

import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/screens/downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class DownloadLibrary extends ChangeNotifier implements LibraryState {
  final rows = <DownloadRow>[];
  @override
  List<DownloadRow> get downloads => rows;
  @override
  int get downloadBytes => rows.fold(0, (sum, row) => sum + row.size);
  @override
  List<Work> get favorites => const [];
  @override
  List<Work> get history => const [];
  Completer<void>? saving;
  @override
  Future<Map<String, String>> downloadedPaths(int workId) async => {};
  @override
  Future<void> saveDownload(DownloadRow row) async {
    if (saving != null) await saving!.future;
    rows.add(row);
  }

  @override
  Future<List<DownloadRow>> downloadsFor(int workId) async =>
      rows.where((r) => r.workId == workId).toList();
  @override
  Future<void> deleteDownloadsOfWork(int workId) async =>
      rows.removeWhere((r) => r.workId == workId);
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
  testWidgets('downloaded work has play button without favorites or history', (
    tester,
  ) async {
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
        ],
        child: const MaterialApp(home: DownloadsScreen()),
      ),
    );
    expect(find.text('Offline work'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
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
}
