//
//  expanded_reaction_picker.dart
//
//  The full reaction picker shown when the quick reaction bar's expand button
//  is tapped. Mirrors Telegram iOS's expanded picker structure: a "Recent"
//  row of the user's own recently picked reactions first, then "All reactions"
//  with everything the server allows on this message, plus premium custom
//  emoji packs via the tab strip. The surface itself is anchored by the
//  caller (chat_view) — this widget only fills the size it is given.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'custom_emoji.dart';
import 'emoji_store.dart';
import 'message_reaction_availability.dart';
import 'quick_reaction_choice.dart';

/// One emoji slot in the picker: scale-pops on tap, then reports the choice.
///
/// iOS animates a fly-out toward the message on select; Mithka's reaction
/// overlay dismisses immediately, so the pop doubles as the press feedback.
/// Reduced motion renders the glyph statically and still fires the tap.
@visibleForTesting
class ReactionPickerPopTile extends StatefulWidget {
  const ReactionPickerPopTile({
    super.key,
    required this.child,
    required this.onTap,
    this.peakScale = 1.35,
  });

  /// Overshoot scale at the pop's peak.
  static const defaultPeakScale = 1.35;
  static const popDuration = Duration(milliseconds: 220);

  final Widget child;
  final VoidCallback onTap;
  final double peakScale;

  @override
  State<ReactionPickerPopTile> createState() => _ReactionPickerPopTileState();
}

class _ReactionPickerPopTileState extends State<ReactionPickerPopTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ReactionPickerPopTile.popDuration,
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: widget.peakScale),
      weight: 0.35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: widget.peakScale, end: 1.0),
      weight: 1,
    ),
  ]).animate(CurvedAnimation(parent: _controller, curve: AppMotion.standard));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    if (!AppMotion.isReduced(context) &&
        _controller.status != AnimationStatus.forward &&
        _controller.status != AnimationStatus.completed) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.isReduced(context);
    final tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: Center(child: widget.child),
    );
    if (reduced) return tile;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: tile,
    );
  }
}

class ExpandedReactionPicker extends StatelessWidget {
  const ExpandedReactionPicker({
    super.key,
    required this.availability,
    required this.tab,
    required this.recents,
    required this.onReaction,
    required this.onTabChanged,
    required this.onOpenSettings,
    this.packs = const <CustomEmojiPack>[],
  });

  static const tabStandard = 'standard';

  /// Widest comfortable picker: beyond this the emoji tiles drift too far
  /// apart to scan. The caller clamps against the screen for narrow phones.
  static const maxWidth = 340.0;
  static const preferredHeight = 320.0;
  static const tabStripHeight = 46.0;
  static const reactionEmojiSize = 28.0;

  final MessageReactionAvailability availability;
  final String tab;
  final List<QuickReactionChoice> recents;
  final ValueChanged<QuickReactionChoice> onReaction;
  final ValueChanged<String> onTabChanged;
  final VoidCallback onOpenSettings;
  final List<CustomEmojiPack> packs;

  /// Clamps the picker into the viewport with [margin] to spare on every side.
  static Size sizeFor({
    required Size screen,
    EdgeInsets safeArea = EdgeInsets.zero,
    double margin = 12,
  }) {
    final width = (screen.width - margin * 2).clamp(0.0, maxWidth);
    final height = (screen.height - safeArea.top - safeArea.bottom - margin * 2)
        .clamp(0.0, preferredHeight);
    return Size(width, height);
  }

  /// Recents this message actually accepts, canonicalized so sending one goes
  /// through the exact choice the server advertised.
  List<QuickReactionChoice> recentChoices() {
    final result = <QuickReactionChoice>[];
    final seen = <String>{};
    for (final recent in recents) {
      final canonical = availability.canonicalChoice(recent);
      if (canonical != null && seen.add(canonical.storageValue)) {
        result.add(canonical);
      }
    }
    return result;
  }

  int _columnCount(double width) =>
      ((width - 20) / (reactionEmojiSize + 16)).floor().clamp(6, 8);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('expanded-reaction-picker'),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _columnCount(constraints.maxWidth);
          return Column(
            children: [
              Expanded(child: _content(context, columns)),
              _tabStrip(context),
            ],
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, int columns) {
    if (tab != tabStandard) {
      final id = int.tryParse(tab);
      CustomEmojiPack? pack;
      for (final candidate in packs) {
        if (candidate.id == id) {
          pack = candidate;
          break;
        }
      }
      if (pack != null) {
        return _grid(
          columns,
          children: [
            for (final item in pack.emoji)
              if (item.customEmojiId != 0)
                ReactionPickerPopTile(
                  key: ValueKey(
                    'expanded-reaction-custom:${item.customEmojiId}',
                  ),
                  onTap: () => onReaction(
                    QuickReactionChoice.custom(item.customEmojiId),
                  ),
                  child: CustomEmojiView(
                    id: item.customEmojiId,
                    size: reactionEmojiSize,
                    color: Colors.white,
                  ),
                ),
          ],
        );
      }
    }
    final recents = recentChoices();
    return ListView(
      key: const ValueKey('expanded-reaction-list'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        if (recents.isNotEmpty) ...[
          _sectionHeader(
            key: const ValueKey('expanded-reaction-recent-header'),
            label: context.l10n.t(AppStringKeys.chatStickerPacksSortRecent),
          ),
          _section(recents, columns, keyPrefix: 'expanded-reaction-recent'),
          const SizedBox(height: 10),
        ],
        if (availability.choices.isNotEmpty) ...[
          _sectionHeader(
            key: const ValueKey('expanded-reaction-all-header'),
            label: context.l10n.t(AppStringKeys.groupAdminAllReactions),
          ),
          _section(availability.choices, columns),
        ],
      ],
    );
  }

  Widget _sectionHeader({required Key key, required String label}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white54,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _section(
    List<QuickReactionChoice> choices,
    int columns, {
    String keyPrefix = 'expanded-reaction',
  }) {
    final rows = <Widget>[];
    for (var start = 0; start < choices.length; start += columns) {
      final row = choices.skip(start).take(columns).toList();
      rows.add(
        Row(
          children: [
            for (var index = 0; index < columns; index++)
              Expanded(
                child: index < row.length
                    ? SizedBox(
                        height: 44,
                        child: ReactionPickerPopTile(
                          key: ValueKey(
                            '$keyPrefix-${row[index].storageValue}',
                          ),
                          onTap: () => onReaction(row[index]),
                          child: row[index].isCustom
                              ? CustomEmojiView(
                                  id: row[index].customEmojiId,
                                  size: reactionEmojiSize,
                                  color: Colors.white,
                                )
                              : Text(
                                  row[index].emoji,
                                  textScaler: TextScaler.noScaling,
                                  style: const TextStyle(
                                    fontSize: reactionEmojiSize,
                                  ),
                                ),
                        ),
                      )
                    : const SizedBox(height: 44),
              ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _grid(int columns, {required List<Widget> children}) {
    return GridView.count(
      crossAxisCount: columns,
      padding: const EdgeInsets.all(10),
      childAspectRatio: 0.95,
      children: children,
    );
  }

  Widget _tabStrip(BuildContext context) {
    return Container(
      height: tabStripHeight,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF3A3A3C), width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              children: [
                _tabButton(
                  tabStandard,
                  const AppIcon(
                    HeroAppIcons.solidFaceSmile,
                    size: 22,
                    color: Colors.white70,
                  ),
                ),
                for (final pack in packs)
                  _tabButton(
                    pack.id.toString(),
                    pack.emoji.isNotEmpty && pack.emoji.first.customEmojiId != 0
                        ? CustomEmojiView(
                            id: pack.emoji.first.customEmojiId,
                            size: 26,
                            color: Colors.white,
                          )
                        : const AppIcon(
                            HeroAppIcons.objectGroup,
                            size: 20,
                            color: Colors.white70,
                          ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            key: const ValueKey('quick-reaction-settings'),
            behavior: HitTestBehavior.opaque,
            onTap: onOpenSettings,
            child: const SizedBox(
              width: 44,
              height: tabStripHeight,
              child: Center(
                child: AppIcon(
                  HeroAppIcons.gear,
                  size: 21,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String key, Widget child) {
    final selected = tab == key;
    return GestureDetector(
      key: ValueKey('expanded-reaction-tab-$key'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onTabChanged(key),
      child: Container(
        width: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A4A4E) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: SizedBox(width: 28, height: 28, child: Center(child: child)),
      ),
    );
  }
}
