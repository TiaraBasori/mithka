import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import 'app_theme.dart';
import 'telegram_cloud_theme.dart';
import 'telegram_cloud_theme_view.dart';
import 'theme_controller.dart';

/// Global Telegram .attheme management. This intentionally contains no chat
/// emoji themes: a cloud theme replaces the app UI palette while it is active.
class GlobalThemeView extends StatefulWidget {
  const GlobalThemeView({super.key});

  @override
  State<GlobalThemeView> createState() => _GlobalThemeViewState();
}

class _GlobalThemeViewState extends State<GlobalThemeView> {
  final _linkController = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;

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
      final theme = await TelegramCloudThemeService().load(link);
      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => TelegramCloudThemePreviewView(theme: theme),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, AppStringKeys.cloudThemeLoadFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<ThemeController>();
    final theme = controller.cloudTheme;
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
                _activeThemeCard(controller, theme),
                const SizedBox(height: 22),
                Text(
                  AppStringKeys.globalThemeImport.l10n(context),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _linkField(),
                const SizedBox(height: 10),
                _loadButton(),
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

  Widget _activeThemeCard(
    ThemeController controller,
    TelegramCloudTheme? theme,
  ) {
    final c = context.colors;
    final colors = theme?.appColors;
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
            ],
          ),
          if (colors != null) ...[
            const SizedBox(height: 16),
            Text(
              AppStringKeys.globalThemeColors.l10n(context),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                _swatch(colors.background),
                _swatch(colors.card),
                _swatch(colors.navBar),
                _swatch(colors.linkBlue),
                _swatch(theme?.incomingColor ?? colors.bubbleIncoming),
                _swatch(theme?.outgoingColor ?? theme!.accentColor),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: controller.clearCloudTheme,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.searchFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  AppStringKeys.globalThemeReset.l10n(context),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.linkBlue,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _swatch(Color color) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x22000000)),
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 4),
      ],
    ),
  );

  Widget _linkField() {
    final c = context.colors;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
        ],
      ),
    );
  }

  Widget _loadButton() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loading ? null : _loadTheme,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _loading ? c.linkBlue.withValues(alpha: 0.45) : c.linkBlue,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          _loading
              ? AppStringKeys.globalThemeLoading.l10n(context)
              : AppStringKeys.globalThemePreview.l10n(context),
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
