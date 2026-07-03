import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'country_names.dart';
import 'messages/de.dart';
import 'messages/en.dart';
import 'messages/es.dart';
import 'messages/fr.dart';
import 'messages/ja.dart';
import 'messages/ko.dart';
import 'messages/zh_hans.dart';
import 'messages/zh_hant.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const fallbackLocale = Locale('en');
  static const supportedLocales = [
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
    Locale('ko'),
    Locale('en'),
    Locale('fr'),
    Locale('es'),
    Locale('de'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static bool isSupportedLocale(Locale locale) =>
      supportedLocales.any((supported) {
        if (supported.languageCode != locale.languageCode) return false;
        if (supported.scriptCode == null) return true;
        return supported.scriptCode == locale.scriptCode ||
            (supported.scriptCode == 'Hans' &&
                locale.languageCode == 'zh' &&
                locale.scriptCode == null);
      });

  static Locale resolve(Locale locale) {
    if (locale.languageCode == 'zh') {
      final isTraditional =
          locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK' ||
          locale.countryCode == 'MO';
      return isTraditional
          ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
          : const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    }
    return supportedLocales.firstWhere(
      (supported) => supported.languageCode == locale.languageCode,
      orElse: () => fallbackLocale,
    );
  }

  static Locale? localeFromTag(String? tag) {
    final normalized = tag?.trim().replaceAll('_', '-');
    if (normalized == null || normalized.isEmpty || normalized == 'system') {
      return null;
    }
    final parts = normalized
        .split('-')
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    final language = parts.first.toLowerCase();
    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (part.length == 4 && script == null) {
        script =
            part.substring(0, 1).toUpperCase() +
            part.substring(1).toLowerCase();
      } else if ((part.length == 2 || part.length == 3) && country == null) {
        country = part.toUpperCase();
      }
    }

    return Locale.fromSubtags(
      languageCode: language,
      scriptCode: script,
      countryCode: country,
    );
  }

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(fallbackLocale);

  static String localeKeyFor(Locale locale) {
    if (locale.languageCode == 'zh') {
      return locale.scriptCode == 'Hant' ||
              locale.countryCode == 'TW' ||
              locale.countryCode == 'HK' ||
              locale.countryCode == 'MO'
          ? 'zhHant'
          : 'zhHans';
    }
    return locale.languageCode;
  }

  String get _key => localeKeyFor(locale);

  String t(String key, [Map<String, Object?> placeholders = const {}]) =>
      AppStrings.tForLocale(_key, key, placeholders);

  String format(String key, String value) =>
      t(key, {'value1': value, 'value': value});
}

extension LocalizedString on String {
  String l10n(BuildContext context) => AppLocalizations.of(context).t(this);
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

abstract final class AppStringKeys {
  static const aboutTelegramChannel = 'aboutTelegramChannel';
  static const aboutTitle = 'aboutTitle';
  static const aboutVersion = 'aboutVersion';
  static const accountBackupCreate = 'accountBackupCreate';
  static const accountBackupDeleteMessage = 'accountBackupDeleteMessage';
  static const accountBackupDeleteTitle = 'accountBackupDeleteTitle';
  static const accountBackupEmpty = 'accountBackupEmpty';
  static const accountBackupEnabled = 'accountBackupEnabled';
  static const accountBackupIOSOnly = 'accountBackupIOSOnly';
  static const accountBackupNotice = 'accountBackupNotice';
  static const accountBackupRestore = 'accountBackupRestore';
  static const accountBackupRestoreAccount = 'accountBackupRestoreAccount';
  static const accountBackupRestored = 'accountBackupRestored';
  static const accountBackupRestoreMessage = 'accountBackupRestoreMessage';
  static const accountBackupRestoreTitle = 'accountBackupRestoreTitle';
  static const accountBackupSaved = 'accountBackupSaved';
  static const accountBackupSessions = 'accountBackupSessions';
  static const accountBackupTitle = 'accountBackupTitle';
  static const accentColorPickerSave = 'accentColorPickerSave';
  static const apiCredentialsCustomClientApi = 'apiCredentialsCustomClientApi';
  static const apiCredentialsTitle = 'apiCredentialsTitle';
  static const addMembersDone = 'addMembersDone';
  static const addMembersDoneWithCount = 'addMembersDoneWithCount';
  static const addMembersInviteMembersTitle = 'addMembersInviteMembersTitle';
  static const addMembersInvitePermissionError =
      'addMembersInvitePermissionError';
  static const addPeopleFindGroups = 'addPeopleFindGroups';
  static const addPeopleFindPeople = 'addPeopleFindPeople';
  static const addPeopleGroupNameOrLinkPlaceholder =
      'addPeopleGroupNameOrLinkPlaceholder';
  static const addPeopleNoGroupsOrChannelsFound =
      'addPeopleNoGroupsOrChannelsFound';
  static const addPeopleNoUsersFound = 'addPeopleNoUsersFound';
  static const addPeopleUsernameOrPhonePlaceholder =
      'addPeopleUsernameOrPhonePlaceholder';
  static const appLocaleArabic = 'appLocaleArabic';
  static const appLocaleFollowSystem = 'appLocaleFollowSystem';
  static const appLocaleEnglish = 'appLocaleEnglish';
  static const appLocaleFrench = 'appLocaleFrench';
  static const appLocaleGerman = 'appLocaleGerman';
  static const appLocaleHindi = 'appLocaleHindi';
  static const appLocaleIndonesian = 'appLocaleIndonesian';
  static const appLocaleItalian = 'appLocaleItalian';
  static const appLocaleJapanese = 'appLocaleJapanese';
  static const appLocaleKorean = 'appLocaleKorean';
  static const appLocaleMalay = 'appLocaleMalay';
  static const appLocalePortuguese = 'appLocalePortuguese';
  static const appLocaleRussian = 'appLocaleRussian';
  static const appLocaleSimplifiedChinese = 'appLocaleSimplifiedChinese';
  static const appLocaleSpanish = 'appLocaleSpanish';
  static const appLocaleThai = 'appLocaleThai';
  static const appLocaleTraditionalChinese = 'appLocaleTraditionalChinese';
  static const appLocaleTurkish = 'appLocaleTurkish';
  static const appLocaleUkrainian = 'appLocaleUkrainian';
  static const appLocaleVietnamese = 'appLocaleVietnamese';
  static const appearanceAddFont = 'appearanceAddFont';
  static const appearanceAddTextFont = 'appearanceAddTextFont';
  static const appearanceCacheCleaned = 'appearanceCacheCleaned';
  static const appearanceCacheFiles = 'appearanceCacheFiles';
  static const appearanceCacheRefreshed = 'appearanceCacheRefreshed';
  static const appearanceCapUnreadCountAt99 = 'appearanceCapUnreadCountAt99';
  static const appearanceChatList = 'appearanceChatList';
  static const appearanceChatView = 'appearanceChatView';
  static const appearanceCleanUnusedFonts = 'appearanceCleanUnusedFonts';
  static const appearanceCleanableSize = 'appearanceCleanableSize';
  static const appearanceClearTextFonts = 'appearanceClearTextFonts';
  static const appearanceColor = 'appearanceColor';
  static const appearanceDisplay = 'appearanceDisplay';
  static const appearanceDownloadFailed = 'appearanceDownloadFailed';
  static const appearanceEmojiFont = 'appearanceEmojiFont';
  static const appearanceEmojiFontCatalogDescription =
      'appearanceEmojiFontCatalogDescription';
  static const appearanceFileCount = 'appearanceFileCount';
  static const appearanceFont = 'appearanceFont';
  static const appearanceFontCache = 'appearanceFontCache';
  static const appearanceFontCacheDescription =
      'appearanceFontCacheDescription';
  static const appearanceFontChainDescription =
      'appearanceFontChainDescription';
  static const appearanceFontDownloadFailedName =
      'appearanceFontDownloadFailedName';
  static const appearanceFontInUse = 'appearanceFontInUse';
  static const appearanceFontLoadFailed = 'appearanceFontLoadFailed';
  static const appearanceFontSize = 'appearanceFontSize';
  static const appearanceFontUnused = 'appearanceFontUnused';
  static const appearanceGoogleDownloaded = 'appearanceGoogleDownloaded';
  static const appearanceGroupAssistantPosition =
      'appearanceGroupAssistantPosition';
  static const appearanceHidePhoneInSidebar = 'appearanceHidePhoneInSidebar';
  static const appearanceInUseSize = 'appearanceInUseSize';
  static const appearanceInterfaceSize = 'appearanceInterfaceSize';
  static const appearanceManage = 'appearanceManage';
  static const appearanceMergeConsecutiveImages =
      'appearanceMergeConsecutiveImages';
  static const appearanceMode = 'appearanceMode';
  static const appearanceMonospaceFont = 'appearanceMonospaceFont';
  static const appearanceNoCleanableFonts = 'appearanceNoCleanableFonts';
  static const appearanceNoDownloadedFontCache =
      'appearanceNoDownloadedFontCache';
  static const appearanceNoMatchingFonts = 'appearanceNoMatchingFonts';
  static const appearanceRefreshCacheList = 'appearanceRefreshCacheList';
  static const appearanceRoundGroupAvatars = 'appearanceRoundGroupAvatars';
  static const appearanceSearchFont = 'appearanceSearchFont';
  static const appearanceShowChatFiltersOnTop =
      'appearanceShowChatFiltersOnTop';
  static const appearanceShowChatListSearch = 'appearanceShowChatListSearch';
  static const appearanceShowEditAndReadMarks =
      'appearanceShowEditAndReadMarks';
  static const appearanceShowGroupMemberTitles =
      'appearanceShowGroupMemberTitles';
  static const appearanceShowPremiumNameColor =
      'appearanceShowPremiumNameColor';
  static const appearanceShowPremiumStatusEmoji =
      'appearanceShowPremiumStatusEmoji';
  static const appearanceShowUnreadChatCount = 'appearanceShowUnreadChatCount';
  static const appearanceSize = 'appearanceSize';
  static const appearanceSystem = 'appearanceSystem';
  static const appearanceSystemEmojiFont = 'appearanceSystemEmojiFont';
  static const appearanceTextFont = 'appearanceTextFont';
  static const appearanceTextFontOrderHint = 'appearanceTextFontOrderHint';
  static const appearanceTextFontUnsetHint = 'appearanceTextFontUnsetHint';
  static const appearanceTitle = 'appearanceTitle';
  static const appearanceTotalSize = 'appearanceTotalSize';
  static const appearanceUnreadBadge = 'appearanceUnreadBadge';
  static const archivedChatsGroupAssistant = 'archivedChatsGroupAssistant';
  static const audioSearchChatTab = 'audioSearchChatTab';
  static const audioSearchFailed = 'audioSearchFailed';
  static const audioSearchFetchingSource = 'audioSearchFetchingSource';
  static const audioSearchNoResults = 'audioSearchNoResults';
  static const audioSearchPlaceholder = 'audioSearchPlaceholder';
  static const audioSearchSendAudioFailed = 'audioSearchSendAudioFailed';
  static const audioSearchTelegramAudioTitle = 'audioSearchTelegramAudioTitle';
  static const authCodeExpiredRetry = 'authCodeExpiredRetry';
  static const authCodeSent = 'authCodeSent';
  static const authCodeSentByFlashCall = 'authCodeSentByFlashCall';
  static const authCodeSentByPhoneCall = 'authCodeSentByPhoneCall';
  static const authCodeSentBySms = 'authCodeSentBySms';
  static const authCodeSentToTelegramDevices = 'authCodeSentToTelegramDevices';
  static const authInvalidPassword = 'authInvalidPassword';
  static const authInvalidPhoneNumber = 'authInvalidPhoneNumber';
  static const authInvalidVerificationCode = 'authInvalidVerificationCode';
  static const autoDeleteAfterOneDay = 'autoDeleteAfterOneDay';
  static const autoDeleteAfterOneMonth = 'autoDeleteAfterOneMonth';
  static const autoDeleteAfterOneWeek = 'autoDeleteAfterOneWeek';
  static const autoDeleteDescription = 'autoDeleteDescription';
  static const callAccept = 'callAccept';
  static const callCamera = 'callCamera';
  static const callConnecting = 'callConnecting';
  static const callDecline = 'callDecline';
  static const callEndToEndEncrypted = 'callEndToEndEncrypted';
  static const callEnded = 'callEnded';
  static const callFrontCamera = 'callFrontCamera';
  static const callHangUp = 'callHangUp';
  static const callIncomingCallInvite = 'callIncomingCallInvite';
  static const callMute = 'callMute';
  static const callRearCamera = 'callRearCamera';
  static const callSelectCamera = 'callSelectCamera';
  static const callSpeakerphone = 'callSpeakerphone';
  static const callWaitingForInviteAccept = 'callWaitingForInviteAccept';
  static const channelsFileAttachment = 'channelsFileAttachment';
  static const channelsLoading = 'channelsLoading';
  static const channelsNoTopicChannels = 'channelsNoTopicChannels';
  static const chatAdminsOnlyPosting = 'chatAdminsOnlyPosting';
  static const chatAllMembersMuted = 'chatAllMembersMuted';
  static const chatAndOthersCount = 'chatAndOthersCount';
  static const chatAutoDeleteCountdown = 'chatAutoDeleteCountdown';
  static const chatButtonUnsupported = 'chatButtonUnsupported';
  static const chatCannotSendMessages = 'chatCannotSendMessages';
  static const chatContactCallsOnly = 'chatContactCallsOnly';
  static const chatDelete = 'chatDelete';
  static const chatDeleteMessagesQuestion = 'chatDeleteMessagesQuestion';
  static const chatDeleteSelectedMessagesConfirmation =
      'chatDeleteSelectedMessagesConfirmation';
  static const chatDeleteSingleMessageQuestion =
      'chatDeleteSingleMessageQuestion';
  static const chatEditMessageTitle = 'chatEditMessageTitle';
  static const chatForwardFailed = 'chatForwardFailed';
  static const chatForwardToTitle = 'chatForwardToTitle';
  static const chatForwardedToName = 'chatForwardedToName';
  static const chatInfoAlbum = 'chatInfoAlbum';
  static const chatInfoAutoDeleteMessages = 'chatInfoAutoDeleteMessages';
  static const chatInfoAutoDeleteOff = 'chatInfoAutoDeleteOff';
  static const chatInfoAutoDeleteOneDay = 'chatInfoAutoDeleteOneDay';
  static const chatInfoAutoDeleteOneMonth = 'chatInfoAutoDeleteOneMonth';
  static const chatInfoAutoDeleteSevenDays = 'chatInfoAutoDeleteSevenDays';
  static const chatInfoChatFolders = 'chatInfoChatFolders';
  static const chatInfoClear = 'chatInfoClear';
  static const chatInfoClearHistory = 'chatInfoClearHistory';
  static const chatInfoClearHistoryDescription =
      'chatInfoClearHistoryDescription';
  static const chatInfoClearHistoryIrreversibleWarning =
      'chatInfoClearHistoryIrreversibleWarning';
  static const chatInfoClearHistoryQuestion = 'chatInfoClearHistoryQuestion';
  static const chatInfoConfirmAgain = 'chatInfoConfirmAgain';
  static const chatInfoConfirmClearHistory = 'chatInfoConfirmClearHistory';
  static const chatInfoCreate = 'chatInfoCreate';
  static const chatInfoCreateFolderFailed = 'chatInfoCreateFolderFailed';
  static const chatInfoCreateFolderTitle = 'chatInfoCreateFolderTitle';
  static const chatInfoDisableExplicitFolderWarning =
      'chatInfoDisableExplicitFolderWarning';
  static const chatInfoFolderName = 'chatInfoFolderName';
  static const chatInfoFolderNameLabel = 'chatInfoFolderNameLabel';
  static const chatInfoGroupAlbum = 'chatInfoGroupAlbum';
  static const chatInfoGroupApps = 'chatInfoGroupApps';
  static const chatInfoGroupChat = 'chatInfoGroupChat';
  static const chatInfoGroupFiles = 'chatInfoGroupFiles';
  static const chatInfoGroupId = 'chatInfoGroupId';
  static const chatInfoGroupMembers = 'chatInfoGroupMembers';
  static const chatInfoGroupVideos = 'chatInfoGroupVideos';
  static const chatInfoLeaveGroup = 'chatInfoLeaveGroup';
  static const chatInfoLoadFoldersFailed = 'chatInfoLoadFoldersFailed';
  static const chatInfoManageGroup = 'chatInfoManageGroup';
  static const chatInfoMoveToGroupAssistant = 'chatInfoMoveToGroupAssistant';
  static const chatInfoNewFolder = 'chatInfoNewFolder';
  static const chatInfoNoFolders = 'chatInfoNoFolders';
  static const chatInfoNotSearchable = 'chatInfoNotSearchable';
  static const chatInfoPin = 'chatInfoPin';
  static const chatInfoPinChat = 'chatInfoPinChat';
  static const chatInfoPinFailed = 'chatInfoPinFailed';
  static const chatInfoPinFailedWithReason = 'chatInfoPinFailedWithReason';
  static const chatInfoPinLimit = 'chatInfoPinLimit';
  static const chatInfoPinLimitReachedError = 'chatInfoPinLimitReachedError';
  static const chatInfoPinnedHighlights = 'chatInfoPinnedHighlights';
  static const chatInfoRemove = 'chatInfoRemove';
  static const chatInfoSearchHistory = 'chatInfoSearchHistory';
  static const chatInfoTitle = 'chatInfoTitle';
  static const chatInlineSwitchButtonUnsupported =
      'chatInlineSwitchButtonUnsupported';
  static const chatJoinGroup = 'chatJoinGroup';
  static const chatJoinRequestPending = 'chatJoinRequestPending';
  static const chatJoinRequestSent = 'chatJoinRequestSent';
  static const chatListAddFriendOrGroup = 'chatListAddFriendOrGroup';
  static const chatListBlockedPlaceholder = 'chatListBlockedPlaceholder';
  static const chatListChannelName = 'chatListChannelName';
  static const chatListCreateChannel = 'chatListCreateChannel';
  static const chatListCreateChannelFailed = 'chatListCreateChannelFailed';
  static const chatListCreateGroup = 'chatListCreateGroup';
  static const chatListMarkUnread = 'chatListMarkUnread';
  static const chatListUnpin = 'chatListUnpin';
  static const chatLoadingTopics = 'chatLoadingTopics';
  static const chatMeLabel = 'chatMeLabel';
  static const chatMemberCount = 'chatMemberCount';
  static const chatMembersRemoveFailedPermission =
      'chatMembersRemoveFailedPermission';
  static const chatMembersRemoveMemberConfirmation =
      'chatMembersRemoveMemberConfirmation';
  static const chatMembersRemoveMemberTitle = 'chatMembersRemoveMemberTitle';
  static const chatMembersTitleWithCount = 'chatMembersTitleWithCount';
  static const chatMenu = 'chatMenu';
  static const chatMessageInputPlaceholder = 'chatMessageInputPlaceholder';
  static const chatMessageRequired = 'chatMessageRequired';
  static const chatMessagesForwardedCount = 'chatMessagesForwardedCount';
  static const chatMessagesSavedCount = 'chatMessagesSavedCount';
  static const chatMoreActionsUnsupported = 'chatMoreActionsUnsupported';
  static const chatNewMessagesCount = 'chatNewMessagesCount';
  static const chatNewMessagesDivider = 'chatNewMessagesDivider';
  static const chatNoTopics = 'chatNoTopics';
  static const chatOffline = 'chatOffline';
  static const chatOnline = 'chatOnline';
  static const chatOnlineWithinMonth = 'chatOnlineWithinMonth';
  static const chatOnlineWithinWeek = 'chatOnlineWithinWeek';
  static const chatPeopleTyping = 'chatPeopleTyping';
  static const chatPickerChooseChat = 'chatPickerChooseChat';
  static const chatRecentlyOnline = 'chatRecentlyOnline';
  static const chatRequestToJoin = 'chatRequestToJoin';
  static const chatRestrictedAcknowledge = 'chatRestrictedAcknowledge';
  static const chatRestrictedLeaveFailed = 'chatRestrictedLeaveFailed';
  static const chatRestrictedTelegramTosMessage =
      'chatRestrictedTelegramTosMessage';
  static const chatRestrictedTitle = 'chatRestrictedTitle';
  static const chatSaveFailed = 'chatSaveFailed';
  static const chatSavedToSavedMessages = 'chatSavedToSavedMessages';
  static const chatSearchHistoryTitle = 'chatSearchHistoryTitle';
  static const chatSearchMessagePlaceholder = 'chatSearchMessagePlaceholder';
  static const chatSearchMessageResultLabel = 'chatSearchMessageResultLabel';
  static const chatSearchNoMessagesFound = 'chatSearchNoMessagesFound';
  static const chatSelectUntilHere = 'chatSelectUntilHere';
  static const chatSelectedMessagesCount = 'chatSelectedMessagesCount';
  static const chatStickerAddSuccess = 'chatStickerAddSuccess';
  static const chatTodoSetFailed = 'chatTodoSetFailed';
  static const chatTodoSetSuccess = 'chatTodoSetSuccess';
  static const chatTodoUnsetFailed = 'chatTodoUnsetFailed';
  static const chatTodoUnsetSuccess = 'chatTodoUnsetSuccess';
  static const chatTranslateFailed = 'chatTranslateFailed';
  static const chatTyping = 'chatTyping';
  static const chatUnmute = 'chatUnmute';
  static const chatUserFallbackName = 'chatUserFallbackName';
  static const chatUserLeftGroup = 'chatUserLeftGroup';
  static const chatUserTyping = 'chatUserTyping';
  static const chatUsersJoinedGroup = 'chatUsersJoinedGroup';
  static const chatVideoPlaceholder = 'chatVideoPlaceholder';
  static const chatYouAreMuted = 'chatYouAreMuted';
  static const chatYouWereRemovedFromGroup = 'chatYouWereRemovedFromGroup';
  static const chatsSearchBots = 'chatsSearchBots';
  static const chatsSearchNoResults = 'chatsSearchNoResults';
  static const chatsSearchPlaceholder = 'chatsSearchPlaceholder';
  static const chatsSearchPublicGroupsAndChannels =
      'chatsSearchPublicGroupsAndChannels';
  static const checklistComposerAddTask = 'checklistComposerAddTask';
  static const checklistComposerNewChecklistTitle =
      'checklistComposerNewChecklistTitle';
  static const checklistComposerPremiumLimitHint =
      'checklistComposerPremiumLimitHint';
  static const checklistComposerTaskLabel = 'checklistComposerTaskLabel';
  static const checklistComposerTitleLabel = 'checklistComposerTitleLabel';
  static const commonUiDraftBadge = 'commonUiDraftBadge';
  static const commonUiGroupOwner = 'commonUiGroupOwner';
  static const commonUiMentionMeBadge = 'commonUiMentionMeBadge';
  static const commonUiMentionedBySomeoneBadge =
      'commonUiMentionedBySomeoneBadge';
  static const commonUiNewFileBadge = 'commonUiNewFileBadge';
  static const composerAnimatedEmojiPreview = 'composerAnimatedEmojiPreview';
  static const composerAudio = 'composerAudio';
  static const composerCamera = 'composerCamera';
  static const composerChecklist = 'composerChecklist';
  static const composerClipboardNoImage = 'composerClipboardNoImage';
  static const composerFilePreview = 'composerFilePreview';
  static const composerHoldToTalk = 'composerHoldToTalk';
  static const composerImage = 'composerImage';
  static const composerImagePreview = 'composerImagePreview';
  static const composerLoadingEmoji = 'composerLoadingEmoji';
  static const composerLocation = 'composerLocation';
  static const composerLocationPreview = 'composerLocationPreview';
  static const composerMarkdownSupportHint = 'composerMarkdownSupportHint';
  static const composerMicrophonePermissionRequired =
      'composerMicrophonePermissionRequired';
  static const composerMicrophonePermissionSettings =
      'composerMicrophonePermissionSettings';
  static const composerNoEmoji = 'composerNoEmoji';
  static const composerOpenAttachmentFailed = 'composerOpenAttachmentFailed';
  static const composerOpenMenu = 'composerOpenMenu';
  static const composerPaidMessageCost = 'composerPaidMessageCost';
  static const composerPastedImageReadFailed = 'composerPastedImageReadFailed';
  static const composerPoll = 'composerPoll';
  static const composerReleaseFingerToCancel = 'composerReleaseFingerToCancel';
  static const composerReleaseToSendSlideToCancel =
      'composerReleaseToSendSlideToCancel';
  static const composerRichText = 'composerRichText';
  static const composerRichTextMessageTitle = 'composerRichTextMessageTitle';
  static const composerSend = 'composerSend';
  static const composerSendPaidMessageQuestion =
      'composerSendPaidMessageQuestion';
  static const composerVideoCall = 'composerVideoCall';
  static const composerVoiceCall = 'composerVoiceCall';
  static const composerVoicePreview = 'composerVoicePreview';
  static const confirmOk = 'confirmOk';
  static const contactsFriends = 'contactsFriends';
  static const contactsLoading = 'contactsLoading';
  static const contactsNoBots = 'contactsNoBots';
  static const contactsNoChannels = 'contactsNoChannels';
  static const contactsNoContacts = 'contactsNoContacts';
  static const contactsNoGroupChats = 'contactsNoGroupChats';
  static const countryAF = 'countryAF';
  static const countryAL = 'countryAL';
  static const countryDZ = 'countryDZ';
  static const countryAD = 'countryAD';
  static const countryAO = 'countryAO';
  static const countryAR = 'countryAR';
  static const countryAM = 'countryAM';
  static const countryAU = 'countryAU';
  static const countryAT = 'countryAT';
  static const countryAZ = 'countryAZ';
  static const countryBH = 'countryBH';
  static const countryBD = 'countryBD';
  static const countryBY = 'countryBY';
  static const countryBE = 'countryBE';
  static const countryBZ = 'countryBZ';
  static const countryBJ = 'countryBJ';
  static const countryBT = 'countryBT';
  static const countryBO = 'countryBO';
  static const countryBA = 'countryBA';
  static const countryBW = 'countryBW';
  static const countryBR = 'countryBR';
  static const countryBN = 'countryBN';
  static const countryBG = 'countryBG';
  static const countryBF = 'countryBF';
  static const countryKH = 'countryKH';
  static const countryCM = 'countryCM';
  static const countryCA = 'countryCA';
  static const countryTD = 'countryTD';
  static const countryCL = 'countryCL';
  static const countryCN = 'countryCN';
  static const countryCO = 'countryCO';
  static const countryCR = 'countryCR';
  static const countryCI = 'countryCI';
  static const countryHR = 'countryHR';
  static const countryCU = 'countryCU';
  static const countryCY = 'countryCY';
  static const countryCZ = 'countryCZ';
  static const countryCD = 'countryCD';
  static const countryDK = 'countryDK';
  static const countryEC = 'countryEC';
  static const countryEG = 'countryEG';
  static const countrySV = 'countrySV';
  static const countryEE = 'countryEE';
  static const countryET = 'countryET';
  static const countryFJ = 'countryFJ';
  static const countryFI = 'countryFI';
  static const countryFR = 'countryFR';
  static const countryGA = 'countryGA';
  static const countryGE = 'countryGE';
  static const countryDE = 'countryDE';
  static const countryGH = 'countryGH';
  static const countryGR = 'countryGR';
  static const countryGT = 'countryGT';
  static const countryGN = 'countryGN';
  static const countryGY = 'countryGY';
  static const countryHT = 'countryHT';
  static const countryHN = 'countryHN';
  static const countryHK = 'countryHK';
  static const countryHU = 'countryHU';
  static const countryIS = 'countryIS';
  static const countryIN = 'countryIN';
  static const countryID = 'countryID';
  static const countryIR = 'countryIR';
  static const countryIQ = 'countryIQ';
  static const countryIE = 'countryIE';
  static const countryIL = 'countryIL';
  static const countryIT = 'countryIT';
  static const countryJP = 'countryJP';
  static const countryJO = 'countryJO';
  static const countryKZ = 'countryKZ';
  static const countryKE = 'countryKE';
  static const countryXK = 'countryXK';
  static const countryKW = 'countryKW';
  static const countryKG = 'countryKG';
  static const countryLA = 'countryLA';
  static const countryLV = 'countryLV';
  static const countryLB = 'countryLB';
  static const countryLY = 'countryLY';
  static const countryLI = 'countryLI';
  static const countryLT = 'countryLT';
  static const countryLU = 'countryLU';
  static const countryMO = 'countryMO';
  static const countryMG = 'countryMG';
  static const countryMW = 'countryMW';
  static const countryMY = 'countryMY';
  static const countryMV = 'countryMV';
  static const countryML = 'countryML';
  static const countryMT = 'countryMT';
  static const countryMR = 'countryMR';
  static const countryMU = 'countryMU';
  static const countryMX = 'countryMX';
  static const countryMD = 'countryMD';
  static const countryMC = 'countryMC';
  static const countryMN = 'countryMN';
  static const countryME = 'countryME';
  static const countryMA = 'countryMA';
  static const countryMZ = 'countryMZ';
  static const countryMM = 'countryMM';
  static const countryNA = 'countryNA';
  static const countryNP = 'countryNP';
  static const countryNL = 'countryNL';
  static const countryNZ = 'countryNZ';
  static const countryNI = 'countryNI';
  static const countryNE = 'countryNE';
  static const countryNG = 'countryNG';
  static const countryKP = 'countryKP';
  static const countryMK = 'countryMK';
  static const countryNO = 'countryNO';
  static const countryOM = 'countryOM';
  static const countryPK = 'countryPK';
  static const countryPS = 'countryPS';
  static const countryPA = 'countryPA';
  static const countryPG = 'countryPG';
  static const countryPY = 'countryPY';
  static const countryPE = 'countryPE';
  static const countryPH = 'countryPH';
  static const countryPickerCancel = 'countryPickerCancel';
  static const countryPickerSearchPlaceholder =
      'countryPickerSearchPlaceholder';
  static const countryPickerSelectCountryOrRegion =
      'countryPickerSelectCountryOrRegion';
  static const countryPL = 'countryPL';
  static const countryPT = 'countryPT';
  static const countryQA = 'countryQA';
  static const countryCG = 'countryCG';
  static const countryRO = 'countryRO';
  static const countryRU = 'countryRU';
  static const countryRW = 'countryRW';
  static const countryWS = 'countryWS';
  static const countrySM = 'countrySM';
  static const countrySA = 'countrySA';
  static const countrySN = 'countrySN';
  static const countryRS = 'countryRS';
  static const countrySG = 'countrySG';
  static const countrySK = 'countrySK';
  static const countrySI = 'countrySI';
  static const countrySB = 'countrySB';
  static const countrySO = 'countrySO';
  static const countryZA = 'countryZA';
  static const countryKR = 'countryKR';
  static const countrySS = 'countrySS';
  static const countryES = 'countryES';
  static const countryLK = 'countryLK';
  static const countrySD = 'countrySD';
  static const countrySR = 'countrySR';
  static const countrySE = 'countrySE';
  static const countryCH = 'countryCH';
  static const countrySY = 'countrySY';
  static const countryTW = 'countryTW';
  static const countryTJ = 'countryTJ';
  static const countryTZ = 'countryTZ';
  static const countryTH = 'countryTH';
  static const countryTL = 'countryTL';
  static const countryTG = 'countryTG';
  static const countryTO = 'countryTO';
  static const countryTN = 'countryTN';
  static const countryTR = 'countryTR';
  static const countryTM = 'countryTM';
  static const countryUG = 'countryUG';
  static const countryUA = 'countryUA';
  static const countryAE = 'countryAE';
  static const countryGB = 'countryGB';
  static const countryUS = 'countryUS';
  static const countryUY = 'countryUY';
  static const countryUZ = 'countryUZ';
  static const countryVU = 'countryVU';
  static const countryVE = 'countryVE';
  static const countryVN = 'countryVN';
  static const countryYE = 'countryYE';
  static const countryZM = 'countryZM';
  static const countryZW = 'countryZW';
  static const createGroupFailed = 'createGroupFailed';
  static const createGroupOptionalLabel = 'createGroupOptionalLabel';
  static const createGroupStartGroupChat = 'createGroupStartGroupChat';
  static const editProfileAvatarUpdateFailed = 'editProfileAvatarUpdateFailed';
  static const editProfileAvatarUpdated = 'editProfileAvatarUpdated';
  static const editProfileBio = 'editProfileBio';
  static const editProfileBioPlaceholder = 'editProfileBioPlaceholder';
  static const editProfileBirthDay = 'editProfileBirthDay';
  static const editProfileBirthMonth = 'editProfileBirthMonth';
  static const editProfileBirthYear = 'editProfileBirthYear';
  static const editProfileChangeAvatar = 'editProfileChangeAvatar';
  static const editProfileChangeBio = 'editProfileChangeBio';
  static const editProfileChangeName = 'editProfileChangeName';
  static const editProfileChangeUsername = 'editProfileChangeUsername';
  static const editProfileClearBirthday = 'editProfileClearBirthday';
  static const editProfileDefault = 'editProfileDefault';
  static const editProfileInvalidAvatarFile = 'editProfileInvalidAvatarFile';
  static const editProfileNameColor = 'editProfileNameColor';
  static const editProfileNameColorDescription =
      'editProfileNameColorDescription';
  static const editProfileNoBirthYear = 'editProfileNoBirthYear';
  static const editProfileNotBound = 'editProfileNotBound';
  static const editProfilePhone = 'editProfilePhone';
  static const editProfileProfileColor = 'editProfileProfileColor';
  static const editProfileProfileColorDescription =
      'editProfileProfileColorDescription';
  static const editProfileSaveFailed = 'editProfileSaveFailed';
  static const editProfileSetUsername = 'editProfileSetUsername';
  static const editProfileTapToFillBio = 'editProfileTapToFillBio';
  static const editProfileTapToSet = 'editProfileTapToSet';
  static const editProfileTitle = 'editProfileTitle';
  static const editProfileUsername = 'editProfileUsername';
  static const editProfileUsernameUnavailable =
      'editProfileUsernameUnavailable';
  static const editProfileUsernameUnsetHandle =
      'editProfileUsernameUnsetHandle';
  static const emojiCategoryActivitiesAndSports =
      'emojiCategoryActivitiesAndSports';
  static const emojiCategoryAnimalsAndNature = 'emojiCategoryAnimalsAndNature';
  static const emojiCategoryFoodAndDrink = 'emojiCategoryFoodAndDrink';
  static const emojiCategoryObjects = 'emojiCategoryObjects';
  static const emojiCategoryPeopleAndBody = 'emojiCategoryPeopleAndBody';
  static const emojiCategorySmileysAndEmotion =
      'emojiCategorySmileysAndEmotion';
  static const emojiCategorySymbols = 'emojiCategorySymbols';
  static const emojiCategoryTravelAndPlaces = 'emojiCategoryTravelAndPlaces';
  static const emojiFontCatalogSystemDefault = 'emojiFontCatalogSystemDefault';
  static const emojiPreviewFaceWithTearsOfJoy =
      'emojiPreviewFaceWithTearsOfJoy';
  static const emojiStatusClear = 'emojiStatusClear';
  static const emojiStatusNoAvailableStatuses =
      'emojiStatusNoAvailableStatuses';
  static const emojiStatusNoAvailableStatusesPremiumRequired =
      'emojiStatusNoAvailableStatusesPremiumRequired';
  static const emojiStatusSetRequiresPremiumFailed =
      'emojiStatusSetRequiresPremiumFailed';
  static const emojiStatusSetTitle = 'emojiStatusSetTitle';
  static const featureBottomTabs = 'featureBottomTabs';
  static const featureTitle = 'featureTitle';
  static const fileDetailDownloadProgress = 'fileDetailDownloadProgress';
  static const fileDetailNoAppCanOpenFile = 'fileDetailNoAppCanOpenFile';
  static const fileDetailOpen = 'fileDetailOpen';
  static const generalAppLanguage = 'generalAppLanguage';
  static const generalCacheSize = 'generalCacheSize';
  static const generalClearCache = 'generalClearCache';
  static const generalClearingCache = 'generalClearingCache';
  static const generalOpenChatAtLatestMessage =
      'generalOpenChatAtLatestMessage';
  static const generalSendMessageWithEnter = 'generalSendMessageWithEnter';
  static const generalStorage = 'generalStorage';
  static const generalTitle = 'generalTitle';
  static const groupManagementAdminApprovalRequired =
      'groupManagementAdminApprovalRequired';
  static const groupManagementBasicSection = 'groupManagementBasicSection';
  static const groupManagementEditFailed = 'groupManagementEditFailed';
  static const groupManagementEditable = 'groupManagementEditable';
  static const groupManagementGroupName = 'groupManagementGroupName';
  static const groupManagementInviteLinkQr = 'groupManagementInviteLinkQr';
  static const groupManagementJoinBeforePosting =
      'groupManagementJoinBeforePosting';
  static const groupManagementJoinSection = 'groupManagementJoinSection';
  static const groupManagementLoadFailed = 'groupManagementLoadFailed';
  static const groupManagementLogAdmin = 'groupManagementLogAdmin';
  static const groupManagementLogApprovedJoinRequest =
      'groupManagementLogApprovedJoinRequest';
  static const groupManagementLogChangedAdmin =
      'groupManagementLogChangedAdmin';
  static const groupManagementLogChangedGroupDescription =
      'groupManagementLogChangedGroupDescription';
  static const groupManagementLogChangedGroupName =
      'groupManagementLogChangedGroupName';
  static const groupManagementLogChangedGroupPhoto =
      'groupManagementLogChangedGroupPhoto';
  static const groupManagementLogChangedLinkedChat =
      'groupManagementLogChangedLinkedChat';
  static const groupManagementLogChangedMemberPermissions =
      'groupManagementLogChangedMemberPermissions';
  static const groupManagementLogChangedPostingPermissions =
      'groupManagementLogChangedPostingPermissions';
  static const groupManagementLogChangedPublicUsername =
      'groupManagementLogChangedPublicUsername';
  static const groupManagementLogChangedSlowMode =
      'groupManagementLogChangedSlowMode';
  static const groupManagementLogCreatedTopic =
      'groupManagementLogCreatedTopic';
  static const groupManagementLogDeletedInviteLink =
      'groupManagementLogDeletedInviteLink';
  static const groupManagementLogDeletedMessage =
      'groupManagementLogDeletedMessage';
  static const groupManagementLogDeletedTopic =
      'groupManagementLogDeletedTopic';
  static const groupManagementLogEditedInviteLink =
      'groupManagementLogEditedInviteLink';
  static const groupManagementLogEditedMessage =
      'groupManagementLogEditedMessage';
  static const groupManagementLogEditedTopic = 'groupManagementLogEditedTopic';
  static const groupManagementLogEmpty = 'groupManagementLogEmpty';
  static const groupManagementLogEndedVideoChat =
      'groupManagementLogEndedVideoChat';
  static const groupManagementLogGenericAdminAction =
      'groupManagementLogGenericAdminAction';
  static const groupManagementLogInvitedMember =
      'groupManagementLogInvitedMember';
  static const groupManagementLogJoinedByInviteLink =
      'groupManagementLogJoinedByInviteLink';
  static const groupManagementLogJoinedGroup = 'groupManagementLogJoinedGroup';
  static const groupManagementLogLeftGroup = 'groupManagementLogLeftGroup';
  static const groupManagementLogNoPermission =
      'groupManagementLogNoPermission';
  static const groupManagementLogPinnedMessage =
      'groupManagementLogPinnedMessage';
  static const groupManagementLogRevokedInviteLink =
      'groupManagementLogRevokedInviteLink';
  static const groupManagementLogStartedVideoChat =
      'groupManagementLogStartedVideoChat';
  static const groupManagementLogTitle = 'groupManagementLogTitle';
  static const groupManagementLogUnpinnedMessage =
      'groupManagementLogUnpinnedMessage';
  static const groupManagementMembers = 'groupManagementMembers';
  static const groupManagementMembersSection = 'groupManagementMembersSection';
  static const groupManagementNoEditInfoPermission =
      'groupManagementNoEditInfoPermission';
  static const groupManagementNotSet = 'groupManagementNotSet';
  static const groupManagementPermissionCreateTopics =
      'groupManagementPermissionCreateTopics';
  static const groupManagementPermissionEditGroupInfo =
      'groupManagementPermissionEditGroupInfo';
  static const groupManagementPermissionLinkPreviews =
      'groupManagementPermissionLinkPreviews';
  static const groupManagementPermissionPinMessages =
      'groupManagementPermissionPinMessages';
  static const groupManagementPermissionSendFiles =
      'groupManagementPermissionSendFiles';
  static const groupManagementPermissionSendMessages =
      'groupManagementPermissionSendMessages';
  static const groupManagementPermissionSendMusic =
      'groupManagementPermissionSendMusic';
  static const groupManagementPermissionSendPhotos =
      'groupManagementPermissionSendPhotos';
  static const groupManagementPermissionSendPolls =
      'groupManagementPermissionSendPolls';
  static const groupManagementPermissionSendStickersAndGifs =
      'groupManagementPermissionSendStickersAndGifs';
  static const groupManagementPermissionSendVideoMessages =
      'groupManagementPermissionSendVideoMessages';
  static const groupManagementPermissionSendVideos =
      'groupManagementPermissionSendVideos';
  static const groupManagementPermissionSendVoice =
      'groupManagementPermissionSendVoice';
  static const groupManagementPermissionSetFailed =
      'groupManagementPermissionSetFailed';
  static const groupManagementPostingPermissions =
      'groupManagementPostingPermissions';
  static const groupManagementPublicUsername = 'groupManagementPublicUsername';
  static const groupManagementReadOnly = 'groupManagementReadOnly';
  static const groupManagementSetFailed = 'groupManagementSetFailed';
  static const groupManagementUsernameUnavailableOrForbidden =
      'groupManagementUsernameUnavailableOrForbidden';
  static const imageEditAdd = 'imageEditAdd';
  static const imageEditAddText = 'imageEditAddText';
  static const imageEditBrush = 'imageEditBrush';
  static const imageEditCaptionInputPlaceholder =
      'imageEditCaptionInputPlaceholder';
  static const imageEditCrop = 'imageEditCrop';
  static const imageEditCropAvatar = 'imageEditCropAvatar';
  static const imageEditDescriptionPlaceholder =
      'imageEditDescriptionPlaceholder';
  static const imageEditObscure = 'imageEditObscure';
  static const imageEditProcessing = 'imageEditProcessing';
  static const imageEditResetCrop = 'imageEditResetCrop';
  static const imageEditRotate = 'imageEditRotate';
  static const imageEditTextTool = 'imageEditTextTool';
  static const imageEditTitle = 'imageEditTitle';
  static const keywordBlockerDescription = 'keywordBlockerDescription';
  static const keywordBlockerDownload = 'keywordBlockerDownload';
  static const keywordBlockerDownloadFailed = 'keywordBlockerDownloadFailed';
  static const keywordBlockerInputPlaceholder =
      'keywordBlockerInputPlaceholder';
  static const keywordBlockerListUrl = 'keywordBlockerListUrl';
  static const keywordBlockerRulesAdded = 'keywordBlockerRulesAdded';
  static const keywordBlockerRulesUpToDate = 'keywordBlockerRulesUpToDate';
  static const keywordBlockerTitle = 'keywordBlockerTitle';
  static const languageTitle = 'languageTitle';
  static const linkHandlerGroupLabel = 'linkHandlerGroupLabel';
  static const linkHandlerJoin = 'linkHandlerJoin';
  static const linkHandlerJoinNamedGroupQuestion =
      'linkHandlerJoinNamedGroupQuestion';
  static const linkHandlerOpenTelegramLinkFailed =
      'linkHandlerOpenTelegramLinkFailed';
  static const linkHandlerQrLoginWarning = 'linkHandlerQrLoginWarning';
  static const linkHandlerUnsupportedTelegramLink =
      'linkHandlerUnsupportedTelegramLink';
  static const listSeparator = 'listSeparator';
  static const locationDetailFetchingLocation =
      'locationDetailFetchingLocation';
  static const locationPickerDragMapToChoose = 'locationPickerDragMapToChoose';
  static const loginBackToAccount = 'loginBackToAccount';
  static const loginBackToPreviousAccount = 'loginBackToPreviousAccount';
  static const loginCodeWillBeSentToNumber = 'loginCodeWillBeSentToNumber';
  static const loginCompleteRegistration = 'loginCompleteRegistration';
  static const loginFirstName = 'loginFirstName';
  static const loginGetVerificationCode = 'loginGetVerificationCode';
  static const loginLastNameOptional = 'loginLastNameOptional';
  static const loginNewAccountNicknamePrompt = 'loginNewAccountNicknamePrompt';
  static const loginPasswordHint = 'loginPasswordHint';
  static const loginPhoneNumberWithCountryCode =
      'loginPhoneNumberWithCountryCode';
  static const loginQrCodeSubtitle = 'loginQrCodeSubtitle';
  static const loginQrCodeTitle = 'loginQrCodeTitle';
  static const loginReenterPhoneNumber = 'loginReenterPhoneNumber';
  static const loginRefreshQrCode = 'loginRefreshQrCode';
  static const loginResendVerificationCode = 'loginResendVerificationCode';
  static const loginSubmit = 'loginSubmit';
  static const loginSwitchAccount = 'loginSwitchAccount';
  static const loginTelegramAccountTitle = 'loginTelegramAccountTitle';
  static const loginTelegramApiCredentialsMissing =
      'loginTelegramApiCredentialsMissing';
  static const loginTelegramApiPortalInstructions =
      'loginTelegramApiPortalInstructions';
  static const loginTelegramApiSecretsInstructions =
      'loginTelegramApiSecretsInstructions';
  static const loginTwoStepPassword = 'loginTwoStepPassword';
  static const loginVerificationCode = 'loginVerificationCode';
  static const loginVerify = 'loginVerify';
  static const loginWithQrCode = 'loginWithQrCode';
  static const markdownLabel = 'markdownLabel';
  static const messageActionCopy = 'messageActionCopy';
  static const messageActionSelectText = 'messageActionSelectText';
  static const messageActionEdit = 'messageActionEdit';
  static const messageActionFavorite = 'messageActionFavorite';
  static const messageActionForward = 'messageActionForward';
  static const messageActionMultiSelect = 'messageActionMultiSelect';
  static const messageActionPlayMuted = 'messageActionPlayMuted';
  static const messageActionQuote = 'messageActionQuote';
  static const messageActionSetTodo = 'messageActionSetTodo';
  static const messageActionSticker = 'messageActionSticker';
  static const messageActionTranslate = 'messageActionTranslate';
  static const messageActionUnsetTodo = 'messageActionUnsetTodo';
  static const messageBubbleCallCanceled = 'messageBubbleCallCanceled';
  static const messageBubbleCallDeclined = 'messageBubbleCallDeclined';
  static const messageBubbleCallDeclinedByOther =
      'messageBubbleCallDeclinedByOther';
  static const messageBubbleCallDuration = 'messageBubbleCallDuration';
  static const messageBubbleCallMissed = 'messageBubbleCallMissed';
  static const messageBubbleCallNoAnswer = 'messageBubbleCallNoAnswer';
  static const messageBubbleCollapse = 'messageBubbleCollapse';
  static const messageBubbleExpandQuote = 'messageBubbleExpandQuote';
  static const messageBubbleForwardedFrom = 'messageBubbleForwardedFrom';
  static const messageBubbleTranslating = 'messageBubbleTranslating';
  static const momentsCommentCount = 'momentsCommentCount';
  static const momentsCommentPlaceholder = 'momentsCommentPlaceholder';
  static const momentsCreatePostTitle = 'momentsCreatePostTitle';
  static const momentsDetails = 'momentsDetails';
  static const momentsLikeFailed = 'momentsLikeFailed';
  static const momentsLiked = 'momentsLiked';
  static const momentsLikedByCount = 'momentsLikedByCount';
  static const momentsLikedByListWithOthers = 'momentsLikedByListWithOthers';
  static const momentsLoadingPosts = 'momentsLoadingPosts';
  static const momentsMore = 'momentsMore';
  static const momentsNewPostsCount = 'momentsNewPostsCount';
  static const momentsNoChannelContent = 'momentsNoChannelContent';
  static const momentsNoComments = 'momentsNoComments';
  static const momentsNoFriendPosts = 'momentsNoFriendPosts';
  static const momentsNoPostableChannels = 'momentsNoPostableChannels';
  static const momentsNoPostsFound = 'momentsNoPostsFound';
  static const momentsNoSearchableChannels = 'momentsNoSearchableChannels';
  static const momentsNotifySubscribers = 'momentsNotifySubscribers';
  static const momentsOpenOriginalMessage = 'momentsOpenOriginalMessage';
  static const momentsPickPhotoFailed = 'momentsPickPhotoFailed';
  static const momentsPostAction = 'momentsPostAction';
  static const momentsPostFailed = 'momentsPostFailed';
  static const momentsPostedTo = 'momentsPostedTo';
  static const momentsPublishTo = 'momentsPublishTo';
  static const momentsReplied = 'momentsReplied';
  static const momentsReplyFailed = 'momentsReplyFailed';
  static const momentsReplyPrefix = 'momentsReplyPrefix';
  static const momentsReplyToPlaceholder = 'momentsReplyToPlaceholder';
  static const momentsReplyToUser = 'momentsReplyToUser';
  static const momentsReplyToUserPlaceholder = 'momentsReplyToUserPlaceholder';
  static const momentsReplyUnavailable = 'momentsReplyUnavailable';
  static const momentsSearchChannelPosts = 'momentsSearchChannelPosts';
  static const momentsSearchJoinedChannelPosts =
      'momentsSearchJoinedChannelPosts';
  static const momentsSearching = 'momentsSearching';
  static const momentsSelectChannel = 'momentsSelectChannel';
  static const momentsSending = 'momentsSending';
  static const momentsShareSomethingPlaceholder =
      'momentsShareSomethingPlaceholder';
  static const momentsStories = 'momentsStories';
  static const momentsUnknown = 'momentsUnknown';
  static const momentsUserLiked = 'momentsUserLiked';
  static const myAlbumNoPhotos = 'myAlbumNoPhotos';
  static const netemoMusicLabel = 'netemoMusicLabel';
  static const notificationGroupMessages = 'notificationGroupMessages';
  static const notificationPreview = 'notificationPreview';
  static const notificationPrivateMessages = 'notificationPrivateMessages';
  static const notificationSound = 'notificationSound';
  static const notificationTitle = 'notificationTitle';
  static const pinnedMessagesEmpty = 'pinnedMessagesEmpty';
  static const pinnedMessagesSentBy = 'pinnedMessagesSentBy';
  static const pollComposerAddOption = 'pollComposerAddOption';
  static const pollComposerCreatePollTitle = 'pollComposerCreatePollTitle';
  static const pollComposerOptionLabel = 'pollComposerOptionLabel';
  static const pollComposerQuestionRequired = 'pollComposerQuestionRequired';
  static const pollComposerSingleChoiceLimitHint =
      'pollComposerSingleChoiceLimitHint';
  static const premiumLabel = 'premiumLabel';
  static const privacyBlockedUsers = 'privacyBlockedUsers';
  static const privacyBlockedUsersEmpty = 'privacyBlockedUsersEmpty';
  static const privacyCurrentDevice = 'privacyCurrentDevice';
  static const privacyDeviceApp = 'privacyDeviceApp';
  static const privacyDisabled = 'privacyDisabled';
  static const privacyEnabled = 'privacyEnabled';
  static const privacyLastSeen = 'privacyLastSeen';
  static const privacyLoggedInDevices = 'privacyLoggedInDevices';
  static const privacyOtherDevices = 'privacyOtherDevices';
  static const privacyProfilePhoto = 'privacyProfilePhoto';
  static const privacySectionTitle = 'privacySectionTitle';
  static const privacySecuritySectionTitle = 'privacySecuritySectionTitle';
  static const privacySecurityTitle = 'privacySecurityTitle';
  static const privacyTerminateAllOtherSessions =
      'privacyTerminateAllOtherSessions';
  static const privacyTerminateSession = 'privacyTerminateSession';
  static const privacyTwoStepVerification = 'privacyTwoStepVerification';
  static const privacyUnblock = 'privacyUnblock';
  static const privacyVisibilityContacts = 'privacyVisibilityContacts';
  static const privacyVisibilityEveryone = 'privacyVisibilityEveryone';
  static const privacyVisibilityNobody = 'privacyVisibilityNobody';
  static const profileAddAccount = 'profileAddAccount';
  static const profileDayMode = 'profileDayMode';
  static const profileDetailAudioVideoCall = 'profileDetailAudioVideoCall';
  static const profileDetailBio = 'profileDetailBio';
  static const profileDetailBirthday = 'profileDetailBirthday';
  static const profileDetailCardLinkCopied = 'profileDetailCardLinkCopied';
  static const profileDetailFeaturedPhotos = 'profileDetailFeaturedPhotos';
  static const profileDetailLocation = 'profileDetailLocation';
  static const profileDetailMediaFiles = 'profileDetailMediaFiles';
  static const profileDetailMonthDayDate = 'profileDetailMonthDayDate';
  static const profileDetailMusic = 'profileDetailMusic';
  static const profileDetailSendMessage = 'profileDetailSendMessage';
  static const profileDetailYearMonthDate = 'profileDetailYearMonthDate';
  static const profileNightMode = 'profileNightMode';
  static const profileRemoveAccount = 'profileRemoveAccount';
  static const profileRemoveAccountConfirm = 'profileRemoveAccountConfirm';
  static const profileSettings = 'profileSettings';
  static const proxyAddFailed = 'proxyAddFailed';
  static const proxyAddProxy = 'proxyAddProxy';
  static const proxyDeleteProxy = 'proxyDeleteProxy';
  static const proxyDescription = 'proxyDescription';
  static const proxyDisabled = 'proxyDisabled';
  static const proxyHostOrIp = 'proxyHostOrIp';
  static const proxyOptional = 'proxyOptional';
  static const proxyPassword = 'proxyPassword';
  static const proxyPort = 'proxyPort';
  static const proxySecret = 'proxySecret';
  static const proxyServer = 'proxyServer';
  static const proxyTitle = 'proxyTitle';
  static const qrCodeGroupTitle = 'qrCodeGroupTitle';
  static const qrCodeMineTitle = 'qrCodeMineTitle';
  static const qrCodeNoGroupQrCode = 'qrCodeNoGroupQrCode';
  static const qrCodeScanToAddFriend = 'qrCodeScanToAddFriend';
  static const qrCodeScanToJoinGroup = 'qrCodeScanToJoinGroup';
  static const richTextComposerContentPlaceholder =
      'richTextComposerContentPlaceholder';
  static const richTextComposerPhotoVideo = 'richTextComposerPhotoVideo';
  static const settingsAboutMithka = 'settingsAboutMithka';
  static const settingsLogOut = 'settingsLogOut';
  static const sharedMediaChatFiles = 'sharedMediaChatFiles';
  static const sharedMediaEmpty = 'sharedMediaEmpty';
  static const sharedMediaLinks = 'sharedMediaLinks';
  static const sharedMediaPhotosAndVideos = 'sharedMediaPhotosAndVideos';
  static const sharedMediaVideos = 'sharedMediaVideos';
  static const sharedMediaVoice = 'sharedMediaVoice';
  static const sharedMediaVoiceMessages = 'sharedMediaVoiceMessages';
  static const startButton = 'startButton';
  static const stickerSetDetailActionFailed = 'stickerSetDetailActionFailed';
  static const stickerSetDetailAddSuccess = 'stickerSetDetailAddSuccess';
  static const stickerSetDetailRemoved = 'stickerSetDetailRemoved';
  static const stickerSetDetailStickerCount = 'stickerSetDetailStickerCount';
  static const stickerSetDetailTitle = 'stickerSetDetailTitle';
  static const stickerStoreRecent = 'stickerStoreRecent';
  static const stickerViewerInCollection = 'stickerViewerInCollection';
  static const stickerViewerView = 'stickerViewerView';
  static const storyLoadFailed = 'storyLoadFailed';
  static const storyUnsupported = 'storyUnsupported';
  static const tabChannels = 'tabChannels';
  static const tabContacts = 'tabContacts';
  static const tabFriendMoments = 'tabFriendMoments';
  static const tabMessages = 'tabMessages';
  static const tabMoments = 'tabMoments';
  static const tabSelectChannelContent = 'tabSelectChannelContent';
  static const tabSelectContact = 'tabSelectContact';
  static const tdMessageAutoDeleteTimerChanged =
      'tdMessageAutoDeleteTimerChanged';
  static const tdMessageAutoDeleteTimerDisabled =
      'tdMessageAutoDeleteTimerDisabled';
  static const tdMessageBoostedGroup = 'tdMessageBoostedGroup';
  static const tdMessageChecklist = 'tdMessageChecklist';
  static const tdMessageContactCard = 'tdMessageContactCard';
  static const tdMessageDaysDuration = 'tdMessageDaysDuration';
  static const tdMessageDice = 'tdMessageDice';
  static const tdMessageExpiredPhoto = 'tdMessageExpiredPhoto';
  static const tdMessageExpiredVideo = 'tdMessageExpiredVideo';
  static const tdMessageFileWithName = 'tdMessageFileWithName';
  static const tdMessageForwardedStory = 'tdMessageForwardedStory';
  static const tdMessageGame = 'tdMessageGame';
  static const tdMessageGift = 'tdMessageGift';
  static const tdMessageGiveaway = 'tdMessageGiveaway';
  static const tdMessageGroupCreated = 'tdMessageGroupCreated';
  static const tdMessageGroupNameChanged = 'tdMessageGroupNameChanged';
  static const tdMessageGroupPhotoDeleted = 'tdMessageGroupPhotoDeleted';
  static const tdMessageGroupPhotoUpdated = 'tdMessageGroupPhotoUpdated';
  static const tdMessageGroupVideoChatEnded = 'tdMessageGroupVideoChatEnded';
  static const tdMessageGroupVideoChatStarted =
      'tdMessageGroupVideoChatStarted';
  static const tdMessageHoursDuration = 'tdMessageHoursDuration';
  static const tdMessageJoinedGroupByLink = 'tdMessageJoinedGroupByLink';
  static const tdMessageLastSeenMonthDay = 'tdMessageLastSeenMonthDay';
  static const tdMessageLastSeenTodayTime = 'tdMessageLastSeenTodayTime';
  static const tdMessageLastSeenUnknown = 'tdMessageLastSeenUnknown';
  static const tdMessageLastSeenYearMonthDay = 'tdMessageLastSeenYearMonthDay';
  static const tdMessageLastSeenYesterdayTime =
      'tdMessageLastSeenYesterdayTime';
  static const tdMessageMemberLeftGroup = 'tdMessageMemberLeftGroup';
  static const tdMessageMessagePinned = 'tdMessageMessagePinned';
  static const tdMessageMinutesDuration = 'tdMessageMinutesDuration';
  static const tdMessageMusic = 'tdMessageMusic';
  static const tdMessageNewMemberJoinedGroup = 'tdMessageNewMemberJoinedGroup';
  static const tdMessageNoAudio = 'tdMessageNoAudio';
  static const tdMessageNoFiles = 'tdMessageNoFiles';
  static const tdMessageNoLinks = 'tdMessageNoLinks';
  static const tdMessageNoMembers = 'tdMessageNoMembers';
  static const tdMessageNoPhotoVideo = 'tdMessageNoPhotoVideo';
  static const tdMessageNoStickers = 'tdMessageNoStickers';
  static const tdMessageNoVoice = 'tdMessageNoVoice';
  static const tdMessagePaidContent = 'tdMessagePaidContent';
  static const tdMessagePaidMessagePriceChanged =
      'tdMessagePaidMessagePriceChanged';
  static const tdMessagePaidMessageSettingsChanged =
      'tdMessagePaidMessageSettingsChanged';
  static const tdMessagePaidMessagesDisabled = 'tdMessagePaidMessagesDisabled';
  static const tdMessagePhotoVideo = 'tdMessagePhotoVideo';
  static const tdMessagePoll = 'tdMessagePoll';
  static const tdMessageProduct = 'tdMessageProduct';
  static const tdMessageSecondsDuration = 'tdMessageSecondsDuration';
  static const tdMessageSticker = 'tdMessageSticker';
  static const tdMessageStickerPreview = 'tdMessageStickerPreview';
  static const tdMessageStickerWithEmoji = 'tdMessageStickerWithEmoji';
  static const tdMessageSubmission = 'tdMessageSubmission';
  static const tdMessageSystemMessage = 'tdMessageSystemMessage';
  static const tdMessageUnsupportedCurrentVersion =
      'tdMessageUnsupportedCurrentVersion';
  static const tdMessageUserJoinedTelegram = 'tdMessageUserJoinedTelegram';
  static const tdMessageVideoCall = 'tdMessageVideoCall';
  static const tdMessageVideoMessage = 'tdMessageVideoMessage';
  static const tdMessageVoiceCall = 'tdMessageVoiceCall';
  static const themeApplePingFangFamily = 'themeApplePingFangFamily';
  static const themeGroupAssistantSecondPageFirst =
      'themeGroupAssistantSecondPageFirst';
  static const themeGroupAssistantSortByTime = 'themeGroupAssistantSortByTime';
  static const themeGroupAssistantTopCollapsed =
      'themeGroupAssistantTopCollapsed';
  static const themeModeDark = 'themeModeDark';
  static const themeModeLight = 'themeModeLight';
  static const themePingFangHongKong = 'themePingFangHongKong';
  static const themePingFangSimplifiedChinese =
      'themePingFangSimplifiedChinese';
  static const themePingFangTraditionalChinese =
      'themePingFangTraditionalChinese';
  static const themeSystemMonospace = 'themeSystemMonospace';
  static const themeUnreadChatCount = 'themeUnreadChatCount';
  static const themeUnreadCountCapAt99 = 'themeUnreadCountCapAt99';
  static const themeUnreadCountShowActual = 'themeUnreadCountShowActual';
  static const themeUnreadMessageCount = 'themeUnreadMessageCount';
  static const topicChatAllFilter = 'topicChatAllFilter';
  static const topicChatAllTopics = 'topicChatAllTopics';
  static const topicChatAwaitingYourPost = 'topicChatAwaitingYourPost';
  static const topicChatBeKindPrompt = 'topicChatBeKindPrompt';
  static const topicChatBrowseCount = 'topicChatBrowseCount';
  static const topicChatChannelMembers = 'topicChatChannelMembers';
  static const topicChatChannelMessages = 'topicChatChannelMessages';
  static const topicChatChannelNumber = 'topicChatChannelNumber';
  static const topicChatChannelSettings = 'topicChatChannelSettings';
  static const topicChatCommentCount = 'topicChatCommentCount';
  static const topicChatComposerPlaceholder = 'topicChatComposerPlaceholder';
  static const topicChatExpand = 'topicChatExpand';
  static const topicChatGroupChatTitle = 'topicChatGroupChatTitle';
  static const topicChatInvite = 'topicChatInvite';
  static const topicChatLeave = 'topicChatLeave';
  static const topicChatLeaveChannel = 'topicChatLeaveChannel';
  static const topicChatLeaveChannelConfirm = 'topicChatLeaveChannelConfirm';
  static const topicChatLeaveChannelFailed = 'topicChatLeaveChannelFailed';
  static const topicChatLikeCommentSummary = 'topicChatLikeCommentSummary';
  static const topicChatLoading = 'topicChatLoading';
  static const topicChatMemberCount = 'topicChatMemberCount';
  static const topicChatMostRelevant = 'topicChatMostRelevant';
  static const topicChatMuteFailed = 'topicChatMuteFailed';
  static const topicChatMuteMessagesToggle = 'topicChatMuteMessagesToggle';
  static const topicChatMyProfile = 'topicChatMyProfile';
  static const topicChatNoMoreContent = 'topicChatNoMoreContent';
  static const topicChatPinToggle = 'topicChatPinToggle';
  static const topicChatPinnedPrefix = 'topicChatPinnedPrefix';
  static const topicChatPublish = 'topicChatPublish';
  static const topicChatReplyCount = 'topicChatReplyCount';
  static const topicChatSearch = 'topicChatSearch';
  static const topicChatSelectSection = 'topicChatSelectSection';
  static const topicChatSelectTime = 'topicChatSelectTime';
  static const topicChatSetPinnedFailed = 'topicChatSetPinnedFailed';
  static const topicChatShare = 'topicChatShare';
  static const topicChatTopicCount = 'topicChatTopicCount';
  static const topicChatTopicTitle = 'topicChatTopicTitle';
  static const topicChatUsers = 'topicChatUsers';
  static const topicPostContentActionFailed = 'topicPostContentActionFailed';
  static const topicPostContentCopied = 'topicPostContentCopied';
  static const topicPostContentCopiedQuery = 'topicPostContentCopiedQuery';
  static const topicPostContentFile = 'topicPostContentFile';
  static const translationInternalNoExternalApi =
      'translationInternalNoExternalApi';
  static const translationLibreTranslateNoResult =
      'translationLibreTranslateNoResult';
  static const translationLibreTranslateUrlRequired =
      'translationLibreTranslateUrlRequired';
  static const translationLingvaNoResult = 'translationLingvaNoResult';
  static const translationMlKitLocal = 'translationMlKitLocal';
  static const translationMyMemoryNoResult = 'translationMyMemoryNoResult';
  static const translationNativeCancelledOrTimedOut =
      'translationNativeCancelledOrTimedOut';
  static const translationNativeNoExternalApi =
      'translationNativeNoExternalApi';
  static const translationNativeNoResult = 'translationNativeNoResult';
  static const translationServiceInvalidResponse =
      'translationServiceInvalidResponse';
  static const translationServiceReturnedStatus =
      'translationServiceReturnedStatus';
  static const translationServiceUrlInvalid = 'translationServiceUrlInvalid';
  static const translationSettingsService = 'translationSettingsService';
  static const translationSettingsTargetLanguage =
      'translationSettingsTargetLanguage';
  static const translationSettingsTitle = 'translationSettingsTitle';
  static const translationSystem = 'translationSystem';
  static const translationTelegram = 'translationTelegram';
  static const updateAction = 'updateAction';
  static const updateLater = 'updateLater';
  static const updateNewVersionFound = 'updateNewVersionFound';
  static const updateVersionPrompt = 'updateVersionPrompt';
  static const videoPlayerCachedLocally = 'videoPlayerCachedLocally';
  static const videoPlayerCannotPlay = 'videoPlayerCannotPlay';
  static const videoPlayerForwardUnsupported = 'videoPlayerForwardUnsupported';
  static const videoPlayerFullscreen = 'videoPlayerFullscreen';
  static const videoPlayerLoadFailed = 'videoPlayerLoadFailed';
  static const videoPlayerLoading = 'videoPlayerLoading';
  static const videoPlayerPictureInPicture = 'videoPlayerPictureInPicture';
  static const videoPlayerPlaybackSpeed = 'videoPlayerPlaybackSpeed';
  static const videoPlayerSplitScreen = 'videoPlayerSplitScreen';
  static const videoPlayerStreamingWhileDownloading =
      'videoPlayerStreamingWhileDownloading';
  static const videoPlayerToggleDisplayMode = 'videoPlayerToggleDisplayMode';
  static const videoPlayerWaitingForFile = 'videoPlayerWaitingForFile';
  static const vipBadgeLabel = 'vipBadgeLabel';
}

abstract final class AppStrings {
  static String t(String key, [Map<String, Object?> placeholders = const {}]) {
    final locale =
        AppLocalizations.localeFromTag(Intl.getCurrentLocale()) ??
        AppLocalizations.fallbackLocale;
    final resolved = AppLocalizations.resolve(locale);
    return tForLocale(
      AppLocalizations.localeKeyFor(resolved),
      key,
      placeholders,
    );
  }

  static String tForLocale(
    String localeKey,
    String key, [
    Map<String, Object?> placeholders = const {},
  ]) {
    final countryValue = countryNameForLocale(localeKey, key);
    final localeMessages = _messages[localeKey] ?? _messages['en'];
    var value =
        countryValue ?? localeMessages?[key] ?? _messages['en']?[key] ?? key;
    placeholders.forEach((placeholder, replacement) {
      value = value.replaceAll('{$placeholder}', '$replacement');
    });
    return value;
  }
}

const _messages = <String, Map<String, String>>{
  'zhHans': zhHansMessages,
  'zhHant': zhHantMessages,
  'ja': jaMessages,
  'ko': koMessages,
  'en': enMessages,
  'fr': frMessages,
  'es': esMessages,
  'de': deMessages,
};

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.isSupportedLocale(locale);

  @override
  Future<AppLocalizations> load(Locale locale) {
    final resolved = AppLocalizations.resolve(locale);
    Intl.defaultLocale = resolved.toLanguageTag();
    return SynchronousFuture(AppLocalizations(resolved));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
