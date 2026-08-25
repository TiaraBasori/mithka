// The reaction strip a desktop pointer reveals by resting on a message: what
// makes it appear, where it lands beside the bubble, and that a pointer can
// travel from the bubble onto it without it vanishing on the way.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/message_reaction_availability.dart';
import 'package:mithka/chat/quick_reaction_choice.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _strip = ValueKey('hover-reaction-bar');
const _expand = ValueKey('hover-reaction-expand');

MessageReactionAvailability _availability({
  List<String> emoji = const ['👍', '❤️', '🔥', '🎉', '😁'],
  bool allowArbitraryCustom = false,
}) => MessageReactionAvailability.fallback(
  choices: [for (final value in emoji) QuickReactionChoice.emoji(value)],
  allowArbitraryCustom: allowArbitraryCustom,
);

ChatMessage _message({
  int id = 900,
  bool isOutgoing = false,
  String text = 'ok',
}) => ChatMessage(
  id: id,
  isOutgoing: isOutgoing,
  text: text,
  date: 1,
  contentType: 'messageText',
);

Future<TestGesture> _hover(WidgetTester tester, Offset location) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(location);
  await tester.pump();
  // The dwell the bubble waits out before it asks what it may be reacted with,
  // then the query, then the strip's entry animation.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return gesture;
}

Future<void> _pumpBubble(
  WidgetTester tester, {
  required ChatMessage message,
  Future<MessageReactionAvailability?> Function(ChatMessage)? resolve,
  void Function(ChatMessage, QuickReactionChoice)? onReaction,
  void Function(ChatMessage, Rect?, MessageReactionAvailability)? onExpand,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          // Given unbounded height rather than the body's own, so the row
          // sizes to its content the way a list item does — the strip is
          // placed against the row's bounds.
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
                onResolveHoverReactions: resolve,
                onHoverReaction: onReaction,
                onExpandHoverReactions: onExpand,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resting on a bubble reveals the strip beside it', (
    tester,
  ) async {
    final message = _message();
    await _pumpBubble(
      tester,
      message: message,
      resolve: (_) async => _availability(),
    );

    expect(find.byKey(_strip), findsNothing);
    final bubble = find.byKey(const ValueKey('messageTapTarget-900'));
    await _hover(tester, tester.getCenter(bubble));

    expect(find.byKey(_strip), findsOneWidget);
    // An incoming bubble is left-aligned, so the strip takes the gutter on its
    // right, and stays inside the row: a child painted outside takes no hits.
    expect(
      tester.getTopLeft(find.byKey(_strip)).dx,
      greaterThanOrEqualTo(tester.getBottomRight(bubble).dx),
    );
    expect(
      tester.getBottomRight(find.byKey(_strip)).dx,
      lessThanOrEqualTo(800 - 12 + 0.01),
    );
  });

  testWidgets('an outgoing bubble puts the strip on its left', (tester) async {
    final message = _message(id: 901, isOutgoing: true);
    await _pumpBubble(
      tester,
      message: message,
      resolve: (_) async => _availability(),
    );

    final bubble = find.byKey(const ValueKey('messageTapTarget-901'));
    await _hover(tester, tester.getCenter(bubble));

    expect(find.byKey(_strip), findsOneWidget);
    expect(
      tester.getBottomRight(find.byKey(_strip)).dx,
      lessThanOrEqualTo(tester.getTopLeft(bubble).dx),
    );
    expect(tester.getTopLeft(find.byKey(_strip)).dx, greaterThanOrEqualTo(12));
  });

  testWidgets('a bubble too wide for a gutter keeps the strip reachable', (
    tester,
  ) async {
    final message = _message(
      id: 902,
      text: 'a message long enough to run out to the bubble width cap ' * 4,
    );
    await _pumpBubble(
      tester,
      message: message,
      resolve: (_) async => _availability(),
    );

    final bubble = find.byKey(const ValueKey('messageTapTarget-902'));
    await _hover(tester, tester.getCenter(bubble));

    final strip = tester.getRect(find.byKey(_strip));
    expect(strip.right, closeTo(800 - 12, 0.01));
    // It has slid over the bubble's corner rather than off the row.
    expect(strip.left, lessThan(tester.getBottomRight(bubble).dx));
  });

  testWidgets('the pointer can travel from the bubble onto the strip', (
    tester,
  ) async {
    final message = _message();
    QuickReactionChoice? reacted;
    await _pumpBubble(
      tester,
      message: message,
      resolve: (_) async => _availability(),
      onReaction: (_, reaction) => reacted = reaction,
    );

    final bubble = find.byKey(const ValueKey('messageTapTarget-900'));
    final gesture = await _hover(tester, tester.getCenter(bubble));

    await gesture.moveTo(tester.getCenter(find.byKey(_strip)));
    await tester.pump();
    expect(find.byKey(_strip), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hover-reaction-emoji:👍')));
    await tester.pump();
    expect(reacted, const QuickReactionChoice.emoji('👍'));
  });

  testWidgets('leaving the bubble takes the strip with it', (tester) async {
    final message = _message();
    await _pumpBubble(
      tester,
      message: message,
      resolve: (_) async => _availability(),
    );

    final bubble = find.byKey(const ValueKey('messageTapTarget-900'));
    final gesture = await _hover(tester, tester.getCenter(bubble));

    await gesture.moveTo(const Offset(400, 580));
    await tester.pump();
    expect(find.byKey(_strip), findsNothing);
  });

  testWidgets('the expand button hands over the bubble and its choices', (
    tester,
  ) async {
    final availability = _availability();
    final message = _message();
    ChatMessage? expanded;
    Rect? bounds;
    MessageReactionAvailability? handed;
    await _pumpBubble(
      tester,
      message: message,
      resolve: (_) async => availability,
      onExpand: (value, rect, choices) {
        expanded = value;
        bounds = rect;
        handed = choices;
      },
    );

    await _hover(
      tester,
      tester.getCenter(find.byKey(const ValueKey('messageTapTarget-900'))),
    );
    await tester.tap(find.byKey(_expand));
    await tester.pump();

    expect(expanded, same(message));
    expect(handed, same(availability));
    expect(
      bounds,
      tester.getRect(find.byKey(const ValueKey('messageTapTarget-900'))),
    );
  });

  testWidgets('a message that takes no reaction shows no strip', (
    tester,
  ) async {
    await _pumpBubble(
      tester,
      message: _message(),
      resolve: (_) async => _availability(emoji: const []),
    );

    await _hover(
      tester,
      tester.getCenter(find.byKey(const ValueKey('messageTapTarget-900'))),
    );
    expect(find.byKey(_strip), findsNothing);
  });

  testWidgets('a failed availability query leaves the strip closed', (
    tester,
  ) async {
    await _pumpBubble(tester, message: _message(), resolve: (_) async => null);

    await _hover(
      tester,
      tester.getCenter(find.byKey(const ValueKey('messageTapTarget-900'))),
    );
    expect(find.byKey(_strip), findsNothing);
  });

  testWidgets('a caller without a pointer never grows the strip', (
    tester,
  ) async {
    await _pumpBubble(tester, message: _message());

    await _hover(
      tester,
      tester.getCenter(find.byKey(const ValueKey('messageTapTarget-900'))),
    );
    expect(find.byKey(_strip), findsNothing);
  });

  testWidgets('the strip stops at the count the gutter can hold', (
    tester,
  ) async {
    await _pumpBubble(
      tester,
      message: _message(),
      resolve: (_) async => _availability(
        emoji: const ['👍', '❤️', '🔥', '🎉', '😁', '😢', '😡'],
      ),
    );

    await _hover(
      tester,
      tester.getCenter(find.byKey(const ValueKey('messageTapTarget-900'))),
    );
    expect(find.byKey(_strip), findsOneWidget);
    expect(
      tester.getSize(find.byKey(_strip)).width,
      HoverReactionBar.widthFor(HoverReactionBar.maxReactionCount),
    );
  });
}
