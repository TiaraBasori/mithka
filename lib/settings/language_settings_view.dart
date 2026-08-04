import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/desktop_content_constraint.dart';
import '../components/ui_components.dart';
import '../l10n/app_locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'translation_settings_view.dart';

class LanguageSettingsView extends StatelessWidget {
  const LanguageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = context.watch<AppLocaleController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.languageTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: DesktopContentConstraint(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  SettingsCard(
                    children: [
                      _NavLanguageRow(
                        icon: HeroAppIcons.globe,
                        title: AppStringKeys.languageMithkaLanguage.l10n(
                          context,
                        ),
                        subtitle: locale.selectedLabel(context),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AppLanguageSettingsView(),
                          ),
                        ),
                      ),
                      const InsetDivider(leadingInset: 56),
                      _NavLanguageRow(
                        icon: HeroAppIcons.comment,
                        title: AppStrings.t(
                          AppStringKeys.messageActionTranslate,
                        ),
                        subtitle: AppStrings.t(
                          AppStringKeys.translationSettingsTitle,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TranslationSettingsView(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppLanguageSettingsView extends StatelessWidget {
  const AppLanguageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<AppLocaleController>();
    const options = AppLocaleController.options;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.languageMithkaLanguage.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: DesktopContentConstraint(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  SettingsCard(
                    children: [
                      _LanguageRow(
                        title: AppStringKeys.appLocaleFollowSystem.l10n(
                          context,
                        ),
                        selected: controller.followsSystem,
                        onTap: () => controller.locale = null,
                      ),
                      const InsetDivider(leadingInset: 16),
                      for (final option in options) ...[
                        _LanguageRow(
                          title: AppStrings.t(option.label),
                          selected:
                              !controller.followsSystem &&
                              AppLocaleController.labelFor(
                                    controller.locale!,
                                  ) ==
                                  AppStrings.t(option.label),
                          onTap: () => controller.locale = option.locale,
                        ),
                        if (option != options.last)
                          const InsetDivider(leadingInset: 16),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavLanguageRow extends StatelessWidget {
  const _NavLanguageRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcon(icon, size: 22, color: AppTheme.brand),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: c.textTertiary),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 14,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                  ],
                ),
              ),
              if (selected)
                AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
            ],
          ),
        ),
      ),
    );
  }
}
