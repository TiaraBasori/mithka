import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/image_media_album_bubble.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('non-channel comment metadata enables transcript attachments', () {
    final thread = ChatMessage(
      id: 1,
      isOutgoing: false,
      text: 'Thread',
      date: 1,
      hasCommentThread: true,
    );
    final counted = ChatMessage(
      id: 2,
      isOutgoing: false,
      text: 'Counted',
      date: 1,
      commentCount: 4,
    );
    final plain = ChatMessage(id: 3, isOutgoing: false, text: 'Plain', date: 1);

    expect(
      chatTranscriptAllowsCommentAttachment(isChannel: false, message: thread),
      isTrue,
    );
    expect(
      chatTranscriptAllowsCommentAttachment(isChannel: false, message: counted),
      isTrue,
    );
    expect(
      chatTranscriptAllowsCommentAttachment(isChannel: false, message: plain),
      isFalse,
    );
    expect(
      chatTranscriptAlbumAllowsCommentAttachment(
        isChannel: false,
        messages: [plain, counted],
      ),
      isTrue,
    );
  });

  test('interaction updates refresh channel discussion metadata', () {
    final vm = ChatViewModel(
      chatId: 42,
      title: 'Channel',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    final message = ChatMessage(
      id: 7,
      chatId: 42,
      isOutgoing: false,
      text: 'Post',
      date: 1,
    );
    vm.messages.add(message);

    vm.applyLiveUpdateForTesting({
      '@type': 'updateMessageInteractionInfo',
      'chat_id': 42,
      'message_id': 7,
      'interaction_info': {
        '@type': 'messageInteractionInfo',
        'view_count': 510,
        'forward_count': 3,
        'reply_info': {
          '@type': 'messageReplyInfo',
          'reply_count': 7,
          'last_message_id': 99,
        },
      },
    });

    expect(message.hasCommentThread, isTrue);
    expect(message.commentThreadMetadataKnown, isTrue);
    expect(message.commentCount, 7);
    expect(message.lastCommentMessageId, 99);
    expect(message.viewCount, 510);
    expect(message.forwardCount, 3);
  });

  test('parser marks explicit no-thread interaction metadata as known', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 7,
      'chat_id': 42,
      'is_outgoing': false,
      'date': 1,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'Post', 'entities': []},
      },
      'interaction_info': {
        '@type': 'messageInteractionInfo',
        'view_count': 1,
        'forward_count': 0,
        'reply_info': null,
      },
    });

    expect(message, isNotNull);
    expect(message!.commentThreadMetadataKnown, isTrue);
    expect(message.hasCommentThread, isFalse);
    expect(message.commentCount, 0);
  });

  test('supergroup updates expose a linked channel discussion', () {
    final vm =
        ChatViewModel(chatId: 42, title: 'Channel', markReadOnOpen: false)
          ..isChannel = true
          ..peerSupergroupId = 5;
    addTearDown(vm.dispose);

    vm.applyLiveUpdateForTesting({
      '@type': 'updateSupergroupFullInfo',
      'supergroup_id': 5,
      'supergroup_full_info': {
        '@type': 'supergroupFullInfo',
        'linked_chat_id': 84,
      },
    });

    expect(vm.hasLinkedDiscussion, isTrue);
  });

  test('album comments take ownership ahead of reactions', () {
    final reacted = ChatMessage(id: 1, isOutgoing: false, text: '', date: 1)
      ..reactions = const [
        MessageReaction(emoji: '👍', count: 1, chosen: false),
      ];
    final commented = ChatMessage(
      id: 2,
      isOutgoing: false,
      text: '',
      date: 1,
      commentCount: 7,
    );

    expect(selectMediaAlbumInteractionOwner([reacted, commented]), commented);
  });
}
