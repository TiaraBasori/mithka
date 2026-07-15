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

  bool get isBuiltIn => slug.startsWith('builtin:');

  bool get isDark =>
      baseTheme == 'builtInThemeNight' || baseTheme == 'builtInThemeTinted';

  Color get accentColor => _themeColor(
    accentColorValue,
    fallback: isDark ? const Color(0xFF5EA0FF) : const Color(0xFF4B8DEE),
  );

  /// Returns an official built-in theme with a user-selected Telegram tint.
  /// Imported `.attheme` palettes are intentionally immutable: changing a
  /// color there would no longer represent the installed theme document.
  TelegramCloudTheme withBuiltInAccent(Color color) {
    if (!isBuiltIn) return this;
    final rgb = color.toARGB32() & 0x00FFFFFF;
    final updatedPalette = Map<String, int>.of(palette);
    for (final key in const [
      'list.accent',
      'windowBackgroundWhiteBlueText',
      'windowActiveTextFg',
      'list_itemAccent',
      'chat_linkText',
    ]) {
      updatedPalette[key] = rgb;
    }
    final hsl = HSLColor.fromColor(color);
    final outgoing = isDark
        ? hsl
              .withSaturation((hsl.saturation * 0.72).clamp(0.18, 0.78))
              .withLightness((hsl.lightness * 0.58).clamp(0.20, 0.42))
              .toColor()
        : hsl
              .withSaturation((hsl.saturation * 0.34).clamp(0.10, 0.42))
              .withLightness((0.90 + hsl.lightness * 0.06).clamp(0.88, 0.96))
              .toColor();
    return TelegramCloudTheme(
      slug: slug,
      title: title,
      baseTheme: baseTheme,
      accentColorValue: rgb,
      outgoingColors: [outgoing.toARGB32() & 0x00FFFFFF],
      palette: Map.unmodifiable(updatedPalette),
      wallpaper: wallpaper,
    );
  }

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

  /// Semantic UI variables derived from Telegram's platform-specific keys.
  /// Consumers should use these tokens instead of reading raw palette keys.
  AppColors get uiColors {
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
    final accent = value(const [
      'list.accent',
      'windowBackgroundWhiteBlueText',
      'windowActiveTextFg',
      'list_itemAccent',
      'chat_linkText',
    ], accentColor);
    return base.copyWith(
      background: background,
      pinnedRow: value(const [
        'chatList.pinnedItemBackground',
        'chatList_pinnedItemBackground',
        'chatListPinnedItemBackground',
        'chats_pinnedOverlay',
        'list.itemHighlightedBg',
        'list.itemHighlightedBackground',
        'list_itemHighlightedBackground',
      ], background),
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
      linkBlue: accent,
      onAccent: readableForeground(accent),
    );
  }

  AppColors get appColors => uiColors;

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

/// Telegram iOS exposes these four built-in global themes alongside installed
/// cloud themes. Emoji-labelled chat themes are a separate carousel.
const builtInTelegramCloudThemes = <TelegramCloudTheme>[
  TelegramCloudTheme(
    slug: 'builtin:classic',
    title: 'Classic',
    baseTheme: 'builtInThemeClassic',
    accentColorValue: 0x168ACD,
    outgoingColors: [0xE1FFC7],
    palette: {
      'list.plainBg': 0xFFFFFF,
      'list.itemBlocksBg': 0xFFFFFF,
      'list.blocksBg': 0xF2F2F7,
      'list.primaryText': 0x000000,
      'list.secondaryText': 0x8E8E93,
      'list.accent': 0x168ACD,
      'root.navBar.opaqueBackground': 0xF7F7F7,
      'chat.message.incoming.bubble.withWp.bg': 0xFFFFFF,
      'chat.message.incoming.primaryText': 0x171717,
      'chat.message.outgoing.primaryText': 0x171717,
      'chats_pinnedOverlay': 0xFFFFFF,
    },
  ),
  TelegramCloudTheme(
    slug: 'builtin:day',
    title: 'Day',
    baseTheme: 'builtInThemeDay',
    accentColorValue: 0x2481CC,
    outgoingColors: [0xD8F3FF],
    palette: {
      'list.plainBg': 0xFFFFFF,
      'list.itemBlocksBg': 0xFFFFFF,
      'list.blocksBg': 0xF2F2F7,
      'list.primaryText': 0x000000,
      'list.secondaryText': 0x8E8E93,
      'list.accent': 0x2481CC,
      'root.navBar.opaqueBackground': 0xFFFFFF,
      'chat.message.incoming.bubble.withWp.bg': 0xFFFFFF,
      'chat.message.incoming.primaryText': 0x171717,
      'chat.message.outgoing.primaryText': 0x171717,
      'chats_pinnedOverlay': 0xFFFFFF,
    },
  ),
  TelegramCloudTheme(
    slug: 'builtin:dark',
    title: 'Dark',
    baseTheme: 'builtInThemeTinted',
    accentColorValue: 0x6AB3F3,
    outgoingColors: [0x2B5278],
    palette: {
      'list.plainBg': 0x17212B,
      'list.itemBlocksBg': 0x17212B,
      'list.blocksBg': 0x0E1621,
      'list.primaryText': 0xF5F5F5,
      'list.secondaryText': 0x708499,
      'list.accent': 0x6AB3F3,
      'root.navBar.opaqueBackground': 0x17212B,
      'chat.message.incoming.bubble.withWp.bg': 0x182533,
      'chat.message.incoming.primaryText': 0xF5F5F5,
      'chat.message.outgoing.primaryText': 0xFFFFFF,
      'chats_pinnedOverlay': 0x17212B,
    },
  ),
  TelegramCloudTheme(
    slug: 'builtin:night',
    title: 'Night',
    baseTheme: 'builtInThemeNight',
    accentColorValue: 0x6AB3F3,
    outgoingColors: [0x3D5A80],
    palette: {
      'list.plainBg': 0x0E1621,
      'list.itemBlocksBg': 0x0E1621,
      'list.blocksBg': 0x090F17,
      'list.primaryText': 0xF5F5F5,
      'list.secondaryText': 0x708499,
      'list.accent': 0x6AB3F3,
      'root.navBar.opaqueBackground': 0x0E1621,
      'chat.message.incoming.bubble.withWp.bg': 0x182533,
      'chat.message.incoming.primaryText': 0xF5F5F5,
      'chat.message.outgoing.primaryText': 0xFFFFFF,
      'chats_pinnedOverlay': 0x0E1621,
    },
  ),
];

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

  /// Loads every account-level cloud theme saved in Telegram, then appends
  /// locally imported themes that aren't present in Telegram's response.
  ///
  /// `getInstalledCloudThemes` is a small Mithka TDLib extension backed by
  /// `account.getThemes`. Released builds with an older stock TDLib don't know
  /// that request, so failure deliberately falls back to [fallback] instead of
  /// making the user's locally imported theme library disappear.
  Future<List<TelegramCloudTheme>> loadInstalled({
    Iterable<TelegramCloudTheme> fallback = const [],
  }) async {
    final localBySlug = <String, TelegramCloudTheme>{};
    for (final theme in fallback) {
      if (theme.slug.isNotEmpty && !theme.slug.startsWith('builtin:')) {
        localBySlug[theme.slug] = theme;
      }
    }

    late final Map<String, dynamic> response;
    try {
      response = await _query({
        '@type': 'getInstalledCloudThemes',
        // Telegram iOS requests this exact platform format. Theme documents
        // themselves still use the iOS -> Android -> Desktop fallback below.
        'theme_format': 'ios',
      });
    } catch (_) {
      return _rehydrateLocalThemes(localBySlug);
    }
    if (response.type != 'installedCloudThemes') {
      return _rehydrateLocalThemes(localBySlug);
    }

    final installed = <TelegramCloudTheme>[];
    final seen = <String>{};
    for (final Map<String, dynamic> metadata
        in response.objects('themes') ?? const <Map<String, dynamic>>[]) {
      final slug = metadata.str('slug')?.trim() ?? '';
      if (slug.isEmpty || !seen.add(slug)) continue;
      final local = localBySlug.remove(slug);
      try {
        final loaded = await load('https://t.me/addtheme/$slug');
        final title = metadata.str('title')?.trim();
        installed.add(
          title == null || title.isEmpty
              ? loaded
              : _cloudThemeWithTitle(loaded, title),
        );
      } catch (_) {
        // A deleted platform document or one temporarily unavailable theme
        // must not hide the rest. Retain the local copy when one exists.
        if (local != null) installed.add(local);
      }
    }
    installed.addAll(localBySlug.values);
    return List.unmodifiable(installed);
  }

  Future<List<TelegramCloudTheme>> _rehydrateLocalThemes(
    Map<String, TelegramCloudTheme> localBySlug,
  ) async {
    final refreshed = <TelegramCloudTheme>[];
    for (final entry in localBySlug.entries) {
      try {
        refreshed.add(await load('https://t.me/addtheme/${entry.key}'));
      } catch (_) {
        refreshed.add(entry.value);
      }
    }
    return List.unmodifiable(refreshed);
  }

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
        backgroundName: slug,
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
    final rawParts = descriptor
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList();
    if (rawParts.isEmpty || rawParts.first.toLowerCase() == 'builtin') {
      return null;
    }
    String? backgroundName;
    final colors = <int>[];
    int? intensity;
    var rotation = 0;
    var blur = false;
    var motion = false;
    final firstUri = Uri.tryParse(rawParts.first);
    if (firstUri != null &&
        (firstUri.host == 't.me' || firstUri.host == 'telegram.me') &&
        firstUri.pathSegments.length >= 2 &&
        firstUri.pathSegments.first.toLowerCase() == 'bg') {
      backgroundName = firstUri.pathSegments.last;
      final linkedColors = firstUri.queryParameters['bg_color'];
      if (linkedColors != null) {
        for (final value in linkedColors.split(RegExp(r'[~-]'))) {
          final color = _parseWallpaperColor(value);
          if (color != null) colors.add(color);
        }
      }
      intensity = int.tryParse(firstUri.queryParameters['intensity'] ?? '');
      rotation =
          int.tryParse(firstUri.queryParameters['rotation'] ?? '') ?? rotation;
      final modes = (firstUri.queryParameters['mode'] ?? '')
          .split(RegExp(r'[+\s]'))
          .map((value) => value.toLowerCase())
          .toSet();
      blur = modes.contains('blur');
      motion = modes.contains('motion');
      rawParts.removeAt(0);
    }
    final parts = rawParts;
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final color = _parseWallpaperColor(part);
      if (backgroundName == null && index == 0 && color == null) {
        backgroundName = part;
      } else if (color != null) {
        colors.add(color);
      } else if (part == 'blur') {
        blur = true;
      } else if (part == 'motion') {
        motion = true;
      } else {
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
        backgroundName: remote.backgroundName,
        mimeType: remote.mimeType,
        colors: remote.colors,
        rotationAngle: remote.rotationAngle,
        intensity: remote.intensity,
        isInverted: remote.isInverted,
        isBlurred: blur || remote.isBlurred,
        isMoving: motion || remote.isMoving,
        isTiled: remote.isTiled,
      );
    }
    return ChatWallpaper.telegram(
      backgroundId: remote.backgroundId,
      remoteType: 'pattern',
      fileId: remote.fileId,
      imagePath: remote.imagePath,
      backgroundName: remote.backgroundName,
      mimeType: remote.mimeType,
      colors: colors,
      rotationAngle: rotation,
      intensity: intensity?.abs() ?? remote.intensity,
      isInverted: (intensity ?? 0) < 0,
      isBlurred: blur,
      isMoving: motion || remote.isMoving,
      isTiled: remote.isTiled,
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
    backgroundName: background.str('name'),
    mimeType: document?.str('mime_type'),
    themeName: type?.str('theme_name'),
    colors: _fillColors(fill),
    rotationAngle: fill?.integer('rotation_angle') ?? 0,
    intensity: type?.integer('intensity') ?? 0,
    isInverted: type?.boolean('is_inverted') ?? false,
    isBlurred: type?.boolean('is_blurred') ?? false,
  );
}

TelegramCloudTheme _cloudThemeWithTitle(
  TelegramCloudTheme theme,
  String title,
) => TelegramCloudTheme(
  slug: theme.slug,
  title: title,
  baseTheme: theme.baseTheme,
  accentColorValue: theme.accentColorValue,
  outgoingColors: theme.outgoingColors,
  palette: theme.palette,
  wallpaper: theme.wallpaper,
);

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
