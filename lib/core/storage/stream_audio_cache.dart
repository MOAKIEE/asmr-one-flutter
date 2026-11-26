import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 流媒体音频缓存的唯一身份键（不携带完整 URL 或明文令牌）。
@immutable
class AudioCacheKey {
  const AudioCacheKey({
    required this.accountScope,
    required this.workId,
    required this.trackId,
    required this.lowQuality,
  });

  final String accountScope;
  final int workId;
  final String trackId;
  final bool lowQuality;

  String get qualityTag => lowQuality ? 'low' : 'high';

  String get canonical => 'v1|$accountScope|$workId|$trackId|$qualityTag';

  /// 确定性 SHA-256 摘要，用作跨平台安全文件名。
  String get id => _sha256Hex(canonical);

  @override
  bool operator ==(Object other) =>
      other is AudioCacheKey && canonical == other.canonical;

  @override
  int get hashCode => canonical.hashCode;
}

class _CacheEntry {
  _CacheEntry({
    required this.id,
    required this.file,
    required this.metaFile,
    required this.size,
    required this.lastAccessedMs,
    required this.complete,
    required this.expectedLength,
    required this.contentType,
  });

  final String id;
  final File file;
  final File metaFile;
  final int size;
  final int lastAccessedMs;
  final bool complete;
  final int expectedLength;
  final String contentType;
}

class _ProxyTarget {
  const _ProxyTarget({
    required this.key,
    required this.remoteUri,
    required this.headers,
  });

  final AudioCacheKey key;
  final Uri remoteUri;
  final Map<String, String> headers;
}

/// 在线流媒体音频缓存管理器（独立于用户显式下载目录）。
///
/// - 身份按「账号范围 + 曲目标识 + 实际音质」隔离，令牌刷新后仍命中同一资源。
/// - 仅已确认完整写入的文件才可作为本地整轨播放；中途中断产生的 `.part` 自动回收。
/// - 拖动至未缓存区间时直接透传 `Range` 请求至上游，不阻塞拖动。
/// - 容量超限时按最近使用时间（LRU）从旧到新回收闲置文件，跳过正在使用的文件。
class StreamAudioCache extends ChangeNotifier {
  StreamAudioCache({
    Future<Directory> Function()? directoryProvider,
    this.maxBytes = 200 * 1024 * 1024,
    DateTime Function()? now,
    HttpClient? httpClient,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory,
       _now = now ?? DateTime.now,
       _httpClient = httpClient ?? HttpClient();

  final Future<Directory> Function() _directoryProvider;
  final int maxBytes;
  final DateTime Function() _now;
  final HttpClient _httpClient;

  Directory? _dir;
  HttpServer? _server;
  final Map<String, _ProxyTarget> _routes = {};
  final Map<String, int> _activeRefs = {};
  int _routeSeq = 0;
  int _cachedBytes = 0;
  bool _disposed = false;

  // 轻量级运行统计（供对照试验与诊断核对传输量）。
  int upstreamRequests = 0;
  int upstreamBytes = 0;
  int cacheHitRequests = 0;
  int cacheHitBytes = 0;

  int get cachedBytes => _cachedBytes;

  static Future<Directory> _defaultDirectory() async {
    final base = await getTemporaryDirectory();
    return Directory(p.join(base.path, 'stream_audio_cache'));
  }

  /// 计算不含明文令牌的账号范围，令牌刷新后同一账号保持不变。
  static String accountScopeFor({
    required bool hasToken,
    String? userId,
    String? userName,
  }) {
    if (!hasToken) return 'guest';
    final uid = userId?.trim() ?? '';
    if (uid.isNotEmpty) return 'uid:$uid';
    final uname = userName?.trim().toLowerCase() ?? '';
    if (uname.isNotEmpty) return 'uname:$uname';
    return 'auth:session';
  }

  Future<Directory> _ensureDir() async {
    final existing = _dir;
    if (existing != null && await existing.exists()) return existing;
    final dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  File _cacheFile(Directory dir, String id) =>
      File(p.join(dir.path, '$id.cache'));

  File _partFile(Directory dir, String id) =>
      File(p.join(dir.path, '$id.part'));

  File _metaFile(Directory dir, String id) =>
      File(p.join(dir.path, '$id.meta.json'));

  /// 标记某缓存键正在被播放或写入，防止被并发清理/回收。
  void markActive(String keyId) {
    _activeRefs[keyId] = (_activeRefs[keyId] ?? 0) + 1;
  }

  /// 释放活跃占用；若仍有超限则触发延后回收。
  void releaseActive(String keyId, {bool triggerEviction = true}) {
    final current = _activeRefs[keyId] ?? 0;
    if (current <= 1) {
      _activeRefs.remove(keyId);
      if (triggerEviction && !_disposed && _cachedBytes > maxBytes) {
        unawaited(evictIfNeeded());
      }
    } else {
      _activeRefs[keyId] = current - 1;
    }
  }

  bool isActive(String keyId) => (_activeRefs[keyId] ?? 0) > 0;

  void resetMetrics() {
    upstreamRequests = 0;
    upstreamBytes = 0;
    cacheHitRequests = 0;
    cacheHitBytes = 0;
  }

  /// 查询已确认完整且可读的本地缓存文件；命中时刷新最近使用时间。
  Future<File?> lookupComplete(AudioCacheKey key) async {
    try {
      final dir = await _ensureDir();
      final entry = await _readValidEntry(dir, key.id);
      if (entry == null) return null;
      await _touchMeta(entry);
      return entry.file;
    } catch (_) {
      return null;
    }
  }

  /// 按播放源优先级返回本地完整缓存文件或本地代理 URI；初始化失败时返回 `null` 由调用方降级在线播放。
  Future<Uri?> resolvePlayableUri({
    required AudioCacheKey key,
    required Uri remoteUri,
    Map<String, String> headers = const {},
  }) async {
    try {
      await _ensureDir();
      final existing = await lookupComplete(key);
      if (existing != null) {
        cacheHitRequests++;
        cacheHitBytes += await existing.length();
        return Uri.file(existing.path);
      }
      final server = await _ensureServer();
      final routeId = '${++_routeSeq}_${key.id.substring(0, 12)}';
      _routes[routeId] = _ProxyTarget(
        key: key,
        remoteUri: remoteUri,
        headers: Map<String, String>.from(headers),
      );
      if (_routes.length > 256) {
        _routes.remove(_routes.keys.first);
      }
      return Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/stream/$routeId',
      );
    } catch (_) {
      return null;
    }
  }

  /// 统计当前缓存目录实际占用字节数（仅计算缓存目录，不涉及离线下载目录）。
  Future<int> refreshStats() async {
    try {
      final dir = await _ensureDir();
      var total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File &&
            (entity.path.endsWith('.cache') || entity.path.endsWith('.part'))) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      _cachedBytes = total;
      _notify();
      return total;
    } catch (_) {
      return _cachedBytes;
    }
  }

  /// 先统计实际占用，再按最近使用时间从旧到新回收闲置文件，跳过正在使用的文件。
  Future<int> evictIfNeeded() async {
    try {
      final dir = await _ensureDir();
      final entries = <_CacheEntry>[];
      var total = 0;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.endsWith('.part')) {
          final id = name.substring(0, name.length - '.part'.length);
          if (!isActive(id)) {
            await _safeDelete(entity);
          } else {
            try {
              total += await entity.length();
            } catch (_) {}
          }
          continue;
        }
        if (!name.endsWith('.cache')) continue;
        final id = name.substring(0, name.length - '.cache'.length);
        final valid = await _readValidEntry(dir, id);
        if (valid == null) {
          if (!isActive(id)) {
            await _safeDelete(entity);
            await _safeDelete(_metaFile(dir, id));
          }
          continue;
        }
        total += valid.size;
        entries.add(valid);
      }

      if (total > maxBytes) {
        entries.sort((a, b) => a.lastAccessedMs.compareTo(b.lastAccessedMs));
        for (final entry in entries) {
          if (total <= maxBytes) break;
          if (isActive(entry.id)) continue;
          final deleted = await _safeDelete(entry.file);
          await _safeDelete(entry.metaFile);
          if (deleted) {
            total = (total - entry.size).clamp(0, 1 << 62);
          }
        }
      }

      _cachedBytes = total;
      _notify();
      return total;
    } catch (_) {
      return _cachedBytes;
    }
  }

  /// 清空在线播放临时缓存，跳过正在使用的文件（除非 `includeActive` 为 true）。
  Future<int> clearAll({bool includeActive = false}) async {
    var skipped = 0;
    try {
      final dir = await _ensureDir();
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        String? id;
        if (name.endsWith('.cache')) {
          id = name.substring(0, name.length - '.cache'.length);
        } else if (name.endsWith('.part')) {
          id = name.substring(0, name.length - '.part'.length);
        } else if (name.endsWith('.meta.json')) {
          id = name.substring(0, name.length - '.meta.json'.length);
        }
        if (id != null && !includeActive && isActive(id)) {
          skipped++;
          continue;
        }
        await _safeDelete(entity);
      }
    } catch (_) {}
    await refreshStats();
    return skipped;
  }

  // ---------------------------------------------------------------------------
  // Loopback 代理：完整播放边播边写，Range 拖动直接透传
  // ---------------------------------------------------------------------------

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handleRequest, onError: (Object _) {});
    return server;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length != 2 || segments.first != 'stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final target = _routes[segments[1]];
    if (target == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      // 若期间已经完成缓存，直接走本地完整文件响应（支持 Range）。
      final cached = await lookupComplete(target.key);
      if (cached != null) {
        await _serveLocalFile(request, cached, target.key.id);
        return;
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final isFullStreamCandidate = _isFullRange(rangeHeader);

      if (isFullStreamCandidate) {
        await _proxyAndCacheFull(request, target, rangeHeader);
      } else {
        await _proxyRangePassThrough(request, target, rangeHeader);
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }

  static bool _isFullRange(String? rangeHeader) {
    if (rangeHeader == null || rangeHeader.trim().isEmpty) return true;
    final normalized = rangeHeader.trim().toLowerCase();
    return normalized == 'bytes=0-';
  }

  Future<void> _serveLocalFile(
    HttpRequest request,
    File file,
    String keyId,
  ) async {
    markActive(keyId);
    try {
      final length = await file.length();
      final dir = await _ensureDir();
      final meta = await _readValidEntry(dir, keyId);
      final contentType = meta?.contentType ?? 'audio/mpeg';
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final spec = rangeHeader.substring('bytes='.length).split(',').first;
        final parts = spec.split('-');
        final start = int.tryParse(parts[0].trim()) ?? 0;
        final end = parts.length > 1 && parts[1].trim().isNotEmpty
            ? (int.tryParse(parts[1].trim()) ?? (length - 1))
            : (length - 1);
        if (start < 0 || start >= length || end < start) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */$length',
          );
          await request.response.close();
          return;
        }
        final clampedEnd = end >= length ? length - 1 : end;
        final chunkLen = clampedEnd - start + 1;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$clampedEnd/$length',
        );
        request.response.contentLength = chunkLen;
        cacheHitRequests++;
        cacheHitBytes += chunkLen;
        await request.response.addStream(file.openRead(start, clampedEnd + 1));
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.contentLength = length;
        cacheHitRequests++;
        cacheHitBytes += length;
        await request.response.addStream(file.openRead());
        await request.response.close();
      }
    } finally {
      releaseActive(keyId);
    }
  }

  Future<void> _proxyRangePassThrough(
    HttpRequest request,
    _ProxyTarget target,
    String? rangeHeader,
  ) async {
    final upReq = await _httpClient.getUrl(target.remoteUri);
    target.headers.forEach(upReq.headers.set);
    if (rangeHeader != null) {
      upReq.headers.set(HttpHeaders.rangeHeader, rangeHeader);
    }
    final upRes = await upReq.close();
    upstreamRequests++;

    request.response.statusCode = upRes.statusCode;
    for (final header in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
    ]) {
      final value = upRes.headers.value(header);
      if (value != null) request.response.headers.set(header, value);
    }
    if (upRes.contentLength >= 0) {
      request.response.contentLength = upRes.contentLength;
    }

    await for (final chunk in upRes) {
      upstreamBytes += chunk.length;
      request.response.add(chunk);
    }
    await request.response.close();
  }

  Future<void> _proxyAndCacheFull(
    HttpRequest request,
    _ProxyTarget target,
    String? rangeHeader,
  ) async {
    final upReq = await _httpClient.getUrl(target.remoteUri);
    target.headers.forEach(upReq.headers.set);
    if (rangeHeader != null) {
      upReq.headers.set(HttpHeaders.rangeHeader, rangeHeader);
    }
    final upRes = await upReq.close();
    upstreamRequests++;

    final status = upRes.statusCode;
    final contentType =
        upRes.headers.value(HttpHeaders.contentTypeHeader) ?? 'audio/mpeg';
    final expectedLength = upRes.contentLength;
    final contentRange = upRes.headers.value(HttpHeaders.contentRangeHeader);
    final canCache =
        status == HttpStatus.ok ||
        (status == HttpStatus.partialContent &&
            _isFullEntityRange(contentRange, expectedLength));

    request.response.statusCode = status;
    request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    final acceptRanges = upRes.headers.value(HttpHeaders.acceptRangesHeader);
    if (acceptRanges != null) {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, acceptRanges);
    }
    if (contentRange != null) {
      request.response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
    }
    if (expectedLength >= 0) {
      request.response.contentLength = expectedLength;
    }

    Directory? dir;
    File? part;
    RandomAccessFile? raf;
    var writeFailed = false;
    var received = 0;
    var activeMarked = false;

    if (canCache) {
      try {
        dir = await _ensureDir();
        markActive(target.key.id);
        activeMarked = true;
        part = _partFile(dir, target.key.id);
        raf = await part.open(mode: FileMode.write);
      } catch (_) {
        writeFailed = true;
        raf = null;
      }
    }

    var finalized = false;

    Future<void> commitIfReady() async {
      if (finalized) return;
      if (raf != null) {
        try {
          await raf!.close();
        } catch (_) {
          writeFailed = true;
        }
        raf = null;
      }
      final cacheDir = dir;
      final partFile = part;
      if (canCache && cacheDir != null && partFile != null) {
        final complete =
            !writeFailed &&
            received > 0 &&
            (expectedLength < 0 || received == expectedLength);
        if (complete) {
          try {
            final dest = _cacheFile(cacheDir, target.key.id);
            if (await dest.exists()) await dest.delete();
            await partFile.rename(dest.path);
            await _writeMeta(
              _metaFile(cacheDir, target.key.id),
              id: target.key.id,
              size: received,
              lastAccessedMs: _now().millisecondsSinceEpoch,
              expectedLength: expectedLength > 0 ? expectedLength : received,
              contentType: contentType,
            );
            finalized = true;
          } catch (_) {
            await _safeDelete(partFile);
          }
        } else {
          await _safeDelete(partFile);
        }
      }
      if (canCache) {
        await evictIfNeeded();
      }
      if (activeMarked) {
        // 刚提交的新文件若因更旧的活跃文件占用而暂超上限，等待旧文件释放后再回收，不立刻删掉刚写完的新文件。
        releaseActive(target.key.id, triggerEviction: false);
        activeMarked = false;
      }
    }

    try {
      await for (final chunk in upRes) {
        upstreamBytes += chunk.length;
        received += chunk.length;
        if (raf != null && !writeFailed) {
          try {
            await raf!.writeFrom(chunk);
          } catch (_) {
            writeFailed = true;
          }
        }
        // 当上游给出精确 Content-Length 且收齐最后一片时，先完成落盘提交再把末片发给客户端，
        // 避免客户端一收到 Content-Length 字节立刻重播时还没完成重命名。
        if (canCache &&
            !writeFailed &&
            expectedLength > 0 &&
            received == expectedLength) {
          await commitIfReady();
        }
        request.response.add(chunk);
      }
      await commitIfReady();
      await request.response.close();
    } finally {
      if (raf != null) {
        try {
          await raf!.close();
        } catch (_) {}
      }
      if (!finalized && part != null) {
        await _safeDelete(part);
      }
      if (activeMarked) {
        releaseActive(target.key.id);
      }
    }
  }

  static bool _isFullEntityRange(String? contentRange, int contentLength) {
    if (contentRange == null) return false;
    final match = RegExp(r'^bytes\s+0-(\d+)/(\d+)$').firstMatch(
      contentRange.trim(),
    );
    if (match == null) return false;
    final end = int.tryParse(match.group(1)!);
    final total = int.tryParse(match.group(2)!);
    if (end == null || total == null || total <= 0) return false;
    return end + 1 == total && (contentLength < 0 || contentLength == total);
  }

  // ---------------------------------------------------------------------------
  // 元数据校验与辅助方法
  // ---------------------------------------------------------------------------

  Future<_CacheEntry?> _readValidEntry(Directory dir, String id) async {
    final file = _cacheFile(dir, id);
    final meta = _metaFile(dir, id);
    if (!await file.exists() || !await meta.exists()) return null;
    try {
      final decoded = jsonDecode(await meta.readAsString());
      if (decoded is! Map) return null;
      if (decoded['complete'] != true) return null;
      final expected = (decoded['expectedLength'] as num?)?.toInt() ?? 0;
      final actualSize = await file.length();
      if (actualSize <= 0) return null;
      if (expected > 0 && actualSize != expected) return null;
      final lastAccessedMs =
          (decoded['lastAccessedMs'] as num?)?.toInt() ??
          (await file.lastModified()).millisecondsSinceEpoch;
      final contentType = decoded['contentType'] as String? ?? 'audio/mpeg';
      return _CacheEntry(
        id: id,
        file: file,
        metaFile: meta,
        size: actualSize,
        lastAccessedMs: lastAccessedMs,
        complete: true,
        expectedLength: expected,
        contentType: contentType,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _touchMeta(_CacheEntry entry) async {
    try {
      await _writeMeta(
        entry.metaFile,
        id: entry.id,
        size: entry.size,
        lastAccessedMs: _now().millisecondsSinceEpoch,
        expectedLength: entry.expectedLength,
        contentType: entry.contentType,
      );
    } catch (_) {}
  }

  Future<void> _writeMeta(
    File metaFile, {
    required String id,
    required int size,
    required int lastAccessedMs,
    required int expectedLength,
    required String contentType,
  }) async {
    await metaFile.writeAsString(
      jsonEncode({
        'id': id,
        'size': size,
        'lastAccessedMs': lastAccessedMs,
        'complete': true,
        'expectedLength': expectedLength,
        'contentType': contentType,
      }),
    );
  }

  Future<bool> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _routes.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
    _httpClient.close(force: true);
    super.dispose();
  }
}

// -----------------------------------------------------------------------------
// Pure Dart SHA-256 (FIPS 180-4) 用于生成稳定、无碰撞的缓存键文件名
// -----------------------------------------------------------------------------

const List<int> _sha256K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

String _sha256Hex(String input) {
  final bytes = utf8.encode(input);
  final bitLen = bytes.length * 8;
  final paddedLen = ((bytes.length + 9 + 63) ~/ 64) * 64;
  final data = Uint8List(paddedLen);
  data.setAll(0, bytes);
  data[bytes.length] = 0x80;
  final bd = ByteData.sublistView(data);
  bd.setUint32(paddedLen - 8, (bitLen ~/ 0x100000000) & 0xffffffff);
  bd.setUint32(paddedLen - 4, bitLen & 0xffffffff);

  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  int rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
  final w = Uint32List(64);

  for (var offset = 0; offset < paddedLen; offset += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(offset + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;

    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final temp1 = (h + s1 + ch + _sha256K[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }

    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  final out = StringBuffer();
  for (final v in [h0, h1, h2, h3, h4, h5, h6, h7]) {
    out.write(v.toRadixString(16).padLeft(8, '0'));
  }
  return out.toString();
}
