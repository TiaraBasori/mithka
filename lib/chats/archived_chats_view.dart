//
//  archived_chats_view.dart
//
//  Telegram archived chats folded behind a dedicated entry. The row is
//  revealed below search by pulling down, then opens ArchivedChatsView.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'chat_row_view.dart';

class ArchivedChatsRow extends StatelessWidget {
  const ArchivedChatsRow({
    super.key,
    required this.archived,
    this.onClearUnread,
  });
  final List<ChatSummary> archived;
  final VoidCallback? onClearUnread;

  ChatSummary? get _latest => archived.isEmpty ? null : archived.first;
  int get _totalUnread => archived.fold(0, (a, c) => a + c.unreadCount);
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final rowHeight = theme.rowHeight;
    final avatarSize = theme.avatarSize;
    return Container(
      height: rowHeight,
      color: c.background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.listHeaderTint,
              shape: BoxShape.circle,
            ),
            child: AppIcon(
              HeroAppIcons.inbox,
              size: theme.scaled(23),
              color: c.linkBlue,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t(AppStringKeys.archivedChatsGroupAssistant),
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ChatPreviewText(
                  sender: _latest?.title,
                  message: _latest?.lastMessage ?? '',
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (_totalUnread > 0)
            UnreadBadge(
              count: _totalUnread,
              muted: true,
              onClear: onClearUnread,
            )
          else
            Text(
              DateText.listLabel(_latest?.date ?? 0),
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: c.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

class ArchivedChatsView extends StatelessWidget {
  const ArchivedChatsView({super.key, required this.chats, this.onClearUnread});
  final List<ChatSummary> chats;
  final ValueChanged<ChatSummary>? onClearUnread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.archivedChatsGroupAssistant),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: chats.length,
              itemBuilder: (context, i) {
                final chat = chats[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ChatView(chatId: chat.id, title: chat.title),
                    ),
                  ),
                  child: ChatRowView(
                    chat: chat,
                    archived: true,
                    onClearUnread: () => onClearUnread?.call(chat),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
