import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// Partial bytes are only appended when the server confirms the exact range
/// and a stable entity validator. A server without range support restarts safely.
class ResumableDownload {
  ResumableDownload(this.dio);
  final Dio dio;

  Future<void> download({
    required String url,
    required String savePath,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final partial = File('$savePath.part');
    final validatorFile = File('$savePath.validator');
    var offset = await partial.exists() ? await partial.length() : 0;
    String? validator;
    if (await validatorFile.exists()) {
      try {
        validator = jsonDecode(await validatorFile.readAsString()) as String?;
      } catch (_) {}
    }
    if (validator == null) offset = 0;
    Future<Response<ResponseBody>> request(int start) => dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (s) => s == 200 || s == 206 || s == 416,
        headers: {
          'Accept-Encoding': 'identity',
          if (start > 0) 'Range': 'bytes=$start-',
          if (start > 0) 'If-Range': validator,
        },
      ),
    );
    var response = await request(offset);
    if (response.statusCode == 416) {
      await response.data!.stream.drain<void>();
      offset = 0;
      response = await request(0);
    }
    if (response.statusCode == 200) offset = 0;
    final range = response.headers.value('content-range');
    final match = range == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
    if (response.statusCode == 206 &&
        (match == null || int.parse(match[1]!) != offset)) {
      await response.data!.stream.drain<void>();
      throw const FormatException('服务器返回了不匹配的下载范围');
    }
    final etag = response.headers.value('etag');
    final nextValidator = etag != null && !etag.startsWith('W/')
        ? etag
        : response.headers.value('last-modified');
    if (offset > 0 && nextValidator != null && nextValidator != validator) {
      await response.data!.stream.drain<void>();
      await partial.delete();
      if (await validatorFile.exists()) await validatorFile.delete();
      throw const FormatException('远端文件已更新，请重新下载');
    }
    await validatorFile.writeAsString(jsonEncode(nextValidator), flush: true);
    final length =
        int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
    final total = match != null && response.statusCode == 206
        ? int.parse(match[3]!)
        : length;
    var received = offset;
    final sink = partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await for (final bytes in response.data!.stream) {
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        sink.add(bytes);
        received += bytes.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    if (received == 0 || (total >= 0 && received != total)) {
      throw const FormatException('下载不完整，请重试');
    }
    await partial.rename(savePath);
    if (await validatorFile.exists()) await validatorFile.delete();
  }
}
