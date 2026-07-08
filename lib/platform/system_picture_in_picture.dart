import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class SystemPictureInPicture {
  SystemPictureInPicture._();

  static const MethodChannel _channel = MethodChannel(
    'mithka/system_picture_in_picture',
  );
  static final Map<String, Future<void> Function()> _cleanupById = {};
  static bool _handlerAttached = false;

  static bool get isSupportedPlatform => Platform.isIOS;

  static Future<bool> isSupported() async {
    if (!isSupportedPlatform) return false;
    _attachHandler();
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start({
    required String id,
    required Uri uri,
    required Duration position,
    required double speed,
    required bool muted,
    Future<void> Function()? onStop,
  }) async {
    if (!isSupportedPlatform) return false;
    _attachHandler();
    if (onStop != null) _cleanupById[id] = onStop;
    try {
      final started =
          await _channel.invokeMethod<bool>('start', {
            'id': id,
            'url': uri.toString(),
            'positionMs': position.inMilliseconds,
            'speed': speed,
            'muted': muted,
          }) ??
          false;
      if (!started) {
        _cleanupById.remove(id);
        return false;
      }
      return true;
    } catch (_) {
      _cleanupById.remove(id);
      return false;
    }
  }

  static Future<bool> prepare({
    required String id,
    required Uri uri,
    required Duration position,
    required double speed,
    required bool muted,
    Future<void> Function()? onStop,
  }) async {
    if (!isSupportedPlatform) return false;
    _attachHandler();
    if (onStop != null) _cleanupById[id] = onStop;
    try {
      final prepared =
          await _channel.invokeMethod<bool>('prepare', {
            'id': id,
            'url': uri.toString(),
            'positionMs': position.inMilliseconds,
            'speed': speed,
            'muted': muted,
          }) ??
          false;
      if (!prepared) _cleanupById.remove(id);
      return prepared;
    } catch (_) {
      _cleanupById.remove(id);
      return false;
    }
  }

  static Future<bool> startPrepared({
    required String id,
    required Duration position,
    required double speed,
    required bool muted,
  }) async {
    if (!isSupportedPlatform) return false;
    _attachHandler();
    try {
      return await _channel.invokeMethod<bool>('startPrepared', {
            'id': id,
            'positionMs': position.inMilliseconds,
            'speed': speed,
            'muted': muted,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> updatePrepared({
    required String id,
    required Duration position,
    required double speed,
    required bool muted,
    required bool playing,
  }) async {
    if (!isSupportedPlatform) return;
    _attachHandler();
    try {
      await _channel.invokeMethod<void>('update', {
        'id': id,
        'positionMs': position.inMilliseconds,
        'speed': speed,
        'muted': muted,
        'playing': playing,
      });
    } catch (_) {}
  }

  static Future<void> cancelPrepared(String id) async {
    if (!isSupportedPlatform) return;
    _cleanupById.remove(id);
    _attachHandler();
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!isSupportedPlatform) return;
    _attachHandler();
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  static void _attachHandler() {
    if (_handlerAttached) return;
    _handlerAttached = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'didStop':
          final args = call.arguments as Map?;
          final id = args?['id'] as String?;
          if (id != null) {
            final cleanup = _cleanupById.remove(id);
            if (cleanup != null) await cleanup();
          }
      }
    });
  }
}
