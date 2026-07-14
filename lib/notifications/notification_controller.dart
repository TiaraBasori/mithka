//
//  notification_controller.dart
//
//  Local notifications driven by TDLib updates. This is not a push service:
//  it can notify while the Flutter/TDLib process is alive in the background,
//  but APNs/FCM would still be needed for killed-app delivery.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../app/chat_deep_link_controller.dart';
import '../l10n/telegram_language_controller.dart';
import '../settings/country_message_filter.dart';
import '../settings/keyword_blocker.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'notification_target.dart';
import 'scope_notification_settings.dart';

class NotificationController with WidgetsBindingObserver {
  NotificationController._();
  static final NotificationController shared = NotificationController._();

  static const _androidChannel = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'Incoming Mithka messages',
    importance: Importance.high,
  );
  static const _notificationTapChannel = MethodChannel(
    'mithka/notification_tap',
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final TdClient _client = TdClient.shared;
  StreamSubscription? _sub;
  AppLifecycleState _state = AppLifecycleState.resumed;
  bool _ready = false;
  bool _notificationsAvailable = true;
  int _notificationSeed = 0;
  NotificationTarget? _lastOpenedTarget;
  DateTime? _lastOpenedAt;

  Future<void> start() async {
    if (_ready) return;
    WidgetsBinding.instance.addObserver(this);
    _state =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentBanner: false,
          defaultPresentList: false,
          defaultPresentSound: false,
          defaultPresentBadge: false,
        ),
      ),
      onDidReceiveNotificationResponse: _openNotification,
    );

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _notificationTapChannel.setMethodCallHandler(_handleNativeTap);
      try {
        final initial = await _notificationTapChannel
            .invokeMapMethod<String, dynamic>('getInitialNotification');
        if (initial != null) _openRemoteNotification(initial);
      } on PlatformException catch (error) {
        debugPrint('Initial notification tap lookup failed: $error');
      }
    }

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNotification(launch?.notificationResponse);
      });
    }

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
    await requestPermissions();

    _sub = _client.subscribe().listen(_handle);
    _ready = true;
  }

  Future<void> requestPermissions() async {
    try {
      final androidGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      final iosGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (androidGranted == false || iosGranted == false) {
        _notificationsAvailable = false;
      }
    } on PlatformException catch (error) {
      _notificationsAvailable = false;
      debugPrint('Local notification permission request failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
  }

  Future<void> _handle(Map<String, dynamic> update) async {
    if (update.type != 'updateNewMessage') return;
    if (_state == AppLifecycleState.resumed) return;
    if (!_notificationsAvailable) return;

    final raw = update.obj('message');
    if (raw == null || (raw.boolean('is_outgoing') ?? false)) return;

    final chatId = raw.int64('chat_id');
    final messageId = raw.int64('id');
    final content = raw.obj('content');
    if (chatId == null || messageId == null || content == null) return;

    final chat = await _chat(chatId);
    if (chat == null || _isMuted(chat) || await _isCountryFiltered(chat)) {
      return;
    }

    final title = chat.str('title') ?? 'Mithka';
    final body = _notificationText(content);
    if (KeywordBlocker.shared.matches(body)) return;
    final payload = jsonEncode({
      'chat_id': chatId,
      'message_id': messageId,
      'title': title,
    });

    _notificationSeed = (_notificationSeed + 1) & 0x7fffffff;
    try {
      await _plugin.show(
        id: _notificationSeed,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            channelDescription: 'Incoming Mithka messages',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } on PlatformException catch (error) {
      if (_isNotificationAuthorizationError(error)) {
        _notificationsAvailable = false;
      }
      debugPrint('Local notification display failed: $error');
    }
  }

  bool _isNotificationAuthorizationError(PlatformException error) {
    final text = '${error.code} ${error.message} ${error.details}';
    return text.contains('not authorized') ||
        text.contains('UNErrorDomain') ||
        text.contains('Error 2003');
  }

  Future<Map<String, dynamic>?> _chat(int chatId) async {
    try {
      return await _client.query({'@type': 'getChat', 'chat_id': chatId});
    } catch (_) {
      return null;
    }
  }

  bool _isMuted(Map<String, dynamic> chat) {
    return ScopeNotificationSettings.shared.isMuted(chat);
  }

  Future<bool> _isCountryFiltered(Map<String, dynamic> chat) async {
    final type = chat.obj('type');
    if (type?.type != 'chatTypePrivate' && type?.type != 'chatTypeSecret') {
      return false;
    }
    final userId = type?.int64('user_id');
    if (userId == null) return false;
    try {
      final user = await _client.query({'@type': 'getUser', 'user_id': userId});
      return CountryMessageFilter.shared.matchesUser(
        isContact: user.boolean('is_contact') ?? false,
        phoneNumber: user.str('phone_number'),
      );
    } catch (_) {
      return false;
    }
  }

  String _notificationText(Map<String, dynamic> content) {
    final text = TDParse.messageText(content).replaceAll('\n', ' ').trim();
    return text.isEmpty
        ? telegramText(AppStringKeys.chatSearchMessageResultLabel)
        : text;
  }

  void _openNotification(NotificationResponse? response) {
    final target = NotificationTarget.fromLocalPayload(response?.payload);
    if (target != null) _openTarget(target);
  }

  Future<dynamic> _handleNativeTap(MethodCall call) async {
    if (call.method != 'notificationTap') return;
    _openRemoteNotification(call.arguments);
  }

  void _openRemoteNotification(Object? userInfo) {
    final target = NotificationTarget.fromRemoteUserInfo(userInfo);
    if (target != null) _openTarget(target);
  }

  void _openTarget(NotificationTarget target) {
    final now = DateTime.now();
    final previous = _lastOpenedTarget;
    if (previous?.chatId == target.chatId &&
        previous?.messageId == target.messageId &&
        now.difference(
              _lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastOpenedTarget = target;
    _lastOpenedAt = now;
    ChatDeepLinkController.shared.openChat(
      chatId: target.chatId,
      title: target.title ?? 'Mithka',
      messageId: target.messageId,
    );
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    await _sub?.cancel();
    _sub = null;
    _ready = false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _notificationTapChannel.setMethodCallHandler(null);
    }
  }
}
