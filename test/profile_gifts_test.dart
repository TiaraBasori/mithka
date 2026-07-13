import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/profile_gifts.dart';

void main() {
  test('parses regular and upgraded gift stickers', () {
    Map<String, dynamic> sticker(int id, String emoji) => {
      '@type': 'sticker',
      'sticker': {
        '@type': 'file',
        'id': id,
        'remote': {'@type': 'remoteFile', 'id': 'remote-$id'},
      },
      'format': {'@type': 'stickerFormatWebp'},
      'width': 512,
      'height': 512,
      'emoji': emoji,
    };

    final gifts = parseReceivedGiftStickers({
      '@type': 'receivedGifts',
      'gifts': [
        {
          '@type': 'receivedGift',
          'gift': {
            '@type': 'sentGiftRegular',
            'gift': {'@type': 'gift', 'sticker': sticker(101, '🎁')},
          },
        },
        {
          '@type': 'receivedGift',
          'gift': {
            '@type': 'sentGiftUpgraded',
            'gift': {
              '@type': 'upgradedGift',
              'model': {
                '@type': 'upgradedGiftModel',
                'sticker': sticker(202, '⭐'),
              },
            },
          },
        },
        {
          '@type': 'receivedGift',
          'gift': {'@type': 'sentGiftPremiumSubscription'},
        },
      ],
    });

    expect(gifts.map((gift) => gift.id), [101, 202]);
    expect(gifts.map((gift) => gift.emoji), ['🎁', '⭐']);
  });
}
