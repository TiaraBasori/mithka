//
//  recent_reactions_store.dart
//
//  Device-local history of reactions the user actually picks, powering the
//  "Recent" section at the top of the expanded reaction picker — the same
//  lead-with-recents organization Telegram iOS uses. Entries are stored as
//  QuickReactionChoice storage values, so standard emoji and premium custom
//  emoji share one list.
//
//  Simplification on purpose: the list is shared across every account on this
//  device. Recents are a convenience ordering, not user data — a stale entry
//  is filtered against the message's availability before it is ever shown or
//  sent, so cross-account bleed can at most surface an emoji the other
//  account also reacts with.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quick_reaction_choice.dart';

class RecentReactionsStore extends ChangeNotifier {
  RecentReactionsStore._();

  static final RecentReactionsStore shared = RecentReactionsStore._();

  static const storageKey = 'recentReactions.v1';

  /// Enough history to fill two picker rows on a tablet without turning the
  /// section into a second full grid.
  static const maxRecents = 16;

  List<QuickReactionChoice> _recents = const [];
  bool _loaded = false;

  /// Most recently used first. Never contains duplicates by storage value.
  List<QuickReactionChoice> get recents => _recents;

  /// Reads the persisted list. Idempotent: callers may invoke it every time
  /// the reaction menu opens.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final decoded = decodeStored(prefs.getString(storageKey));
    if (!listEquals(decoded, _recents)) {
      _recents = decoded;
      notifyListeners();
    }
  }

  /// Records a reaction the user picked, moving it to the front.
  Future<void> record(QuickReactionChoice choice) async {
    final next = mergedWith(_recents, choice);
    if (listEquals(next, _recents)) return;
    _recents = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(next.map((item) => item.storageValue).toList()),
    );
  }

  /// Drops everything; used by tests and available for a future "clear
  /// history" affordance.
  Future<void> clear() async {
    _recents = const [];
    _loaded = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  @visibleForTesting
  void resetForTesting() {
    _recents = const [];
    _loaded = false;
  }

  /// Parses a persisted list, discarding entries that no longer decode into a
  /// valid choice and enforcing the cap.
  @visibleForTesting
  static List<QuickReactionChoice> decodeStored(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <QuickReactionChoice>[];
      final seen = <String>{};
      for (final value in decoded) {
        if (value is! String) continue;
        final choice = QuickReactionChoice.fromStorage(value);
        if (choice == null || !seen.add(choice.storageValue)) continue;
        result.add(choice);
        if (result.length >= maxRecents) break;
      }
      return List.unmodifiable(result);
    } catch (_) {
      return const [];
    }
  }

  /// Move-to-front insert with deduplication and the cap applied.
  @visibleForTesting
  static List<QuickReactionChoice> mergedWith(
    List<QuickReactionChoice> current,
    QuickReactionChoice choice, {
    int limit = maxRecents,
  }) {
    final next = <QuickReactionChoice>[
      choice,
      for (final item in current)
        if (item.storageValue != choice.storageValue) item,
    ];
    return List.unmodifiable(next.take(limit).toList());
  }
}
