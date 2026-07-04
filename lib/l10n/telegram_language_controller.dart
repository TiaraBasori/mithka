import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'app_localizations.dart';

String telegramText(
  String appFallbackKey, [
  Map<String, Object?> placeholders = const {},
]) {
  return TelegramLanguageController.shared.text(
    appFallbackKey,
    placeholders: placeholders,
  );
}

class TelegramLanguagePackOption {
  const TelegramLanguagePackOption({
    required this.id,
    required this.baseLanguagePackId,
    required this.name,
    required this.nativeName,
    required this.pluralCode,
    required this.isOfficial,
    required this.isRtl,
    required this.isBeta,
    required this.isInstalled,
  });

  factory TelegramLanguagePackOption.fromJson(Map<String, dynamic> json) {
    return TelegramLanguagePackOption(
      id: json.str('id') ?? '',
      baseLanguagePackId: json.str('base_language_pack_id') ?? '',
      name: json.str('name') ?? '',
      nativeName: json.str('native_name') ?? '',
      pluralCode: json.str('plural_code') ?? '',
      isOfficial: json.boolean('is_official') ?? false,
      isRtl: json.boolean('is_rtl') ?? false,
      isBeta: json.boolean('is_beta') ?? false,
      isInstalled: json.boolean('is_installed') ?? false,
    );
  }

  final String id;
  final String baseLanguagePackId;
  final String name;
  final String nativeName;
  final String pluralCode;
  final bool isOfficial;
  final bool isRtl;
  final bool isBeta;
  final bool isInstalled;

  String get displayName => nativeName.trim().isNotEmpty
      ? nativeName.trim()
      : name.trim().isNotEmpty
      ? name.trim()
      : id;
}

class TelegramLanguageController extends ChangeNotifier {
  TelegramLanguageController._();

  static final shared = TelegramLanguageController._();
  static const _selectedPackKey = 'telegram.language_pack_id';
  static const _targetOption = 'localization_target';
  static const _packOption = 'language_pack_id';

  SharedPreferences? _prefs;
  Locale? _appLocale;
  bool _initialized = false;
  bool _loading = false;
  String? _selectedPackId;
  String? _activePackId;
  String? _errorText;
  bool _refreshAgain = false;
  StreamSubscription<Map<String, dynamic>>? _languageUpdates;
  List<TelegramLanguagePackOption> _packs = const [];
  final Map<String, String> _strings = {};

  bool get followsAppLanguage => _selectedPackId == null;
  bool get isLoading => _loading;
  String? get errorText => _errorText;
  String? get activePackId => _activePackId;
  List<TelegramLanguagePackOption> get packs => List.unmodifiable(_packs);

  Future<void> initialize(SharedPreferences prefs) async {
    if (_initialized) return;
    _initialized = true;
    _prefs = prefs;
    final stored = prefs.getString(_selectedPackKey)?.trim();
    _selectedPackId = stored == null || stored.isEmpty ? null : stored;
    _languageUpdates ??= TdClient.shared.subscribe().listen(_handleTdUpdate);
    await refresh();
  }

  Future<void> syncAppLocale(Locale? locale) async {
    final resolved = locale == null ? null : AppLocalizations.resolve(locale);
    if (_sameLocale(_appLocale, resolved)) return;
    _appLocale = resolved;
    if (followsAppLanguage) {
      await refresh();
    }
  }

  Future<void> setSelectedPack(String? packId) async {
    final normalized = packId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_selectedPackId == next) return;
    _selectedPackId = next;
    final prefs = _prefs;
    if (prefs != null) {
      if (next == null) {
        await prefs.remove(_selectedPackKey);
      } else {
        await prefs.setString(_selectedPackKey, next);
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (!_initialized) return;
    if (_loading) {
      _refreshAgain = true;
      return;
    }
    do {
      _refreshAgain = false;
      _loading = true;
      _errorText = null;
      notifyListeners();
      try {
        await _applyLocalizationTarget();
        await _loadAvailablePacks();
        final packId = _selectedPackId ?? _packIdForLocale(_appLocale);
        await _applyPack(packId);
        await _loadStringsForPack(packId);
        _activePackId = packId;
      } catch (error) {
        _errorText = error.toString();
        if (kDebugMode) debugPrint('Telegram language pack failed: $error');
      } finally {
        _loading = false;
        notifyListeners();
      }
    } while (_refreshAgain);
  }

  String text(
    String appFallbackKey, {
    Map<String, Object?> placeholders = const {},
  }) {
    final telegramKey = _telegramKeyForAppKey[appFallbackKey];
    final template = telegramKey == null ? null : _strings[telegramKey];
    final fallback = AppStrings.t(appFallbackKey, placeholders);
    if (template == null || template.trim().isEmpty) return fallback;
    return _interpolate(template, placeholders);
  }

  String raw(String telegramKey, String fallback) {
    final value = _strings[telegramKey];
    return value == null || value.trim().isEmpty ? fallback : value;
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    if (update.type != 'updateLanguagePackStrings') return;
    final packId = update.str('language_pack_id');
    final activePack = _packs
        .where((pack) => pack.id == _activePackId)
        .firstOrNull;
    final isActivePack =
        packId == _activePackId ||
        (activePack?.baseLanguagePackId.isNotEmpty == true &&
            packId == activePack?.baseLanguagePackId);
    if (!isActivePack) return;

    final changed = update.objects('strings');
    if (changed == null || changed.isEmpty) {
      unawaited(refresh());
      return;
    }
    final allowedKeys = _telegramKeyForAppKey.values.toSet();
    var touched = false;
    for (final item in changed) {
      final key = item.str('key');
      if (key == null || !allowedKeys.contains(key)) continue;
      final value = _languagePackStringValue(item.obj('value'));
      if (value == null) {
        _strings.remove(key);
      } else {
        _strings[key] = value;
      }
      touched = true;
    }
    if (touched) notifyListeners();
  }

  Future<void> _applyLocalizationTarget() async {
    await _query({
      '@type': 'setOption',
      'name': _targetOption,
      'value': {'@type': 'optionValueString', 'value': _localizationTarget()},
    });
  }

  Future<void> _loadAvailablePacks() async {
    final response = await _query({
      '@type': 'getLocalizationTargetInfo',
      'only_local': false,
    });
    final packs = response
        .objects('language_packs')
        ?.map(TelegramLanguagePackOption.fromJson)
        .where((pack) => pack.id.isNotEmpty && !pack.isBeta)
        .toList();
    if (packs == null || packs.isEmpty) return;
    packs.sort((a, b) {
      final official = (b.isOfficial ? 1 : 0) - (a.isOfficial ? 1 : 0);
      if (official != 0) return official;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    _packs = packs;
  }

  Future<void> _applyPack(String packId) async {
    await _query({
      '@type': 'setOption',
      'name': _packOption,
      'value': {'@type': 'optionValueString', 'value': packId},
    });
  }

  Future<void> _loadStringsForPack(String packId) async {
    final merged = <String, String>{};
    final pack = _packs.where((pack) => pack.id == packId).firstOrNull;
    final baseId = pack?.baseLanguagePackId.trim();
    if (baseId != null && baseId.isNotEmpty) {
      merged.addAll(await _fetchPackStrings(baseId));
    }
    merged.addAll(await _fetchPackStrings(packId));
    _strings
      ..clear()
      ..addAll(merged);
  }

  Future<Map<String, String>> _fetchPackStrings(String packId) async {
    final response = await _query({
      '@type': 'getLanguagePackStrings',
      'language_pack_id': packId,
      'keys': _telegramKeyForAppKey.values.toSet().toList(),
    });
    final result = <String, String>{};
    for (final item in response.objects('strings') ?? const []) {
      final key = item.str('key');
      final value = _languagePackStringValue(item.obj('value'));
      if (key != null && value != null) result[key] = value;
    }
    return result;
  }

  Future<Map<String, dynamic>> _query(Map<String, dynamic> request) {
    return _waitForTdClient().then(
      (_) => TdClient.shared.query(request).timeout(const Duration(seconds: 8)),
    );
  }

  Future<void> _waitForTdClient() async {
    for (var attempt = 0; attempt < 40; attempt += 1) {
      if (TdClient.shared.hasActiveClient) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('TDLib client is not active yet');
  }

  String _packIdForLocale(Locale? locale) {
    final resolved =
        locale ?? AppLocalizations.resolve(PlatformDispatcher.instance.locale);
    final candidates = _candidatePackIds(resolved);
    for (final candidate in candidates) {
      if (_packs.any((pack) => pack.id == candidate)) return candidate;
    }
    for (final candidate in candidates) {
      final lower = candidate.toLowerCase();
      final match = _packs.where((pack) {
        return pack.id.toLowerCase() == lower ||
            pack.pluralCode.toLowerCase() == lower;
      }).firstOrNull;
      if (match != null) return match.id;
    }
    return 'en';
  }

  List<String> _candidatePackIds(Locale locale) {
    if (locale.languageCode == 'zh') {
      final traditional =
          locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK' ||
          locale.countryCode == 'MO';
      return traditional
          ? const ['zh-hant', 'zh-tw', 'zh-hk', 'zh']
          : const ['zh-hans', 'zh-cn', 'zh'];
    }
    return [locale.languageCode.toLowerCase()];
  }

  static String? _languagePackStringValue(Map<String, dynamic>? value) {
    switch (value?.type) {
      case 'languagePackStringValueOrdinary':
        return value?.str('value');
      case 'languagePackStringValuePluralized':
        return value?.str('other_value') ??
            value?.str('many_value') ??
            value?.str('few_value') ??
            value?.str('two_value') ??
            value?.str('one_value') ??
            value?.str('zero_value');
      default:
        return null;
    }
  }

  static String _localizationTarget() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows || Platform.isLinux) return 'tdesktop';
    return 'web';
  }

  static String _interpolate(
    String template,
    Map<String, Object?> placeholders,
  ) {
    var result = template;
    placeholders.forEach((key, value) {
      final replacement = '$value';
      result = result
          .replaceAll('{$key}', replacement)
          .replaceAll('%$key%', replacement);
    });
    final value1 = placeholders['value1'];
    if (value1 != null) {
      result = result
          .replaceAll('{user}', '$value1')
          .replaceAll('{name}', '$value1')
          .replaceAll('%1\$@', '$value1')
          .replaceAll('%@', '$value1');
    }
    return result;
  }

  static bool _sameLocale(Locale? a, Locale? b) =>
      a?.languageCode == b?.languageCode &&
      a?.scriptCode == b?.scriptCode &&
      a?.countryCode == b?.countryCode;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}

const _telegramKeyForAppKey = <String, String>{
  AppStringKeys.channelsFileAttachment: 'AttachDocument',
  AppStringKeys.chatInfoGroupMembers: 'Members',
  AppStringKeys.chatJoinGroup: 'JoinGroup',
  AppStringKeys.chatRequestToJoin: 'RequestToJoin',
  AppStringKeys.chatSearchMessageResultLabel: 'Message',
  AppStringKeys.chatSearchNoMessagesFound: 'NoResult',
  AppStringKeys.chatVideoPlaceholder: 'AttachVideo',
  AppStringKeys.composerAnimatedEmojiPreview: 'AttachGif',
  AppStringKeys.composerAudio: 'AttachMusic',
  AppStringKeys.composerImagePreview: 'AttachPhoto',
  AppStringKeys.composerLocationPreview: 'AttachLocation',
  AppStringKeys.composerVoicePreview: 'AttachAudio',
  AppStringKeys.messageActionCopy: 'Copy',
  AppStringKeys.messageActionEdit: 'Edit',
  AppStringKeys.messageActionForward: 'Forward',
  AppStringKeys.messageActionMultiSelect: 'Select',
  AppStringKeys.messageActionQuote: 'QuoteMessage',
  AppStringKeys.messageActionSelectText: 'SelectText',
  AppStringKeys.messageActionSticker: 'AttachSticker',
  AppStringKeys.messageActionTranslate: 'TranslateMessage',
  AppStringKeys.messageBubbleForwardedFrom: 'ForwardedFrom',
  AppStringKeys.pinnedMessagesEmpty: 'NoPinnedMessages',
  AppStringKeys.pinnedMessagesSentBy: 'SentBy',
  AppStringKeys.sharedMediaEmpty: 'NoMedia',
  AppStringKeys.sharedMediaFilterAll: 'AllMedia',
  AppStringKeys.sharedMediaFilterDownloaded: 'Downloaded',
  AppStringKeys.sharedMediaFilterNotDownloaded: 'NotDownloaded',
  AppStringKeys.sharedMediaLinks: 'SharedLinksTab2',
  AppStringKeys.sharedMediaNoMatches: 'NoResult',
  AppStringKeys.sharedMediaPhotosAndVideos: 'SharedMediaTab2',
  AppStringKeys.sharedMediaVideos: 'SharedMediaTab2',
  AppStringKeys.sharedMediaVoice: 'AttachAudio',
  AppStringKeys.sharedMediaVoiceMessages: 'VoiceMessages',
  AppStringKeys.topicPostContentFile: 'AttachDocument',
  AppStringKeys.tdMessageAutoDeleteTimerChanged: 'AutoDeleteTimerSet',
  AppStringKeys.tdMessageAutoDeleteTimerDisabled: 'AutoDeleteTimerDisabled',
  AppStringKeys.tdMessageChecklist: 'AttachChecklist',
  AppStringKeys.tdMessageContactCard: 'AttachContact',
  AppStringKeys.tdMessageDice: 'DiceInfo2',
  AppStringKeys.tdMessageExpiredPhoto: 'AttachDestructingPhotoExpired',
  AppStringKeys.tdMessageExpiredVideo: 'AttachDestructingVideoExpired',
  AppStringKeys.tdMessageForwardedStory: 'ForwardedStory',
  AppStringKeys.tdMessageGame: 'AttachGame',
  AppStringKeys.tdMessageGift: 'ActionGift',
  AppStringKeys.tdMessageGiveaway: 'BoostingGiveaway',
  AppStringKeys.tdMessageGroupCreated: 'ActionCreateGroup',
  AppStringKeys.tdMessageGroupPhotoDeleted: 'ActionRemovedPhoto',
  AppStringKeys.tdMessageGroupPhotoUpdated: 'ActionChangedPhoto',
  AppStringKeys.tdMessageGroupVideoChatEnded: 'VoipGroupVoiceChatEnded',
  AppStringKeys.tdMessageGroupVideoChatStarted: 'VoipGroupVoiceChatStarted',
  AppStringKeys.tdMessageJoinedGroupByLink: 'ActionInviteUser',
  AppStringKeys.tdMessageMemberLeftGroup: 'ActionKickUser',
  AppStringKeys.tdMessageMessagePinned: 'ActionPinnedText',
  AppStringKeys.tdMessageMusic: 'AttachMusic',
  AppStringKeys.tdMessageNewMemberJoinedGroup: 'ActionAddUser',
  AppStringKeys.tdMessageNoAudio: 'NoAudioFiles',
  AppStringKeys.tdMessageNoFiles: 'NoSharedFiles',
  AppStringKeys.tdMessageNoLinks: 'NoSharedLinks',
  AppStringKeys.tdMessageNoMembers: 'NoMembers',
  AppStringKeys.tdMessageNoPhotoVideo: 'NoMedia',
  AppStringKeys.tdMessageNoStickers: 'NoStickers',
  AppStringKeys.tdMessageNoVoice: 'NoVoiceMessages',
  AppStringKeys.tdMessagePaidContent: 'PaidMedia',
  AppStringKeys.tdMessagePhotoVideo: 'SharedMediaTab2',
  AppStringKeys.tdMessagePoll: 'Poll',
  AppStringKeys.tdMessageProduct: 'PaymentInvoice',
  AppStringKeys.tdMessageSticker: 'AttachSticker',
  AppStringKeys.tdMessageStickerPreview: 'AttachSticker',
  AppStringKeys.tdMessageSubmission: 'ActionSuggestedPost',
  AppStringKeys.tdMessageSystemMessage: 'SystemMessage',
  AppStringKeys.tdMessageUnsupportedCurrentVersion: 'UnsupportedAttachment',
  AppStringKeys.tdMessageUserJoinedTelegram: 'NotificationContactJoined',
  AppStringKeys.tdMessageVideoCall: 'CallMessageVideoIncoming',
  AppStringKeys.tdMessageVideoMessage: 'AttachRound',
  AppStringKeys.tdMessageVoiceCall: 'CallMessageIncoming',
};
