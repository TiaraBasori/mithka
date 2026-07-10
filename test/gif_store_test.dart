import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/gif_item.dart';
import 'package:mithka/chat/gif_store.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('parseSavedAnimations keeps send and preview metadata', () {
    final items = parseSavedAnimations([
      {
        '@type': 'animation',
        'duration': 4,
        'width': 640,
        'height': 360,
        'mime_type': 'video/mp4',
        'animation': {
          '@type': 'file',
          'id': 42,
          'remote': {'@type': 'remoteFile', 'id': 'remote-animation'},
        },
        'thumbnail': {
          '@type': 'thumbnail',
          'file': {'@type': 'file', 'id': 43},
        },
      },
    ]);

    expect(items, hasLength(1));
    expect(items.single.id, 42);
    expect(items.single.remoteId, 'remote-animation');
    expect(items.single.duration, 4);
    expect(items.single.width, 640);
    expect(items.single.height, 360);
    expect(items.single.mimeType, 'video/mp4');
    expect(items.single.thumbnail?.id, 43);
  });

  test('parseSavedAnimations skips entries without an animation file', () {
    expect(
      parseSavedAnimations([
        {'@type': 'animation', 'duration': 1},
      ]),
      isEmpty,
    );
  });

  test('saved GIF messages reuse the active account file id', () {
    final gif = GifItem(
      id: 42,
      remoteId: 'remote-animation',
      duration: 4,
      width: 640,
      height: 360,
      mimeType: 'video/mp4',
      file: TdFileRef(id: 42),
    );

    expect(gifMessageContent(gif), {
      '@type': 'inputMessageAnimation',
      'animation': {'@type': 'inputFileId', 'id': 42},
      'duration': 4,
      'width': 640,
      'height': 360,
    });
  });
}
