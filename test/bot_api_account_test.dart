import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/bot_api/bot_api_account.dart';
import 'package:mithka/bot_api/bot_api_client.dart';

void main() {
  group('normalizeBotApiEndpoint', () {
    test('keeps custom HTTPS roots and trims trailing slashes', () {
      expect(
        normalizeBotApiEndpoint('https://bots.example.test/telegram///'),
        Uri.parse('https://bots.example.test/telegram'),
      );
    });

    test('allows local Bot API servers over HTTP', () {
      expect(
        normalizeBotApiEndpoint('http://192.168.1.20:8081/'),
        Uri.parse('http://192.168.1.20:8081'),
      );
      expect(
        normalizeBotApiEndpoint('http://localhost:8081'),
        Uri.parse('http://localhost:8081'),
      );
    });

    test('rejects public HTTP and token-bearing endpoints', () {
      expect(
        () => normalizeBotApiEndpoint('http://bots.example.test'),
        throwsFormatException,
      );
      expect(
        () => normalizeBotApiEndpoint(
          'https://api.telegram.org/bot123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef',
        ),
        throwsFormatException,
      );
    });
  });

  test('uses a custom endpoint root for Bot API methods', () async {
    late http.Request captured;
    final client = BotApiClient(
      token: '123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef',
      endpoint: Uri.parse('https://bots.example.test/telegram'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'result': {'id': 123456, 'is_bot': true},
          }),
          200,
        );
      }),
    );

    final result = await client.call('getMe');

    expect((result as Map)['id'], 123456);
    expect(
      captured.url.path,
      '/telegram/bot123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef/getMe',
    );
    client.close();
  });

  test('does not expose a token through HTTP failure text', () async {
    const token = '123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef';
    final client = BotApiClient(
      token: token,
      endpoint: Uri.parse('https://bots.example.test'),
      httpClient: MockClient((_) async => throw http.ClientException('bad')),
    );

    await expectLater(
      client.call('getMe'),
      throwsA(
        isA<BotApiException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(token)),
        ),
      ),
    );
    client.close();
  });

  test('redacts a token echoed by a custom endpoint', () async {
    const token = '123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef';
    final client = BotApiClient(
      token: token,
      endpoint: Uri.parse('https://bots.example.test'),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': false,
            'error_code': 401,
            'description': 'Rejected credential $token',
          }),
          401,
        ),
      ),
    );

    await expectLater(
      client.call('getMe'),
      throwsA(
        isA<BotApiException>()
            .having(
              (error) => error.toString(),
              'message',
              contains('[redacted]'),
            )
            .having(
              (error) => error.toString(),
              'secret-safe message',
              isNot(contains(token)),
            ),
      ),
    );
    client.close();
  });
}
