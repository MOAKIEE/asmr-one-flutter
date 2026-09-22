import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asmr_one/core/api/resumable_download.dart';

void main() {
  for (final supportsRange in [true, false]) {
    test(
      'partial download is safe when range support is $supportsRange',
      () async {
        final dir = await Directory.systemTemp.createTemp('asmr-range-');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final file = File('${dir.path}/audio');
        await File('${file.path}.part').writeAsString('abc');
        await File('${file.path}.validator').writeAsString('"v1"');
        server.listen((req) async {
          expect(req.headers.value('range'), 'bytes=3-');
          expect(req.headers.value('if-range'), 'v1');
          req.response.headers.set('etag', 'v1');
          req.response.statusCode = supportsRange ? 206 : 200;
          if (supportsRange)
            req.response.headers.set('content-range', 'bytes 3-5/6');
          req.response.write(supportsRange ? 'def' : 'abcdef');
          await req.response.close();
        });
        final dio = Dio();
        await ResumableDownload(dio).download(
          url: 'http://127.0.0.1:${server.port}/audio',
          savePath: file.path,
        );
        expect(await file.readAsString(), 'abcdef');
        expect(await File('${file.path}.part').exists(), isFalse);
        dio.close();
        await server.close(force: true);
        await dir.delete(recursive: true);
      },
    );
  }
}
