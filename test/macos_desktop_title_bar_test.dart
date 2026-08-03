import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/macos_desktop_title_bar.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets('desktop title bar reserves native chrome and drag geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            child: MacosDesktopTitleBar(
              appIdentity: SizedBox(width: 112, child: Text('Mithka')),
              accountIdentity: SizedBox(width: 96, child: Text('Account')),
            ),
          ),
        ),
      ),
    );

    final titleBar = find.byKey(const ValueKey('macos-desktop-title-bar'));
    final trafficLightClearance = find.byKey(
      const ValueKey('macos-traffic-light-clearance'),
    );
    final dragArea = find.byKey(const ValueKey('macos-title-bar-drag-area'));

    expect(tester.getSize(titleBar).height, MacosDesktopTitleBar.height);
    expect(
      tester.getSize(trafficLightClearance).width,
      MacosDesktopTitleBar.trafficLightLeadingClearance,
    );
    expect(tester.getSize(dragArea).width, greaterThan(250));
    expect(find.byKey(const ValueKey('macos-app-identity')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('macos-account-identity')),
      findsOneWidget,
    );

    final decoration = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('macos-desktop-title-bar-decoration')),
    );
    final boxDecoration = decoration.decoration as BoxDecoration;
    final border = boxDecoration.border as Border;
    expect(border.bottom.width, MacosDesktopTitleBar.dividerWidth);
  });

  test('native macOS window uses full-size transparent titlebar chrome', () {
    final runner = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(runner, contains('titleVisibility = .hidden'));
    expect(runner, contains('titlebarAppearsTransparent = true'));
    expect(runner, contains('styleMask.insert(.fullSizeContentView)'));
    expect(runner, contains('titlebarSeparatorStyle = .none'));
    expect(runner, isNot(contains('standardWindowButton')));
  });

  test('window drag entry point stays portable outside desktop IO builds', () {
    final entryPoint = File(
      'lib/app/desktop_window_drag_area.dart',
    ).readAsStringSync();
    final stub = File(
      'lib/app/desktop_window_drag_area_stub.dart',
    ).readAsStringSync();

    expect(entryPoint, contains('if (dart.library.io)'));
    expect(entryPoint, isNot(contains("import 'dart:io'")));
    expect(entryPoint, isNot(contains('package:multi_window_manager/')));
    expect(stub, isNot(contains('multi_window_manager')));
  });
}
