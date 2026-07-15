import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../chat/chat_wallpaper.dart';
import '../chat/chat_wallpaper_color_view.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import 'app_theme.dart';
import 'telegram_cloud_theme.dart';
import 'telegram_cloud_theme_view.dart';
import 'theme_controller.dart';

/// Global Telegram .attheme management. This intentionally contains no chat
/// emoji themes. Applying its palette to the rest of the app is opt-in.
class GlobalThemeView extends StatefulWidget {
  const GlobalThemeView({super.key, this.themeService});

  final TelegramCloudThemeService? themeService;

  @override
  State<GlobalThemeView> createState() => _GlobalThemeViewState();
}

class _GlobalThemeViewState extends State<GlobalThemeView> {
  static const _officialAccentPresets = <Color>[
    Color(0xFF168ACD),
    Color(0xFF30A3E6),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFFF3B30),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
    Color(0xFF8E8E93),
  ];
  final _linkController = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _requestedCommunityThemes = false;
  bool _initializedTargetBrightness = false;
  List<TelegramCloudTheme>? _communityThemes;
  Brightness _targetBrightness = Brightness.light;

  TelegramCloudThemeService get _themeService =>
      widget.themeService ?? TelegramCloudThemeService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedTargetBrightness) {
      _initializedTargetBrightness = true;
      _targetBrightness = Theme.of(context).brightness;
    }
    if (_requestedCommunityThemes) return;
    _requestedCommunityThemes = true;
    _synchronizeCommunityThemes(context.read<ThemeController>());
  }

  @override
  void dispose() {
    _linkController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final link = _linkController.text.trim();
    if (_loading || link.isEmpty) return;
    setState(() => _loading = true);
    try {
      final theme = await _themeService.load(link);
      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => TelegramCloudThemePreviewView(
            theme: theme,
            targetBrightness: _targetBrightness,
          ),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      if (!mounted) return;
      final local = context.read<ThemeController>().installedCloudThemes;
      setState(() {
        _loading = false;
        _communityThemes = _mergeCommunityThemes(
          _communityThemes ?? const [],
          local,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, AppStringKeys.cloudThemeLoadFailed);
    }
  }

  Future<void> _synchronizeCommunityThemes(ThemeController controller) async {
    final themes = await _themeService.loadInstalled(
      fallback: controller.installedCloudThemes,
    );
    if (!mounted) return;
    controller.synchronizeInstalledCloudThemes(themes);
    setState(() => _communityThemes = themes);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<ThemeController>();
    final theme = controller.cloudThemeFor(_targetBrightness);
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.globalThemeTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                _brightnessPicker(),
                const SizedBox(height: 14),
                _activeThemeCard(controller, theme),
                const SizedBox(height: 22),
                _sectionTitle(AppStringKeys.globalThemeOfficial),
                const SizedBox(height: 9),
                _themeStrip(controller, theme, builtInTelegramCloudThemes),
                const SizedBox(height: 22),
                _sectionTitle(AppStringKeys.globalThemeCommunity),
                const SizedBox(height: 9),
                _communityThemeStrip(controller, theme),
                const SizedBox(height: 22),
                _sectionTitle(AppStringKeys.globalThemeCustomize),
                const SizedBox(height: 8),
                _themeLinkControl(),
                const SizedBox(height: 8),
                Text(
                  AppStringKeys.globalThemeDescription.l10n(context),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _brightnessPicker() {
    final c = context.colors;
    return Container(
      key: const ValueKey('global-theme-brightness-picker'),
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _brightnessButton(
              brightness: Brightness.light,
              icon: HeroAppIcons.sun,
              label: AppStringKeys.globalThemeDay,
            ),
          ),
          Expanded(
            child: _brightnessButton(
              brightness: Brightness.dark,
              icon: HeroAppIcons.moon,
              label: AppStringKeys.globalThemeNight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _brightnessButton({
    required Brightness brightness,
    required AppIconData icon,
    required String label,
  }) {
    final c = context.colors;
    final selected = _targetBrightness == brightness;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _targetBrightness = brightness),
      child: AnimatedContainer(
        key: ValueKey('global-theme-brightness-${brightness.name}'),
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? c.linkBlue.withValues(alpha: 0.15)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                icon,
                size: 17,
                color: selected ? c.linkBlue : c.textTertiary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label.l10n(context),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? c.linkBlue : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String key) {
    final c = context.colors;
    return Text(
      key.l10n(context),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textSecondary,
      ),
    );
  }

  Widget _communityThemeStrip(
    ThemeController controller,
    TelegramCloudTheme? selectedTheme,
  ) {
    final themes = _communityThemes;
    if (themes == null) {
      return SizedBox(
        height: 126,
        child: Center(
          child: Text(
            AppStringKeys.globalThemeLoading.l10n(context),
            style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
          ),
        ),
      );
    }
    if (themes.isEmpty) {
      return SizedBox(
        height: 54,
        child: Center(
          child: Text(
            AppStringKeys.globalThemeCommunityEmpty.l10n(context),
            style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
          ),
        ),
      );
    }
    return _themeStrip(controller, selectedTheme, themes);
  }

  Widget _themeStrip(
    ThemeController controller,
    TelegramCloudTheme? selectedTheme,
    Iterable<TelegramCloudTheme> source,
  ) {
    final themes = source.toList(growable: false);
    return SizedBox(
      height: 126,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: themes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final sourceTheme = themes[index];
          // A customized built-in keeps the same official identity/slug. Show
          // the persisted tint in the strip rather than the stock constant.
          final theme = selectedTheme?.slug == sourceTheme.slug
              ? selectedTheme!
              : sourceTheme;
          return _installedThemeCard(
            theme,
            selected: selectedTheme?.slug == theme.slug,
            onTap: () => controller.installCloudTheme(
              theme,
              brightness: _targetBrightness,
            ),
          );
        },
      ),
    );
  }

  Widget _installedThemeCard(
    TelegramCloudTheme theme, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    final themeColors = theme.uiColors;
    final outgoing = theme.outgoingColor ?? themeColors.linkBlue;
    final wallpaperController = ChatWallpaperController.shared;
    final wallpaper = theme.wallpaper;
    Widget preview(Widget child) {
      if (wallpaper == null) {
        return ColoredBox(color: themeColors.background, child: child);
      }
      return AnimatedBuilder(
        animation: wallpaperController,
        builder: (context, _) {
          final resolved = wallpaperController.resolvedWallpaper(wallpaper);
          return RepaintBoundary(
            key: ValueKey('global-theme-wallpaper-${theme.slug}'),
            child: ChatWallpaperBackground(
              wallpaper: resolved,
              fallbackColor: themeColors.chatBackground,
              brightness: theme.isDark ? Brightness.dark : Brightness.light,
              imageScrim: const Color(0x16000000),
              child: child,
            ),
          );
        },
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 142,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 92,
              padding: EdgeInsets.all(selected ? 2.5 : 1),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: selected ? c.linkBlue : c.divider,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 11.5 : 13),
                child: preview(
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 72,
                            height: 20,
                            decoration: BoxDecoration(
                              color: themeColors.bubbleIncoming,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 78,
                            height: 20,
                            decoration: BoxDecoration(
                              color: outgoing,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              theme.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? c.linkBlue : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeThemeCard(
    ThemeController controller,
    TelegramCloudTheme? theme,
  ) {
    final c = context.colors;
    final colors = theme?.uiColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (theme?.accentColor ?? c.linkBlue).withValues(
                    alpha: 0.16,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: AppIcon(
                  HeroAppIcons.palette,
                  size: 23,
                  color: theme?.accentColor ?? c.linkBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme?.title ??
                          AppStringKeys.globalThemeDefault.l10n(context),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    if (theme != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '@${theme.slug}',
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (theme != null) ...[
                const SizedBox(width: 12),
                _themeColorGrid(theme, colors!),
              ],
            ],
          ),
          if (colors != null) ...[
            if (theme?.isBuiltIn == true) ...[
              const SizedBox(height: 16),
              _builtInAccentPicker(controller, theme!),
            ],
          ],
        ],
      ),
    );
  }

  Widget _swatch(Color color) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x22000000)),
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 4),
      ],
    ),
  );

  Widget _themeColorGrid(TelegramCloudTheme theme, AppColors colors) {
    final swatches = <Color>[
      colors.background,
      colors.card,
      colors.navBar,
      colors.linkBlue,
      theme.incomingColor ?? colors.bubbleIncoming,
      theme.outgoingColor ?? theme.accentColor,
    ];
    return SizedBox(
      key: const ValueKey('global-theme-color-grid'),
      width: 74,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: [for (final color in swatches) _swatch(color)],
      ),
    );
  }

  Widget _builtInAccentPicker(
    ThemeController controller,
    TelegramCloudTheme theme,
  ) {
    final c = context.colors;
    final selected = theme.accentColor.toARGB32();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStringKeys.chatWallpaperColor.l10n(context),
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 44,
          child: ListView.separated(
            key: const ValueKey('global-theme-accent-list'),
            scrollDirection: Axis.horizontal,
            itemCount: _officialAccentPresets.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index < _officialAccentPresets.length) {
                final color = _officialAccentPresets[index];
                return _accentChoice(
                  color: color,
                  selected: color.toARGB32() == selected,
                  onTap: () => controller.installCloudTheme(
                    theme.withBuiltInAccent(color),
                    brightness: _targetBrightness,
                  ),
                );
              }
              return GestureDetector(
                key: const ValueKey('global-theme-custom-accent'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _chooseCustomAccent(controller, theme),
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.searchFill,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.divider),
                  ),
                  child: AppIcon(
                    HeroAppIcons.palette,
                    size: 19,
                    color: c.linkBlue,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _accentChoice({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? context.colors.textPrimary
              : const Color(0x22000000),
          width: selected ? 2.5 : 1,
        ),
      ),
      child: selected
          ? AppIcon(
              HeroAppIcons.check,
              size: 17,
              color: readableForeground(color),
            )
          : null,
    ),
  );

  Future<void> _chooseCustomAccent(
    ThemeController controller,
    TelegramCloudTheme theme,
  ) async {
    final rgb = theme.accentColor.toARGB32() & 0x00FFFFFF;
    final result = await Navigator.of(context).push<ChatWallpaper>(
      PageRouteBuilder<ChatWallpaper>(
        pageBuilder: (_, _, _) => ChatWallpaperColorView(
          controller: ChatWallpaperController.shared,
          dark: _targetBrightness == Brightness.dark,
          colorOnly: true,
          initial: ChatWallpaper.telegram(
            backgroundId: 0,
            remoteType: 'fill',
            colors: [rgb],
          ),
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || result == null || result.colors.isEmpty) return;
    controller.installCloudTheme(
      theme.withBuiltInAccent(
        Color(0xFF000000 | (result.colors.first & 0x00FFFFFF)),
      ),
      brightness: _targetBrightness,
    );
  }

  Widget _themeLinkControl() {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = (constraints.maxWidth * 0.38)
            .clamp(92.0, 132.0)
            .toDouble();
        return Container(
          key: const ValueKey('global-theme-link-control'),
          height: 48,
          padding: const EdgeInsets.fromLTRB(12, 3, 3, 3),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.divider),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              AppIcon(HeroAppIcons.link, size: 18, color: c.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: EditableText(
                  controller: _linkController,
                  focusNode: _focusNode,
                  style: TextStyle(fontSize: 15, color: c.textPrimary),
                  cursorColor: c.linkBlue,
                  backgroundCursorColor: c.textTertiary,
                  selectionColor: c.linkBlue.withValues(alpha: 0.25),
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _loadTheme(),
                ),
              ),
              const SizedBox(width: 7),
              GestureDetector(
                key: const ValueKey('global-theme-preview-action'),
                behavior: HitTestBehavior.opaque,
                onTap: _loading ? null : _loadTheme,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: actionWidth,
                  height: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _loading
                        ? c.linkBlue.withValues(alpha: 0.45)
                        : c.linkBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      AppStringKeys.globalThemePreview.l10n(context),
                      maxLines: 1,
                      style: TextStyle(
                        color: c.onAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<TelegramCloudTheme> _mergeCommunityThemes(
  Iterable<TelegramCloudTheme> first,
  Iterable<TelegramCloudTheme> second,
) {
  final bySlug = <String, TelegramCloudTheme>{};
  for (final theme in [...first, ...second]) {
    if (!theme.slug.startsWith('builtin:')) bySlug[theme.slug] = theme;
  }
  return List.unmodifiable(bySlug.values);
}
