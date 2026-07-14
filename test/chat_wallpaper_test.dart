import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wallpaper JSON preserves preset and image values', () {
    const preset = ChatWallpaper.preset('sky');
    const image = ChatWallpaper.image('/tmp/wallpaper.png');

    expect(ChatWallpaper.fromJson(preset.toJson()), preset);
    expect(ChatWallpaper.fromJson(image.toJson()), image);
    expect(
      ChatWallpaper.fromJson(const {'kind': 'preset', 'preset_id': 'missing'}),
      isNull,
    );
  });

  test('wallpapers are persisted per account and chat', () async {
    SharedPreferences.setMockInitialValues({});
    var activeSlot = 0;
    final controller = ChatWallpaperController(activeSlot: () => activeSlot);

    await controller.setPreset(42, 'sky');
    expect(controller.wallpaperFor(42), const ChatWallpaper.preset('sky'));

    activeSlot = 1;
    await controller.load(42);
    expect(controller.wallpaperFor(42), isNull);
    await controller.setPreset(42, 'night');

    activeSlot = 0;
    expect(controller.wallpaperFor(42), const ChatWallpaper.preset('sky'));

    final restored = ChatWallpaperController(activeSlot: () => activeSlot);
    await restored.load(42);
    expect(restored.wallpaperFor(42), const ChatWallpaper.preset('sky'));
  });

  test(
    'custom image is copied into support storage and removed on reset',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp(
        'mithka_wallpaper_test',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final source = File('${root.path}/source.png');
      await source.writeAsBytes(const [137, 80, 78, 71]);
      final support = Directory('${root.path}/support');
      final controller = ChatWallpaperController(
        activeSlot: () => 3,
        supportDirectory: () async => support,
      );

      await controller.setImage(99, source.path);
      final stored = controller.wallpaperFor(99);
      expect(stored?.kind, ChatWallpaperKind.image);
      expect(stored?.imagePath, isNot(source.path));
      expect(await File(stored!.imagePath!).exists(), isTrue);

      await controller.clear(99);
      expect(controller.wallpaperFor(99), isNull);
      expect(await File(stored.imagePath!).exists(), isFalse);
    },
  );
}
