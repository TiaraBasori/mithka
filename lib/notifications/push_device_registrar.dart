import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tdlib/json_helpers.dart' show TdJson, jsonInt;
import '../tdlib/td_client.dart';
import 'ios_communication_notification.dart';
import 'notification_preferences.dart';

/// Builds the DeviceToken variant TDLib expects for a platform, or null on a
/// platform with no push transport.
@visibleForTesting
Map<String, dynamic>? deviceTokenRequestFor({
  required String platform,
  required String token,
  required bool encrypt,
  required bool isAppSandbox,
}) {
  switch (platform) {
    case 'android':
      return {
        '@type': 'deviceTokenFirebaseCloudMessaging',
        'token': token,
        'encrypt': encrypt,
      };
    case 'ios':
      return {
        '@type': 'deviceTokenApplePush',
        'device_token': token,
        'is_app_sandbox': isAppSandbox,
      };
    default:
      return null;
  }
}

/// Extracts the Telegram push payload map out of an FCM message's `data`
/// without asserting on its shape: a non-Telegram FCM message (analytics,
/// crash reporter) is data the registrar never touches.
@visibleForTesting
Map<String, dynamic>? telegramPushPayloadFromFCMData(
  Map<String, dynamic>? data,
) {
  if (data == null) return null;
  // FCM delivers the whole payload JSON-encoded under "p" when it is too
  // large for the dictionary form.
  final outerPayload = data['p'];
  if (outerPayload is String && outerPayload.isNotEmpty) {
    try {
      final decoded = jsonDecode(outerPayload);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
  }
  if (data.containsKey('loc_key') || data.containsKey('custom')) {
    return data;
  }
  final nested = data['data'];
  if (nested is Map) {
    final inner = nested.map((key, value) => MapEntry(key.toString(), value));
    if (inner.containsKey('loc_key') || inner.containsKey('custom')) {
      return inner;
    }
  }
  return null;
}

/// Serializes registration work while remembering that inputs changed during
/// an in-flight pass. The queued pass observes the newest token/account policy.
@visibleForTesting
class PushRegistrationDrain {
  bool _running = false;
  bool _queued = false;

  bool get isRunning => _running;
  bool get isQueued => _queued;

  Future<void> run(Future<void> Function() operation) async {
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      do {
        _queued = false;
        await operation();
      } while (_queued);
    } finally {
      _running = false;
    }
  }
}

class PushDeviceRegistrar {
  PushDeviceRegistrar._();
  static final PushDeviceRegistrar shared = PushDeviceRegistrar._();

  static const _channel = MethodChannel('mithka/push');

  final TdClient _client = TdClient.shared;
  final NotificationPreferences _preferences = NotificationPreferences.shared;
  StreamSubscription? _sub;
  StreamSubscription<int>? _accountSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  String? _deviceToken;
  String? _lastRegistrationSignature;
  bool _running = false;
  final PushRegistrationDrain _registrationDrain = PushRegistrationDrain();

  /// Platform gate, replaced in tests so the Android branch runs on the host.
  @visibleForTesting
  String Function() debugPlatformName = () => Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
      ? 'android'
      : 'other';

  /// FCM bootstrap, replaced in tests to avoid a live Firebase instance.
  @visibleForTesting
  Future<FCMBootstrap?> Function()? debugFCMBootstrap;

  Future<void> start() async {
    if (_running) return;
    final platform = debugPlatformName();
    if (platform != 'ios' && platform != 'android') return;
    _running = true;
    _preferences.addListener(_preferencesChanged);
    _channel.setMethodCallHandler(_handleNativeMethod);
    _sub = _client.subscribe().listen(_handleTdUpdate);
    _accountSub = _client.subscribeActiveSlotChanges().listen((_) {
      if (_preferences.accountMode != NotificationAccountMode.current) return;
      _lastRegistrationSignature = null;
      unawaited(_registerIfPossible());
    });
    if (platform == 'ios') {
      try {
        final token = await _channel.invokeMethod<String>(
          'registerForRemoteNotifications',
        );
        _setDeviceToken(token);
      } catch (error) {
        debugPrint('APNs registration request failed: $error');
      }
    } else {
      unawaited(_bootstrapFCM());
    }
    unawaited(_registerIfPossible());
  }

  Future<void> _bootstrapFCM() async {
    final bootstrap = await (debugFCMBootstrap?.call() ?? _liveFCMBootstrap());
    if (bootstrap == null) {
      debugPrint('FCM registration skipped: Firebase not configured');
      return;
    }
    _setDeviceToken(bootstrap.initialToken);
    unawaited(_registerIfPossible());
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = bootstrap.tokenRefresh.listen((token) {
      _setDeviceToken(token);
      unawaited(_registerIfPossible());
    });
    await _foregroundMessageSub?.cancel();
    _foregroundMessageSub = bootstrap.foregroundMessages.listen(
      _handleFCMForegroundMessage,
    );
  }

  Future<FCMBootstrap?> _liveFCMBootstrap() async {
    try {
      // Firebase.initializeApp runs in main's telemetry task; wait for its
      // side effect rather than racing a second initialize call.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (Firebase.apps.isEmpty) {
        if (DateTime.now().isAfter(deadline)) return null;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      return FCMBootstrap(
        initialToken: token,
        tokenRefresh: FirebaseMessaging.instance.onTokenRefresh,
        foregroundMessages: FirebaseMessaging.onMessage,
      );
    } catch (error) {
      debugPrint('FCM registration failed: $error');
      return null;
    }
  }

  void _handleFCMForegroundMessage(RemoteMessage message) {
    final payload = telegramPushPayloadFromFCMData(message.data);
    if (payload == null) return;
    unawaited(_processPush(payload));
  }

  /// Routes a Telegram FCM payload to the account that owns it. Telegram's
  /// payload carries a `user_id` naming the receiving account, and a multi-
  /// account client must not feed account A's push into account B's TDLib.
  Future<void> _processPush(Map<String, dynamic> payload) async {
    final custom = payload['custom'];
    final userId =
        jsonInt(payload['user_id']) ??
        jsonInt(custom is Map ? custom['user_id'] : null);
    final targetClientId = _clientIdForPushUserId(userId);
    final request = {
      '@type': 'processPushNotification',
      'payload': jsonEncode(payload),
    };
    try {
      if (targetClientId != null) {
        await _client.queryTo(request, targetClientId);
      } else {
        await _client.query(request);
      }
    } catch (error) {
      debugPrint('processPushNotification failed: $error');
    }
  }

  int? _clientIdForPushUserId(int? userId) {
    if (userId == null) return null;
    for (final entry in _knownUserIdsByClient.entries) {
      if (entry.value == userId) return entry.key;
    }
    return null;
  }

  /// accountId → userId, filled by each registration pass so push routing can
  /// pick the owning TDLib client without another getMe round trip.
  final Map<int, int> _knownUserIdsByClient = {};

  void _preferencesChanged() {
    _lastRegistrationSignature = null;
    unawaited(_registerIfPossible());
  }

  Future<dynamic> _handleNativeMethod(MethodCall call) async {
    switch (call.method) {
      case 'deviceToken':
        _setDeviceToken(call.arguments as String?);
        unawaited(_registerIfPossible());
      case 'registrationError':
        debugPrint('APNs registration failed: ${call.arguments}');
    }
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    if (update.type != 'updateAuthorizationState') return;
    final state = update.obj('authorization_state');
    if (state?.type == 'authorizationStateReady') {
      unawaited(_registerIfPossible());
    }
  }

  void _setDeviceToken(String? token) {
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) return;
    if (_deviceToken == normalized) return;
    _deviceToken = normalized;
    _lastRegistrationSignature = null;
  }

  Future<void> _registerIfPossible() =>
      _registrationDrain.run(_registerOnceIfPossible);

  Future<void> _registerOnceIfPossible() async {
    final token = _deviceToken;
    if (token == null || !_running) return;
    try {
      final readyUsersByClient = await _readyUsersByClient();
      final usersByClient = <int, int>{
        for (final entry in readyUsersByClient.entries)
          if (_preferences.receivesNotificationsFrom(
            userId: entry.value,
            isActiveAccount: entry.key == _client.activeClientId,
          ))
            entry.key: entry.value,
      };
      if (usersByClient.isEmpty) return;
      final userIds = usersByClient.values.toSet().toList()..sort();
      _knownUserIdsByClient
        ..clear()
        ..addAll(usersByClient);
      final platform = debugPlatformName();
      final signature = '$platform|$token|$kDebugMode|${userIds.join(',')}';
      if (_lastRegistrationSignature == signature) return;

      for (final entry in usersByClient.entries) {
        final otherUserIds = userIds
            .where((userId) => userId != entry.value)
            .toList(growable: false);
        final deviceToken = deviceTokenRequestFor(
          platform: platform,
          token: token,
          encrypt: false,
          isAppSandbox: kDebugMode,
        );
        if (deviceToken == null) return;
        await _client.queryTo(
          {
            '@type': 'registerDevice',
            'device_token': deviceToken,
            'other_user_ids': otherUserIds,
          },
          entry.key,
          timeout: const Duration(seconds: 8),
        );
      }
      _lastRegistrationSignature = signature;
      // The service extension stamps the slot onto a delivered push, so it
      // needs the mapping before the next one arrives rather than at tap time.
      await _publishAccountSlots(usersByClient);
      debugPrint('Registered $platform push device token with TDLib');
    } catch (error) {
      debugPrint('TDLib push device registration failed: $error');
    }
  }

  Future<void> _publishAccountSlots(Map<int, int> usersByClient) async {
    if (!Platform.isIOS) return;
    final slotsByUserId = <int, int>{};
    for (final entry in usersByClient.entries) {
      final slot = _client.slotForClient(entry.key);
      if (slot != null) slotsByUserId[entry.value] = slot;
    }
    try {
      await const IOSCommunicationNotificationBridge().setAccountSlots(
        slotsByUserId,
      );
    } catch (error) {
      debugPrint('Publishing notification account slots failed: $error');
    }
  }

  Future<Map<int, int>> _readyUsersByClient() async {
    final usersByClient = <int, int>{};
    for (final slot in _client.configuredSlots) {
      final clientId = _client.clientId(slot);
      if (clientId == null) continue;
      try {
        final state = await _client.queryTo(
          {'@type': 'getAuthorizationState'},
          clientId,
          timeout: const Duration(seconds: 2),
        );
        if (state.type != 'authorizationStateReady') continue;
        final me = await _client.queryTo(
          {'@type': 'getMe'},
          clientId,
          timeout: const Duration(seconds: 3),
        );
        final userId = me.int64('id');
        if (userId != null) usersByClient[clientId] = userId;
      } catch (_) {
        continue;
      }
    }
    return usersByClient;
  }

  Future<void> stop() async {
    _preferences.removeListener(_preferencesChanged);
    await _sub?.cancel();
    _sub = null;
    await _accountSub?.cancel();
    _accountSub = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _foregroundMessageSub?.cancel();
    _foregroundMessageSub = null;
    _running = false;
  }
}

/// The FCM surface [PushDeviceRegistrar] needs, mirrored by tests.
class FCMBootstrap {
  const FCMBootstrap({
    required this.initialToken,
    required this.tokenRefresh,
    required this.foregroundMessages,
  });

  final String? initialToken;
  final Stream<String> tokenRefresh;
  final Stream<RemoteMessage> foregroundMessages;
}
