import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('message parser preserves TDLib unread mention state', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 91,
      'chat_id': 12,
      'date': 1,
      'is_outgoing': false,
      'contains_unread_mention': true,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': '@me hello',
          'entities': <Object>[],
        },
      },
    });

    expect(message, isNotNull);
    expect(message!.containsUnreadMention, isTrue);
  });

  test('viewing mentions decrements the badge without going negative', () {
    expect(unreadMentionCountAfterReading(3, 1), 2);
    expect(unreadMentionCountAfterReading(1, 1), 0);
    expect(unreadMentionCountAfterReading(0, 4), 0);
    expect(unreadMentionCountAfterReading(2, -1), 2);
  });
}
