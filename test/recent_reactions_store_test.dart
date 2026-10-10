import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_reaction_availability.dart';
import 'package:mithka/chat/quick_reaction_choice.dart';
import 'package:mithka/chat/recent_reactions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RecentReactionsStore.shared.resetForTesting();
  });

  test(
    'records picks move-to-front and persists across store reloads',
    () async {
      final store = RecentReactionsStore.shared;
      await store.load();
      expect(store.recents, isEmpty);

      await store.record(const QuickReactionChoice.emoji('🔥'));
      await store.record(const QuickReactionChoice.custom(42));
      await store.record(const QuickReactionChoice.emoji('🔥'));

      expect(store.recents, const [
        QuickReactionChoice.emoji('🔥'),
        QuickReactionChoice.custom(42),
      ]);

      final restored = RecentReactionsStore.shared;
      restored.resetForTesting();
      await restored.load();
      expect(restored.recents, const [
        QuickReactionChoice.emoji('🔥'),
        QuickReactionChoice.custom(42),
      ]);
    },
  );

  test('caps the persisted history at the maximum', () async {
    final store = RecentReactionsStore.shared;
    await store.load();
    for (final emoji in availableStandardReactions) {
      await store.record(QuickReactionChoice.emoji(emoji));
    }
    expect(store.recents, hasLength(RecentReactionsStore.maxRecents));
    // Most recent pick leads; oldest overflowed off the end.
    expect(store.recents.first, const QuickReactionChoice.emoji('😴'));

    store.resetForTesting();
    await store.load();
    expect(store.recents, hasLength(RecentReactionsStore.maxRecents));
  });

  test('decoding drops duplicates, garbage, and over-cap entries', () {
    final decoded = RecentReactionsStore.decodeStored(
      '["emoji:👍",42,"emoji:👍","custom:notAnId","emoji:","emoji:🔥"]',
    );
    expect(decoded, const [
      QuickReactionChoice.emoji('👍'),
      QuickReactionChoice.emoji('🔥'),
    ]);
    expect(RecentReactionsStore.decodeStored('not json'), isEmpty);
    expect(RecentReactionsStore.decodeStored(null), isEmpty);
    expect(RecentReactionsStore.decodeStored('{"a":1}'), isEmpty);
  });

  test('mergedWith dedupes by storage value and applies the limit', () {
    final merged = RecentReactionsStore.mergedWith(const [
      QuickReactionChoice.emoji('👍'),
      QuickReactionChoice.emoji('❤️'),
      QuickReactionChoice.custom(7),
    ], const QuickReactionChoice.emoji('❤️'));
    expect(merged, const [
      QuickReactionChoice.emoji('❤️'),
      QuickReactionChoice.emoji('👍'),
      QuickReactionChoice.custom(7),
    ]);

    final capped = RecentReactionsStore.mergedWith(
      const [QuickReactionChoice.emoji('👍'), QuickReactionChoice.emoji('❤️')],
      const QuickReactionChoice.emoji('🔥'),
      limit: 2,
    );
    expect(capped, const [
      QuickReactionChoice.emoji('🔥'),
      QuickReactionChoice.emoji('👍'),
    ]);
  });

  test('clear empties the store and the persisted value', () async {
    final store = RecentReactionsStore.shared;
    await store.load();
    await store.record(const QuickReactionChoice.emoji('🎉'));
    await store.clear();
    expect(store.recents, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(RecentReactionsStore.storageKey), isNull);
  });

  test('recording notifies listeners only on change', () async {
    final store = RecentReactionsStore.shared;
    await store.load();
    var notifications = 0;
    store.addListener(() => notifications++);
    await store.record(const QuickReactionChoice.emoji('👍'));
    expect(notifications, 1);
    await store.record(const QuickReactionChoice.emoji('👍'));
    expect(notifications, 1);
  });

  group('filtering against availability', () {
    MessageReactionAvailability availability({
      required List<String> emoji,
      bool allowCustom = false,
      bool isPremium = false,
    }) => MessageReactionAvailability.fromTd({
      '@type': 'availableReactions',
      'top_reactions': [
        for (final value in emoji)
          {
            '@type': 'availableReaction',
            'type': {'@type': 'reactionTypeEmoji', 'emoji': value},
            'needs_premium': false,
          },
      ],
      'recent_reactions': <Map<String, dynamic>>[],
      'popular_reactions': <Map<String, dynamic>>[],
      'allow_custom_emoji': allowCustom,
      'are_tags': false,
      'unavailability_reason': null,
    }, isPremium: isPremium);

    test('recents unavailable in this chat are filtered, not sent', () {
      final available = availability(emoji: ['👍', '🔥']);
      const recents = [
        QuickReactionChoice.emoji('🎉'), // not available here
        QuickReactionChoice.emoji('🔥'),
        QuickReactionChoice.custom(42), // premium-only entry
        QuickReactionChoice.emoji('👍'),
        QuickReactionChoice.emoji('🔥'), // duplicate
      ];
      final filtered = <QuickReactionChoice>[];
      final seen = <String>{};
      for (final recent in recents) {
        final canonical = available.canonicalChoice(recent);
        if (canonical != null && seen.add(canonical.storageValue)) {
          filtered.add(canonical);
        }
      }
      expect(filtered, const [
        QuickReactionChoice.emoji('🔥'),
        QuickReactionChoice.emoji('👍'),
      ]);
      for (final choice in filtered) {
        expect(available.allows(choice), isTrue);
      }
    });

    test('custom recents survive when arbitrary custom is allowed', () {
      final available = availability(
        emoji: ['👍'],
        allowCustom: true,
        isPremium: true,
      );
      expect(
        available.canonicalChoice(const QuickReactionChoice.custom(42)),
        const QuickReactionChoice.custom(42),
      );
    });
  });
}
