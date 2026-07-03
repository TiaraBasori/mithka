import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

class AccountSessionBackup {
  const AccountSessionBackup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    required this.sessionString,
    this.phone,
    this.userId,
  });

  final String id;
  final String name;
  final String? phone;
  final int? userId;
  final DateTime createdAt;
  final int sizeBytes;
  final String sessionString;

  String get displayName => name.trim().isEmpty ? id : name;
}

class AccountBackupService {
  AccountBackupService._();
  static final AccountBackupService shared = AccountBackupService._();

  static const _channel = MethodChannel('mithka/account_backup');
  static const _format = 'mithka.tdlib.session_string.v1';
  static const _enabledKey = 'mithka.accountBackup.enabled';
  final Set<int> _inFlightAutoBackups = {};

  Future<bool> get isSupported async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('isSupported') ?? false;
  }

  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!value) {
      await deleteAll();
    }
  }

  Future<void> backupActiveAccountIfEnabled() async {
    if (!await isEnabled) return;
    if (!await isSupported) return;

    final slot = TdClient.shared.activeSlot;
    if (!_inFlightAutoBackups.add(slot)) return;
    try {
      await backupActiveAccount();
    } catch (error) {
      stderr.writeln('☁️ [Mithka] account backup skipped: $error');
    } finally {
      _inFlightAutoBackups.remove(slot);
    }
  }

  Future<List<AccountSessionBackup>> listBackups() async {
    if (!await isSupported) return const [];
    final rawItems = await _channel.invokeListMethod<Object?>('getAllSessions');
    final backupsById = <String, AccountSessionBackup>{};
    for (final raw in rawItems ?? const []) {
      final data = raw is Uint8List ? raw : null;
      if (data == null) continue;
      final backup = _decode(data);
      if (backup == null) continue;
      final existing = backupsById[backup.id];
      if (existing == null || backup.createdAt.isAfter(existing.createdAt)) {
        backupsById[backup.id] = backup;
      }
    }
    final backups = backupsById.values.toList();
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  Future<AccountSessionBackup> backupActiveAccount() async {
    if (!await isSupported) {
      throw UnsupportedError('Account session backup is only available on iOS');
    }
    final slot = TdClient.shared.activeSlot;
    final me = await TdClient.shared.query({'@type': 'getMe'});
    final userId = me.int64('id');
    final name = TDParse.userName(me);
    final phone = TDParse.formatPhone(me.str('phone_number'));
    final sessionString = await TdClient.shared.exportSessionStringForSlot(
      slot,
    );
    if (sessionString.trim().isEmpty) {
      throw StateError('TDLib session string is empty');
    }

    final id = userId?.toString() ?? 'slot-$slot';
    final createdAt = DateTime.now().toUtc();
    final data = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'format': _format,
          'id': id,
          'accountId': id,
          'slot': slot,
          'userId': userId,
          'name': name,
          'phone': phone,
          'createdAt': createdAt.toIso8601String(),
          'sessionString': sessionString,
        }),
      ),
    );
    await _channel.invokeMethod<void>('saveSession', {'id': id, 'data': data});
    return AccountSessionBackup(
      id: id,
      name: name,
      phone: phone,
      userId: userId,
      createdAt: createdAt,
      sizeBytes: utf8.encode(sessionString).length,
      sessionString: sessionString,
    );
  }

  Future<int> restore(AccountSessionBackup backup) async {
    final slot = await TdClient.shared.restoreSessionSlot(backup.sessionString);
    return slot;
  }

  Future<void> delete(AccountSessionBackup backup) async {
    if (!await isSupported) return;
    await _channel.invokeMethod<void>('deleteSession', {'id': backup.id});
  }

  Future<void> deleteAll() async {
    if (!await isSupported) return;
    await _channel.invokeMethod<void>('deleteAllSessions');
  }

  AccountSessionBackup? _decode(Uint8List data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['format'] != _format) return null;
      final sessionString = decoded['sessionString'];
      if (sessionString is! String || sessionString.trim().isEmpty) {
        return null;
      }
      final createdAtText = decoded['createdAt'];
      final createdAt = createdAtText is String
          ? DateTime.tryParse(createdAtText)
          : null;
      final id = decoded['accountId']?.toString() ?? decoded['id']?.toString();
      if (id == null || id.isEmpty) return null;
      final userIdValue = decoded['userId'];
      return AccountSessionBackup(
        id: id,
        name: decoded['name']?.toString() ?? id,
        phone: decoded['phone']?.toString(),
        userId: userIdValue is int ? userIdValue : int.tryParse('$userIdValue'),
        createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        sizeBytes: utf8.encode(sessionString).length,
        sessionString: sessionString,
      );
    } catch (_) {
      return null;
    }
  }
}
