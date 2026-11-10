import 'dart:convert';
import 'dart:typed_data';

import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestAdapter implements HttpClientAdapter {
  TestAdapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object data, {int statusCode = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

void main() {
  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await AppPrefs.load();
  });

  test('login posts credentials to the public auth endpoint', () async {
    prefs.token = 'expired-token';
    final adapter = TestAdapter((request) {
      if (request.method == 'POST' && request.uri.path == '/api/auth/me') {
        return jsonResponse({'token': 'new-token'});
      }
      return jsonResponse({
        'error': 'No authorization token was found',
      }, statusCode: 401);
    });
    final api = ApiClient(adapter: adapter)..attachPrefs(prefs);

    expect(await api.login('test-user', 'test-password'), 'new-token');
    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://api.asmr.one/api/auth/me');
    expect(request.data, {'name': 'test-user', 'password': 'test-password'});
    expect(request.headers.containsKey('Authorization'), isFalse);
  });

  test('session lookup sends the token returned by login', () async {
    final adapter = TestAdapter((request) {
      if (request.method == 'POST') {
        return jsonResponse({'token': 'new-token'});
      }
      return jsonResponse({
        'user': {'loggedIn': true, 'name': 'test-user'},
        'auth': true,
        'reg': true,
      });
    });
    final api = ApiClient(adapter: adapter)..attachPrefs(prefs);

    prefs.token = await api.login('test-user', 'test-password');
    final session = await api.fetchSession();

    expect(session.user.loggedIn, isTrue);
    expect(session.user.name, 'test-user');
    final request = adapter.requests.last;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/auth/me');
    expect(request.headers['Authorization'], 'Bearer new-token');
  });

  test('login rejects a successful response without a token', () async {
    final adapter = TestAdapter((_) => jsonResponse({'user': {}}));
    final api = ApiClient(adapter: adapter);

    await expectLater(
      api.login('test-user', 'test-password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '登录失败：服务端未返回令牌。',
        ),
      ),
    );
  });

  test('invalid credentials show the server error without retrying', () async {
    final adapter = TestAdapter(
      (_) => jsonResponse({'error': '用户名或密码错误'}, statusCode: 401),
    );
    final api = ApiClient(adapter: adapter);

    await expectLater(
      api.login('test-user', 'wrong-password'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', '用户名或密码错误'),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });

  test(
    'login displays field validation errors from the errors array',
    () async {
      final adapter = TestAdapter(
        (_) => jsonResponse({
          'errors': [
            {'msg': '用户名长度至少为 5', 'param': 'name', 'location': 'body'},
            {'msg': '密码长度至少为 5', 'param': 'password', 'location': 'body'},
          ],
        }, statusCode: 422),
      );
      final api = ApiClient(adapter: adapter);

      await expectLater(
        api.login('', ''),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 422)
              .having(
                (error) => error.message,
                'message',
                '用户名长度至少为 5\n密码长度至少为 5',
              ),
        ),
      );
    },
  );

  test('registration skips empty validation messages', () async {
    final adapter = TestAdapter(
      (_) => jsonResponse({
        'errors': [
          null,
          {},
          {'msg': ''},
          {'msg': '  '},
          {'msg': ' 用户名已存在 '},
        ],
      }, statusCode: 422),
    );
    final api = ApiClient(adapter: adapter);

    await expectLater(
      api.register('test-user', 'test-password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '用户名已存在',
        ),
      ),
    );
  });

  test('protected endpoints retain the login-required message', () async {
    final adapter = TestAdapter(
      (_) => jsonResponse({
        'error': 'No authorization token was found',
        'errors': [
          {'msg': 'other validation error'},
        ],
      }, statusCode: 401),
    );
    final api = ApiClient(adapter: adapter);

    await expectLater(
      api.fetchTags(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.isAuthError, 'isAuthError', isTrue)
            .having(
              (error) => error.message,
              'message',
              '需要登录后才能使用该功能，请先在「我的」中登录账号。',
            ),
      ),
    );
  });
}
