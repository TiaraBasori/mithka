import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/developer_badge.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [AppLocalizations.delegate],
  theme: ThemeData(extensions: [AppColors.light]),
  home: Scaffold(body: Center(child: child)),
);

const _avatar = SizedBox.square(key: ValueKey('avatar'), dimension: 88);

void main() {
  test('only the listed accounts are developers', () {
    for (final id in [5555116287, 7041948142, 176871465, 5896096480]) {
      expect(isMithkaDeveloper(id), isTrue, reason: '$id');
    }
    expect(isMithkaDeveloper(null), isFalse);
    expect(isMithkaDeveloper(777000), isFalse);
  });

  testWidgets('other users keep the bare avatar', (tester) async {
    final avatar = DeveloperAvatarBadge.wrap(
      userId: 42,
      avatarSize: 88,
      child: _avatar,
    );
    expect(identical(avatar, _avatar), isTrue);
    await tester.pumpWidget(_app(avatar));
    expect(find.byType(DeveloperBadge), findsNothing);
  });

  testWidgets('a developer avatar carries the badge at its bottom-right', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        DeveloperAvatarBadge.wrap(
          userId: 7041948142,
          avatarSize: 88,
          child: _avatar,
        ),
      ),
    );
    final avatar = tester.getRect(find.byKey(const ValueKey('avatar')));
    final badge = tester.getRect(find.byType(DeveloperBadge));
    expect(badge.center.dx, greaterThan(avatar.center.dx));
    expect(badge.center.dy, greaterThan(avatar.center.dy));
    expect(avatar.contains(badge.bottomRight - const Offset(1, 1)), isTrue);
    expect(find.byKey(const ValueKey('developerBadgeTapTarget')), findsNothing);
  });

  testWidgets('tapping the profile badge explains it and dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        DeveloperAvatarBadge.wrap(
          userId: 5555116287,
          avatarSize: 88,
          interactive: true,
          child: _avatar,
        ),
      ),
    );
    final target = find.byKey(const ValueKey('developerBadgeTapTarget'));
    expect(find.text('Mithka Developer'), findsNothing);

    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('Mithka Developer'), findsOneWidget);
    expect(
      find.text('A core developer who helps build and maintain Mithka.'),
      findsOneWidget,
    );
    final bubble = tester.getRect(
      find.byKey(const ValueKey('developerBadgeBubble')),
    );
    expect(bubble.bottom, lessThanOrEqualTo(tester.getRect(target).top));

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Mithka Developer'), findsNothing);

    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('Mithka Developer'), findsOneWidget);
    await tester.pump(DeveloperBadgeInfoTarget.autoDismissAfter);
    await tester.pumpAndSettle();
    expect(find.text('Mithka Developer'), findsNothing);
  });
}
