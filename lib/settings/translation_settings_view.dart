//
//  translation_settings_view.dart
//
//  翻译 settings: provider and target language preferences.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'ai_settings_controller.dart';
import 'ai_settings_view.dart';
import 'ai_translation_prompt.dart';
import 'translation_api.dart';
import 'translation_controller.dart';

class TranslationSettingsView extends StatefulWidget {
  const TranslationSettingsView({super.key});

  @override
  State<TranslationSettingsView> createState() =>
      _TranslationSettingsViewState();
}

class _AiTranslationPromptEditorView extends StatefulWidget {
  const _AiTranslationPromptEditorView({required this.translation});

  final TranslationController translation;

  @override
  State<_AiTranslationPromptEditorView> createState() =>
      _AiTranslationPromptEditorViewState();
}

class _AiTranslationPromptEditorViewState
    extends State<_AiTranslationPromptEditorView> {
  late final TextEditingController _prompt;

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(
      text: widget.translation.aiTranslationPrompt,
    );
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: AppStringKeys.translationSettingsAiPrompt.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          Text(
            AppStringKeys.translationSettingsAiPromptDescription.l10n(context),
            style: AppTextStyle.footnote(c.textSecondary).copyWith(height: 1.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            textField: true,
            label: AppStringKeys.translationSettingsAiPrompt.l10n(context),
            child: SettingsPanel(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 300),
                child: TextField(
                  key: const ValueKey('aiTranslationPromptField'),
                  controller: _prompt,
                  minLines: 14,
                  maxLines: null,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  cursorColor: AppTheme.brand,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: defaultAiTranslationPrompt.trim(),
                    hintStyle: TextStyle(
                      color: c.textTertiary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _actionButton(
            label: AppStringKeys.translationSettingsAiPromptSave.l10n(context),
            onTap: _save,
          ),
          const SizedBox(height: AppSpacing.sm),
          _actionButton(
            label: AppStringKeys.translationSettingsAiPromptReset.l10n(context),
            onTap: () => setState(
              () => _prompt.text = defaultAiTranslationPrompt.trim(),
            ),
            backgroundColor: c.card,
            foregroundColor: AppTheme.brand,
            borderColor: AppTheme.brand,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? borderColor,
  }) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor ?? AppTheme.brand,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: borderColor == null ? null : Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foregroundColor ?? const Color(0xFFFFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  void _save() {
    if (_prompt.text.trim().isEmpty) {
      showToast(
        context,
        AppStringKeys.translationSettingsAiPromptEmpty.l10n(context),
      );
      return;
    }
    widget.translation.setAiTranslationPrompt(_prompt.text);
    Navigator.of(context).pop();
  }
}

class _TranslationSettingsViewState extends State<TranslationSettingsView> {
  late final Future<Set<TranslationProvider>> _availableProvidersFuture =
      NativeTranslationApi.availableProviders();

  @override
  Widget build(BuildContext context) {
    final translation = context.watch<TranslationController>();
    final ai = context.watch<AiSettingsController>();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.messageActionTranslate),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsSection(
            rows: [
              SettingsSwitchRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.language),
                title: AppStrings.t(
                  AppStringKeys.translationSettingsShowTranslateButton,
                ),
                value: translation.enabled,
                onChanged: (value) => translation.enabled = value,
              ),
              SettingsSwitchRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.comments),
                title: AppStrings.t(
                  AppStringKeys.translationSettingsTranslateChats,
                ),
                value: translation.translateChats,
                onChanged: (value) => translation.translateChats = value,
              ),
              SettingsRow(
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.quoteLeft,
                ),
                title: AppStringKeys.translationSettingsDisplayStyle,
                value: translation.displayStyleLabel,
                onTap: () => _showDisplayStylePicker(context),
              ),
            ],
          ),
          SettingsSection(
            titleKey: AppStringKeys.translationSettingsAiSection,
            rows: [
              SettingsSwitchRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.cpuChip),
                title: AppStringKeys.translationSettingsAiEnabled.l10n(context),
                value: translation.aiTranslationEnabled,
                onChanged: (value) => translation.aiTranslationEnabled = value,
              ),
              SettingsRow(
                leading: SettingsLeadingIcon(
                  icon: switch (ai.translationModelCandidate.kind) {
                    AiModelCandidateKind.applePcc => HeroAppIcons.cloud,
                    AiModelCandidateKind.appleOnDevice => HeroAppIcons.cpuChip,
                    AiModelCandidateKind.server => HeroAppIcons.cube,
                    AiModelCandidateKind.telegramCocoon =>
                      HeroAppIcons.wandMagicSparkles,
                  },
                ),
                title: AppStringKeys.aiTranslateUsing.l10n(context),
                value: _aiModelLabel(context, ai.translationModelCandidate),
                onTap: () => showAiFeatureModelPicker(
                  context,
                  settings: ai,
                  feature: AiFeature.translation,
                ),
              ),
              SettingsRow(
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.penToSquare,
                ),
                title: AppStringKeys.translationSettingsAiPrompt.l10n(context),
                value:
                    (translation.hasCustomAiTranslationPrompt
                            ? AppStringKeys.translationSettingsAiPromptCustom
                            : AppStringKeys.translationSettingsAiPromptDefault)
                        .l10n(context),
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => _AiTranslationPromptEditorView(
                      translation: translation,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SettingsNote(
            text: AppStringKeys.translationSettingsAiDescription.l10n(context),
          ),
          SettingsSection(
            titleKey: AppStringKeys.translationSettingsStandardSection,
            rows: [
              SettingsRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.server),
                title: AppStrings.t(AppStringKeys.translationSettingsService),
                value: translation.providerLabel,
                onTap: () => _showProviderPicker(context),
              ),
              SettingsRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.globe),
                title: AppStrings.t(
                  AppStringKeys.translationSettingsTargetLanguage,
                ),
                value: translation.targetLanguageLabel,
                onTap: () => _showTargetPicker(context),
              ),
              if (translation.enabled || translation.translateChats) ...[
                SettingsRow(
                  leading: const SettingsLeadingIcon(icon: HeroAppIcons.ban),
                  title: AppStrings.t(
                    AppStringKeys.translationSettingsDoNotTranslate,
                  ),
                  value: _ignoredLanguagesSummary(translation),
                  onTap: () => _showIgnoredLanguagesPicker(context),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showProviderPicker(BuildContext context) {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final translation = context.watch<TranslationController>();
        return SafeArea(
          child: SettingsPanel(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            clipBehavior: Clip.antiAlias,
            child: FutureBuilder<Set<TranslationProvider>>(
              future: _availableProvidersFuture,
              builder: (context, snapshot) {
                final nativeProviders =
                    snapshot.data ?? const <TranslationProvider>{};
                final providers = TranslationProvider.selectableProviders
                    .where(
                      (provider) =>
                          !provider.isNative ||
                          nativeProviders.contains(provider),
                    )
                    .toList();
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: providers.length,
                  separatorBuilder: (_, _) => const SettingsDivider(),
                  itemBuilder: (context, i) {
                    final provider = providers[i];
                    final selected = translation.provider == provider;
                    return SettingsRow(
                      title: provider.label,
                      leading: const SettingsLeadingIcon(
                        icon: HeroAppIcons.server,
                      ),
                      showChevron: false,
                      trailing: selected
                          ? AppIcon(
                              HeroAppIcons.check,
                              size: AppIconSize.lg,
                              color: AppTheme.brand,
                            )
                          : null,
                      onTap: () {
                        translation.provider = provider;
                        Navigator.of(context).pop();
                      },
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showDisplayStylePicker(BuildContext context) {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final translation = context.watch<TranslationController>();
        return SafeArea(
          child: SettingsPanel(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: TranslationDisplayStyle.values.length,
              separatorBuilder: (_, _) => const SettingsDivider(),
              itemBuilder: (context, index) {
                final style = TranslationDisplayStyle.values[index];
                final selected = translation.displayStyle == style;
                return SettingsRow(
                  key: ValueKey('translation-display-style-${style.name}'),
                  title: style.label,
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.quoteLeft,
                  ),
                  showChevron: false,
                  trailing: selected
                      ? AppIcon(
                          HeroAppIcons.check,
                          size: AppIconSize.lg,
                          color: AppTheme.brand,
                        )
                      : null,
                  onTap: () {
                    translation.displayStyle = style;
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showTargetPicker(BuildContext context) {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final translation = context.watch<TranslationController>();
        return SafeArea(
          child: SettingsPanel(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: TranslationController.targetLanguages.length,
              separatorBuilder: (_, _) => const SettingsDivider(),
              itemBuilder: (context, i) {
                final language = TranslationController.targetLanguages[i];
                final selected =
                    translation.targetLanguageCode == language.code;
                return SettingsRow(
                  title: language.label,
                  leading: const SettingsLeadingIcon(icon: HeroAppIcons.globe),
                  showChevron: false,
                  trailing: selected
                      ? AppIcon(
                          HeroAppIcons.check,
                          size: AppIconSize.lg,
                          color: AppTheme.brand,
                        )
                      : null,
                  onTap: () {
                    translation.targetLanguageCode = language.code;
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _ignoredLanguagesSummary(TranslationController translation) {
    final ignored = translation.ignoredLanguageCodes;
    if (ignored.isEmpty) {
      return AppStrings.t(AppStringKeys.translationSettingsNone);
    }
    if (ignored.length == 1) {
      final code = ignored.single;
      final language = TranslationController.targetLanguages.firstWhere(
        (language) =>
            TranslationController.normalizeLanguageCode(language.code) == code,
        orElse: () => TranslationLanguage(code, code.toUpperCase()),
      );
      return language.label;
    }
    return AppStrings.t(AppStringKeys.translationSettingsLanguageCount, {
      'value1': ignored.length,
    });
  }

  String _aiModelLabel(BuildContext context, AiModelCandidate candidate) =>
      switch (candidate.kind) {
        AiModelCandidateKind.applePcc => AppStringKeys.aiProviderApplePcc.l10n(
          context,
        ),
        AiModelCandidateKind.appleOnDevice =>
          AppStringKeys.aiProviderAppleOnDevice.l10n(context),
        AiModelCandidateKind.server => candidate.model,
        AiModelCandidateKind.telegramCocoon =>
          AppStringKeys.aiProviderTelegramCocoon.l10n(context),
      };

  void _showIgnoredLanguagesPicker(BuildContext context) {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final translation = context.watch<TranslationController>();
        return SafeArea(
          child: SettingsPanel(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SettingsSectionHeader(
                  AppStringKeys.translationSettingsDoNotTranslate,
                ),
                const SettingsDivider.text(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: TranslationController.targetLanguages.length,
                    separatorBuilder: (_, _) => const SettingsDivider(),
                    itemBuilder: (context, i) {
                      final language = TranslationController.targetLanguages[i];
                      final normalized =
                          TranslationController.normalizeLanguageCode(
                            language.code,
                          );
                      final selected =
                          normalized != null &&
                          translation.ignoredLanguageCodes.contains(normalized);
                      return SettingsRow(
                        title: language.label,
                        leading: const SettingsLeadingIcon(
                          icon: HeroAppIcons.ban,
                        ),
                        showChevron: false,
                        trailing: selected
                            ? AppIcon(
                                HeroAppIcons.check,
                                size: AppIconSize.lg,
                                color: AppTheme.brand,
                              )
                            : null,
                        onTap: () => translation.setIgnoredLanguage(
                          language.code,
                          !selected,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
