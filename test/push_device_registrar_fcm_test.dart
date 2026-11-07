import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/push_device_registrar.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for tdjson: allocates a client id per slot and answers nothing
/// else — the scripted queryOverride serves every request the test cares
/// about.
class _FakeBindings implements TdBindings {
  int _nextClientId = 500;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {}

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void importSessionString(String sessionString, String destinationPath) {
    File(destinationPath).writeAsBytesSync(Uint8List.fromList(const [1]));
  }

  @override
  bool get supportsSessionStringBackup => true;

  @override
  bool get supportsTransferBoost => false;

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

void main() {
  test('device token request picks the TDLib variant per platform', () {
    expect(
      deviceTokenRequestFor(
        platform: 'android',
        token: 'fcm-token',
        encrypt: false,
        isAppSandbox: false,
      ),
      {
        '@type': 'deviceTokenFirebaseCloudMessaging',
        'token': 'fcm-token',
        'encrypt': false,
      },
    );
    expect(
      deviceTokenRequestFor(
        platform: 'ios',
        token: 'apns-token',
        encrypt: false,
        isAppSandbox: true,
      ),
      {
        '@type': 'deviceTokenApplePush',
        'device_token': 'apns-token',
        'is_app_sandbox': true,
      },
    );
    expect(
      deviceTokenRequestFor(
        platform: 'macos',
        token: 'x',
        encrypt: false,
        isAppSandbox: false,
      ),
      isNull,
    );
  });

  group('telegramPushPayloadFromFCMData', () {
    test('passes through a flat Telegram payload', () {
      final payload = telegramPushPayloadFromFCMData({
        'loc_key': 'MESSAGE_TEXT',
        'loc_args': ['hi'],
        'custom': {'msg_id': '42', 'from_id': '10'},
      });
      expect(payload, isNotNull);
      expect(payload!['loc_key'], 'MESSAGE_TEXT');
    });

    test('decodes the JSON-encoded large-payload form under p', () {
      final payload = telegramPushPayloadFromFCMData({
        'p': '{"loc_key":"MESSAGE_PHOTO","custom":{"channel_id":"100"}}',
      });
      expect(payload, isNotNull);
      expect(payload!['loc_key'], 'MESSAGE_PHOTO');
      expect((payload['custom'] as Map)['channel_id'], '100');
    });

    test('unwraps one level of nesting under data', () {
      final payload = telegramPushPayloadFromFCMData({
        'data': {'loc_key': 'MESSAGE_TEXT'},
      });
      expect(payload, isNotNull);
      expect(payload!['loc_key'], 'MESSAGE_TEXT');
    });

    test('ignores non-Telegram FCM messages', () {
      expect(
        telegramPushPayloadFromFCMData({
          'google.c.a.ts': '123',
          'cmp': 'campaign',
        }),
        isNull,
      );
      expect(telegramPushPayloadFromFCMData(null), isNull);
      expect(telegramPushPayloadFromFCMData({}), isNull);
    });
  });

  test('android FCM messages reach TDLib as processPushNotification', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final supportDir = Directory.systemTemp.createTempSync('mithka_fcm_test');
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });

    final requests = <Map<String, dynamic>>[];
    addTearDown(() async {
      await PushDeviceRegistrar.shared.stop();
    });

    TdClient.shared.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: _FakeBindings(),
      queryOverride: (request, clientId) async {
        requests.add(request);
        return _answerFor(request);
      },
    );
    final slot = TdClient.shared.addSlot();
    TdClient.shared.setActive(slot);

    final foregroundMessages = StreamController<RemoteMessage>.broadcast();
    PushDeviceRegistrar.shared.debugPlatformName = () => 'android';
    PushDeviceRegistrar.shared.debugFCMBootstrap = () async => FCMBootstrap(
      initialToken: 'fcm-token',
      tokenRefresh: const Stream.empty(),
      foregroundMessages: foregroundMessages.stream,
    );
    await PushDeviceRegistrar.shared.start();

    // The registration pass fires unawaited; let the routing table fill so
    // the push routes to a known client before the message arrives.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (requests.any((r) => r['@type'] == 'registerDevice')) break;
    }
    expect(requests.where((r) => r['@type'] == 'registerDevice'), isNotEmpty);
    final register = requests.firstWhere((r) => r['@type'] == 'registerDevice');
    expect(
      register['device_token']['@type'],
      'deviceTokenFirebaseCloudMessaging',
    );
    expect(register['device_token']['token'], 'fcm-token');

    foregroundMessages.add(
      const RemoteMessage(
        data: {
          'loc_key': 'MESSAGE_TEXT',
          'custom': {'msg_id': '42', 'from_id': '10'},
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final pushRequests = requests
        .where((r) => r['@type'] == 'processPushNotification')
        .toList();
    expect(pushRequests, hasLength(1));
    final payload = pushRequests.single['payload'] as String;
    expect(payload, contains('MESSAGE_TEXT'));
    await foregroundMessages.close();
  });
}

Map<String, dynamic> _answerFor(Map<String, dynamic> request) {
  switch (request['@type']) {
    case 'getAuthorizationState':
      return {'@type': 'authorizationStateReady'};
    case 'getMe':
      return {'@type': 'user', 'id': '7041948142'};
    case 'registerDevice':
      return {'@type': 'pushReceiverId', 'id': '1'};
    default:
      return {'@type': 'ok'};
  }
}
