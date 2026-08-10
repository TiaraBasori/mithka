import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/bot_api/bot_api_account.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'moves only metadata-backed legacy slots and preserves metadata ordering',
    () async {
      final metadata = [
        jsonEncode(_account(7).toJson()),
        jsonEncode(_account(3).toJson()),
      ];
      SharedPreferences.setMockInitialValues({
        BotApiAccountRegistry.metadataKey: metadata,
      });
      final preferences = await SharedPreferences.getInstance();
      final key3 = _tokenKey(3);
      final key7 = _tokenKey(7);
      const current3 = '300003:CurrentTokenABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final harness = _KeychainHarness(
        current: {key3: current3},
        legacy: {
          key3: '300003:StaleLegacyTokenABCDEFGHIJKLMNOPQRSTUV',
          key7: '700007:LegacyTokenABCDEFGHIJKLMNOPQRSTUVWXYZ',
          _tokenKey(99): '990099:UnownedTokenABCDEFGHIJKLMNOPQRSTUVWXYZ',
        },
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, harness.handle);

      await BotApiAccountRegistry.migrateLegacyMacOsKeychain(preferences);

      expect(harness.current[key3], current3);
      expect(
        harness.current[key7],
        '700007:LegacyTokenABCDEFGHIJKLMNOPQRSTUVWXYZ',
      );
      expect(harness.legacy, contains(_tokenKey(99)));
      expect(harness.legacy, isNot(contains(key3)));
      expect(harness.legacy, isNot(contains(key7)));
      expect(harness.legacyReads, isNot(contains(key3)));
      expect(harness.legacyReads, contains(key7));
      expect(harness.legacyReads, isNot(contains(_tokenKey(99))));
      expect(harness.legacyDeletes, [key3, key7]);
      expect(
        preferences.getBool(
          BotApiAccountRegistry.legacyMacOsKeychainMigrationKey,
        ),
        isTrue,
      );
      expect(
        preferences.getStringList(
          BotApiAccountRegistry.legacyMacOsKeychainPendingSlotsKey,
        ),
        isEmpty,
      );
      expect(
        preferences.getStringList(BotApiAccountRegistry.metadataKey),
        metadata,
      );
      final completedCallCount = harness.callCount;
      await BotApiAccountRegistry.migrateLegacyMacOsKeychain(preferences);
      expect(harness.callCount, completedCallCount);
      expect(harness.legacyOptions, isNotEmpty);
      for (final options in harness.legacyOptions) {
        expect(options['accountName'], 'flutter_secure_storage_service');
        expect(options['usesDataProtectionKeychain'], 'false');
        expect(options['synchronizable'], 'false');
        expect(options['authenticationUIBehavior'], 'u_AuthUIF');
      }
    },
  );

  test('keeps a failed source without probing its ACL again', () async {
    final metadata = [
      jsonEncode(_account(1).toJson()),
      jsonEncode(_account(2).toJson()),
    ];
    SharedPreferences.setMockInitialValues({
      BotApiAccountRegistry.metadataKey: metadata,
    });
    final preferences = await SharedPreferences.getInstance();
    final key1 = _tokenKey(1);
    final key2 = _tokenKey(2);
    final harness = _KeychainHarness(
      legacy: {
        key1: '100001:LegacyTokenABCDEFGHIJKLMNOPQRSTUVWXYZ',
        key2: '200002:LegacyTokenABCDEFGHIJKLMNOPQRSTUVWXYZ',
      },
      failingCurrentWrites: {key2},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, harness.handle);

    await BotApiAccountRegistry.migrateLegacyMacOsKeychain(preferences);

    expect(harness.current, contains(key1));
    expect(harness.legacy, isNot(contains(key1)));
    expect(harness.current, isNot(contains(key2)));
    expect(harness.legacy, contains(key2));
    expect(
      preferences.getBool(
        BotApiAccountRegistry.legacyMacOsKeychainMigrationKey,
      ),
      isTrue,
    );
    expect(
      preferences.getStringList(
        BotApiAccountRegistry.legacyMacOsKeychainPendingSlotsKey,
      ),
      ['2'],
    );

    final completedCallCount = harness.callCount;
    await BotApiAccountRegistry.migrateLegacyMacOsKeychain(preferences);

    expect(harness.callCount, completedCallCount);
    expect(harness.current, contains(key1));
    expect(harness.current, isNot(contains(key2)));
    expect(harness.legacy, contains(key2));
  });

  test(
    'does not delete legacy data when read-back verification fails',
    () async {
      final metadata = [jsonEncode(_account(4).toJson())];
      SharedPreferences.setMockInitialValues({
        BotApiAccountRegistry.metadataKey: metadata,
      });
      final preferences = await SharedPreferences.getInstance();
      final key = _tokenKey(4);
      final harness = _KeychainHarness(
        legacy: {key: '400004:LegacyTokenABCDEFGHIJKLMNOPQRSTUVWXYZ'},
        mismatchedCurrentReadsAfterWrite: {key},
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, harness.handle);

      await BotApiAccountRegistry.migrateLegacyMacOsKeychain(preferences);

      expect(harness.legacy, contains(key));
      expect(harness.legacyDeletes, isEmpty);
      expect(
        preferences.getBool(
          BotApiAccountRegistry.legacyMacOsKeychainMigrationKey,
        ),
        isTrue,
      );
      expect(
        preferences.getStringList(
          BotApiAccountRegistry.legacyMacOsKeychainPendingSlotsKey,
        ),
        ['4'],
      );
    },
  );

  test('does not retry cleanup after a verified current write', () async {
    final metadata = [jsonEncode(_account(5).toJson())];
    SharedPreferences.setMockInitialValues({
      BotApiAccountRegistry.metadataKey: metadata,
    });
    final preferences = await SharedPreferences.getInstance();
    final key = _tokenKey(5);
    final harness = _KeychainHarness(
      current: {key: '500005:CurrentTokenABCDEFGHIJKLMNOPQRSTUVWXYZ'},
      legacy: {key: '500005:LegacyTokenABCDEFGHIJKLMNOPQRSTUVWXYZ'},
      failingLegacyDeletes: {key},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, harness.handle);

    await BotApiAccountRegistry.migrateLegacyMacOsKeychain(preferences);

    expect(harness.current, contains(key));
    expect(harness.legacy, contains(key));
    expect(
      preferences.getStringList(
        BotApiAccountRegistry.legacyMacOsKeychainPendingSlotsKey,
      ),
      isEmpty,
    );
    final completedCallCount = harness.callCount;
    await BotApiAccountRegistry.migrateLegacyMacOsKeychain(preferences);
    expect(harness.callCount, completedCallCount);
  });

  test('save and remove clear only their completed pending slots', () async {
    final metadata = [
      jsonEncode(_account(1).toJson()),
      jsonEncode(_account(2).toJson()),
    ];
    SharedPreferences.setMockInitialValues({
      BotApiAccountRegistry.metadataKey: metadata,
      BotApiAccountRegistry.legacyMacOsKeychainMigrationKey: true,
      BotApiAccountRegistry.legacyMacOsKeychainPendingSlotsKey: ['1', '2'],
    });
    final preferences = await SharedPreferences.getInstance();
    final harness = _KeychainHarness();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, harness.handle);

    await BotApiAccountRegistry.save(
      preferences,
      _account(1),
      '100001:ReplacementTokenABCDEFGHIJKLMNOPQRSTUVWXYZ',
    );

    expect(
      preferences.getStringList(
        BotApiAccountRegistry.legacyMacOsKeychainPendingSlotsKey,
      ),
      ['2'],
    );

    await BotApiAccountRegistry.remove(preferences, 2);

    expect(
      preferences.getStringList(
        BotApiAccountRegistry.legacyMacOsKeychainPendingSlotsKey,
      ),
      isEmpty,
    );
    expect(BotApiAccountRegistry.load(preferences).map((item) => item.slot), [
      1,
    ]);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.windows]) {
    test('never probes macOS legacy storage on ${platform.name}', () async {
      SharedPreferences.setMockInitialValues({
        BotApiAccountRegistry.metadataKey: [jsonEncode(_account(8).toJson())],
      });
      final preferences = await SharedPreferences.getInstance();
      debugDefaultTargetPlatformOverride = platform;
      var methodCallCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            methodCallCount += 1;
            return null;
          });

      await BotApiAccountRegistry.migrateLegacyMacOsKeychain(preferences);

      expect(methodCallCount, 0);
      expect(
        preferences.getBool(
          BotApiAccountRegistry.legacyMacOsKeychainMigrationKey,
        ),
        isNull,
      );
    });
  }
}

BotApiAccount _account(int slot) => BotApiAccount(
  slot: slot,
  endpoint: Uri.parse('https://bots.example.test'),
  bot: {'id': slot + 100000, 'is_bot': true},
);

String _tokenKey(int slot) => 'mithka.bot_api.token.$slot';

class _KeychainHarness {
  _KeychainHarness({
    Map<String, String>? current,
    Map<String, String>? legacy,
    Set<String>? failingCurrentWrites,
    Set<String>? failingLegacyDeletes,
    Set<String>? mismatchedCurrentReadsAfterWrite,
  }) : current = {...?current},
       legacy = {...?legacy},
       failingCurrentWrites = {...?failingCurrentWrites},
       failingLegacyDeletes = {...?failingLegacyDeletes},
       mismatchedCurrentReadsAfterWrite = {
         ...?mismatchedCurrentReadsAfterWrite,
       };

  final Map<String, String> current;
  final Map<String, String> legacy;
  final Set<String> failingCurrentWrites;
  final Set<String> failingLegacyDeletes;
  final Set<String> mismatchedCurrentReadsAfterWrite;
  final Set<String> _currentWrites = {};
  final List<String> legacyReads = [];
  final List<String> legacyDeletes = [];
  final List<Map<String, String>> legacyOptions = [];
  int callCount = 0;

  Future<Object?> handle(MethodCall call) async {
    callCount += 1;
    final arguments = (call.arguments as Map).cast<Object?, Object?>();
    final key = arguments['key']! as String;
    final options = (arguments['options'] as Map).cast<String, String>();
    final isLegacy = options['usesDataProtectionKeychain'] == 'false';
    final values = isLegacy ? legacy : current;
    if (isLegacy) legacyOptions.add(options);

    switch (call.method) {
      case 'read':
        if (isLegacy) legacyReads.add(key);
        if (!isLegacy &&
            _currentWrites.contains(key) &&
            mismatchedCurrentReadsAfterWrite.contains(key)) {
          return '999999:DifferentTokenABCDEFGHIJKLMNOPQRSTUVWXYZ';
        }
        return values[key];
      case 'write':
        if (!isLegacy && failingCurrentWrites.contains(key)) {
          throw PlatformException(code: 'current-store-unavailable');
        }
        values[key] = arguments['value']! as String;
        if (!isLegacy) _currentWrites.add(key);
        return null;
      case 'delete':
        if (isLegacy && failingLegacyDeletes.contains(key)) {
          throw PlatformException(code: 'legacy-acl-denied');
        }
        values.remove(key);
        if (isLegacy) legacyDeletes.add(key);
        return null;
      default:
        fail('Unexpected secure-storage method ${call.method}');
    }
  }
}
