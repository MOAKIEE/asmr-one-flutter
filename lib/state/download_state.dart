import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/api/api_client.dart';
import '../core/models/track.dart';
import '../core/models/work.dart';
import '../core/storage/library_db.dart';
import '../core/utils/formatters.dart';
import 'library_state.dart';

enum DownloadStatus { queued, running, paused, done, failed, cancelled }

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
    this.trackIndex = 0,
    this.folderLabel = '',
  });

  final int workId;
  final String workTitle;
  final String hash;
  final String title;
  final String url;
  final double duration;
  final int trackIndex;
  final String folderLabel;

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
    this.readQueue,
    this.writeQueue,
    Future<List<ConnectivityResult>> Function()? checkNetwork,
    this.networkChanges,
  }) : _downloadFile = downloadFile ?? ApiClient.instance.downloadRaw,
       _workDirectory = workDirectory ?? _workDir,
       _checkNetwork = checkNetwork ?? Connectivity().checkConnectivity;

  final LibraryState _library;
  final ApiClient _api = ApiClient.instance;
  final DownloadFile _downloadFile;
  final Future<Directory> Function(int) _workDirectory;
  final Future<Object?> Function()? readQueue;
  final Future<void> Function(Object?)? writeQueue;
  final Future<List<ConnectivityResult>> Function() _checkNetwork;
  final Stream<List<ConnectivityResult>>? networkChanges;
  Future<void>? _initialization;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  bool _wifiOnly = false;
  bool _networkAllowed = true;
  bool _disposed = false;
  bool get wifiOnly => _wifiOnly;
  bool get waitingForWifi => _wifiOnly && !_networkAllowed;
  Future<void> _persistQueue() async {
    await writeQueue?.call({
      'wifiOnly': _wifiOnly,
      'tasks': [
        for (final t in tasks.where(
          (t) =>
              t.status != DownloadStatus.done &&
              t.status != DownloadStatus.cancelled,
        ))
          {
            'workId': t.workId,
            'workTitle': t.workTitle,
            'hash': t.hash,
            'title': t.title,
            'url': _withoutToken(t.url),
            'duration': t.duration,
            'trackIndex': t.trackIndex,
            'folderLabel': t.folderLabel,
            'status': t.status.name,
          },
      ],
    });
  }

  static String _withoutToken(String url) {
    final uri = Uri.parse(url);
    return uri
        .replace(queryParameters: {...uri.queryParameters}..remove('token'))
        .toString();
  }

  String _downloadUrl(DownloadTask task) {
    final uri = Uri.parse(task.url);
    if (ApiClient.baseUrls.any((base) => Uri.parse(base).host == uri.host) &&
        uri.path.startsWith('/api/media/')) {
      return uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              'token': _api.token ?? '',
            },
          )
          .toString();
    }
    return task.url;
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    final saved = await readQueue?.call();
    if (saved is Map) {
      _wifiOnly = saved['wifiOnly'] == true;
      final downloadedByWork = <int, Set<String>>{};
      for (final raw in (saved['tasks'] as List? ?? [])) {
        final m = raw as Map;
        final task = DownloadTask(
          workId: m['workId'] as int,
          workTitle: m['workTitle'] as String,
          hash: m['hash'] as String,
          title: m['title'] as String,
          url: m['url'] as String,
          duration: (m['duration'] as num).toDouble(),
          trackIndex: m['trackIndex'] as int,
          folderLabel: m['folderLabel'] as String,
        );
        task.status = m['status'] == 'paused'
            ? DownloadStatus.paused
            : m['status'] == 'failed'
            ? DownloadStatus.failed
            : DownloadStatus.queued;
        final downloadedHashes = downloadedByWork[task.workId] ??=
            (await _library.downloadedPaths(task.workId)).keys.toSet();
        if (!downloadedHashes.contains(task.hash)) {
          _tasks[task.hash] = task;
        }
      }
    }
    _networkAllowed =
        !_wifiOnly || (await _checkNetwork()).contains(ConnectivityResult.wifi);
    if (_disposed) return;
    _networkSubscription =
        (networkChanges ?? Connectivity().onConnectivityChanged).listen((
          result,
        ) {
          _networkAllowed =
              !_wifiOnly || result.contains(ConnectivityResult.wifi);
          if (!_networkAllowed && _current?.status == DownloadStatus.running) {
            _current!.status = DownloadStatus.queued;
            _cancelToken?.cancel('wifi');
          } else if (_networkAllowed) {
            unawaited(_pump());
          }
          notifyListeners();
        });
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> setWifiOnly(bool value) async {
    _wifiOnly = value;
    _networkAllowed =
        !value || (await _checkNetwork()).contains(ConnectivityResult.wifi);
    if (!_networkAllowed && _current?.status == DownloadStatus.running) {
      _current!.status = DownloadStatus.queued;
      _cancelToken?.cancel('wifi');
    }
    await _persistQueue();
    notifyListeners();
    if (_networkAllowed) unawaited(_pump());
  }

  Future<void> pauseTask(DownloadTask task) async {
    if (!task.isActive) return;
    task.status = DownloadStatus.paused;
    if (identical(task, _current)) _cancelToken?.cancel('pause');
    await _persistQueue();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _networkSubscription?.cancel();
    if (_current != null) _current!.status = DownloadStatus.paused;
    _cancelToken?.cancel('dispose');
    super.dispose();
  }

  final Map<int, Future<int>> _deletingWorks = {};
  Future<int>? _clearOperation;
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
          t.status == DownloadStatus.cancelled,
    );
    unawaited(_persistQueue());
    notifyListeners();
  }

  /// 把整个作品的曲目加入下载队列。
  ///
  /// 返回 `({queued, skipped})`：`skipped` 为已下载或无法解析地址的曲目数。
  Future<({int queued, int skipped})> enqueueWork(
    Work work,
    List<AudioTrack> tracks,
  ) async {
    if (readQueue != null) await initialize();
    var queued = 0;
    var skipped = 0;
    final existing = await _library.downloadedPaths(work.id);
    if (_clearOperation != null || _deletingWorks.containsKey(work.id)) {
      return (queued: 0, skipped: tracks.length);
    }

    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
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
      if (_tasks.containsKey(hash) &&
          _tasks[hash]!.status != DownloadStatus.cancelled) {
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
        trackIndex: i,
        folderLabel: t.folderLabel,
      );
      queued++;
    }

    await _persistQueue();
    notifyListeners();
    if (queued > 0) unawaited(_pump());
    return (queued: queued, skipped: skipped);
  }

  Future<void> _pump() async {
    if (_running || !_networkAllowed || _disposed || _clearOperation != null) {
      return;
    }
    _running = true;
    try {
      while (true) {
        if (!_networkAllowed || _disposed || _clearOperation != null) break;
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
          await _persistQueue();
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
      file = await _targetFile(task);
      if (token.isCancelled) throw token.cancelError!;
      if (await file.exists()) {
        await file.delete();
      }
      await _downloadFile(
        url: _downloadUrl(task),
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
          trackIndex: task.trackIndex,
          folderLabel: task.folderLabel,
        ),
      );
    } catch (e) {
      if (token.isCancelled) {
        if (task.status != DownloadStatus.paused &&
            task.status != DownloadStatus.queued) {
          task.status = DownloadStatus.cancelled;
        }
      } else {
        task
          ..status = DownloadStatus.failed
          ..error = e is ApiException ? e.message : '$e';
      }
      try {
        if (file != null && await file.exists()) await file.delete();
        if (file != null && task.status == DownloadStatus.cancelled) {
          for (final suffix in ['.part', '.validator']) {
            final partial = File('${file.path}$suffix');
            if (await partial.exists()) await partial.delete();
          }
        }
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
    if (!_cancelTask(task)) return;
    if (!identical(task, _current)) unawaited(_deletePartial(task));
    unawaited(_persistQueue());
    notifyListeners();
  }

  bool _cancelTask(DownloadTask task) {
    if (!task.isActive &&
        task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed) {
      return false;
    }
    task.status = DownloadStatus.cancelled;
    if (identical(task, _current)) {
      _cancelToken?.cancel('user');
    }
    return true;
  }

  void retry(DownloadTask task) {
    if (_clearOperation != null ||
        _deletingWorks.containsKey(task.workId) ||
        identical(task, _current)) {
      return;
    }
    task
      ..status = DownloadStatus.queued
      ..error = null
      ..progress = 0
      ..received = 0;
    unawaited(_persistQueue());
    notifyListeners();
    unawaited(_pump());
  }

  /// 清理全部下载及残片，返回删除失败的文件数。
  Future<int> clearAll() => _clearOperation ??= _clearAll().whenComplete(() {
    _clearOperation = null;
    notifyListeners();
  });

  Future<int> _clearAll() async {
    if (readQueue != null) await initialize();
    await Future.wait(_deletingWorks.values);
    final failures = await _cancelAndClean(tasks, _currentFinished?.future);
    await _library.refreshDownloads();
    return failures + await _deleteFiles(_library.downloads);
  }

  /// 删除作品的本地文件，返回删除失败的文件数。
  Future<int> deleteWorkFiles(int workId) async {
    while (_clearOperation != null) {
      await _clearOperation;
    }
    return _deletingWorks[workId] ??= _deleteWorkFiles(workId).whenComplete(() {
      _deletingWorks.remove(workId);
      notifyListeners();
    });
  }

  Future<int> _deleteWorkFiles(int workId) async {
    if (readQueue != null) await initialize();
    final finished = _current?.workId == workId ? _currentFinished?.future : null;
    final failures = await _cancelAndClean(tasksOf(workId), finished);
    return failures + await _deleteFiles(await _library.downloadsFor(workId));
  }

  Future<int> _cancelAndClean(
    List<DownloadTask> tasks,
    Future<void>? finished,
  ) async {
    for (final task in tasks) {
      _cancelTask(task);
    }
    // 等待下载完成落库后再查询文件记录。
    if (finished != null) await finished;
    var failures = 0;
    for (final task in tasks) {
      failures += await _deletePartial(task);
      _tasks.remove(task.hash);
    }
    await _persistQueue();
    return failures;
  }

  Future<int> _deleteFiles(List<DownloadRow> rows) async {
    var failures = 0;
    final deletedIds = <int>[];
    for (final row in rows) {
      if (await _tryDelete(File(row.filePath))) {
        if (row.id case final id?) deletedIds.add(id);
      } else {
        failures++;
      }
    }
    if (deletedIds.isNotEmpty) await _library.deleteDownloads(deletedIds);
    return failures;
  }

  static Future<bool> _tryDelete(File file) async {
    try {
      await file.delete();
      return true;
    } on PathNotFoundException {
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static Future<Directory> _workDir(int workId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'asmr_downloads', '$workId'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _targetFile(DownloadTask task) async {
    final dir = await _workDirectory(task.workId);
    final name =
        '${task.hash.replaceAll('/', '_')}_${_safeFileName(task.title)}';
    return File(p.join(dir.path, name));
  }

  Future<int> _deletePartial(DownloadTask task) async {
    final File target;
    try {
      target = await _targetFile(task);
    } on FileSystemException {
      return 1;
    }
    var failures = 0;
    for (final suffix in ['.part', '.validator']) {
      if (!await _tryDelete(File('${target.path}$suffix'))) failures++;
    }
    return failures;
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
