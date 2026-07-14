import 'package:flutter/widgets.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../chat/chat_wallpaper.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import 'app_theme.dart';
import 'telegram_cloud_theme.dart';
import 'theme_controller.dart';

class TelegramCloudThemePreviewView extends StatelessWidget {
  const TelegramCloudThemePreviewView({super.key, required this.theme});

  final TelegramCloudTheme theme;

  @override
  Widget build(BuildContext context) {
    final colors = theme.appColors;
    return ColoredBox(
      color: colors.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.cloudThemePreviewTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                _identity(context, colors),
                const SizedBox(height: AppSpacing.xl),
                _chatPreview(context, colors),
              ],
            ),
          ),
          _applyBar(context, colors),
        ],
      ),
    );
  }

  Widget _identity(BuildContext context, AppColors colors) => Container(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.accentColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: AppIcon(
            HeroAppIcons.palette,
            size: AppIconSize.toolbar,
            color: theme.accentColor,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                theme.title,
                style: AppTextStyle.title(
                  colors.textPrimary,
                  weight: AppTextWeight.semibold,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '@${theme.slug}',
                style: AppTextStyle.footnote(colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStringKeys.cloudThemeOfficialDescription.l10n(context),
                style: AppTextStyle.caption(colors.textTertiary),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _chatPreview(BuildContext context, AppColors colors) {
    final outgoing = theme.outgoingColor ?? theme.accentColor;
    final outgoingText =
        theme.outgoingTextColor ??
        (outgoing.computeLuminance() > 0.64
            ? const Color(0xFF171717)
            : const Color(0xFFFFFFFF));
    final incoming = theme.incomingColor ?? colors.bubbleIncoming;
    final incomingText = theme.incomingTextColor ?? colors.bubbleIncomingText;
    final wallpaperController = ChatWallpaperController.shared;
    return AnimatedBuilder(
      animation: wallpaperController,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          height: 360,
          child: ChatWallpaperBackground(
            wallpaper: theme.wallpaper == null
                ? null
                : wallpaperController.resolvedWallpaper(theme.wallpaper!),
            fallbackColor: colors.chatBackground,
            brightness: theme.isDark ? Brightness.dark : Brightness.light,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _bubble(
                    AppStringKeys.chatWallpaperPreviewIncoming.l10n(context),
                    incoming,
                    incomingText,
                    Alignment.centerLeft,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _bubble(
                    AppStringKeys.chatWallpaperPreviewOutgoing.l10n(context),
                    outgoing,
                    outgoingText,
                    Alignment.centerRight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(
    String text,
    Color background,
    Color foreground,
    Alignment alignment,
  ) => Align(
    alignment: alignment,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(text, style: AppTextStyle.body(foreground)),
    ),
  );

  Widget _applyBar(BuildContext context, AppColors colors) => ColoredBox(
    color: colors.card,
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.all(AppSpacing.xl),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          context.read<ThemeController>().installCloudTheme(theme);
          Navigator.of(context).pop();
        },
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.accentColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Text(
            AppStringKeys.cloudThemeApply.l10n(context),
            style: AppTextStyle.bodyLarge(
              theme.accentColor.computeLuminance() > 0.64
                  ? const Color(0xFF171717)
                  : const Color(0xFFFFFFFF),
              weight: AppTextWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}
