//
//  desktop_chat_context_pane.dart
//
//  Compact, read-only context for the optional native-desktop chat pane. The
//  pane deliberately reuses ChatInfoViewModel so it cannot drift from the full
//  chat-info screen, while keeping every mutating control in ChatInfoView.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_info_view.dart';
import 'group_remark_controller.dart';

/// Read-only chat context intended for the compact trailing pane on macOS.
///
/// By default the pane owns and loads its [ChatInfoViewModel]. Tests and
/// specialized owners can inject [viewModel]. The pane listens to both the
/// server-backed model and account-scoped local [groupRemarks], but never
/// invokes a TDLib mutation or edits the local remark.
class DesktopChatContextPane extends StatefulWidget {
  const DesktopChatContextPane({
    super.key,
    required this.chatId,
    required this.title,
    required this.onSearch,
    required this.onClose,
    required this.onOpenFullInfo,
    this.groupRemarks,
    this.onOpenMembers,
    this.onOpenMember,
    this.viewModel,
  });

  final int chatId;
  final String title;
  final GroupRemarkController? groupRemarks;
  final VoidCallback onSearch;
  final VoidCallback onClose;
  final VoidCallback onOpenFullInfo;
  final VoidCallback? onOpenMembers;
  final ValueChanged<ChatMember>? onOpenMember;

  /// Tests and specialized owners may inject an already-loaded model. Normal
  /// integration should omit this so the pane owns the read-only model load.
  @visibleForTesting
  final ChatInfoViewModel? viewModel;

  @override
  State<DesktopChatContextPane> createState() => _DesktopChatContextPaneState();
}

class _DesktopChatContextPaneState extends State<DesktopChatContextPane> {
  late ChatInfoViewModel _viewModel;
  late bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _installViewModel();
  }

  @override
  void didUpdateWidget(DesktopChatContextPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId == widget.chatId &&
        oldWidget.title == widget.title &&
        identical(oldWidget.viewModel, widget.viewModel)) {
      return;
    }
    if (_ownsViewModel) _viewModel.dispose();
    _installViewModel();
  }

  void _installViewModel() {
    _ownsViewModel = widget.viewModel == null;
    _viewModel =
        widget.viewModel ??
        ChatInfoViewModel(chatId: widget.chatId, title: widget.title);
    if (_ownsViewModel) _viewModel.load();
  }

  @override
  void dispose() {
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  GroupRemarkController? _resolveGroupRemarks() {
    if (widget.groupRemarks != null) return widget.groupRemarks;
    try {
      return context.read<GroupRemarkController?>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupRemarks = _resolveGroupRemarks();
    final listenables = <Listenable>[_viewModel];
    if (groupRemarks != null) listenables.add(groupRemarks);
    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) => _DesktopChatContextPaneBody(
        viewModel: _viewModel,
        groupRemarks: groupRemarks,
        onSearch: widget.onSearch,
        onClose: widget.onClose,
        onOpenFullInfo: widget.onOpenFullInfo,
        onOpenMembers: widget.onOpenMembers,
        onOpenMember: widget.onOpenMember,
      ),
    );
  }
}

class _DesktopChatContextPaneBody extends StatelessWidget {
  const _DesktopChatContextPaneBody({
    required this.viewModel,
    required this.groupRemarks,
    required this.onSearch,
    required this.onClose,
    required this.onOpenFullInfo,
    required this.onOpenMembers,
    required this.onOpenMember,
  });

  final ChatInfoViewModel viewModel;
  final GroupRemarkController? groupRemarks;
  final VoidCallback onSearch;
  final VoidCallback onClose;
  final VoidCallback onOpenFullInfo;
  final VoidCallback? onOpenMembers;
  final ValueChanged<ChatMember>? onOpenMember;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final remark = viewModel.isGroup && !viewModel.isChannel
        ? groupRemarks?.remarkFor(viewModel.chatId)
        : null;
    final displayTitle = remark ?? viewModel.title;

    return ColoredBox(
      key: const ValueKey('desktopChatContextPane'),
      color: c.panelBackground,
      child: Column(
        children: [
          _PaneToolbar(onClose: onClose, onOpenFullInfo: onOpenFullInfo),
          Divider(height: 1, thickness: 1, color: c.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _IdentityHeader(
                  title: displayTitle,
                  photo: viewModel.photo,
                  isGroup: viewModel.isGroup,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (viewModel.isGroup && !viewModel.isChannel) ...[
                  _ReadOnlyDetail(
                    key: const ValueKey('desktopChatContextRemark'),
                    label: AppStringKeys.chatInfoGroupRemark.l10n(context),
                    value:
                        remark ??
                        AppStringKeys.chatInfoGroupRemarkEmpty.l10n(context),
                    supportingText: AppStringKeys.chatInfoGroupRemarkLocalOnly
                        .l10n(context),
                    empty: remark == null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (viewModel.isGroup) ...[
                  _ReadOnlyDetail(
                    key: const ValueKey('desktopChatContextAnnouncement'),
                    label: AppStringKeys.chatInfoGroupAnnouncement.l10n(
                      context,
                    ),
                    value: viewModel.description.trim().isEmpty
                        ? AppStringKeys.chatInfoGroupAnnouncementEmpty.l10n(
                            context,
                          )
                        : viewModel.description,
                    empty: viewModel.description.trim().isEmpty,
                    maxLines: 4,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _MemberSection(
                    memberCount: viewModel.memberCount,
                    members: viewModel.members,
                    onSearch: onSearch,
                    onOpenMembers: onOpenMembers,
                    onOpenMember: onOpenMember,
                  ),
                ] else
                  _SearchCard(onSearch: onSearch),
                const SizedBox(height: AppSpacing.md),
                _FullInfoCard(onOpenFullInfo: onOpenFullInfo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaneToolbar extends StatelessWidget {
  const _PaneToolbar({required this.onClose, required this.onOpenFullInfo});

  final VoidCallback onClose;
  final VoidCallback onOpenFullInfo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: const ValueKey('desktopChatContextToolbar'),
      height: 48,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.xxl,
          right: AppSpacing.sm,
        ),
        child: Row(
          children: [
            _SquareAction(
              key: const ValueKey('desktopChatContextClose'),
              label: AppStringKeys.musicPlayerClose.l10n(context),
              icon: HeroAppIcons.xmark,
              onTap: onClose,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                AppStringKeys.chatInfoTitle.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.callout(
                  c.textPrimary,
                  weight: AppTextWeight.semibold,
                ),
              ),
            ),
            _SquareAction(
              key: const ValueKey('desktopChatContextOpenFullInfoTop'),
              label: AppStringKeys.chatInfoTitle.l10n(context),
              icon: HeroAppIcons.gear,
              onTap: onOpenFullInfo,
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({
    required this.title,
    required this.photo,
    required this.isGroup,
  });

  final String title;
  final TdFileRef? photo;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      key: const ValueKey('desktopChatContextIdentity'),
      children: [
        PhotoAvatar(
          title: title,
          photo: photo,
          size: 58,
          square: isGroup,
          allowAnimation: false,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyle.bodyLarge(
            c.textPrimary,
            weight: AppTextWeight.semibold,
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyDetail extends StatelessWidget {
  const _ReadOnlyDetail({
    super.key,
    required this.label,
    required this.value,
    required this.empty,
    this.supportingText,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final String? supportingText;
  final bool empty;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyle.caption(
              c.textSecondary,
              weight: AppTextWeight.medium,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.callout(
              empty ? c.textTertiary : c.textPrimary,
            ).copyWith(height: 1.35),
          ),
          if (supportingText != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              supportingText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption(c.textTertiary).copyWith(height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberSection extends StatelessWidget {
  const _MemberSection({
    required this.memberCount,
    required this.members,
    required this.onSearch,
    required this.onOpenMembers,
    required this.onOpenMember,
  });

  final int memberCount;
  final List<ChatMember> members;
  final VoidCallback onSearch;
  final VoidCallback? onOpenMembers;
  final ValueChanged<ChatMember>? onOpenMember;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final resolvedCount = memberCount > 0 ? memberCount : members.length;
    final shownMembers = members.take(8).toList(growable: false);
    return Container(
      key: const ValueKey('desktopChatContextMembers'),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AppInteractiveSurface(
            key: const ValueKey('desktopChatContextMembersHeader'),
            onTap: onOpenMembers,
            child: SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStringKeys.chatInfoGroupMembers.l10n(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.callout(
                          c.textPrimary,
                          weight: AppTextWeight.medium,
                        ),
                      ),
                    ),
                    Text(
                      '$resolvedCount',
                      style: AppTextStyle.caption(c.textSecondary),
                    ),
                    if (onOpenMembers != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      AppIcon(
                        HeroAppIcons.chevronRight,
                        size: AppIconSize.sm,
                        color: c.textTertiary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.divider),
          _SearchAction(onSearch: onSearch),
          if (members.isNotEmpty) ...[
            Divider(height: 1, thickness: 1, color: c.divider),
            for (var index = 0; index < shownMembers.length; index++) ...[
              _MemberRow(
                member: shownMembers[index],
                onTap: onOpenMember == null
                    ? onOpenMembers
                    : () => onOpenMember!(shownMembers[index]),
              ),
              if (index < shownMembers.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Divider(height: 1, thickness: 1, color: c.divider),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});

  final ChatMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      onTap: onTap,
      child: SizedBox(
        key: ValueKey('desktopChatContextMember-${member.id}'),
        height: 42,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              PhotoAvatar(
                title: member.name,
                photo: member.photo,
                size: 28,
                allowAnimation: false,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote(c.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('desktopChatContextPrivateActions'),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: _SearchAction(onSearch: onSearch),
    );
  }
}

class _SearchAction extends StatelessWidget {
  const _SearchAction({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: const ValueKey('desktopChatContextSearch'),
      onTap: onSearch,
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: AppIconSize.md,
                color: c.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  AppStringKeys.chatInfoSearchHistory.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote(c.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullInfoCard extends StatelessWidget {
  const _FullInfoCard({required this.onOpenFullInfo});

  final VoidCallback onOpenFullInfo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: const ValueKey('desktopChatContextOpenFullInfo'),
      onTap: onOpenFullInfo,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider),
        ),
        child: Row(
          children: [
            AppIcon(
              HeroAppIcons.gear,
              size: AppIconSize.md,
              color: c.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                AppStringKeys.chatInfoTitle.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote(c.textPrimary),
              ),
            ),
            AppIcon(
              HeroAppIcons.chevronRight,
              size: AppIconSize.sm,
              color: c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: AppInteractiveSurface(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: AppMetric.hitTarget,
          height: AppMetric.hitTarget,
          child: Center(
            child: AppIcon(icon, size: AppIconSize.lg, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}
