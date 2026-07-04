import 'package:flutter/foundation.dart';

class ChatDeepLinkRequest {
  const ChatDeepLinkRequest({
    required this.chatId,
    required this.title,
    this.messageId,
  });

  final int chatId;
  final String title;
  final int? messageId;
}

class ChatDeepLinkController extends ChangeNotifier {
  ChatDeepLinkController._();

  static final ChatDeepLinkController shared = ChatDeepLinkController._();

  ChatDeepLinkRequest? _pending;

  void openChat({required int chatId, required String title, int? messageId}) {
    _pending = ChatDeepLinkRequest(
      chatId: chatId,
      title: title,
      messageId: messageId,
    );
    notifyListeners();
  }

  ChatDeepLinkRequest? consumePending() {
    final request = _pending;
    _pending = null;
    return request;
  }
}
