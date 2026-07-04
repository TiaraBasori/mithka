import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../components/app_icons.dart';
import '../theme/app_theme.dart';
import 'package:mithka/l10n/app_localizations.dart';

class RichTextComposerResult {
  const RichTextComposerResult({required this.text, required this.media});

  final String text;
  final List<XFile> media;
}

Future<RichTextComposerResult?> showRichTextComposerSheet(
  BuildContext context, {
  required String initialText,
  String title = AppStringKeys.topicChatShare,
  String submitText = AppStringKeys.topicChatPublish,
  String hintText = AppStringKeys.richTextComposerContentPlaceholder,
  bool allowMedia = true,
}) {
  return showGeneralDialog<RichTextComposerResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title.l10n(context),
    barrierColor: Colors.black.withValues(alpha: 0.36),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, _) {
      return RichTextComposerView(
        initialText: initialText,
        title: title,
        submitText: submitText,
        hintText: hintText,
        allowMedia: allowMedia,
        asSheet: true,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class RichTextComposerView extends StatefulWidget {
  const RichTextComposerView({
    super.key,
    required this.initialText,
    this.title = AppStringKeys.topicChatShare,
    this.submitText = AppStringKeys.topicChatPublish,
    this.hintText = AppStringKeys.richTextComposerContentPlaceholder,
    this.allowMedia = true,
    this.asSheet = false,
  });

  final String initialText;
  final String title;
  final String submitText;
  final String hintText;
  final bool allowMedia;
  final bool asSheet;

  @override
  State<RichTextComposerView> createState() => _RichTextComposerViewState();
}

class _RichTextComposerViewState extends State<RichTextComposerView> {
  late final TextEditingController _controller;
  final _picker = ImagePicker();
  final _media = <XFile>[];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _wrap(String left, [String? right]) {
    right ??= left;
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final selected = value.text.substring(start, end);
    final next = value.text.replaceRange(start, end, '$left$selected$right');
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + left.length + selected.length,
      ),
    );
  }

  void _prefixLine(String prefix) {
    final value = _controller.value;
    final offset = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final lineStart = value.text.lastIndexOf('\n', offset - 1) + 1;
    final next = value.text.replaceRange(lineStart, lineStart, prefix);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset + prefix.length),
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      RichTextComposerResult(
        text: _controller.text,
        media: List<XFile>.of(_media),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = SafeArea(
      top: !widget.asSheet,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      AppStringKeys.countryPickerCancel.l10n(context),
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.title.l10n(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      widget.submitText.l10n(context),
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.divider),
          _toolbar(c),
          if (widget.allowMedia) _mediaStrip(c),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              contextMenuBuilder: (context, editableTextState) {
                return AdaptiveTextSelectionToolbar.editableText(
                  editableTextState: editableTextState,
                );
              },
              style: TextStyle(fontSize: 16, height: 1.4, color: c.textPrimary),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
                hintText: widget.hintText.l10n(context),
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
    if (!widget.asSheet) {
      return Scaffold(backgroundColor: c.background, body: content);
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: FractionallySizedBox(
          heightFactor: 0.86,
          widthFactor: 1,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: ColoredBox(color: c.background, child: content),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(AppColors c) {
    return Container(
      height: 44,
      color: c.navBar,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _formatButton(c, 'B', () => _wrap('**')),
          _formatButton(c, 'I', () => _wrap('*')),
          _formatButton(c, 'U', () => _wrap('__')),
          _formatButton(c, 'S', () => _wrap('~~')),
          _formatButton(c, '</>', () => _wrap('`')),
          _formatButton(c, 'H', () => _prefixLine('## ')),
          _formatButton(c, '•', () => _prefixLine('- ')),
          _formatButton(
            c,
            AppStringKeys.messageActionQuote,
            () => _wrap('> ', ''),
          ),
        ],
      ),
    );
  }

  Widget _mediaStrip(AppColors c) {
    if (_media.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _pickMedia,
          icon: const AppIcon(HeroAppIcons.image, size: 20),
          label: Text(AppStringKeys.richTextComposerPhotoVideo.l10n(context)),
        ),
      );
    }
    return SizedBox(
      height: 94,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        scrollDirection: Axis.horizontal,
        itemCount: _media.length + (_media.length < 9 ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _media.length) return _addMediaTile(c);
          return _mediaTile(c, index);
        },
      ),
    );
  }

  Widget _addMediaTile(AppColors c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickMedia,
      child: Container(
        width: 84,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: AppIcon(HeroAppIcons.plus, color: c.textTertiary),
      ),
    );
  }

  Widget _mediaTile(AppColors c, int index) {
    final item = _media[index];
    final isVideo = _isVideoPath(item.path);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(item.path),
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 84,
              height: 84,
              color: c.searchFill,
              child: AppIcon(
                isVideo ? HeroAppIcons.solidFileVideo : HeroAppIcons.image,
                color: c.textTertiary,
              ),
            ),
          ),
        ),
        if (isVideo)
          const Positioned.fill(
            child: Center(
              child: AppIcon(HeroAppIcons.play, color: Colors.white, size: 24),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _media.removeAt(index)),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                HeroAppIcons.xmark,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickMedia() async {
    try {
      final picked = await _picker.pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;
      final remaining = 9 - _media.length;
      setState(() => _media.addAll(picked.take(remaining)));
    } catch (_) {}
  }

  Widget _formatButton(AppColors c, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: c.textPrimary)),
      ),
    );
  }

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm');
  }
}
