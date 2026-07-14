import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/sticker_export_service.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  ChatMessage message({TdFileRef? animatedSticker}) => ChatMessage(
    id: 41,
    isOutgoing: false,
    text: '',
    date: 1,
    animatedSticker: animatedSticker,
    image: animatedSticker == null ? TdFileRef(id: 7) : null,
  );

  test('offers PNG, GIF, and MOV when alpha MOV is supported', () {
    final formats = StickerExportService.availableFormats(
      message(),
      supportsMov: true,
    );
    expect(formats, [
      StickerExportFormat.png,
      StickerExportFormat.gif,
      StickerExportFormat.mov,
    ]);
  });

  test('labels animated PNG exports as APNG', () {
    final animated = message(animatedSticker: TdFileRef(id: 9));
    expect(StickerExportService.isAnimated(animated), isTrue);
    expect(StickerExportFormat.png.label(animated: true), 'APNG');
    expect(StickerExportFormat.png.label(animated: false), 'PNG');
  });

  test('APNG encoder keeps animation frames and full alpha', () {
    final bytes = StickerExportService.encodeRgbaFramesForTest(
      [
        Uint8List.fromList([255, 0, 0, 0]),
        Uint8List.fromList([0, 255, 0, 128]),
      ],
      width: 1,
      height: 1,
      durationMs: 50,
      format: StickerExportFormat.png,
    );

    expect(bytes, isNotNull);
    final decoded = image_lib.decodePng(bytes!);
    expect(decoded, isNotNull);
    expect(decoded!.numFrames, 2);
    expect(decoded.frames[0].getPixel(0, 0).a.toInt(), 0);
    expect(decoded.frames[1].getPixel(0, 0).a.toInt(), 128);
    expect(decoded.frames[0].frameDuration, 50);
  });

  test('GIF encoder produces an animated GIF', () {
    final bytes = StickerExportService.encodeRgbaFramesForTest(
      [
        Uint8List.fromList([255, 0, 0, 0]),
        Uint8List.fromList([0, 0, 255, 255]),
      ],
      width: 1,
      height: 1,
      durationMs: 60,
      format: StickerExportFormat.gif,
    );

    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!.take(6)), startsWith('GIF8'));
    expect(image_lib.decodeGif(bytes)?.numFrames, 2);
  });
}
