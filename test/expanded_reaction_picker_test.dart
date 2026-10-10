import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/emoji_store.dart';
import 'package:mithka/chat/expanded_reaction_picker.dart';
import 'package:mithka/chat/message_reaction_availability.dart';
import 'package:mithka/chat/quick_reaction_choice.dart';
import 'package:mithka/chat/recent_reactions_store.dart';

Map<String, dynamic> _emoji(String emoji, {bool premium = false}) => {
  '@type': 'availableReaction',
  'type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
  'needs_premium': premium,
};

MessageReactionAvailability _availability({
  List<String> top = const ['👍', '❤️', '🔥', '🎉', '😁', '😢', '😡'],
  List<String> popular = const ['🤔', '👏'],
  bool allowCustom = false,
}) => MessageReactionAvailability.fromTd({
  '@type': 'availableReactions',
  'top_reactions': [for (final e in top) _emoji(e)],
  'recent_reactions': <Map<String, dynamic>>[],
  'popular_reactions': [for (final e in popular) _emoji(e)],
  'allow_custom_emoji': allowCustom,
  'are_tags': false,
  'unavailability_reason': null,
}, isPremium: false);

Future<void> _pumpPicker(
  WidgetTester tester, {
  required MessageReactionAvailability availability,
  List<QuickReactionChoice> recents = const [],
  ValueChanged<QuickReactionChoice>? onReaction,
  VoidCallback? onOpenSettings,
  Size surface = const Size(400, 900),
  EdgeInsets safeArea = EdgeInsets.zero,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final size = ExpandedReactionPicker.sizeFor(
    screen: surface,
    safeArea: safeArea,
  );
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: surface, padding: safeArea),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: size,
              child: ExpandedReactionPicker(
                availability: availability,
                tab: ExpandedReactionPicker.tabStandard,
                recents: recents,
                onReaction: onReaction ?? (_) {},
                onTabChanged: (_) {},
                onOpenSettings: onOpenSettings ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recent section leads, then all reactions, tap sends choice', (
    tester,
  ) async {
    QuickReactionChoice? sent;
    await _pumpPicker(
      tester,
      availability: _availability(),
      recents: const [
        QuickReactionChoice.emoji('🔥'),
        QuickReactionChoice.emoji('🎉'),
      ],
      onReaction: (choice) => sent = choice,
    );

    // Both section headers render, recents first.
    final recentHeader = find.byKey(
      const ValueKey('expanded-reaction-recent-header'),
    );
    final allHeader = find.byKey(
      const ValueKey('expanded-reaction-all-header'),
    );
    expect(recentHeader, findsOneWidget);
    expect(allHeader, findsOneWidget);
    expect(
      tester.getTopLeft(recentHeader).dy < tester.getTopLeft(allHeader).dy,
      isTrue,
    );

    // The recents row carries its own keys and fires the exact choice.
    final recentTile = find.byKey(
      const ValueKey('expanded-reaction-recent-emoji:🔥'),
    );
    expect(recentTile, findsOneWidget);
    await tester.tap(recentTile);
    expect(sent, const QuickReactionChoice.emoji('🔥'));

    // The all-reactions section also sends through the canonical choice.
    sent = null;
    await tester.tap(find.byKey(const ValueKey('expanded-reaction-emoji:👏')));
    expect(sent, const QuickReactionChoice.emoji('👏'));
  });

  testWidgets('empty recents hide the section; unavailable recents filtered', (
    tester,
  ) async {
    await _pumpPicker(tester, availability: _availability());
    expect(
      find.byKey(const ValueKey('expanded-reaction-recent-header')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('expanded-reaction-all-header')),
      findsOneWidget,
    );

    // Recents that this chat does not allow never reach the grid.
    await _pumpPicker(
      tester,
      availability: _availability(top: ['👍'], popular: []),
      recents: const [
        QuickReactionChoice.emoji('🎉'),
        QuickReactionChoice.custom(42),
      ],
    );
    expect(
      find.byKey(const ValueKey('expanded-reaction-recent-header')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('expanded-reaction-recent-emoji:🎉')),
      findsNothing,
    );
  });

  testWidgets(
    'no custom pack tabs without allowArbitraryCustom; gear opens settings',
    (tester) async {
      var opened = false;
      await _pumpPicker(
        tester,
        availability: _availability(),
        onOpenSettings: () => opened = true,
      );
      expect(
        find.byKey(const ValueKey('expanded-reaction-tab-standard')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('quick-reaction-settings')));
      expect(opened, isTrue);
      expect(EmojiStore.shared.customPacks, isEmpty);
    },
  );

  testWidgets('selection fires immediately even under reduced motion', (
    tester,
  ) async {
    QuickReactionChoice? sent;
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 900),
          disableAnimations: true,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                height: 320,
                child: ExpandedReactionPicker(
                  availability: _availability(),
                  tab: ExpandedReactionPicker.tabStandard,
                  recents: const [],
                  onReaction: (choice) => sent = choice,
                  onTabChanged: (_) {},
                  onOpenSettings: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expanded-reaction-emoji:👍')));
    expect(sent, const QuickReactionChoice.emoji('👍'));
  });

  test('sizeFor clamps narrow phones and tall screens', () {
    final narrow = ExpandedReactionPicker.sizeFor(screen: const Size(320, 568));
    expect(narrow.width, 320 - 24);
    expect(narrow.height, ExpandedReactionPicker.preferredHeight);

    final short = ExpandedReactionPicker.sizeFor(
      screen: const Size(800, 300),
      safeArea: const EdgeInsets.only(top: 40, bottom: 20),
    );
    expect(short.width, ExpandedReactionPicker.maxWidth);
    expect(short.height, 300 - 40 - 20 - 24);

    final tablet = ExpandedReactionPicker.sizeFor(
      screen: const Size(1024, 1366),
    );
    expect(
      tablet,
      const Size(
        ExpandedReactionPicker.maxWidth,
        ExpandedReactionPicker.preferredHeight,
      ),
    );
  });

  test('recents storage round-trips through the store key', () {
    // Guards the storageValue contract the picker's keys rely on.
    const choice = QuickReactionChoice.custom(99);
    expect(RecentReactionsStore.decodeStored('["custom:99"]'), const [choice]);
  });
}
