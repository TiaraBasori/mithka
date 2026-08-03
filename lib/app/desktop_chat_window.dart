import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'desktop_chat_media.dart';
import 'desktop_chat_window_models.dart';
import 'desktop_chat_window_stub.dart'
    if (dart.library.io) 'desktop_chat_window_io.dart'
    as implementation;
import 'desktop_window_controls.dart';
import 'macos_desktop_title_bar.dart';

export 'desktop_chat_window_models.dart';

class DesktopChatWindowService {
  DesktopChatWindowService._();

  static final DesktopChatWindowService instance = DesktopChatWindowService._();

  bool get isSupported => implementation.supportsDesktopChatWindows;

  void attachMainProxy() => implementation.attachDesktopChatMainProxy();

  void detachMainProxy() => implementation.detachDesktopChatMainProxy();

  Future<bool> open(DesktopChatWindowArguments arguments) =>
      implementation.openDesktopChatWindow(arguments);

  DesktopChatWindowChildController createChildController(
    DesktopChatWindowArguments arguments,
  ) => implementation.createDesktopChatWindowChildController(arguments);

  Future<void> closeCurrentWindow() =>
      implementation.closeCurrentDesktopChatWindow();
}

/// Lightweight secondary-window application.
///
/// It intentionally owns no Telegram client or authentication lifecycle. All
/// snapshots and sends travel through the main isolate's bounded IPC proxy.
class DesktopChatWindowApp extends StatelessWidget {
  const DesktopChatWindowApp({super.key, required this.arguments});

  final DesktopChatWindowArguments arguments;

  ThemeData _theme(Brightness brightness) {
    final colors = arguments.palette.toAppColors();
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: colors.chatBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: arguments.palette.brandColor,
        brightness: brightness,
      ),
      extensions: [colors],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.applyBrand(arguments.palette.brandColor);
    final locale = AppLocalizations.localeFromTag(arguments.localeTag);
    return MaterialApp(
      title: arguments.title,
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: arguments.dark ? ThemeMode.dark : ThemeMode.light,
      home: implementation.buildDesktopChatWindowHost(
        initialArguments: arguments,
        builder: (context, currentArguments) => DesktopChatWindowPage(
          key: ValueKey(currentArguments.encode()),
          arguments: currentArguments,
        ),
      ),
    );
  }
}

class DesktopChatWindowPage extends StatefulWidget {
  const DesktopChatWindowPage({
    super.key,
    required this.arguments,
    this.controller,
  });

  final DesktopChatWindowArguments arguments;
  final DesktopChatWindowChildController? controller;

  @override
  State<DesktopChatWindowPage> createState() => _DesktopChatWindowPageState();
}

class _DesktopChatWindowPageState extends State<DesktopChatWindowPage> {
  late final DesktopChatWindowChildController _controller =
      (widget.controller ??
            DesktopChatWindowService.instance.createChildController(
              widget.arguments,
            ))
        ..addListener(_handleControllerUpdate);
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _messages = ScrollController();
  int _lastMessageId = 0;

  bool get _hasActiveTextComposition {
    final composing = _composer.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  @override
  void initState() {
    super.initState();
    _lastMessageId = _controller.snapshot?.messages.lastOrNull?.id ?? 0;
  }

  void _handleControllerUpdate() {
    if (!mounted) return;
    final latest = _controller.snapshot?.messages.lastOrNull?.id ?? 0;
    final shouldScroll = latest != 0 && latest != _lastMessageId;
    _lastMessageId = latest;
    setState(() {});
    if (shouldScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    }
  }

  void _scrollToLatest() {
    if (!_messages.hasClients) return;
    unawaited(
      _messages.animateTo(
        _messages.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _controller.sending) return;
    final sent = await _controller.sendText(text);
    if (!mounted || !sent) return;
    _composer.clear();
    _composerFocus.requestFocus();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerUpdate)
      ..dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _messages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final snapshot = _controller.snapshot;
    final title = snapshot?.title ?? widget.arguments.title;
    final isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final isNativeDesktop =
        !kIsWeb &&
        switch (defaultTargetPlatform) {
          TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux => true,
          _ => false,
        };
    return Scaffold(
      backgroundColor: colors.chatBackground,
      body: Column(
        children: [
          if (isNativeDesktop)
            MacosDesktopTitleBar(
              leadingClearance: isMacOS ? 78 : 8,
              trailingControls: usesFlutterDesktopWindowControls
                  ? const DesktopWindowControls()
                  : null,
              onDragAreaDoubleTap: usesFlutterDesktopWindowControls
                  ? () => unawaited(togglePrimaryDesktopWindowMaximized())
                  : null,
              appIdentity: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    HeroAppIcons.message,
                    size: 18,
                    color: colors.textPrimary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Mithka',
                    style: AppTextStyle.callout(
                      colors.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ],
              ),
              accountIdentity: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption(colors.textSecondary),
                ),
              ),
              backgroundColor: colors.navBar,
            ),
          _DesktopChatHeader(title: title),
          Expanded(child: _transcript(snapshot)),
          _composerBar(snapshot),
        ],
      ),
    );
  }

  Widget _transcript(DesktopChatWindowSnapshot? snapshot) {
    final colors = context.colors;
    if (_controller.loading && snapshot == null) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.arguments.palette.brandColor,
          ),
        ),
      );
    }
    if (snapshot == null || snapshot.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Text(
            AppStringKeys.desktopChatWindowUnavailable.l10n(context),
            textAlign: TextAlign.center,
            style: AppTextStyle.callout(colors.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('desktop-chat-window-transcript'),
      controller: _messages,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.section,
        vertical: AppSpacing.xxl,
      ),
      itemCount: snapshot.messages.length,
      itemBuilder: (context, index) => _DesktopChatMessageBubble(
        message: snapshot.messages[index],
        brandColor: widget.arguments.palette.brandColor,
      ),
    );
  }

  Widget _composerBar(DesktopChatWindowSnapshot? snapshot) {
    final colors = context.colors;
    final canSend = snapshot?.canSend == true && !snapshot!.failed;
    final shortcut = widget.arguments.enterToSend ? 'Enter' : 'Ctrl+Enter';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.inputBarBackground,
        border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, AppSpacing.md, 18, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Shortcuts(
                  shortcuts: widget.arguments.enterToSend
                      ? const {
                          SingleActivator(LogicalKeyboardKey.enter):
                              _DesktopChatSendIntent(),
                          SingleActivator(LogicalKeyboardKey.numpadEnter):
                              _DesktopChatSendIntent(),
                        }
                      : const {
                          SingleActivator(
                            LogicalKeyboardKey.enter,
                            control: true,
                          ): _DesktopChatSendIntent(),
                          SingleActivator(
                            LogicalKeyboardKey.numpadEnter,
                            control: true,
                          ): _DesktopChatSendIntent(),
                        },
                  child: Actions(
                    actions: {
                      _DesktopChatSendIntent: _DesktopChatSendAction(
                        canInvoke: () => canSend && !_hasActiveTextComposition,
                        onInvoke: () => unawaited(_send()),
                      ),
                    },
                    child: TextField(
                      key: const ValueKey('desktop-chat-window-composer'),
                      controller: _composer,
                      focusNode: _composerFocus,
                      enabled: canSend,
                      minLines: 2,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: AppTextStyle.body(colors.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: colors.background,
                        hintText: AppStringKeys.composerSend.l10n(context),
                        hintStyle: AppTextStyle.body(colors.textTertiary),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          borderSide: BorderSide(color: colors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          borderSide: BorderSide(color: colors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          borderSide: BorderSide(
                            color: widget.arguments.palette.brandColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Semantics(
                button: true,
                enabled: canSend && !_controller.sending,
                label:
                    '${AppStringKeys.composerSend.l10n(context)} ($shortcut)',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canSend && !_controller.sending
                      ? () => unawaited(_send())
                      : null,
                  child: Container(
                    key: const ValueKey('desktop-chat-window-send'),
                    height: 36,
                    constraints: const BoxConstraints(minWidth: 112),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: canSend && !_controller.sending
                          ? widget.arguments.palette.brandColor
                          : widget.arguments.palette.brandColor.withValues(
                              alpha: 0.42,
                            ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(
                          HeroAppIcons.solidPaperPlane,
                          size: 15,
                          color: colors.onAccent,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          shortcut,
                          style: AppTextStyle.tiny(
                            colors.onAccent.withValues(alpha: 0.8),
                            weight: AppTextWeight.medium,
                          ),
                        ),
                      ],
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
}

class _DesktopChatHeader extends StatelessWidget {
  const _DesktopChatHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('desktop-chat-window-header'),
      height: 52,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.title(
          colors.textPrimary,
          weight: AppTextWeight.semibold,
        ),
      ),
    );
  }
}

class _DesktopChatMessageBubble extends StatelessWidget {
  const _DesktopChatMessageBubble({
    required this.message,
    required this.brandColor,
  });

  final DesktopChatMessageSnapshot message;
  final Color brandColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final outgoing = message.outgoing;
    final bubbleColor = outgoing ? brandColor : colors.bubbleIncoming;
    final textColor = outgoing ? colors.onAccent : colors.bubbleIncomingText;
    final mediaPath = message.mediaPath;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!outgoing && message.senderName.trim().isNotEmpty) ...[
                    Text(
                      message.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption(
                        colors.linkBlue,
                        weight: AppTextWeight.semibold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  if (mediaPath != null && mediaPath.isNotEmpty) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 420,
                        maxHeight: 320,
                      ),
                      child: desktopChatLocalMedia(
                        path: mediaPath,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    if (message.text.trim().isNotEmpty)
                      const SizedBox(height: AppSpacing.sm),
                  ],
                  if (message.text.trim().isNotEmpty)
                    SelectableText(
                      message.text,
                      style: AppTextStyle.callout(textColor),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          _contentIcon(message.contentType),
                          size: 16,
                          color: textColor.withValues(alpha: 0.78),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          AppStringKeys.chatSearchMessageResultLabel.l10n(
                            context,
                          ),
                          style: AppTextStyle.callout(
                            textColor.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _timeLabel(message.date),
                      style: AppTextStyle.tiny(
                        textColor.withValues(alpha: 0.64),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static AppIconData _contentIcon(String type) => switch (type) {
    'messagePhoto' => HeroAppIcons.image,
    'messageVideo' ||
    'messageVideoNote' ||
    'messageAnimation' => HeroAppIcons.video,
    'messageAudio' || 'messageVoiceNote' => HeroAppIcons.music,
    'messageDocument' => HeroAppIcons.file,
    'messageLocation' || 'messageVenue' => HeroAppIcons.locationPin,
    _ => HeroAppIcons.message,
  };

  static String _timeLabel(int unixSeconds) {
    if (unixSeconds <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
    ).toLocal();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _DesktopChatSendIntent extends Intent {
  const _DesktopChatSendIntent();
}

class _DesktopChatSendAction extends Action<_DesktopChatSendIntent> {
  _DesktopChatSendAction({required this.canInvoke, required this.onInvoke});

  final bool Function() canInvoke;
  final VoidCallback onInvoke;

  @override
  bool isEnabled(_DesktopChatSendIntent intent) => canInvoke();

  @override
  Object? invoke(_DesktopChatSendIntent intent) {
    onInvoke();
    return null;
  }
}
