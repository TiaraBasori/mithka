import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_appearance_preview.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sender name readability plate is off by default and persists',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final controller = ThemeController(preferences);

      expect(controller.showSenderNameReadabilityPlate, isFalse);

      controller.showSenderNameReadabilityPlate = true;
      expect(controller.showSenderNameReadabilityPlate, isTrue);
      expect(preferences.getBool('showSenderNameReadabilityPlate'), isTrue);

      final restored = ThemeController(preferences);
      expect(restored.showSenderNameReadabilityPlate, isTrue);
    },
  );

  testWidgets('sender name plate only decorates its child when enabled', (
    tester,
  ) async {
    Future<void> pump(bool enabled) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SenderNameReadabilityPlate(
          enabled: enabled,
          bubbleColor: const Color(0xFF223344),
          child: const Text('Bob Harris'),
        ),
      ),
    );

    await pump(false);
    expect(
      find.byKey(const ValueKey('senderNameReadabilityPlate')),
      findsNothing,
    );

    await pump(true);
    expect(
      find.byKey(const ValueKey('senderNameReadabilityPlate')),
      findsOneWidget,
    );
    final decoration = senderNameReadabilityDecoration(const Color(0xFF223344));
    expect(decoration.borderRadius, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
  });
}
