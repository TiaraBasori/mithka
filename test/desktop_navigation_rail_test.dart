import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/app/desktop_navigation_rail.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'desktop rail keeps a fixed width and exposes every destination',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController(await SharedPreferences.getInstance());
      addTearDown(theme.dispose);
      var selection = -1;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 500,
                child: DesktopNavigationRail(
                  destinations: const [
                    DesktopNavigationDestination(
                      label: 'Messages',
                      icon: HeroAppIcons.solidMessage,
                    ),
                    DesktopNavigationDestination(
                      label: 'Contacts',
                      icon: HeroAppIcons.users,
                    ),
                  ],
                  selection: 0,
                  unread: 4,
                  onClearUnread: () {},
                  onSelect: (value) => selection = value,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester
            .getSize(find.byKey(const ValueKey('desktop-navigation-rail')))
            .width,
        desktopNavigationRailWidth,
      );
      expect(find.bySemanticsLabel('Messages'), findsOneWidget);
      expect(find.bySemanticsLabel('Contacts'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Contacts'));
      expect(selection, 1);
    },
  );
}
