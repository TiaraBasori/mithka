import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses official nested iOS theme colors and wallpaper', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''
name: Mountain Solitude
dark: true
list:
  plainBg: 101820
  primaryText: f2f5f7
  accent: 5f9ea0
chat:
  defaultWallpaper: mountain_solitude 18263b 65
  message:
    incoming:
      bubble:
        withWp:
          bg: 22313b
      primaryText: f2f5f7
    outgoing:
      bubble:
        withWp:
          bg: f3b4bd
      primaryText: 101820
'''),
    );

    final parsed = parseTelegramThemeFile(TelegramThemePlatform.ios, bytes)!;

    expect(parsed.palette['dark'], 1);
    expect(parsed.palette['list.plainBg'], 0x101820);
    expect(parsed.palette['chat.message.incoming.bubble.withWp.bg'], 0x22313B);
    expect(parsed.palette['chat.message.outgoing.bubble.withWp.bg'], 0xF3B4BD);
    expect(parsed.wallpaperDescriptor, 'mountain_solitude 18263b 65');
  });

  test('parses Android ARGB values and embedded wallpaper', () {
    final bytes = Uint8List.fromList([
      ...utf8.encode('''
windowBackgroundWhite=#ff101820
chat_inBubble=-14536389
chat_outBubble=#fff3b4bd
'''),
      ...ascii.encode('\nWPS\n'),
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      1,
      2,
      3,
      0xFF,
      0xD9,
    ]);

    final parsed = parseTelegramThemeFile(
      TelegramThemePlatform.android,
      bytes,
    )!;

    expect(parsed.palette['windowBackgroundWhite'], 0xFF101820);
    expect(parsed.palette['chat_inBubble'], (-14536389) & 0xFFFFFFFF);
    expect(parsed.palette['chat_outBubble'], 0xFFF3B4BD);
    expect(parsed.wallpaperExtension, '.jpg');
    expect(parsed.wallpaperBytes, [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      1,
      2,
      3,
      0xFF,
      0xD9,
    ]);
  });

  test('parses Desktop archive colors, aliases, alpha, and tiled image', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('colors.tdesktop-theme', '''
windowBg: #101820;
windowFg: #f2f5f7;
msgInBg: #22313b;
msgOutBg: #f3b4bd;
historyTextInFg: windowFg;
historyTextOutFg: windowBg;
windowShadowFg: #01020380;
'''),
      )
      ..addFile(ArchiveFile('tiled.jpg', 7, [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

    final parsed = parseTelegramThemeFile(
      TelegramThemePlatform.desktop,
      bytes,
    )!;

    expect(parsed.palette['msgInBg'], 0x22313B);
    expect(parsed.palette['historyTextInFg'], 0xF2F5F7);
    expect(parsed.palette['windowShadowFg'], 0x80010203);
    expect(parsed.wallpaperIsTiled, isTrue);
    expect(parsed.wallpaperExtension, '.jpg');
  });

  test('cloud theme loader prefers iOS then Android then Desktop', () async {
    final root = await Directory.systemTemp.createTemp('mithka_theme_order');
    addTearDown(() => root.delete(recursive: true));
    final ios = File('${root.path}/theme.tgios-theme');
    final android = File('${root.path}/theme.attheme');
    final desktop = File('${root.path}/theme.tdesktop-theme');
    await ios.writeAsString(_iosTheme);
    await android.writeAsString('''
windowBackgroundWhite=#ff334455
chat_inBubble=#ff445566
chat_outBubble=#ff556677
''');
    final desktopArchive = Archive()
      ..addFile(
        ArchiveFile.string(
          'colors.tdesktop-theme',
          'windowBg: #667788; msgInBg: #778899; msgOutBg: #8899aa;',
        ),
      );
    await desktop.writeAsBytes(ZipEncoder().encode(desktopArchive)!);

    final service = TelegramCloudThemeService(
      query: (_) async => _themePreview([
        _themeDocument(3, 'theme.tdesktop-theme', 'tgtheme-tdesktop'),
        _themeDocument(2, 'theme.attheme', 'tgtheme-android'),
        _themeDocument(1, 'theme.tgios-theme', 'tgtheme-ios'),
      ]),
      filePath: (id) async =>
          {1: ios.path, 2: android.path, 3: desktop.path}[id],
      supportDirectory: () async => root,
    );

    final theme = await service.load('https://t.me/addtheme/MountainSolitude');

    expect(theme.palette['list.plainBg'], 0x101820);
    expect(theme.incomingColor?.toARGB32(), 0xFF22313B);
    expect(theme.outgoingColor?.toARGB32(), 0xFFF3B4BD);
    expect(theme.incomingTextColor?.toARGB32(), 0xFFF2F5F7);
    expect(theme.outgoingTextColor?.toARGB32(), 0xFF101820);
  });

  test(
    'falls back from unusable iOS to Android and persists its image',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mithka_theme_fallback',
      );
      addTearDown(() => root.delete(recursive: true));
      final ios = File('${root.path}/empty.tgios-theme')
        ..writeAsStringSync('name: empty');
      final android = File('${root.path}/theme.attheme');
      await android.writeAsBytes([
        ...utf8.encode('''
windowBackgroundWhite=#ff334455
chat_inBubble=#ff445566
chat_outBubble=#ff556677
'''),
        ...ascii.encode('\nWPS\n'),
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        9,
        0xFF,
        0xD9,
      ]);
      final service = TelegramCloudThemeService(
        query: (_) async => _themePreview([
          _themeDocument(1, 'empty.tgios-theme', 'tgtheme-ios'),
          _themeDocument(2, 'theme.attheme', 'tgtheme-android'),
        ]),
        filePath: (id) async => id == 1 ? ios.path : android.path,
        supportDirectory: () async => root,
      );

      final theme = await service.load('https://t.me/addtheme/Fallback');

      expect(theme.palette['windowBackgroundWhite'], 0xFF334455);
      expect(theme.incomingColor?.toARGB32(), 0xFF445566);
      expect(theme.outgoingColor?.toARGB32(), 0xFF556677);
      expect(theme.wallpaper?.mimeType, 'image/jpeg');
      expect(await File(theme.wallpaper!.imagePath!).exists(), isTrue);
    },
  );

  test('falls back through Android to a Desktop archive', () async {
    final root = await Directory.systemTemp.createTemp(
      'mithka_theme_desktop_fallback',
    );
    addTearDown(() => root.delete(recursive: true));
    final ios = File('${root.path}/empty.tgios-theme')
      ..writeAsStringSync('name: empty');
    final android = File('${root.path}/empty.attheme')
      ..writeAsStringSync('name=empty');
    final desktop = File('${root.path}/theme.tdesktop-theme');
    final desktopArchive = Archive()
      ..addFile(
        ArchiveFile.string('colors.tdesktop-theme', '''
windowBg: #101820;
windowFg: #f2f5f7;
msgInBg: #22313b;
msgOutBg: #f3b4bd;
'''),
      )
      ..addFile(ArchiveFile('background.jpg', 5, [0xFF, 0xD8, 1, 0xFF, 0xD9]));
    await desktop.writeAsBytes(ZipEncoder().encode(desktopArchive)!);
    final service = TelegramCloudThemeService(
      query: (_) async => _themePreview([
        _themeDocument(1, 'empty.tgios-theme', 'tgtheme-ios'),
        _themeDocument(2, 'empty.attheme', 'tgtheme-android'),
        _themeDocument(3, 'theme.tdesktop-theme', 'tgtheme-tdesktop'),
      ]),
      filePath: (id) async =>
          {1: ios.path, 2: android.path, 3: desktop.path}[id],
      supportDirectory: () async => root,
    );

    final theme = await service.load('https://t.me/addtheme/DesktopFallback');

    expect(theme.palette['windowBg'], 0x101820);
    expect(theme.incomingColor?.toARGB32(), 0xFF22313B);
    expect(theme.outgoingColor?.toARGB32(), 0xFFF3B4BD);
    expect(theme.wallpaper?.isTiled, isFalse);
    expect(await File(theme.wallpaper!.imagePath!).exists(), isTrue);
  });

  test('resolves an iOS wallpaper slug using Telegram backgrounds', () async {
    final root = await Directory.systemTemp.createTemp(
      'mithka_theme_wallpaper',
    );
    addTearDown(() => root.delete(recursive: true));
    final ios = File('${root.path}/theme.tgios-theme');
    await ios.writeAsString(
      _iosTheme.replaceFirst(
        'defaultWallpaper: builtin',
        'defaultWallpaper: mountain_pattern 18263b 65 37526f 45',
      ),
    );
    final pattern = File('${root.path}/pattern.svg')
      ..writeAsStringSync('<svg/>');
    final requests = <String>[];
    final service = TelegramCloudThemeService(
      query: (request) async {
        requests.add(request['@type'] as String);
        if (request['@type'] == 'searchBackground') {
          expect(request['name'], 'mountain_pattern');
          return {
            '@type': 'background',
            'id': '91',
            'document': {
              '@type': 'document',
              'mime_type': 'image/svg+xml',
              'document': {'@type': 'file', 'id': 44},
            },
            'type': {
              '@type': 'backgroundTypePattern',
              'fill': {'@type': 'backgroundFillSolid', 'color': 0x18263B},
              'intensity': 50,
              'is_inverted': false,
              'is_moving': false,
            },
          };
        }
        return _themePreview([
          _themeDocument(1, 'theme.tgios-theme', 'tgtheme-ios'),
        ]);
      },
      filePath: (id) async => id == 1 ? ios.path : pattern.path,
      supportDirectory: () async => root,
    );

    final theme = await service.load('https://t.me/addtheme/Mountains');

    expect(requests, ['getLinkPreview', 'searchBackground']);
    expect(theme.wallpaper?.remoteType, 'pattern');
    expect(theme.wallpaper?.colors, [0x18263B, 0x37526F]);
    expect(theme.wallpaper?.intensity, 65);
    expect(theme.wallpaper?.rotationAngle, 45);
    expect(theme.wallpaper?.imagePath, pattern.path);
  });

  test('installed cloud themes persist and drive both bubble colors', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const theme = TelegramCloudTheme(
      slug: 'MountainSolitude',
      title: 'Mountain Solitude',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0xFF5F9EA0,
      outgoingColors: [0xFFF3B4BD],
      palette: {
        'list.plainBg': 0x101820,
        'list.primaryText': 0xF2F5F7,
        'chat.message.incoming.bubble.withWp.bg': 0x22313B,
        'chat.message.incoming.primaryText': 0xF2F5F7,
        'chat.message.outgoing.primaryText': 0x101820,
      },
      wallpaper: ChatWallpaper.telegram(
        backgroundId: 81,
        remoteType: 'fill',
        colors: [0x101820],
      ),
    );

    final controller = ThemeController(prefs)..installCloudTheme(theme);
    expect(controller.mode, AppearanceMode.dark);
    expect(controller.cloudTheme?.slug, 'MountainSolitude');
    expect(
      controller.appColorsFor(Brightness.dark).bubbleIncoming.toARGB32(),
      0xFF22313B,
    );

    final restored = ThemeController(prefs);
    expect(restored.cloudTheme?.slug, 'MountainSolitude');
    expect(restored.cloudTheme?.outgoingColor?.toARGB32(), 0xFFF3B4BD);
    expect(restored.cloudTheme?.incomingColor?.toARGB32(), 0xFF22313B);
    expect(restored.cloudTheme?.wallpaper?.colors, [0x101820]);
  });
}

const _iosTheme = '''
name: Mountain Solitude
dark: true
list:
  plainBg: 101820
  primaryText: f2f5f7
  accent: 5f9ea0
chat:
  defaultWallpaper: builtin
  message:
    incoming:
      bubble:
        withWp:
          bg: 22313b
      primaryText: f2f5f7
    outgoing:
      bubble:
        withWp:
          bg: f3b4bd
      primaryText: 101820
''';

Map<String, dynamic> _themeDocument(int id, String name, String mime) => {
  '@type': 'document',
  'file_name': name,
  'mime_type': 'application/x-$mime',
  'document': {'@type': 'file', 'id': id},
};

Map<String, dynamic> _themePreview(List<Map<String, dynamic>> documents) => {
  '@type': 'linkPreview',
  'title': 'Mountain Solitude',
  'type': {
    '@type': 'linkPreviewTypeTheme',
    'documents': documents,
    'settings': {
      '@type': 'themeSettings',
      'base_theme': {'@type': 'builtInThemeNight'},
      'accent_color': 0xFF5F9EA0,
      'background': {
        '@type': 'background',
        'id': '81',
        'type': {
          '@type': 'backgroundTypeFill',
          'fill': {'@type': 'backgroundFillSolid', 'color': 0x101820},
        },
      },
      'outgoing_message_fill': {
        '@type': 'backgroundFillSolid',
        'color': 0x477A7B,
      },
    },
  },
};
