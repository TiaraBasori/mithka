import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mithka/bot_api/bot_api_account.dart';
import 'package:mithka/bot_api/bot_api_client.dart';
import 'package:mithka/bot_api/bot_api_td_backend.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mithka-bot-api-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('commits received updates before exposing local TD history', () async {
    final waitForSecondPoll = Completer<Object?>();
    var updateDelivered = false;
    final api = _FakeBotApiClient(
      (method, parameters) {
        switch (method) {
          case 'getWebhookInfo':
            return <String, dynamic>{'url': ''};
          case 'getUpdates':
            if (!updateDelivered) {
              updateDelivered = true;
              return [
                {
                  'update_id': 42,
                  'message': {
                    'message_id': 7,
                    'date': 1700000000,
                    'from': {'id': 123, 'is_bot': false, 'first_name': 'Ada'},
                    'chat': {'id': 123, 'type': 'private', 'first_name': 'Ada'},
                    'text': 'saved on this device',
                  },
                },
              ];
            }
            return waitForSecondPoll.future;
          default:
            throw BotApiException(400, 'Unexpected $method');
        }
      },
      onClose: () {
        if (!waitForSecondPoll.isCompleted) {
          waitForSecondPoll.complete(const []);
        }
      },
    );
    final updates = <Map<String, dynamic>>[];
    final received = Completer<void>();
    final backend = _backend(
      temporaryDirectory,
      api,
      emit: (update) {
        updates.add(update);
        if (update['@type'] == 'updateNewMessage' && !received.isCompleted) {
          received.complete();
        }
      },
    );

    await backend.start();
    await received.future.timeout(const Duration(seconds: 2));

    final history = await backend.query({
      '@type': 'getChatHistory',
      'chat_id': 123,
      'from_message_id': 0,
      'offset': 0,
      'limit': 50,
      'only_local': false,
    });
    final search = await backend.query({
      '@type': 'searchChatMessages',
      'chat_id': 123,
      'query': 'this device',
      'from_message_id': 0,
      'limit': 20,
    });
    final info = await backend.query({'@type': 'getBotApiAccountInfo'});

    expect(history['@type'], 'messages');
    expect((history['messages'] as List).single['id'], 7);
    expect(
      (((history['messages'] as List).single['content'] as Map)['text']
          as Map)['text'],
      'saved on this device',
    );
    expect((search['messages'] as List), hasLength(1));
    expect(info['next_update_offset'], 43);
    expect(api.methods, containsAllInOrder(['getWebhookInfo', 'getUpdates']));
    expect(api.methods, isNot(contains('getChatHistory')));
    expect(updates.map((update) => update['@type']), contains('updateNewChat'));

    await backend.close();
  });

  test('surfaces a webhook conflict without deleting the webhook', () async {
    final conflict = Completer<void>();
    final api = _FakeBotApiClient((method, _) {
      if (method == 'getWebhookInfo') {
        return <String, dynamic>{'url': 'https://example.test/webhook'};
      }
      throw BotApiException(400, 'Unexpected $method');
    });
    final backend = _backend(
      temporaryDirectory,
      api,
      emit: (update) {
        if (update['@type'] == 'updateBotApiConnectionState' &&
            update['has_webhook_conflict'] == true &&
            !conflict.isCompleted) {
          conflict.complete();
        }
      },
    );

    await backend.start();
    await conflict.future.timeout(const Duration(seconds: 2));
    final info = await backend.query({'@type': 'getBotApiAccountInfo'});

    expect(info['has_webhook_conflict'], isTrue);
    expect(api.methods, ['getWebhookInfo']);
    expect(api.methods, isNot(contains('deleteWebhook')));
    expect(api.methods, isNot(contains('getUpdates')));

    await backend.close();
  });
}

BotApiTdBackend _backend(
  Directory root,
  BotApiClient client, {
  required void Function(Map<String, dynamic>) emit,
}) {
  return BotApiTdBackend(
    account: BotApiAccount(
      slot: 3,
      endpoint: Uri.parse('https://bots.example.test'),
      bot: const {
        'id': 999,
        'is_bot': true,
        'first_name': 'Mithka Test Bot',
        'username': 'mithka_test_bot',
      },
    ),
    token: '999:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij',
    databasePath: '${root.path}/history.sqlite3',
    mediaDirectory: '${root.path}/files',
    emit: emit,
    client: client,
  );
}

typedef _FakeCall =
    FutureOr<Object?> Function(String method, Map<String, dynamic> parameters);

class _FakeBotApiClient extends BotApiClient {
  _FakeBotApiClient(this._call, {this.onClose})
    : super(
        token: '999:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij',
        endpoint: Uri.parse('https://bots.example.test'),
        httpClient: MockClient((_) async => throw StateError('unused')),
      );

  final _FakeCall _call;
  final void Function()? onClose;
  final List<String> methods = [];

  @override
  Future<Object?> call(
    String method, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    methods.add(method);
    return _call(method, parameters);
  }

  @override
  void close() {
    onClose?.call();
    super.close();
  }
}
