//
//  gif_item.dart
//
//  A saved Telegram animation shown in the composer's GIF tab.
//

import '../tdlib/td_models.dart';

class GifItem {
  const GifItem({
    required this.id,
    this.remoteId,
    required this.duration,
    required this.width,
    required this.height,
    required this.mimeType,
    required this.file,
    this.thumbnail,
  });

  final int id;
  final String? remoteId;
  final int duration;
  final int width;
  final int height;
  final String mimeType;
  final TdFileRef file;
  final TdFileRef? thumbnail;
}

Map<String, dynamic> gifMessageContent(GifItem gif) => {
  '@type': 'inputMessageAnimation',
  // Saved animations already belong to the active TDLib account. Reusing the
  // account-local file id retains the file reference required for sending.
  'animation': {'@type': 'inputFileId', 'id': gif.id},
  'duration': gif.duration,
  'width': gif.width,
  'height': gif.height,
};
