import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'desktop_chat_window_models.dart';

const _snapshotMethod = 'mithka.chat.snapshot';
const _snapshotUpdatedMethod = 'mithka.chat.snapshot.updated';
const _sendTextMethod = 'mithka.chat.sendText';

const _chatWindowSize = Size(920, 680);
const _chatWindowMinimumSize = Size(620, 480);

bool get supportsDesktopChatWindows =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

final _mainBridge = _DesktopChatMainBridge();

void attachDesktopChatMainProxy() => _mainBridge.attach();

void detachDesktopChatMainProxy() => _mainBridge.detach();

Future<bool> openDesktopChatWindow(DesktopChatWindowArguments arguments) =>
    _mainBridge.open(arguments);

Future<void> closeCurrentDesktopChatWindow() async {
  if (!supportsDesktopChatWindows || MultiWindowManager.current.id <= 0) {
    return;
  }
  try {
    await MultiWindowManager.current.close();
  } on Object {
    // Closing an already-destroyed native child is a harmless no-op.
  }
}

DesktopChatWindowChildController createDesktopChatWindowChildController(
  DesktopChatWindowArguments arguments,
) => _DesktopChatWindowChildController(arguments);

Widget buildDesktopChatWindowHost({
  required DesktopChatWindowArguments initialArguments,
  required Widget Function(
    BuildContext context,
    DesktopChatWindowArguments arguments,
  )
  builder,
}) {
  if (!Platform.isLinux) {
    return Builder(builder: (context) => builder(context, initialArguments));
  }
  return ReusableWindow(
    initialArgs: [initialArguments.encode()],
    windowOptions: _windowOptions(initialArguments),
    loadingBuilder: (_) =>
        ColoredBox(color: Color(initialArguments.palette.chatBackground)),
    builder: (context, source) {
      final arguments = _parseReusableArguments(source) ?? initialArguments;
      return KeyedSubtree(
        key: ValueKey(arguments.encode()),
        child: builder(context, arguments),
      );
    },
  );
}

DesktopChatWindowArguments? _parseReusableArguments(Object? source) {
  final encoded = switch (source) {
    final String value => value,
    final List values when values.isNotEmpty && values.first is String =>
      values.first! as String,
    _ => null,
  };
  return encoded == null ? null : DesktopChatWindowArguments.tryParse(encoded);
}

WindowOptions _windowOptions(DesktopChatWindowArguments arguments) =>
    WindowOptions(
      size: _chatWindowSize,
      minimumSize: _chatWindowMinimumSize,
      center: true,
      title: arguments.title,
      backgroundColor: Color(arguments.palette.chatBackground),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: Platform.isMacOS,
    );

class _DesktopChatMainBridge with WindowListener {
  final DesktopChatWindowRegistry _registry = DesktopChatWindowRegistry();
  final Map<int, DesktopChatWindowArguments> _argumentsByWindow = {};
  final Map<DesktopChatWindowKey, Timer> _refreshTimers = {};
  StreamSubscription<Map<String, dynamic>>? _tdUpdates;
  bool _attached = false;

  void attach() {
    if (_attached || !supportsDesktopChatWindows) return;
    try {
      MultiWindowManager.current.addListener(this);
      MultiWindowManager.addGlobalListener(this);
      MultiWindowManager.current.activeWindows.addListener(
        _handleActiveWindowsChanged,
      );
      _tdUpdates = TdClient.shared.subscribeAll().listen(_handleTdUpdate);
      _attached = true;
    } on Object {
      // The native plugin is optional on portable builds. Never start another
      // Telegram client as a fallback for a missing window bridge.
    }
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    MultiWindowManager.current.removeListener(this);
    MultiWindowManager.removeGlobalListener(this);
    MultiWindowManager.current.activeWindows.removeListener(
      _handleActiveWindowsChanged,
    );
    unawaited(_tdUpdates?.cancel());
    _tdUpdates = null;
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _refreshTimers.clear();
    _argumentsByWindow.clear();
    _registry.clear();
  }

  Future<bool> open(DesktopChatWindowArguments arguments) async {
    if (!supportsDesktopChatWindows) return false;
    attach();
    MultiWindowManager? createdWindow;
    try {
      final active = await MultiWindowManager.current.getActiveWindowIds();
      final existing = _registry.activeWindowFor(arguments.key, active);
      if (existing != null) {
        final window = MultiWindowManager.fromWindowId(existing);
        await window.show();
        await window.focus();
        return true;
      }

      createdWindow = Platform.isLinux
          ? await MultiWindowManager.createWindowOrReuse(
              args: [arguments.encode()],
            )
          : await MultiWindowManager.createWindow([arguments.encode()]);
      if (createdWindow == null || createdWindow.id <= 0) return false;

      // Register before configuration/show so the child can never authorize
      // itself by echoing account/chat identifiers over IPC. A child whose
      // first request races createWindow's completion retries briefly.
      _registerWindow(createdWindow.id, arguments);

      if (Platform.isLinux) {
        await _waitUntilVisible(createdWindow);
      } else {
        await createdWindow.waitUntilReadyToShow(_windowOptions(arguments));
        await createdWindow.show();
        await createdWindow.focus();
      }
      return true;
    } on Object catch (error) {
      final failedWindow = createdWindow;
      if (failedWindow != null) {
        _removeWindow(failedWindow.id);
        try {
          await failedWindow.close();
        } on Object {
          // The native window may already have closed during startup.
        }
      }
      assert(() {
        debugPrint('Desktop chat window open failed: $error');
        return true;
      }());
      return false;
    }
  }

  Future<void> _waitUntilVisible(MultiWindowManager controller) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (await controller.isVisible()) {
        await controller.focus();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw TimeoutException('Desktop chat window did not become visible.');
  }

  void _registerWindow(int windowId, DesktopChatWindowArguments arguments) {
    for (final entry in _argumentsByWindow.entries.toList(growable: false)) {
      if (entry.key == windowId || entry.value.key == arguments.key) {
        _argumentsByWindow.remove(entry.key);
      }
    }
    _argumentsByWindow[windowId] = arguments;
    _registry.register(arguments.key, windowId);
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    if (fromWindowId <= 0) return null;
    final requestedKey = _keyFromIpc(arguments);
    final registered = _argumentsByWindow[fromWindowId];
    if (requestedKey == null ||
        registered == null ||
        !desktopChatWindowRequestIsRegistered(
          registry: _registry,
          windowId: fromWindowId,
          requestedKey: requestedKey,
        )) {
      return null;
    }

    switch (eventName) {
      case _snapshotMethod:
        return (await _loadSnapshot(registered)).toJson();
      case _sendTextMethod:
        final text = arguments is Map && arguments['text'] is String
            ? arguments['text']! as String
            : '';
        return _sendText(registered, text);
      default:
        return null;
    }
  }

  DesktopChatWindowKey? _keyFromIpc(Object? source) {
    if (source is! Map ||
        source['accountSlot'] is! int ||
        source['chatId'] is! int) {
      return null;
    }
    final accountSlot = source['accountSlot']! as int;
    final chatId = source['chatId']! as int;
    if (accountSlot < 0 || chatId == 0) return null;
    return DesktopChatWindowKey(accountSlot: accountSlot, chatId: chatId);
  }

  Future<Map<String, Object?>> _sendText(
    DesktopChatWindowArguments arguments,
    String source,
  ) async {
    final text = source.trim();
    if (text.isEmpty) return const {'ok': false};
    final clientId = TdClient.shared.clientId(arguments.accountSlot);
    if (clientId == null) return const {'ok': false};
    final bounded = text.length <= 4096 ? text : text.substring(0, 4096);
    try {
      await TdClient.shared.queryTo({
        '@type': 'sendMessage',
        'chat_id': arguments.chatId,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {
            '@type': 'formattedText',
            'text': bounded,
            'entities': const <Object>[],
          },
          'clear_draft': true,
        },
      }, clientId);
      _scheduleRefresh(arguments.key);
      return const {'ok': true};
    } on Object {
      return const {'ok': false};
    }
  }

  Future<DesktopChatWindowSnapshot> _loadSnapshot(
    DesktopChatWindowArguments arguments,
  ) async {
    final clientId = TdClient.shared.clientId(arguments.accountSlot);
    if (clientId == null) {
      return DesktopChatWindowSnapshot(
        title: arguments.title,
        canSend: false,
        messages: const [],
        failed: true,
      );
    }
    try {
      final results = await Future.wait([
        TdClient.shared.queryTo({
          '@type': 'getChat',
          'chat_id': arguments.chatId,
        }, clientId),
        TdClient.shared.queryTo({
          '@type': 'getChatHistory',
          'chat_id': arguments.chatId,
          'from_message_id': 0,
          'offset': 0,
          'limit': 60,
          'only_local': false,
        }, clientId),
      ]);
      final chat = results[0];
      final history = results[1];
      final rawMessages = history.objects('messages') ?? const [];
      final senderNames = await _resolveSenderNames(rawMessages, clientId);
      final messages =
          rawMessages
              .map((message) => _messageSnapshot(message, senderNames))
              .whereType<DesktopChatMessageSnapshot>()
              .toList()
            ..sort((a, b) {
              final byDate = a.date.compareTo(b.date);
              return byDate == 0 ? a.id.compareTo(b.id) : byDate;
            });
      final permissions = chat.obj('permissions');
      return DesktopChatWindowSnapshot(
        title: DesktopChatWindowArguments.normalizeTitle(
          chat.str('title') ?? arguments.title,
        ),
        canSend: permissions?.boolean('can_send_basic_messages') ?? true,
        messages: List.unmodifiable(messages),
      );
    } on Object {
      return DesktopChatWindowSnapshot(
        title: arguments.title,
        canSend: false,
        messages: const [],
        failed: true,
      );
    }
  }

  Future<Map<String, String>> _resolveSenderNames(
    List<Map<String, dynamic>> messages,
    int clientId,
  ) async {
    final senders = <String, Map<String, dynamic>>{};
    for (final message in messages) {
      final sender = message.obj('sender_id');
      final key = _senderKey(sender);
      if (key != null && sender != null) senders[key] = sender;
    }
    final entries = await Future.wait(
      senders.entries.map((entry) async {
        try {
          final sender = entry.value;
          final object = switch (sender.type) {
            'messageSenderUser' => await TdClient.shared.queryTo({
              '@type': 'getUser',
              'user_id': sender.int64('user_id'),
            }, clientId),
            'messageSenderChat' => await TdClient.shared.queryTo({
              '@type': 'getChat',
              'chat_id': sender.int64('chat_id'),
            }, clientId),
            _ => null,
          };
          final title = switch (sender.type) {
            'messageSenderUser' when object != null => TDParse.userName(object),
            'messageSenderChat' when object != null =>
              object.str('title') ?? '',
            _ => '',
          };
          return MapEntry(entry.key, title);
        } on Object {
          return MapEntry(entry.key, '');
        }
      }),
    );
    return Map.fromEntries(entries);
  }

  DesktopChatMessageSnapshot? _messageSnapshot(
    Map<String, dynamic> message,
    Map<String, String> senderNames,
  ) {
    final id = message.int64('id');
    final content = message.obj('content');
    if (id == null || content == null) return null;
    return DesktopChatMessageSnapshot(
      id: id,
      date: message.integer('date') ?? 0,
      outgoing: message.boolean('is_outgoing') ?? false,
      senderName: senderNames[_senderKey(message.obj('sender_id'))] ?? '',
      contentType: content.type ?? 'messageUnsupported',
      text: TDParse.messageText(content),
      mediaPath: _localMediaPath(content),
    );
  }

  String? _senderKey(Map<String, dynamic>? sender) => switch (sender?.type) {
    'messageSenderUser' => 'user:${sender?.int64('user_id')}',
    'messageSenderChat' => 'chat:${sender?.int64('chat_id')}',
    _ => null,
  };

  String? _localMediaPath(Map<String, dynamic> content) {
    Map<String, dynamic>? file;
    switch (content.type) {
      case 'messagePhoto':
        final sizes = content.obj('photo')?.objects('sizes') ?? const [];
        Map<String, dynamic>? largest;
        var largestArea = -1;
        for (final size in sizes) {
          final area =
              (size.integer('width') ?? 0) * (size.integer('height') ?? 0);
          if (area > largestArea) {
            largestArea = area;
            largest = size;
          }
        }
        file = largest?.obj('photo');
      case 'messageVideo':
        file = content.obj('video')?.obj('thumbnail')?.obj('file');
      case 'messageAnimation':
        file = content.obj('animation')?.obj('thumbnail')?.obj('file');
      case 'messageSticker':
        file = content.obj('sticker')?.obj('thumbnail')?.obj('file');
      case 'messageDocument':
        file = content.obj('document')?.obj('thumbnail')?.obj('file');
    }
    final path = file?.obj('local')?.str('path')?.trim();
    return path == null || path.isEmpty ? null : path;
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    final clientId = update.integer('@client_id');
    if (clientId == null) return;
    final slot = TdClient.shared.slotForClient(clientId);
    if (slot == null) return;
    final chatId = _updatedChatId(update);
    if (chatId != null) {
      _scheduleRefresh(DesktopChatWindowKey(accountSlot: slot, chatId: chatId));
      return;
    }
    if (update.type == 'updateUser') {
      for (final arguments in _argumentsByWindow.values) {
        if (arguments.accountSlot == slot) _scheduleRefresh(arguments.key);
      }
    }
  }

  int? _updatedChatId(Map<String, dynamic> update) => switch (update.type) {
    'updateNewMessage' ||
    'updateMessageSendSucceeded' ||
    'updateMessageSendFailed' =>
      update.obj('message')?.int64('chat_id') ?? update.int64('chat_id'),
    'updateMessageContent' ||
    'updateDeleteMessages' ||
    'updateChatTitle' ||
    'updateChatPhoto' ||
    'updateChatReadInbox' ||
    'updateChatLastMessage' => update.int64('chat_id'),
    _ => null,
  };

  void _scheduleRefresh(DesktopChatWindowKey key) {
    final windowId = _registry.activeWindowFor(
      key,
      MultiWindowManager.current.activeWindows.value,
    );
    if (windowId == null) return;
    _refreshTimers.remove(key)?.cancel();
    _refreshTimers[key] = Timer(const Duration(milliseconds: 90), () async {
      _refreshTimers.remove(key);
      final arguments = _argumentsByWindow[windowId];
      if (arguments == null || arguments.key != key) return;
      final snapshot = await _loadSnapshot(arguments);
      try {
        await MultiWindowManager.current.invokeMethodToWindow(
          windowId,
          _snapshotUpdatedMethod,
          snapshot.toJson(),
        );
      } on Object {
        _removeWindow(windowId);
      }
    });
  }

  void _handleActiveWindowsChanged() {
    final active = MultiWindowManager.current.activeWindows.value.toSet();
    for (final windowId in _argumentsByWindow.keys.toList(growable: false)) {
      if (!active.contains(windowId)) _removeWindow(windowId);
    }
    _registry.retainActive(active);
  }

  void _removeWindow(int windowId) {
    final arguments = _argumentsByWindow.remove(windowId);
    if (arguments != null) _refreshTimers.remove(arguments.key)?.cancel();
    _registry.removeWindow(windowId);
  }

  @override
  void onWindowClose([int? windowId]) {
    if (windowId != null && windowId > 0) _removeWindow(windowId);
  }
}

class _DesktopChatWindowChildController extends DesktopChatWindowChildController
    with WindowListener {
  _DesktopChatWindowChildController(this.arguments) {
    MultiWindowManager.current.addListener(this);
    unawaited(_load());
  }

  final DesktopChatWindowArguments arguments;
  DesktopChatWindowSnapshot? _snapshot;
  bool _loading = true;
  bool _sending = false;
  bool _sendFailed = false;
  bool _disposed = false;

  @override
  DesktopChatWindowSnapshot? get snapshot => _snapshot;

  @override
  bool get loading => _loading;

  @override
  bool get sending => _sending;

  @override
  bool get sendFailed => _sendFailed;

  Future<void> _load() async {
    for (
      var attempt = 0;
      attempt < 20 && _snapshot == null && !_disposed;
      attempt += 1
    ) {
      try {
        final result = await MultiWindowManager.current
            .invokeMethodToWindow(0, _snapshotMethod, arguments.toIpcJson())
            .timeout(const Duration(seconds: 2));
        _snapshot = DesktopChatWindowSnapshot.tryParse(result);
      } on Object {
        // The main isolate may still be registering a freshly-created native
        // controller. Retry only the bounded IPC request; never start TDLib.
      }
      if (_snapshot == null && attempt < 19) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (_disposed) return;
    _snapshot ??= DesktopChatWindowSnapshot(
      title: arguments.title,
      canSend: false,
      messages: const [],
      failed: true,
    );
    _loading = false;
    notifyListeners();
  }

  @override
  Future<bool> sendText(String text) async {
    if (_disposed || _sending || text.trim().isEmpty) return false;
    _sending = true;
    _sendFailed = false;
    notifyListeners();
    try {
      final request = {...arguments.toIpcJson(), 'text': text};
      final result = await MultiWindowManager.current
          .invokeMethodToWindow(0, _sendTextMethod, request)
          .timeout(const Duration(seconds: 20));
      final sent = result is Map && result['ok'] == true;
      _sendFailed = !sent;
      return sent;
    } on Object {
      _sendFailed = true;
      return false;
    } finally {
      _sending = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic eventArguments,
  ) async {
    if (_disposed || fromWindowId != 0 || eventName != _snapshotUpdatedMethod) {
      return null;
    }
    final next = DesktopChatWindowSnapshot.tryParse(eventArguments);
    if (next != null) {
      _snapshot = next;
      _loading = false;
      notifyListeners();
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    MultiWindowManager.current.removeListener(this);
    super.dispose();
  }
}
