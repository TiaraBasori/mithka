import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'bot_api_account.dart';
import 'bot_api_client.dart';
import 'bot_api_store.dart';
import 'bot_api_td_converter.dart';

typedef BotApiTdUpdateSink = void Function(Map<String, dynamic> update);

/// A Telegram Bot API account presented as TDLib-shaped JSON.
///
/// The UI continues to query and subscribe through TdClient. Network history is
/// never fabricated: getChatHistory and search read only the SQLite updates this
/// device has already received.
class BotApiTdBackend {
  BotApiTdBackend({
    required this.account,
    required String token,
    required String databasePath,
    required this.mediaDirectory,
    required this._emit,
    BotApiClient? client,
    BotApiStore? store,
  }) : _client =
           client ?? BotApiClient(token: token, endpoint: account.endpoint),
       _store = store ?? BotApiStore(databasePath) {
    _converter = BotApiTdConverter(store: _store, bot: account.bot);
  }

  final BotApiAccount account;
  final String mediaDirectory;
  final BotApiTdUpdateSink _emit;
  final BotApiClient _client;
  final BotApiStore _store;
  late final BotApiTdConverter _converter;

  bool _started = false;
  bool _closed = false;
  bool _polling = false;
  bool _webhookConflict = false;
  String _connectionError = '';
  int _pollGeneration = 0;

  bool get webhookConflict => _webhookConflict;
  String get connectionError => _connectionError;

  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;
    await _store.open();
    final me = _converter.user(account.bot);
    _store.upsertUser(me);
    _emit({'@type': 'updateUser', 'user': me});
    _emit(_authorizationUpdate('authorizationStateReady'));
    _emitConnection('connectionStateConnecting');
    for (final user in _store.users()) {
      if (_int(user['id']) == account.botId) continue;
      _emit({'@type': 'updateUser', 'user': user});
    }
    for (final chat in _store.chats(limit: 1000)) {
      _emit({'@type': 'updateNewChat', 'chat': chat});
    }
    unawaited(_preparePolling());
  }

  Future<void> resume() async {
    if (_closed || !_started || _polling) return;
    _webhookConflict = false;
    _connectionError = '';
    unawaited(_preparePolling());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pollGeneration += 1;
    _client.close();
    _store.close();
    _emit(_authorizationUpdate('authorizationStateClosed'));
  }

  Future<void> send(Map<String, dynamic> request) async {
    await query(request);
  }

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    if (_closed) return _error(499, 'Bot API account is closed.');
    try {
      return await _query(request);
    } on BotApiException catch (error) {
      return _error(error.code, error.message);
    } on FormatException catch (error) {
      return _error(400, error.message);
    } on FileSystemException {
      return _error(500, 'The on-device Bot API history is unavailable.');
    } on Object {
      return _error(500, 'The Bot API request could not be completed.');
    }
  }

  Future<Map<String, dynamic>> _query(Map<String, dynamic> request) async {
    final type = request['@type'] as String? ?? '';
    switch (type) {
      case 'getAuthorizationState':
        return const {'@type': 'authorizationStateReady'};
      case 'getMe':
        return _converter.user(account.bot);
      case 'getConnectionState':
        return {
          '@type': _connectionError.isEmpty
              ? 'connectionStateReady'
              : 'connectionStateConnecting',
        };
      case 'getCurrentState':
        return {
          '@type': 'updates',
          'updates': [
            _authorizationUpdate('authorizationStateReady'),
            {'@type': 'updateUser', 'user': _converter.user(account.bot)},
            for (final chat in _store.chats(limit: 1000))
              {'@type': 'updateNewChat', 'chat': chat},
          ],
        };
      case 'getOption':
        return _option(request['name'] as String? ?? '');
      case 'getBotApiAccountInfo':
        return {
          '@type': 'botApiAccountInfo',
          'endpoint': account.endpoint.toString(),
          'is_polling': _polling,
          'has_webhook_conflict': _webhookConflict,
          'connection_error': _connectionError,
          'next_update_offset': _store.nextUpdateOffset,
        };
      case 'restartBotApiPolling':
        await resume();
        return _ok;
      case 'loadChats':
        for (final chat in _store.chats(limit: _int(request['limit']) ?? 100)) {
          _emit({'@type': 'updateNewChat', 'chat': chat});
        }
        return _ok;
      case 'getChats':
        final chats = _store.chats(limit: _int(request['limit']) ?? 100);
        return {
          '@type': 'chats',
          'total_count': chats.length,
          'chat_ids': [for (final chat in chats) _int(chat['id']) ?? 0],
        };
      case 'getChat':
      case 'createPrivateChat':
        final chatId = type == 'createPrivateChat'
            ? _requiredInt(request, 'user_id')
            : _requiredInt(request, 'chat_id');
        return _getChat(chatId);
      case 'getChatHistory':
        return _history(request);
      case 'getMessage':
        return _store.message(
              _requiredInt(request, 'chat_id'),
              _requiredInt(request, 'message_id'),
            ) ??
            _error(404, 'Message is not available in on-device history.');
      case 'getRepliedMessage':
        return _repliedMessage(request);
      case 'searchChatMessages':
        return _searchChatMessages(request);
      case 'searchMessages':
        return _searchMessages(request);
      case 'getUser':
        final userId = _requiredInt(request, 'user_id');
        return _store.user(userId) ??
            (userId == account.botId
                ? _converter.user(account.bot)
                : _error(404, 'User is not available in on-device history.'));
      case 'getBasicGroup':
        return _groupObject(request, supergroup: false);
      case 'getSupergroup':
        return _groupObject(request, supergroup: true);
      case 'getBasicGroupFullInfo':
      case 'getSupergroupFullInfo':
        return _groupFullInfo(
          request,
          supergroup: type == 'getSupergroupFullInfo',
        );
      case 'getChatMember':
        return _getChatMember(request);
      case 'getSupergroupMembers':
      case 'getChatAdministrators':
        return _getChatAdministrators(request);
      case 'viewMessages':
        return _viewMessages(request);
      case 'openChat':
      case 'closeChat':
      case 'readAllChatMentions':
      case 'readAllChatReactions':
      case 'setChatDraftMessage':
      case 'toggleChatIsMarkedAsUnread':
        return _ok;
      case 'sendChatAction':
        return _sendChatAction(request);
      case 'sendMessage':
        return _sendMessage(request);
      case 'sendMessageAlbum':
        return _sendMessageAlbum(request);
      case 'editMessageText':
        return _editMessageText(request);
      case 'editMessageCaption':
        return _editMessageCaption(request);
      case 'deleteMessages':
        return _deleteMessages(request);
      case 'addMessageReaction':
      case 'setMessageReaction':
        return _setMessageReaction(request);
      case 'removeMessageReaction':
        return _setMessageReaction({...request, 'reaction_type': null});
      case 'pinChatMessage':
        return _simpleMessageMutation('pinChatMessage', request);
      case 'unpinChatMessage':
        return _simpleMessageMutation('unpinChatMessage', request);
      case 'stopPoll':
        return _simpleMessageMutation('stopPoll', request);
      case 'forwardMessages':
        return _forwardMessages(request, copy: false);
      case 'copyMessages':
        return _forwardMessages(request, copy: true);
      case 'getFile':
        return _getFile(_requiredInt(request, 'file_id'));
      case 'downloadFile':
        return _downloadFile(_requiredInt(request, 'file_id'));
      case 'deleteFile':
        return _deleteFile(_requiredInt(request, 'file_id'));
      case 'getRemoteFile':
        final record = _store.registerFile(
          botFileId: request['remote_file_id'] as String? ?? '',
        );
        return _converter.fileFromRecord(record);
      case 'getScopeNotificationSettings':
        return _scopeNotificationSettings;
      case 'getChatNotificationSettingsExceptions':
        return const {'@type': 'chats', 'total_count': 0, 'chat_ids': <int>[]};
      case 'logOut':
        // Bot API logOut is a cloud-to-local-server migration operation and is
        // not equivalent to removing an account from this device.
        return _error(400, 'Use local account removal for Bot API accounts.');
      case 'close':
        unawaited(close());
        return _ok;
      default:
        return _error(400, 'BOT_API_UNSUPPORTED: $type');
    }
  }

  Future<void> _preparePolling() async {
    if (_closed || _polling) return;
    final generation = ++_pollGeneration;
    try {
      final value = await _client.call('getWebhookInfo');
      if (_closed || generation != _pollGeneration) return;
      final info = _map(value);
      if (_string(info?['url']).isNotEmpty) {
        _setPollingConflict(
          'A webhook is configured for this bot. Remove it before using on-device updates.',
        );
        return;
      }
    } on BotApiException catch (error) {
      if (_closed || generation != _pollGeneration) return;
      _connectionError = error.message;
      _emitConnection('connectionStateConnecting');
      // getUpdates can still succeed on compatible endpoints that omit
      // getWebhookInfo, so continue into the poll loop.
    }
    if (_closed || generation != _pollGeneration) return;
    _polling = true;
    unawaited(_pollLoop(generation));
  }

  Future<void> _pollLoop(int generation) async {
    var failures = 0;
    try {
      while (!_closed && generation == _pollGeneration) {
        try {
          final value = await _client.call('getUpdates', {
            'offset': _store.nextUpdateOffset,
            'limit': 100,
            'timeout': 30,
            'allowed_updates': _allowedUpdates,
          });
          if (_closed || generation != _pollGeneration) return;
          failures = 0;
          _connectionError = '';
          _emitConnection('connectionStateReady');
          for (final raw in _list(value)) {
            final update = _map(raw);
            if (update != null) _ingestUpdate(update);
          }
        } on BotApiException catch (error) {
          if (_closed || generation != _pollGeneration) return;
          if (error.code == 409) {
            _setPollingConflict(
              'Another webhook or getUpdates consumer is receiving this bot’s updates.',
            );
            return;
          }
          failures += 1;
          _connectionError = error.message;
          _emitConnection('connectionStateConnecting');
          final seconds = math.min(30, 1 << math.min(failures - 1, 5));
          await Future<void>.delayed(Duration(seconds: seconds));
        } on Object {
          if (_closed || generation != _pollGeneration) return;
          // A conversion or disk failure must not end polling silently. Keep
          // the offset unchanged and retry so a received message is never
          // acknowledged before its on-device transaction succeeds.
          failures += 1;
          _connectionError = 'Could not save Bot API updates on this device.';
          _emitConnection('connectionStateConnecting');
          final seconds = math.min(30, 1 << math.min(failures - 1, 5));
          await Future<void>.delayed(Duration(seconds: seconds));
        }
      }
    } finally {
      if (generation == _pollGeneration) _polling = false;
    }
  }

  void _setPollingConflict(String message) {
    _webhookConflict = true;
    _connectionError = message;
    _polling = false;
    _emitConnection('connectionStateReady');
    _emit({
      '@type': 'updateBotApiConnectionState',
      'endpoint': account.endpoint.toString(),
      'is_polling': false,
      'has_webhook_conflict': true,
      'error': message,
    });
  }

  void _ingestUpdate(Map<String, dynamic> update) {
    final updateId = _int(update['update_id']);
    if (updateId == null) return;
    final emitted = _store.transaction(() {
      if (_store.hasRawUpdate(updateId)) {
        if (_store.nextUpdateOffset <= updateId) {
          _store.setMetadata('next_update_offset', '${updateId + 1}');
        }
        return const <Map<String, dynamic>>[];
      }
      _store.saveRawUpdate(updateId, update);
      final events = _eventsForUpdate(update);
      final next = math.max(_store.nextUpdateOffset, updateId + 1);
      _store.setMetadata('next_update_offset', '$next');
      return events;
    });
    for (final event in emitted) {
      _emit(event);
    }
  }

  List<Map<String, dynamic>> _eventsForUpdate(Map<String, dynamic> update) {
    for (final key in _newMessageKeys) {
      final message = _map(update[key]);
      if (message != null) return _persistMessage(message, edited: false);
    }
    for (final key in _editedMessageKeys) {
      final message = _map(update[key]);
      if (message != null) return _persistMessage(message, edited: true);
    }
    final poll = _map(update['poll']);
    if (poll != null) return _persistPoll(poll);
    final deleted = _map(update['deleted_business_messages']);
    if (deleted != null) return _persistDeletedMessages(deleted);
    final reactionCount = _map(update['message_reaction_count']);
    if (reactionCount != null) return _persistReactionCounts(reactionCount);
    final membership =
        _map(update['my_chat_member']) ?? _map(update['chat_member']);
    if (membership != null) return _persistMembership(membership);
    return const [];
  }

  List<Map<String, dynamic>> _persistMessage(
    Map<String, dynamic> source, {
    required bool edited,
  }) {
    final chatId = _int((_map(source['chat']))?['id']) ?? 0;
    final previous = _store.chat(chatId);
    final converted = _converter.message(
      source,
      previousChat: previous,
      incrementUnread: !edited,
    );
    for (final user in converted.users) {
      _store.upsertUser(user);
    }
    _store.upsertMessage(converted.message);
    _store.upsertChat(converted.chat);
    final events = <Map<String, dynamic>>[
      for (final user in converted.users) {'@type': 'updateUser', 'user': user},
      if (previous == null) {'@type': 'updateNewChat', 'chat': converted.chat},
      if (edited) ...[
        {
          '@type': 'updateMessageContent',
          'chat_id': chatId,
          'message_id': converted.message['id'],
          'new_content': converted.message['content'],
        },
        {
          '@type': 'updateMessageEdited',
          'chat_id': chatId,
          'message_id': converted.message['id'],
          'edit_date': converted.message['edit_date'],
          'reply_markup': converted.message['reply_markup'],
        },
      ] else
        {'@type': 'updateNewMessage', 'message': converted.message},
      ..._chatPositionEvents(converted.chat),
    ];
    return events;
  }

  List<Map<String, dynamic>> _persistPoll(Map<String, dynamic> poll) {
    final botPollId = _string(poll['id']);
    if (botPollId.isEmpty) return const [];
    final events = <Map<String, dynamic>>[];
    final converted = _converter.pollObject(poll);
    for (final message in _store.messagesForPoll(botPollId)) {
      final content = _map(message['content']);
      if (content == null) continue;
      content['poll'] = converted;
      message['content'] = content;
      _store.upsertMessage(message);
      events.add({
        '@type': 'updateMessageContent',
        'chat_id': message['chat_id'],
        'message_id': message['id'],
        'new_content': content,
      });
    }
    return events;
  }

  List<Map<String, dynamic>> _persistDeletedMessages(
    Map<String, dynamic> deleted,
  ) {
    final chatId = _int((_map(deleted['chat']))?['id']) ?? 0;
    final ids = _list(
      deleted['message_ids'],
    ).map(_int).whereType<int>().toList();
    _store.deleteMessages(chatId, ids);
    return [
      {
        '@type': 'updateDeleteMessages',
        'chat_id': chatId,
        'message_ids': ids,
        'is_permanent': true,
        'from_cache': false,
      },
    ];
  }

  List<Map<String, dynamic>> _persistReactionCounts(
    Map<String, dynamic> update,
  ) {
    final chatId = _int((_map(update['chat']))?['id']) ?? 0;
    final messageId = _int(update['message_id']) ?? 0;
    final message = _store.message(chatId, messageId);
    if (message == null) return const [];
    final reactions = {
      '@type': 'messageReactions',
      'reactions': [
        for (final value in _list(update['reactions']))
          if (_map(value) case final reaction?)
            {
              '@type': 'messageReaction',
              'type': _botReactionToTd(_map(reaction['type'])),
              'total_count': _int(reaction['total_count']) ?? 0,
              'is_chosen': false,
              'used_sender_id': null,
              'recent_sender_ids': const <Map<String, dynamic>>[],
            },
      ],
      'are_tags': false,
      'paid_reactors': const <Map<String, dynamic>>[],
      'can_get_added_reactions': true,
    };
    final interaction =
        _map(message['interaction_info']) ??
        {
          '@type': 'messageInteractionInfo',
          'view_count': 0,
          'forward_count': 0,
          'reply_info': null,
        };
    interaction['reactions'] = reactions;
    message['interaction_info'] = interaction;
    _store.upsertMessage(message);
    return [
      {
        '@type': 'updateMessageInteractionInfo',
        'chat_id': chatId,
        'message_id': messageId,
        'interaction_info': interaction,
      },
    ];
  }

  List<Map<String, dynamic>> _persistMembership(Map<String, dynamic> update) {
    final events = <Map<String, dynamic>>[];
    final sourceChat = _map(update['chat']);
    final from = _map(update['from']);
    final memberUser = _map((_map(update['new_chat_member']))?['user']);
    for (final source in [from, memberUser]) {
      if (source == null) continue;
      final user = _converter.user(source);
      _store.upsertUser(user);
      events.add({'@type': 'updateUser', 'user': user});
    }
    if (sourceChat != null) {
      final chatId = _int(sourceChat['id']) ?? 0;
      final previous = _store.chat(chatId);
      final chat = _converter.chat(
        sourceChat,
        lastMessage: _map(previous?['last_message']),
        unreadCount: _int(previous?['unread_count']) ?? 0,
      );
      _store.upsertChat(chat);
      if (previous == null) {
        events.add({'@type': 'updateNewChat', 'chat': chat});
      }
    }
    return events;
  }

  Future<Map<String, dynamic>> _getChat(int chatId) async {
    final existing = _store.chat(chatId);
    if (existing != null) return existing;
    final value = await _client.call('getChat', {'chat_id': chatId});
    final source = _map(value);
    if (source == null) {
      return _error(502, 'The Bot API returned an invalid chat.');
    }
    final chat = _converter.chat(source);
    _store.upsertChat(chat);
    if (_string(source['type']) == 'private') {
      final user = _converter.user({...source, 'is_bot': false});
      _store.upsertUser(user);
      _emit({'@type': 'updateUser', 'user': user});
    }
    _emit({'@type': 'updateNewChat', 'chat': chat});
    return chat;
  }

  Map<String, dynamic> _history(Map<String, dynamic> request) {
    final chatId = _requiredInt(request, 'chat_id');
    final messages = _store.history(
      chatId: chatId,
      fromMessageId: _int(request['from_message_id']) ?? 0,
      offset: _int(request['offset']) ?? 0,
      limit: _int(request['limit']) ?? 50,
    );
    return {
      '@type': 'messages',
      'total_count': _store.messageCount(chatId),
      'messages': messages,
    };
  }

  Map<String, dynamic> _repliedMessage(Map<String, dynamic> request) {
    final chatId = _requiredInt(request, 'chat_id');
    final message = _store.message(chatId, _requiredInt(request, 'message_id'));
    final reply = _map(message?['reply_to']);
    final replyId = _int(reply?['message_id']);
    if (replyId == null) return _error(404, 'Replied message is unavailable.');
    return _store.message(_int(reply?['chat_id']) ?? chatId, replyId) ??
        _error(404, 'Replied message is not in on-device history.');
  }

  Map<String, dynamic> _searchChatMessages(Map<String, dynamic> request) {
    final chatId = _requiredInt(request, 'chat_id');
    final sender = _map(request['sender_id']);
    final messages = _store.searchMessages(
      chatId: chatId,
      query: request['query'] as String? ?? '',
      senderId: _int(sender?['user_id']) ?? _int(sender?['chat_id']),
      fromMessageId: _int(request['from_message_id']) ?? 0,
      limit: _int(request['limit']) ?? 50,
      contentTypes: _contentTypesForFilter(_map(request['filter'])),
    );
    return {
      '@type': 'foundChatMessages',
      'total_count': messages.length,
      'messages': messages,
      'next_from_message_id': messages.isEmpty
          ? 0
          : _int(messages.last['id']) ?? 0,
    };
  }

  Map<String, dynamic> _searchMessages(Map<String, dynamic> request) {
    final messages = _store.searchMessages(
      query: request['query'] as String? ?? '',
      fromMessageId: _int(request['offset_message_id']) ?? 0,
      limit: _int(request['limit']) ?? 50,
      contentTypes: _contentTypesForFilter(_map(request['filter'])),
    );
    return {
      '@type': 'foundMessages',
      'total_count': messages.length,
      'messages': messages,
      'next_offset': messages.isEmpty ? '' : '${messages.last['id']}',
    };
  }

  Map<String, dynamic> _groupObject(
    Map<String, dynamic> request, {
    required bool supergroup,
  }) {
    final peerId = _requiredInt(
      request,
      supergroup ? 'supergroup_id' : 'basic_group_id',
    );
    final chat = _chatForPeer(peerId, supergroup: supergroup);
    if (chat == null) return _error(404, 'Chat is unavailable.');
    return supergroup
        ? _converter.supergroup(chat)
        : _converter.basicGroup(chat);
  }

  Future<Map<String, dynamic>> _groupFullInfo(
    Map<String, dynamic> request, {
    required bool supergroup,
  }) async {
    final peerId = _requiredInt(
      request,
      supergroup ? 'supergroup_id' : 'basic_group_id',
    );
    final stored = _chatForPeer(peerId, supergroup: supergroup);
    if (stored == null) return _error(404, 'Chat is unavailable.');
    final chatId = _int(stored['id']) ?? 0;
    Map<String, dynamic> source = const {};
    try {
      source =
          _map(await _client.call('getChat', {'chat_id': chatId})) ?? const {};
    } on BotApiException {
      // Full info remains useful offline with the locally known chat.
    }
    if (supergroup) {
      return {
        '@type': 'supergroupFullInfo',
        'photo': null,
        'description': _string(source['description']),
        'member_count': 0,
        'administrator_count': 0,
        'restricted_count': 0,
        'banned_count': 0,
        'linked_chat_id': 0,
        'slow_mode_delay': 0,
        'slow_mode_delay_expires_in': 0.0,
        'can_get_members': true,
        'has_hidden_members': false,
        'can_hide_members': false,
        'can_set_sticker_set': false,
        'can_set_location': false,
        'can_get_statistics': false,
        'can_get_revenue_statistics': false,
        'can_get_star_revenue_statistics': false,
        'can_send_gift': false,
        'can_toggle_aggressive_anti_spam': false,
        'is_all_history_available': false,
        'can_have_sponsored_messages': false,
        'has_aggressive_anti_spam_enabled': false,
        'has_paid_media_allowed': false,
        'has_pinned_stories': false,
        'gift_count': 0,
        'my_boost_count': 0,
        'unrestrict_boost_count': 0,
        'sticker_set_id': 0,
        'custom_emoji_sticker_set_id': 0,
        'location': null,
        'invite_link': _inviteLink(source['invite_link']),
        'bot_commands': const <Map<String, dynamic>>[],
        'upgraded_gift_count': 0,
      };
    }
    return {
      '@type': 'basicGroupFullInfo',
      'photo': null,
      'description': _string(source['description']),
      'creator_user_id': 0,
      'members': const <Map<String, dynamic>>[],
      'can_hide_members': false,
      'can_toggle_aggressive_anti_spam': false,
      'invite_link': _inviteLink(source['invite_link']),
      'bot_commands': const <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _getChatMember(
    Map<String, dynamic> request,
  ) async {
    final memberId = _map(request['member_id']);
    final userId = _int(memberId?['user_id']);
    if (userId == null) {
      return _error(400, 'Only user chat members are supported.');
    }
    final value = await _client.call('getChatMember', {
      'chat_id': _requiredInt(request, 'chat_id'),
      'user_id': userId,
    });
    return _chatMember(_map(value));
  }

  Future<Map<String, dynamic>> _getChatAdministrators(
    Map<String, dynamic> request,
  ) async {
    int? chatId = _int(request['chat_id']);
    if (chatId == null) {
      final peerId = _int(request['supergroup_id']);
      chatId = peerId == null
          ? null
          : _int(_chatForPeer(peerId, supergroup: true)?['id']);
    }
    if (chatId == null) return _error(404, 'Chat is unavailable.');
    final value = await _client.call('getChatAdministrators', {
      'chat_id': chatId,
    });
    final members = [
      for (final raw in _list(value))
        if (_map(raw) case final member?) await _chatMember(member),
    ];
    return {
      '@type': 'chatMembers',
      'total_count': members.length,
      'members': members,
    };
  }

  Future<Map<String, dynamic>> _chatMember(Map<String, dynamic>? source) async {
    if (source == null) {
      return _error(502, 'The Bot API returned an invalid member.');
    }
    final sourceUser = _map(source['user']);
    if (sourceUser == null) {
      return _error(502, 'The Bot API returned an invalid member.');
    }
    final user = _converter.user(sourceUser);
    _store.upsertUser(user);
    _emit({'@type': 'updateUser', 'user': user});
    return {
      '@type': 'chatMember',
      'member_id': {'@type': 'messageSenderUser', 'user_id': user['id']},
      'inviter_user_id': 0,
      'joined_chat_date': 0,
      'status': _memberStatus(source),
    };
  }

  Map<String, dynamic> _viewMessages(Map<String, dynamic> request) {
    final chatId = _requiredInt(request, 'chat_id');
    final chat = _store.chat(chatId);
    if (chat == null) return _ok;
    chat['unread_count'] = 0;
    final ids = _list(
      request['message_ids'],
    ).map(_int).whereType<int>().toList();
    final lastRead = ids.isEmpty ? 0 : ids.reduce(math.max);
    chat['last_read_inbox_message_id'] = lastRead;
    _store.upsertChat(chat);
    _emit({
      '@type': 'updateChatReadInbox',
      'chat_id': chatId,
      'last_read_inbox_message_id': lastRead,
      'unread_count': 0,
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _sendChatAction(
    Map<String, dynamic> request,
  ) async {
    final action = _map(request['action']);
    final botAction = switch (action?['@type']) {
      'chatActionTyping' => 'typing',
      'chatActionUploadingPhoto' => 'upload_photo',
      'chatActionRecordingVideo' => 'record_video',
      'chatActionUploadingVideo' => 'upload_video',
      'chatActionRecordingVoiceNote' => 'record_voice',
      'chatActionUploadingVoiceNote' => 'upload_voice',
      'chatActionUploadingDocument' => 'upload_document',
      'chatActionChoosingSticker' => 'choose_sticker',
      'chatActionFindingLocation' => 'find_location',
      'chatActionRecordingVideoNote' => 'record_video_note',
      'chatActionUploadingVideoNote' => 'upload_video_note',
      _ => 'cancel',
    };
    await _client.call('sendChatAction', {
      'chat_id': _requiredInt(request, 'chat_id'),
      'action': botAction,
      'message_thread_id': ?_int(request['message_thread_id']),
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _sendMessage(
    Map<String, dynamic> request,
  ) async {
    final content = _map(request['input_message_content']);
    if (content == null) return _error(400, 'Message content is required.');
    final chatId = _requiredInt(request, 'chat_id');
    final common = _commonSendParameters(request, chatId);
    late final String method;
    late final Map<String, dynamic> parameters;
    _Upload? upload;
    switch (content['@type']) {
      case 'inputMessageText':
        final text = _map(content['text']);
        method = 'sendMessage';
        parameters = {
          ...common,
          'text': _string(text?['text']),
          if (_botEntities(text?['entities']).isNotEmpty)
            'entities': _botEntities(text?['entities']),
          if (_map(content['link_preview_options']) case final options?)
            'link_preview_options': _botLinkPreviewOptions(options),
        };
      case 'inputMessagePhoto':
        method = 'sendPhoto';
        upload = _inputUpload(content['photo'], 'photo');
        parameters = {
          ...common,
          if (upload.remote != null) 'photo': upload.remote,
          ..._captionParameters(content),
          'show_caption_above_media':
              content['show_caption_above_media'] == true,
          'has_spoiler': content['has_spoiler'] == true,
        };
      case 'inputMessageVideo':
        method = 'sendVideo';
        upload = _inputUpload(content['video'], 'video');
        parameters = {
          ...common,
          if (upload.remote != null) 'video': upload.remote,
          ..._captionParameters(content),
          'duration': _nestedInt(content['video'], 'duration') ?? 0,
          'width': _nestedInt(content['video'], 'width') ?? 0,
          'height': _nestedInt(content['video'], 'height') ?? 0,
          'supports_streaming': true,
          'has_spoiler': content['has_spoiler'] == true,
        };
      case 'inputMessageAnimation':
        method = 'sendAnimation';
        upload = _inputUpload(content['animation'], 'animation');
        parameters = {
          ...common,
          if (upload.remote != null) 'animation': upload.remote,
          ..._captionParameters(content),
          'duration': _nestedInt(content['animation'], 'duration') ?? 0,
          'width': _nestedInt(content['animation'], 'width') ?? 0,
          'height': _nestedInt(content['animation'], 'height') ?? 0,
          'has_spoiler': content['has_spoiler'] == true,
        };
      case 'inputMessageAudio':
        method = 'sendAudio';
        upload = _inputUpload(content['audio'], 'audio');
        parameters = {
          ...common,
          if (upload.remote != null) 'audio': upload.remote,
          ..._captionParameters(content),
          'duration': _nestedInt(content['audio'], 'duration') ?? 0,
          'performer': _nestedString(content['audio'], 'performer'),
          'title': _nestedString(content['audio'], 'title'),
        };
      case 'inputMessageDocument':
        method = 'sendDocument';
        upload = _inputUpload(content['document'], 'document');
        parameters = {
          ...common,
          if (upload.remote != null) 'document': upload.remote,
          ..._captionParameters(content),
        };
      case 'inputMessageVoiceNote':
        method = 'sendVoice';
        upload = _inputUpload(content['voice_note'], 'voice');
        parameters = {
          ...common,
          if (upload.remote != null) 'voice': upload.remote,
          ..._captionParameters(content),
          'duration': _nestedInt(content['voice_note'], 'duration') ?? 0,
        };
      case 'inputMessageVideoNote':
        method = 'sendVideoNote';
        upload = _inputUpload(content['video_note'], 'video_note');
        parameters = {
          ...common,
          if (upload.remote != null) 'video_note': upload.remote,
          'duration': _nestedInt(content['video_note'], 'duration') ?? 0,
          'length': _nestedInt(content['video_note'], 'length') ?? 0,
        };
      case 'inputMessageSticker':
        method = 'sendSticker';
        upload = _inputUpload(content['sticker'], 'sticker');
        parameters = {
          ...common,
          if (upload.remote != null) 'sticker': upload.remote,
          if (_string(content['emoji']).isNotEmpty) 'emoji': content['emoji'],
        };
      case 'inputMessageLocation':
        final location = _map(content['location']);
        method = 'sendLocation';
        parameters = {
          ...common,
          'latitude': _double(location?['latitude']) ?? 0,
          'longitude': _double(location?['longitude']) ?? 0,
          if ((_double(location?['horizontal_accuracy']) ?? 0) > 0)
            'horizontal_accuracy': location?['horizontal_accuracy'],
          if ((_int(content['live_period']) ?? 0) > 0)
            'live_period': content['live_period'],
          if ((_int(content['heading']) ?? 0) > 0)
            'heading': content['heading'],
          if ((_int(content['proximity_alert_radius']) ?? 0) > 0)
            'proximity_alert_radius': content['proximity_alert_radius'],
        };
      case 'inputMessageVenue':
        final venue = _map(content['venue']);
        final location = _map(venue?['location']);
        method = 'sendVenue';
        parameters = {
          ...common,
          'latitude': _double(location?['latitude']) ?? 0,
          'longitude': _double(location?['longitude']) ?? 0,
          'title': _string(venue?['title']),
          'address': _string(venue?['address']),
          if (_string(venue?['provider']) == 'foursquare') ...{
            'foursquare_id': _string(venue?['id']),
            'foursquare_type': _string(venue?['type']),
          },
          if (_string(venue?['provider']) == 'google') ...{
            'google_place_id': _string(venue?['id']),
            'google_place_type': _string(venue?['type']),
          },
        };
      case 'inputMessageContact':
        final contact = _map(content['contact']);
        method = 'sendContact';
        parameters = {
          ...common,
          'phone_number': _string(contact?['phone_number']),
          'first_name': _string(contact?['first_name']),
          if (_string(contact?['last_name']).isNotEmpty)
            'last_name': contact?['last_name'],
          if (_string(contact?['vcard']).isNotEmpty) 'vcard': contact?['vcard'],
        };
      case 'inputMessagePoll':
        method = 'sendPoll';
        final question = _map(content['question']);
        final type = _map(content['type']);
        parameters = {
          ...common,
          'question': _string(question?['text']),
          if (_botEntities(question?['entities']).isNotEmpty)
            'question_entities': _botEntities(question?['entities']),
          'options': [
            for (final raw in _list(content['options']))
              if (_map(raw) case final option?)
                {
                  'text': _string((_map(option['text']))?['text']),
                  if (_botEntities(
                    (_map(option['text']))?['entities'],
                  ).isNotEmpty)
                    'text_entities': _botEntities(
                      (_map(option['text']))?['entities'],
                    ),
                },
          ],
          'is_anonymous': content['is_anonymous'] != false,
          'allows_multiple_answers': content['allows_multiple_answers'] == true,
          'type': type?['@type'] == 'inputPollTypeQuiz' ? 'quiz' : 'regular',
          if (type?['@type'] == 'inputPollTypeQuiz' &&
              _list(type?['correct_option_ids']).isNotEmpty)
            'correct_option_id': _int(_list(type?['correct_option_ids']).first),
          if (type?['@type'] == 'inputPollTypeQuiz' &&
              _string((_map(type?['explanation']))?['text']).isNotEmpty)
            'explanation': _string((_map(type?['explanation']))?['text']),
          if ((_int(content['open_period']) ?? 0) > 0)
            'open_period': content['open_period'],
          if ((_int(content['close_date']) ?? 0) > 0)
            'close_date': content['close_date'],
          'is_closed': content['is_closed'] == true,
        };
      case 'inputMessageDice':
        method = 'sendDice';
        parameters = {
          ...common,
          if (_string(content['emoji']).isNotEmpty) 'emoji': content['emoji'],
        };
      case 'inputMessageRichMessage':
        method = 'sendRichMessage';
        parameters = {
          ...common,
          'rich_message': content['message'] ?? content['rich_message'] ?? {},
        };
      default:
        return _error(400, 'BOT_API_UNSUPPORTED: ${content['@type']}');
    }
    final result = upload?.path != null
        ? await _client.callMultipart(
            method,
            fields: _multipartFields(parameters),
            files: {upload!.field: upload.path!},
          )
        : await _client.call(method, parameters);
    return _persistSentResult(result);
  }

  Future<Map<String, dynamic>> _sendMessageAlbum(
    Map<String, dynamic> request,
  ) async {
    final chatId = _requiredInt(request, 'chat_id');
    final contents = _list(
      request['input_message_contents'],
    ).map(_map).whereType<Map<String, dynamic>>().toList();
    if (contents.length < 2 || contents.length > 10) {
      return _error(400, 'A media album must contain 2 to 10 items.');
    }
    final media = <Map<String, dynamic>>[];
    final files = <String, String>{};
    for (var index = 0; index < contents.length; index++) {
      final content = contents[index];
      final field = 'media_$index';
      late final String mediaType;
      late final _Upload upload;
      switch (content['@type']) {
        case 'inputMessagePhoto':
          mediaType = 'photo';
          upload = _inputUpload(content['photo'], field);
        case 'inputMessageVideo':
          mediaType = 'video';
          upload = _inputUpload(content['video'], field);
        case 'inputMessageAudio':
          mediaType = 'audio';
          upload = _inputUpload(content['audio'], field);
        case 'inputMessageDocument':
          mediaType = 'document';
          upload = _inputUpload(content['document'], field);
        default:
          return _error(
            400,
            'This media type cannot be sent in a Bot API album.',
          );
      }
      if (upload.path != null) files[field] = upload.path!;
      final caption = _map(content['caption']);
      media.add({
        'type': mediaType,
        'media': upload.path != null ? 'attach://$field' : upload.remote,
        if (_string(caption?['text']).isNotEmpty) 'caption': caption?['text'],
        if (_botEntities(caption?['entities']).isNotEmpty)
          'caption_entities': _botEntities(caption?['entities']),
        if (mediaType == 'video') ...{
          'duration': _nestedInt(content['video'], 'duration') ?? 0,
          'width': _nestedInt(content['video'], 'width') ?? 0,
          'height': _nestedInt(content['video'], 'height') ?? 0,
          'supports_streaming': true,
          'has_spoiler': content['has_spoiler'] == true,
        },
        if (mediaType == 'photo') 'has_spoiler': content['has_spoiler'] == true,
        if (mediaType == 'audio') ...{
          'duration': _nestedInt(content['audio'], 'duration') ?? 0,
          'performer': _nestedString(content['audio'], 'performer'),
          'title': _nestedString(content['audio'], 'title'),
        },
      });
    }
    final parameters = {
      ..._commonSendParameters(request, chatId),
      'media': media,
    };
    final result = files.isEmpty
        ? await _client.call('sendMediaGroup', parameters)
        : await _client.callMultipart(
            'sendMediaGroup',
            fields: _multipartFields(parameters),
            files: files,
          );
    return _persistSentResult(result);
  }

  Future<Map<String, dynamic>> _editMessageText(
    Map<String, dynamic> request,
  ) async {
    final input = _map(request['input_message_content']);
    final text = _map(input?['text']);
    final result = await _client.call('editMessageText', {
      'chat_id': _requiredInt(request, 'chat_id'),
      'message_id': _requiredInt(request, 'message_id'),
      'text': _string(text?['text']),
      if (_botEntities(text?['entities']).isNotEmpty)
        'entities': _botEntities(text?['entities']),
      if (_map(input?['link_preview_options']) case final options?)
        'link_preview_options': _botLinkPreviewOptions(options),
    });
    return _persistEditedResult(result, request);
  }

  Future<Map<String, dynamic>> _editMessageCaption(
    Map<String, dynamic> request,
  ) async {
    final caption = _map(request['caption']);
    final result = await _client.call('editMessageCaption', {
      'chat_id': _requiredInt(request, 'chat_id'),
      'message_id': _requiredInt(request, 'message_id'),
      'caption': _string(caption?['text']),
      if (_botEntities(caption?['entities']).isNotEmpty)
        'caption_entities': _botEntities(caption?['entities']),
      'show_caption_above_media': request['show_caption_above_media'] == true,
    });
    return _persistEditedResult(result, request);
  }

  Future<Map<String, dynamic>> _persistEditedResult(
    Object? result,
    Map<String, dynamic> request,
  ) async {
    final source = _map(result);
    if (source != null) {
      final events = _store.transaction(
        () => _persistMessage(source, edited: true),
      );
      for (final event in events) {
        _emit(event);
      }
      return _store.message(
            _requiredInt(request, 'chat_id'),
            _requiredInt(request, 'message_id'),
          ) ??
          _ok;
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _deleteMessages(
    Map<String, dynamic> request,
  ) async {
    final chatId = _requiredInt(request, 'chat_id');
    final ids = _list(
      request['message_ids'],
    ).map(_int).whereType<int>().toList();
    if (ids.isEmpty) return _ok;
    try {
      await _client.call('deleteMessages', {
        'chat_id': chatId,
        'message_ids': ids,
      });
    } on BotApiException catch (error) {
      if (error.code != 404 && error.code != 400) rethrow;
      for (final id in ids) {
        await _client.call('deleteMessage', {
          'chat_id': chatId,
          'message_id': id,
        });
      }
    }
    final events = _store.transaction(() {
      _store.deleteMessages(chatId, ids);
      final chat = _store.chat(chatId);
      if (chat != null) {
        chat['last_message'] = _store.latestMessage(chatId);
        _store.upsertChat(chat);
      }
      return <Map<String, dynamic>>[
        {
          '@type': 'updateDeleteMessages',
          'chat_id': chatId,
          'message_ids': ids,
          'is_permanent': true,
          'from_cache': false,
        },
        if (chat != null) ..._chatPositionEvents(chat),
      ];
    });
    for (final event in events) {
      _emit(event);
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _setMessageReaction(
    Map<String, dynamic> request,
  ) async {
    final reaction = _map(request['reaction_type']);
    await _client.call('setMessageReaction', {
      'chat_id': _requiredInt(request, 'chat_id'),
      'message_id': _requiredInt(request, 'message_id'),
      'reaction': [if (reaction != null) _tdReactionToBot(reaction)],
      'is_big': request['is_big'] == true,
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _simpleMessageMutation(
    String method,
    Map<String, dynamic> request,
  ) async {
    final parameters = <String, dynamic>{
      'chat_id': _requiredInt(request, 'chat_id'),
      'message_id': ?_int(request['message_id']),
      if (method == 'pinChatMessage')
        'disable_notification': request['disable_notification'] == true,
    };
    await _client.call(method, parameters);
    return _ok;
  }

  Future<Map<String, dynamic>> _forwardMessages(
    Map<String, dynamic> request, {
    required bool copy,
  }) async {
    final ids = _list(
      request['message_ids'],
    ).map(_int).whereType<int>().toList();
    if (ids.isEmpty) {
      return const {
        '@type': 'messages',
        'total_count': 0,
        'messages': <Map<String, dynamic>>[],
      };
    }
    final method = copy || request['send_copy'] == true
        ? 'copyMessages'
        : 'forwardMessages';
    final result = await _client.call(method, {
      'chat_id': _requiredInt(request, 'chat_id'),
      'from_chat_id': _requiredInt(request, 'from_chat_id'),
      'message_ids': ids,
      'disable_notification':
          _map(request['options'])?['disable_notification'] == true,
      'protect_content': _map(request['options'])?['protect_content'] == true,
      if (request['remove_caption'] == true) 'remove_caption': true,
    });
    return _persistSentResult(result);
  }

  Map<String, dynamic> _getFile(int fileId) {
    final record = _store.file(fileId);
    return record == null
        ? _error(404, 'File is not available in on-device history.')
        : _converter.fileFromRecord(record);
  }

  Future<Map<String, dynamic>> _downloadFile(int fileId) async {
    var record = _store.file(fileId);
    if (record == null) {
      return _error(404, 'File is not available in on-device history.');
    }
    if (record.localPath.isNotEmpty && File(record.localPath).existsSync()) {
      return _converter.fileFromRecord(record);
    }
    final value = await _client.call('getFile', {'file_id': record.botFileId});
    final source = _map(value);
    final remotePath = _string(source?['file_path']);
    if (remotePath.isEmpty) {
      return _error(404, 'The Bot API did not return a file path.');
    }
    final extension = _safeExtension(remotePath);
    final destination = File('$mediaDirectory/$fileId$extension');
    await _client.downloadFile(remotePath, destination);
    _store.updateFile(
      id: fileId,
      remotePath: remotePath,
      localPath: destination.path,
      size: _int(source?['file_size']) ?? destination.lengthSync(),
    );
    record = _store.file(fileId)!;
    final file = _converter.fileFromRecord(record);
    _emit({'@type': 'updateFile', 'file': file});
    return file;
  }

  Future<Map<String, dynamic>> _deleteFile(int fileId) async {
    final record = _store.file(fileId);
    if (record == null) return _ok;
    if (record.localPath.isNotEmpty) {
      final file = File(record.localPath);
      if (await file.exists()) await file.delete();
    }
    _store.updateFile(id: fileId, localPath: '');
    final updated = _converter.fileFromRecord(_store.file(fileId)!);
    _emit({'@type': 'updateFile', 'file': updated});
    return _ok;
  }

  Map<String, dynamic> _persistSentResult(Object? result) {
    final rawMessages = result is List ? result : [result];
    final messages = <Map<String, dynamic>>[];
    final events = _store.transaction(() {
      final updates = <Map<String, dynamic>>[];
      for (final raw in rawMessages) {
        final source = _map(raw);
        if (source == null || source['message_id'] == null) continue;
        final currentEvents = _persistMessage(source, edited: false);
        updates.addAll(currentEvents);
        final chatId = _int((_map(source['chat']))?['id']) ?? 0;
        final messageId = _int(source['message_id']) ?? 0;
        final stored = _store.message(chatId, messageId);
        if (stored != null) messages.add(stored);
      }
      return updates;
    });
    for (final event in events) {
      _emit(event);
    }
    if (result is List) {
      return {
        '@type': 'messages',
        'total_count': messages.length,
        'messages': messages,
      };
    }
    return messages.isEmpty ? _ok : messages.single;
  }

  Map<String, dynamic> _commonSendParameters(
    Map<String, dynamic> request,
    int chatId,
  ) {
    final options = _map(request['options']);
    final reply = _map(request['reply_to']);
    return {
      'chat_id': chatId,
      'message_thread_id': ?_int(request['message_thread_id']),
      if (reply?['@type'] == 'inputMessageReplyToMessage')
        'reply_parameters': {
          'message_id': _int(reply?['message_id']) ?? 0,
          'chat_id': ?_int(reply?['chat_id']),
          'allow_sending_without_reply': true,
        },
      'disable_notification': options?['disable_notification'] == true,
      'protect_content': options?['protect_content'] == true,
    };
  }

  Map<String, dynamic> _captionParameters(Map<String, dynamic> content) {
    final caption = _map(content['caption']);
    return {
      if (_string(caption?['text']).isNotEmpty) 'caption': caption?['text'],
      if (_botEntities(caption?['entities']).isNotEmpty)
        'caption_entities': _botEntities(caption?['entities']),
    };
  }

  List<Map<String, dynamic>> _botEntities(Object? source) => [
    for (final raw in _list(source))
      if (_map(raw) case final entity?)
        {
          'offset': _int(entity['offset']) ?? 0,
          'length': _int(entity['length']) ?? 0,
          ..._botEntityType(_map(entity['type'])),
        },
  ];

  Map<String, dynamic> _botEntityType(Map<String, dynamic>? type) {
    final name = type?['@type'];
    return switch (name) {
      'textEntityTypeMention' => const {'type': 'mention'},
      'textEntityTypeHashtag' => const {'type': 'hashtag'},
      'textEntityTypeCashtag' => const {'type': 'cashtag'},
      'textEntityTypeBotCommand' => const {'type': 'bot_command'},
      'textEntityTypeUrl' => const {'type': 'url'},
      'textEntityTypeEmailAddress' => const {'type': 'email'},
      'textEntityTypePhoneNumber' => const {'type': 'phone_number'},
      'textEntityTypeBold' => const {'type': 'bold'},
      'textEntityTypeItalic' => const {'type': 'italic'},
      'textEntityTypeUnderline' => const {'type': 'underline'},
      'textEntityTypeStrikethrough' => const {'type': 'strikethrough'},
      'textEntityTypeSpoiler' => const {'type': 'spoiler'},
      'textEntityTypeBlockQuote' => const {'type': 'blockquote'},
      'textEntityTypeExpandableBlockQuote' => const {
        'type': 'expandable_blockquote',
      },
      'textEntityTypeCode' => const {'type': 'code'},
      'textEntityTypePre' => const {'type': 'pre'},
      'textEntityTypePreCode' => {
        'type': 'pre',
        'language': _string(type?['language']),
      },
      'textEntityTypeTextUrl' => {
        'type': 'text_link',
        'url': _string(type?['url']),
      },
      'textEntityTypeMentionName' => {
        'type': 'text_mention',
        'user': {
          'id': _int(type?['user_id']) ?? 0,
          'is_bot': false,
          'first_name': '',
        },
      },
      'textEntityTypeCustomEmoji' => {
        'type': 'custom_emoji',
        'custom_emoji_id': '${type?['custom_emoji_id'] ?? ''}',
      },
      _ => const {'type': 'code'},
    };
  }

  Map<String, dynamic> _botLinkPreviewOptions(Map<String, dynamic> source) => {
    'is_disabled': source['is_disabled'] == true,
    if (_string(source['url']).isNotEmpty) 'url': source['url'],
    'prefer_small_media': source['force_small_media'] == true,
    'prefer_large_media': source['force_large_media'] == true,
    'show_above_text': source['show_above_text'] == true,
  };

  _Upload _inputUpload(Object? source, String field) {
    final input = _findInputFile(source);
    if (input == null) {
      throw const FormatException('The attachment file is missing.');
    }
    switch (input['@type']) {
      case 'inputFileLocal':
        final path = _string(input['path']);
        if (path.isEmpty || !File(path).existsSync()) {
          throw const FormatException('The attachment file is unavailable.');
        }
        return _Upload(field: field, path: path);
      case 'inputFileRemote':
        final id = _string(input['id']);
        if (id.isEmpty) {
          throw const FormatException('The remote file is invalid.');
        }
        return _Upload(field: field, remote: id);
      case 'inputFileId':
        final record = _store.file(_int(input['id']) ?? 0);
        if (record == null || record.botFileId.isEmpty) {
          throw const FormatException('The attachment file is unavailable.');
        }
        return _Upload(field: field, remote: record.botFileId);
      default:
        throw const FormatException('This attachment source is unsupported.');
    }
  }

  Map<String, dynamic>? _findInputFile(Object? source) {
    final map = _map(source);
    if (map == null) return null;
    final type = map['@type'];
    if (type == 'inputFileLocal' ||
        type == 'inputFileRemote' ||
        type == 'inputFileId') {
      return map;
    }
    for (final value in map.values) {
      final nested = _findInputFile(value);
      if (nested != null) return nested;
    }
    return null;
  }

  Map<String, String> _multipartFields(Map<String, dynamic> parameters) => {
    for (final entry in parameters.entries)
      if (entry.value != null)
        entry.key: entry.value is Map || entry.value is List
            ? jsonEncode(entry.value)
            : '${entry.value}',
  };

  Map<String, dynamic>? _chatForPeer(int peerId, {required bool supergroup}) {
    for (final chat in _store.chats(limit: 5000)) {
      final type = _map(chat['type']);
      if (supergroup &&
          type?['@type'] == 'chatTypeSupergroup' &&
          _int(type?['supergroup_id']) == peerId) {
        return chat;
      }
      if (!supergroup &&
          type?['@type'] == 'chatTypeBasicGroup' &&
          _int(type?['basic_group_id']) == peerId) {
        return chat;
      }
    }
    return null;
  }

  Map<String, dynamic> _memberStatus(Map<String, dynamic> source) {
    return switch (_string(source['status'])) {
      'creator' => {
        '@type': 'chatMemberStatusCreator',
        'custom_title': _string(source['custom_title']),
        'is_anonymous': source['is_anonymous'] == true,
        'is_member': true,
      },
      'administrator' => {
        '@type': 'chatMemberStatusAdministrator',
        'custom_title': _string(source['custom_title']),
        'can_be_edited': source['can_be_edited'] == true,
        'rights': {
          '@type': 'chatAdministratorRights',
          'can_manage_chat': source['can_manage_chat'] == true,
          'can_change_info': source['can_change_info'] == true,
          'can_post_messages': source['can_post_messages'] == true,
          'can_edit_messages': source['can_edit_messages'] == true,
          'can_delete_messages': source['can_delete_messages'] == true,
          'can_invite_users': source['can_invite_users'] == true,
          'can_restrict_members': source['can_restrict_members'] == true,
          'can_pin_messages': source['can_pin_messages'] == true,
          'can_manage_topics': source['can_manage_topics'] == true,
          'can_promote_members': source['can_promote_members'] == true,
          'can_manage_video_chats': source['can_manage_video_chats'] == true,
          'can_post_stories': source['can_post_stories'] == true,
          'can_edit_stories': source['can_edit_stories'] == true,
          'can_delete_stories': source['can_delete_stories'] == true,
          'is_anonymous': source['is_anonymous'] == true,
        },
      },
      'restricted' => {
        '@type': 'chatMemberStatusRestricted',
        'is_member': source['is_member'] == true,
        'restricted_until_date': _int(source['until_date']) ?? 0,
        'permissions': const {
          '@type': 'chatPermissions',
          'can_send_basic_messages': false,
          'can_send_audios': false,
          'can_send_documents': false,
          'can_send_photos': false,
          'can_send_videos': false,
          'can_send_video_notes': false,
          'can_send_voice_notes': false,
          'can_send_polls': false,
          'can_send_other_messages': false,
          'can_add_link_previews': false,
          'can_change_info': false,
          'can_invite_users': false,
          'can_pin_messages': false,
          'can_create_topics': false,
        },
      },
      'left' => const {'@type': 'chatMemberStatusLeft'},
      'kicked' => {
        '@type': 'chatMemberStatusBanned',
        'banned_until_date': _int(source['until_date']) ?? 0,
      },
      _ => const {'@type': 'chatMemberStatusMember'},
    };
  }

  Map<String, dynamic> _botReactionToTd(Map<String, dynamic>? source) {
    return switch (_string(source?['type'])) {
      'custom_emoji' => {
        '@type': 'reactionTypeCustomEmoji',
        'custom_emoji_id': _stableId(_string(source?['custom_emoji_id'])),
      },
      'paid' => const {'@type': 'reactionTypePaid'},
      _ => {'@type': 'reactionTypeEmoji', 'emoji': _string(source?['emoji'])},
    };
  }

  Map<String, dynamic> _tdReactionToBot(Map<String, dynamic> source) {
    return switch (source['@type']) {
      'reactionTypeCustomEmoji' => {
        'type': 'custom_emoji',
        'custom_emoji_id': '${source['custom_emoji_id'] ?? ''}',
      },
      'reactionTypePaid' => const {'type': 'paid'},
      _ => {'type': 'emoji', 'emoji': _string(source['emoji'])},
    };
  }

  Set<String>? _contentTypesForFilter(Map<String, dynamic>? filter) {
    return switch (filter?['@type']) {
      'searchMessagesFilterPhoto' => {'messagePhoto'},
      'searchMessagesFilterVideo' => {'messageVideo'},
      'searchMessagesFilterPhotoAndVideo' => {'messagePhoto', 'messageVideo'},
      'searchMessagesFilterDocument' => {'messageDocument'},
      'searchMessagesFilterAudio' => {'messageAudio'},
      'searchMessagesFilterVoiceNote' => {'messageVoiceNote'},
      'searchMessagesFilterVideoNote' => {'messageVideoNote'},
      'searchMessagesFilterAnimation' => {'messageAnimation', 'messageSticker'},
      'searchMessagesFilterPoll' => {'messagePoll'},
      _ => null,
    };
  }

  List<Map<String, dynamic>> _chatPositionEvents(Map<String, dynamic> chat) {
    final chatId = _int(chat['id']) ?? 0;
    final positions = _list(
      chat['positions'],
    ).map(_map).whereType<Map<String, dynamic>>().toList();
    return [
      {
        '@type': 'updateChatLastMessage',
        'chat_id': chatId,
        'last_message': chat['last_message'],
        'positions': positions,
      },
      for (final position in positions)
        {
          '@type': 'updateChatPosition',
          'chat_id': chatId,
          'position': position,
        },
      {
        '@type': 'updateChatReadInbox',
        'chat_id': chatId,
        'last_read_inbox_message_id': chat['last_read_inbox_message_id'] ?? 0,
        'unread_count': chat['unread_count'] ?? 0,
      },
    ];
  }

  void _emitConnection(String state) {
    _emit({
      '@type': 'updateConnectionState',
      'state': {'@type': state},
    });
    _emit({
      '@type': 'updateBotApiConnectionState',
      'endpoint': account.endpoint.toString(),
      'is_polling': _polling,
      'has_webhook_conflict': _webhookConflict,
      'error': _connectionError,
    });
  }

  Map<String, dynamic> _authorizationUpdate(String state) => {
    '@type': 'updateAuthorizationState',
    'authorization_state': {'@type': state},
  };

  Map<String, dynamic> _option(String name) {
    return switch (name) {
      'version' => const {
        '@type': 'optionValueString',
        'value': 'Telegram Bot API',
      },
      'my_id' => {'@type': 'optionValueInteger', 'value': account.botId},
      'can_use_login_passkey' => const {
        '@type': 'optionValueBoolean',
        'value': false,
      },
      _ => const {'@type': 'optionValueEmpty'},
    };
  }
}

class _Upload {
  const _Upload({required this.field, this.path, this.remote});

  final String field;
  final String? path;
  final String? remote;
}

const Map<String, dynamic> _ok = {'@type': 'ok'};

const Map<String, dynamic> _scopeNotificationSettings = {
  '@type': 'scopeNotificationSettings',
  'mute_for': 0,
  'sound_id': -1,
  'show_preview': true,
  'use_default_mute_stories': true,
  'mute_stories': false,
  'story_sound_id': -1,
  'show_story_sender': true,
  'disable_pinned_message_notifications': false,
  'disable_mention_notifications': false,
};

const List<String> _allowedUpdates = [
  'message',
  'edited_message',
  'channel_post',
  'edited_channel_post',
  'business_connection',
  'business_message',
  'edited_business_message',
  'deleted_business_messages',
  'message_reaction',
  'message_reaction_count',
  'inline_query',
  'chosen_inline_result',
  'callback_query',
  'shipping_query',
  'pre_checkout_query',
  'purchased_paid_media',
  'poll',
  'poll_answer',
  'my_chat_member',
  'chat_member',
  'chat_join_request',
  'chat_boost',
  'removed_chat_boost',
];

const List<String> _newMessageKeys = [
  'message',
  'channel_post',
  'business_message',
  'guest_message',
];

const List<String> _editedMessageKeys = [
  'edited_message',
  'edited_channel_post',
  'edited_business_message',
  'edited_guest_message',
];

Map<String, dynamic> _error(int code, String message) => {
  '@type': 'error',
  'code': code,
  'message': message,
};

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Object?> _list(Object? value) => value is List ? value : const [];

String _string(Object? value) => value is String ? value : '';

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int _requiredInt(Map<String, dynamic> source, String key) {
  final value = _int(source[key]);
  if (value == null) throw FormatException('$key is required.');
  return value;
}

int? _nestedInt(Object? source, String key) {
  final map = _map(source);
  return _int(map?[key]);
}

String _nestedString(Object? source, String key) {
  final map = _map(source);
  return _string(map?[key]);
}

Map<String, dynamic>? _inviteLink(Object? source) {
  final value = source is String
      ? source
      : _string(_map(source)?['invite_link']);
  if (value.isEmpty) return null;
  return {
    '@type': 'chatInviteLink',
    'invite_link': value,
    'name': '',
    'creator_user_id': 0,
    'date': 0,
    'edit_date': 0,
    'expiration_date': 0,
    'member_limit': 0,
    'member_count': 0,
    'pending_join_request_count': 0,
    'creates_join_request': false,
    'is_primary': true,
    'is_revoked': false,
  };
}

String _safeExtension(String path) {
  final leaf = path.split('/').last;
  final dot = leaf.lastIndexOf('.');
  if (dot < 0) return '';
  final extension = leaf.substring(dot).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension) ? extension : '';
}

int _stableId(String value) {
  if (value.isEmpty) return 0;
  var hash = 0xcbf29ce484222325;
  for (final byte in value.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash;
}
