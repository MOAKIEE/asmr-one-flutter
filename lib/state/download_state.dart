import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/api/api_client.dart';
import '../core/models/track.dart';
import '../core/models/work.dart';
import '../core/storage/library_db.dart';
import '../core/utils/formatters.dart';
import 'library_state.dart';

enum DownloadStatus { queued, running, done, failed, cancelled }

typedef DownloadFile = Future<void> Function({
  required String url,
  required String savePath,
  CancelToken? cancelToken,
  void Function(int received, int total)? onProgress,
});

/// 单个音频的下载任务。
class DownloadTask {
  DownloadTask({
    required this.workId,
    required this.workTitle,
    required this.hash,
    required this.title,
    required this.url,
    this.duration = 0,
  });

  final int workId;
  final String workTitle;
  final String hash;
  final String title;
  final String url;
  final double duration;

  DownloadStatus status = DownloadStatus.queued;
  double progress = 0;
  int received = 0;
  int total = 0;
  String? filePath;
  String? error;

  String get key => hash;

  bool get isActive =>
      status == DownloadStatus.running || status == DownloadStatus.queued;
}

/// 下载管理器：串行下载、进度回调、落库与本地文件管理。
class DownloadState extends ChangeNotifier {
  DownloadState(
    this._library, {
    DownloadFile? downloadFile,
    Future<Directory> Function(int)? workDirectory,
  }) : _downloadFile = downloadFile ?? ApiClient.instance.downloadRaw,
       _workDirectory = workDirectory ?? _workDir;

  final LibraryState _library;
  final ApiClient _api = ApiClient.instance;
  final DownloadFile _downloadFile;
  final Future<Directory> Function(int) _workDirectory;
  final Set<int> _deletingWorks = {};
  Completer<void>? _currentFinished;

  final Map<String, DownloadTask> _tasks = {};
  bool _running = false;
  CancelToken? _cancelToken;
  DownloadTask? _current;

  List<DownloadTask> get tasks => _tasks.values.toList(growable: false);
  DownloadTask? get current => _current;
  bool get hasActive => _tasks.values.any(
    (t) =>
        t.status == DownloadStatus.running || t.status == DownloadStatus.queued,
  );
  int get activeCount => _tasks.values.where((t) => t.isActive).length;

  List<DownloadTask> tasksOf(int workId) =>
      _tasks.values.where((t) => t.workId == workId).toList();

  void clearFinished() {
    _tasks.removeWhere(
      (_, t) =>
          t.status == DownloadStatus.done ||
          t.status == DownloadStatus.failed ||
          t.status == DownloadStatus.cancelled,
    );
    notifyListeners();
  }

  /// 把整个作品的曲目加入下载队列。
  ///
  /// 返回 `({queued, skipped})`：`skipped` 为已下载或无法解析地址的曲目数。
  Future<({int queued, int skipped})> enqueueWork(
    Work work,
    List<AudioTrack> tracks,
  ) async {
    var queued = 0;
    var skipped = 0;
    final existing = await _library.downloadedPaths(work.id);
    if (_deletingWorks.contains(work.id)) {
      return (queued: 0, skipped: tracks.length);
    }

    for (final t in tracks) {
      final hash = t.hash;
      if (hash == null || hash.isEmpty) {
        skipped++;
        continue;
      }
      if (existing.containsKey(hash)) {
        skipped++;
        continue;
      }
      final url = _api.resolveDownloadUrl(t.node);
      if (url == null || url.isEmpty) {
        skipped++;
        continue;
      }
      if (_tasks.containsKey(hash)) {
        skipped++;
        continue;
      }
      _tasks[hash] = DownloadTask(
        workId: work.id,
        workTitle: work.title,
        hash: hash,
        title: t.title,
        url: url,
        duration: t.duration,
      );
      queued++;
    }

    notifyListeners();
    if (queued > 0) unawaited(_pump());
    return (queued: queued, skipped: skipped);
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        DownloadTask? next;
        for (final t in _tasks.values) {
          if (t.status == DownloadStatus.queued) {
            next = t;
            break;
          }
        }
        if (next == null) break;
        final finished = Completer<void>();
        _currentFinished = finished;
        try {
          await _downloadOne(next);
        } finally {
          _current = null;
          _currentFinished = null;
          finished.complete();
        }
      }
    } finally {
      _running = false;
      _current = null;
      notifyListeners();
    }
  }

  Future<void> _downloadOne(DownloadTask task) async {
    task.status = DownloadStatus.running;
    _current = task;
    final token = CancelToken();
    _cancelToken = token;
    notifyListeners();
    File? file;
    try {
      final dir = await _workDirectory(task.workId);
      final safeName = _safeFileName(task.title);
      file = File(
        p.join(dir.path, '${task.hash.replaceAll('/', '_')}_$safeName'),
      );
      if (token.isCancelled) throw token.cancelError!;
      if (await file.exists()) {
        await file.delete();
      }
      await _downloadFile(
        url: task.url,
        savePath: file.path,
        cancelToken: token,
        onProgress: (received, total) {
          task.received = received;
          task.total = total;
          task.progress = total > 0 ? received / total : 0;
          notifyListeners();
        },
      );
      if (token.isCancelled) throw token.cancelError!;
      final size = await file.length();
      task
        ..status = DownloadStatus.done
        ..progress = 1
        ..filePath = file.path
        ..total = size;
      await _library.saveDownload(
        DownloadRow(
          workId: task.workId,
          workTitle: task.workTitle,
          hash: task.hash,
          title: task.title,
          filePath: file.path,
          size: size,
          duration: task.duration,
        ),
      );
    } catch (e) {
      if (token.isCancelled) {
        task.status = DownloadStatus.cancelled;
      } else {
        task
          ..status = DownloadStatus.failed
          ..error = e is ApiException ? e.message : '$e';
      }
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
    } finally {
      _cancelToken = null;
      notifyListeners();
    }
  }

  /// 取消当前下载（未开始的任务会保留在队列中）。
  void cancelCurrent() {
    final task = _current;
    if (task != null) cancel(task);
  }

  void cancel(DownloadTask task) {
    if (!task.isActive) return;
    task.status = DownloadStatus.cancelled;
    if (identical(task, _current)) _cancelToken?.cancel('user');
    notifyListeners();
  }

  void retry(DownloadTask task) {
    if (_deletingWorks.contains(task.workId) || identical(task, _current)) {
      return;
    }
    task
      ..status = DownloadStatus.queued
      ..error = null
      ..progress = 0
      ..received = 0;
    notifyListeners();
    unawaited(_pump());
  }

  /// 删除某作品的全部本地文件。
  Future<void> deleteWorkFiles(int workId) async {
    if (!_deletingWorks.add(workId)) return;
    try {
      final finished = _current?.workId == workId
          ? _currentFinished?.future
          : null;
      for (final task in tasksOf(workId)) {
        cancel(task);
      }
      // 下载可能已进入落库阶段，必须等它完成后再查询并删除记录。
      if (finished != null) await finished;
      final rows = await _library.downloadsFor(workId);
      for (final row in rows) {
        try {
          final f = File(row.filePath);
          if (await f.exists()) await f.delete();
        } catch (_) {
          // 文件可能已被手动删除。
        }
      }
      await _library.deleteDownloadsOfWork(workId);
      _tasks.removeWhere((_, t) => t.workId == workId);
    } finally {
      _deletingWorks.remove(workId);
    }
    notifyListeners();
  }

  Future<void> deleteFile(DownloadRow row) async {
    try {
      final f = File(row.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    if (row.id != null) await _library.deleteDownload(row.id!);
    _tasks.remove(row.hash);
    notifyListeners();
  }

  static Future<Directory> _workDir(int workId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'asmr_downloads', '$workId'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _safeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final shortened = cleaned.length > 96 ? cleaned.substring(0, 96) : cleaned;
    return shortened.isEmpty ? 'audio' : shortened;
  }

  /// 已下载内容的可读体积。
  static String sizeLabel(List<DownloadRow> rows) =>
      Fmt.size(rows.fold(0, (s, r) => s + r.size));
}
