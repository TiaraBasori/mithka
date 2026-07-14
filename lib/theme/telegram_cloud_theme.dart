import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../chat/chat_wallpaper.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import 'app_theme.dart';
import 'telegram_theme_parsers.dart';

export 'telegram_theme_parsers.dart'
    show
        ParsedTelegramThemeFile,
        TelegramThemePlatform,
        parseTelegramAndroidTheme,
        parseTelegramDesktopTheme,
        parseTelegramIosTheme,
        parseTelegramThemeFile,
        telegramThemePlatformForDocument;

typedef TelegramThemeQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);
typedef TelegramThemeFilePath = Future<String?> Function(int fileId);
typedef TelegramThemeSupportDirectory = Future<Directory> Function();

@immutable
class TelegramCloudTheme {
  const TelegramCloudTheme({
    required this.slug,
    required this.title,
    required this.baseTheme,
    required this.accentColorValue,
    required this.outgoingColors,
    required this.palette,
    this.wallpaper,
  });

  final String slug;
  final String title;
  final String baseTheme;
  final int accentColorValue;
  final List<int> outgoingColors;
  final Map<String, int> palette;
  final ChatWallpaper? wallpaper;

  bool get isDark =>
      baseTheme == 'builtInThemeNight' || baseTheme == 'builtInThemeTinted';

  Color get accentColor => _themeColor(
    accentColorValue,
    fallback: isDark ? const Color(0xFF5EA0FF) : const Color(0xFF4B8DEE),
  );

  Color? get outgoingColor {
    if (outgoingColors.isEmpty) {
      return _paletteColor(const [
        'chat.message.outgoing.bubble.withWp.bg',
        'chat.message.outgoing.bubble.withoutWp.bg',
        'chat_outBubble',
        'msgOutBg',
      ]);
    }
    if (outgoingColors.length == 1) {
      return _themeColor(outgoingColors.first);
    }
    return Color.lerp(
      _themeColor(outgoingColors.first),
      _themeColor(outgoingColors.last),
      0.5,
    );
  }

  Color? get outgoingTextColor => _paletteColor(const [
    'chat.message.outgoing.primaryText',
    'chat_messageTextOut',
    'historyTextOutFg',
  ]);

  Color? get incomingColor => _paletteColor(const [
    'chat.message.incoming.bubble.withWp.bg',
    'chat.message.incoming.bubble.withoutWp.bg',
    'chat_inBubble',
    'msgInBg',
  ]);

  Color? get incomingTextColor => _paletteColor(const [
    'chat.message.incoming.primaryText',
    'chat_messageTextIn',
    'historyTextInFg',
  ]);

  AppColors get appColors {
    final base = isDark ? AppColors.dark : AppColors.light;
    Color value(List<String> keys, Color fallback) =>
        _paletteColor(keys) ?? fallback;
    final background = value(const [
      'list.plainBg',
      'windowBackgroundWhite',
      'windowBg',
      'chatList_background',
      'list_plainBackground',
      'root_background',
    ], base.background);
    final card = value(const [
      'list.itemBlocksBg',
      'list.blocksBg',
      'windowBackgroundWhite',
      'boxBg',
      'list_plainBackground',
      'list_blocksBackground',
    ], base.card);
    final primary = value(const [
      'list.primaryText',
      'windowBackgroundWhiteBlackText',
      'windowFg',
      'list_itemPrimaryText',
      'chatList_title',
    ], base.textPrimary);
    final secondary = value(const [
      'list.secondaryText',
      'windowBackgroundWhiteGrayText',
      'windowSubTextFg',
      'list_itemSecondaryText',
      'chatList_message',
    ], base.textSecondary);
    final chatBackground =
        _wallpaperColor() ??
        value(const ['chat_wallpaper', 'chat_background'], base.chatBackground);
    return base.copyWith(
      background: background,
      pinnedRow: value(const ['chatList_pinnedItemBackground'], base.pinnedRow),
      listHeaderTint: value(const [
        'chatList.sectionHeaderBg',
        'chats_menuTopBackground',
        'chatList_sectionHeaderBackground',
      ], background),
      card: card,
      navBar: value(const [
        'root.navBar.opaqueBackground',
        'root.navBar.background',
        'actionBarDefault',
        'titleBgActive',
        'root_navigationBar',
        'root_tabBar_background',
      ], card),
      groupedBackground: value(const [
        'list.blocksBg',
        'windowBackgroundGray',
        'windowBg',
        'list_blocksBackground',
        'root_background',
      ], base.groupedBackground),
      chatBackground: chatBackground,
      searchFill: value(const [
        'root.searchBar.inputFill',
        'chatListSearch',
        'filterInputInactiveBg',
        'chatList_searchBarBackground',
        'list_itemBlocksBackground',
      ], base.searchFill),
      inputBarBackground: value(const [
        'chat.inputPanel.panelBg',
        'chat_messagePanelBackground',
        'historyComposeAreaBg',
        'chat_inputPanel',
        'chat_inputPanelBackground',
      ], base.inputBarBackground),
      panelBackground: value(const [
        'chat.inputMediaPanel.panelContentVibrantOverlay',
        'windowBackgroundGray',
        'emojiPanBg',
        'chat_inputPanel',
        'list_blocksBackground',
      ], base.panelBackground),
      bubbleIncoming: incomingColor ?? base.bubbleIncoming,
      bubbleIncomingText: value(const [
        'chat.message.incoming.primaryText',
        'chat_messageTextIn',
        'historyTextInFg',
        'chat_inPrimaryText',
      ], base.bubbleIncomingText),
      textPrimary: primary,
      textSecondary: secondary,
      textTertiary: value(const [
        'list_itemSecondaryText',
        'chatList_dateText',
      ], base.textTertiary),
      divider: value(const [
        'list.plainSeparator',
        'divider',
        'menuSeparatorFg',
        'list_itemSeparator',
        'chatList_itemSeparator',
      ], base.divider),
      linkBlue: value(const [
        'list.accent',
        'windowBackgroundWhiteBlueText',
        'windowActiveTextFg',
        'list_itemAccent',
        'chat_linkText',
      ], accentColor),
    );
  }

  Color? _paletteColor(List<String> keys) {
    for (final key in keys) {
      final value = palette[key];
      if (value != null) return _themeColor(value);
    }
    return null;
  }

  Color? _wallpaperColor() {
    final colors = wallpaper?.colors ?? const [];
    if (colors.isEmpty) return null;
    return _themeColor(colors.first);
  }

  Map<String, Object?> toJson() => {
    'slug': slug,
    'title': title,
    'base_theme': baseTheme,
    'accent_color': accentColorValue,
    'outgoing_colors': outgoingColors,
    'palette': palette,
    if (wallpaper != null) 'wallpaper': wallpaper?.toJson(),
  };

  static TelegramCloudTheme? fromJson(Object? value) {
    if (value is! Map) return null;
    final slug = value['slug'];
    final title = value['title'];
    final paletteValue = value['palette'];
    if (slug is! String || slug.isEmpty || title is! String) return null;
    final palette = <String, int>{};
    if (paletteValue is Map) {
      for (final entry in paletteValue.entries) {
        if (entry.key is String) {
          palette[entry.key as String] = _jsonThemeInt(entry.value);
        }
      }
    }
    final outgoing = value['outgoing_colors'];
    return TelegramCloudTheme(
      slug: slug,
      title: title,
      baseTheme: value['base_theme'] as String? ?? 'builtInThemeDay',
      accentColorValue: _jsonThemeInt(value['accent_color']),
      outgoingColors: outgoing is List
          ? outgoing.map(_jsonThemeInt).toList(growable: false)
          : const [],
      palette: palette,
      wallpaper: ChatWallpaper.fromJson(value['wallpaper']),
    );
  }
}

class TelegramCloudThemeService {
  TelegramCloudThemeService({
    TelegramThemeQuery? query,
    TelegramThemeFilePath? filePath,
    TelegramThemeSupportDirectory? supportDirectory,
  }) : _query = query ?? TdClient.shared.query,
       _filePath = filePath ?? TdFileCenter.shared.path,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final TelegramThemeQuery _query;
  final TelegramThemeFilePath _filePath;
  final TelegramThemeSupportDirectory _supportDirectory;

  Future<TelegramCloudTheme> load(String link) async {
    final normalized = _normalizedThemeLink(link);
    final preview = await _query({
      '@type': 'getLinkPreview',
      'text': {
        '@type': 'formattedText',
        'text': normalized,
        'entities': <Object>[],
      },
      'link_preview_options': null,
    });
    final type = preview.obj('type');
    if (type?.type != 'linkPreviewTypeTheme') {
      throw const FormatException('The link is not a Telegram cloud theme');
    }

    final slug = Uri.tryParse(normalized)?.pathSegments.lastOrNull ?? 'theme';
    final platformTheme = await _loadPlatformTheme(
      type?.objects('documents') ?? const [],
      slug: slug,
    );
    final palette = platformTheme?.palette ?? const <String, int>{};
    final settings = type?.obj('settings');
    final baseTheme =
        _baseThemeFromPalette(palette) ??
        settings?.obj('base_theme')?.type ??
        'builtInThemeDay';
    final accent =
        _accentFromPalette(palette) ?? settings?.integer('accent_color') ?? 0;
    var wallpaper =
        platformTheme?.wallpaper ??
        _parseBackground(settings?.obj('background'));
    wallpaper = await _resolveWallpaper(wallpaper);
    final paletteOutgoing = _outgoingFromPalette(palette);
    final outgoing = paletteOutgoing.isEmpty
        ? _fillColors(settings?.obj('outgoing_message_fill'))
        : paletteOutgoing;
    final title = preview.str('title')?.trim();
    return TelegramCloudTheme(
      slug: slug,
      title: title == null || title.isEmpty ? slug : title,
      baseTheme: baseTheme,
      accentColorValue: accent,
      outgoingColors: outgoing,
      palette: palette,
      wallpaper: wallpaper,
    );
  }

  Future<_LoadedPlatformTheme?> _loadPlatformTheme(
    List<Map<String, dynamic>> documents, {
    required String slug,
  }) async {
    // Deliberate fidelity order: iOS first, then Android, then Desktop.
    for (final platform in TelegramThemePlatform.values) {
      for (final document in documents) {
        final fileName = _documentName(document);
        final mimeType = document.str('mime_type') ?? '';
        if (telegramThemePlatformForDocument(
              fileName: fileName,
              mimeType: mimeType,
            ) !=
            platform) {
          continue;
        }
        final fileId = document.obj('document')?.integer('id') ?? 0;
        if (fileId == 0) continue;
        try {
          final path = await _filePath(fileId);
          if (path == null || path.isEmpty) continue;
          final parsed = parseTelegramThemeFile(
            platform,
            await File(path).readAsBytes(),
          );
          if (parsed == null || !parsed.isUseful) continue;
          return _LoadedPlatformTheme(
            palette: parsed.palette,
            wallpaper: await _wallpaperFromThemeFile(parsed, slug: slug),
          );
        } catch (_) {
          // Older cloud themes often omit one or more platform documents.
          // Continue to the next matching file instead of failing the link.
        }
      }
    }
    return null;
  }

  Future<ChatWallpaper?> _wallpaperFromThemeFile(
    ParsedTelegramThemeFile parsed, {
    required String slug,
  }) async {
    final bytes = parsed.wallpaperBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final folder = Directory(
        '${(await _supportDirectory()).path}/telegram_themes',
      );
      await folder.create(recursive: true);
      final safeSlug = slug.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final extension = parsed.wallpaperExtension ?? '.jpg';
      final output = File(
        '${folder.path}/${safeSlug}_${parsed.platform.name}$extension',
      );
      if (!await output.exists() || await output.length() != bytes.length) {
        await output.writeAsBytes(bytes, flush: true);
      }
      return ChatWallpaper.telegram(
        backgroundId: 0,
        remoteType: 'wallpaper',
        imagePath: output.path,
        mimeType: extension == '.png' ? 'image/png' : 'image/jpeg',
        isTiled: parsed.wallpaperIsTiled,
      );
    }
    final descriptor = parsed.wallpaperDescriptor;
    return descriptor == null || descriptor.isEmpty
        ? null
        : _resolveIosWallpaperDescriptor(descriptor);
  }

  Future<ChatWallpaper?> _resolveIosWallpaperDescriptor(
    String descriptor,
  ) async {
    final parts = descriptor
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty || parts.first.toLowerCase() == 'builtin') return null;
    String? backgroundName;
    final colors = <int>[];
    int? intensity;
    var rotation = 0;
    var blur = false;
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final color = _parseWallpaperColor(part);
      if (index == 0 && color == null && part.length > 8) {
        backgroundName = part;
      } else if (color != null) {
        colors.add(color);
      } else if (part == 'blur') {
        blur = true;
      } else if (part != 'motion') {
        final number = int.tryParse(part);
        if (number != null && intensity == null && number.abs() <= 100) {
          intensity = number;
        } else if (number != null && number >= 0 && number < 360) {
          rotation = number;
        }
      }
    }

    if (backgroundName == null) {
      if (colors.isEmpty) return null;
      return ChatWallpaper.telegram(
        backgroundId: 0,
        remoteType: 'fill',
        colors: colors,
        rotationAngle: rotation,
      );
    }

    ChatWallpaper? remote;
    try {
      remote = _parseBackground(
        await _query({'@type': 'searchBackground', 'name': backgroundName}),
      );
    } catch (_) {}
    if (remote == null) return null;
    if (colors.isEmpty) {
      return ChatWallpaper.telegram(
        backgroundId: remote.backgroundId,
        remoteType: remote.remoteType ?? 'wallpaper',
        fileId: remote.fileId,
        imagePath: remote.imagePath,
        mimeType: remote.mimeType,
        colors: remote.colors,
        rotationAngle: remote.rotationAngle,
        intensity: remote.intensity,
        isInverted: remote.isInverted,
        isBlurred: blur || remote.isBlurred,
      );
    }
    return ChatWallpaper.telegram(
      backgroundId: remote.backgroundId,
      remoteType: 'pattern',
      fileId: remote.fileId,
      imagePath: remote.imagePath,
      mimeType: remote.mimeType,
      colors: colors,
      rotationAngle: rotation,
      intensity: intensity?.abs() ?? remote.intensity,
      isInverted: (intensity ?? 0) < 0,
      isBlurred: blur,
    );
  }

  Future<ChatWallpaper?> _resolveWallpaper(ChatWallpaper? wallpaper) async {
    if (wallpaper == null || wallpaper.fileId == 0) return wallpaper;
    final path = await _filePath(wallpaper.fileId);
    return path == null || path.isEmpty
        ? wallpaper
        : wallpaper.withImagePath(path);
  }
}

ChatWallpaper? _parseBackground(Map<String, dynamic>? background) {
  if (background == null) return null;
  final type = background.obj('type');
  final remoteType = switch (type?.type) {
    'backgroundTypeWallpaper' => 'wallpaper',
    'backgroundTypePattern' => 'pattern',
    'backgroundTypeFill' => 'fill',
    'backgroundTypeChatTheme' => 'chatTheme',
    _ => null,
  };
  if (remoteType == null) return null;
  final document = background.obj('document');
  final file = document?.obj('document');
  final fill = type?.obj('fill');
  return ChatWallpaper.telegram(
    backgroundId: background.int64('id') ?? 0,
    remoteType: remoteType,
    fileId: file?.integer('id') ?? 0,
    imagePath: file?.obj('local')?.str('path'),
    mimeType: document?.str('mime_type'),
    themeName: type?.str('theme_name'),
    colors: _fillColors(fill),
    rotationAngle: fill?.integer('rotation_angle') ?? 0,
    intensity: type?.integer('intensity') ?? 0,
    isInverted: type?.boolean('is_inverted') ?? false,
    isBlurred: type?.boolean('is_blurred') ?? false,
  );
}

List<int> _fillColors(Map<String, dynamic>? fill) => switch (fill?.type) {
  'backgroundFillSolid' => [fill?.integer('color') ?? 0],
  'backgroundFillGradient' => [
    fill?.integer('top_color') ?? 0,
    fill?.integer('bottom_color') ?? 0,
  ],
  'backgroundFillFreeformGradient' => fill?.int64Array('colors') ?? const [],
  _ => const [],
};

String _documentName(Map<String, dynamic> document) {
  final direct = document.str('file_name');
  if (direct != null && direct.isNotEmpty) return direct;
  for (final attribute in document.objects('attributes') ?? const []) {
    if (attribute['@type'] == 'documentAttributeFilename') {
      return attribute['file_name'] as String? ?? '';
    }
  }
  return '';
}

String _normalizedThemeLink(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri?.scheme.toLowerCase() == 'tg' && uri?.host == 'addtheme') {
    final slug = uri?.queryParameters['slug'] ?? '';
    if (slug.isEmpty) throw const FormatException('Theme slug is missing');
    return 'https://t.me/addtheme/$slug';
  }
  if (uri == null || uri.pathSegments.length < 2) {
    throw const FormatException('Theme link is invalid');
  }
  return uri.replace(scheme: 'https', host: 't.me').toString();
}

String? _baseThemeFromPalette(Map<String, int> palette) {
  final dark = palette['dark'];
  if (dark == 1) return 'builtInThemeNight';
  if (dark == 0) return 'builtInThemeDay';
  final background = _firstPaletteValue(palette, const [
    'list.plainBg',
    'windowBackgroundWhite',
    'windowBg',
    'list_plainBackground',
  ]);
  if (background == null) return null;
  if (_themeColor(background).computeLuminance() < 0.3) {
    return 'builtInThemeNight';
  }
  return 'builtInThemeDay';
}

int? _accentFromPalette(Map<String, int> palette) =>
    _firstPaletteValue(palette, const [
      'list.accent',
      'windowBackgroundWhiteBlueText',
      'windowActiveTextFg',
      'list_itemAccent',
      'chat_linkText',
    ]);

List<int> _outgoingFromPalette(Map<String, int> palette) {
  final first = _firstPaletteValue(palette, const [
    'chat.message.outgoing.bubble.withWp.bg',
    'chat.message.outgoing.bubble.withoutWp.bg',
    'chat_outBubble',
    'msgOutBg',
  ]);
  if (first == null) return const [];
  final second = _firstPaletteValue(palette, const [
    'chat.message.outgoing.bubble.withWp.gradientBg',
    'chat.message.outgoing.bubble.withoutWp.gradientBg',
    'chat_outBubbleGradient1',
  ]);
  return second == null || second == first ? [first] : [first, second];
}

int? _firstPaletteValue(Map<String, int> palette, List<String> keys) {
  for (final key in keys) {
    final value = palette[key];
    if (value != null) return value;
  }
  return null;
}

int? _parseWallpaperColor(String raw) {
  final value = raw.startsWith('#') ? raw.substring(1) : raw;
  if (value.length != 6 && value.length != 8) return null;
  return int.tryParse(value, radix: 16);
}

int _jsonThemeInt(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text) ?? 0,
  _ => 0,
};

Color _themeColor(int value, {Color fallback = const Color(0xFF000000)}) {
  if (value == 0) return fallback;
  final unsigned = value & 0xFFFFFFFF;
  return Color(unsigned <= 0xFFFFFF ? 0xFF000000 | unsigned : unsigned);
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

class _LoadedPlatformTheme {
  const _LoadedPlatformTheme({required this.palette, this.wallpaper});

  final Map<String, int> palette;
  final ChatWallpaper? wallpaper;
}
