import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_chat_window.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  DesktopChatWindowArguments arguments({
    int accountSlot = 2,
    int chatId = -10042,
    String title = 'Desktop group',
    bool enterToSend = false,
  }) => DesktopChatWindowArguments(
    accountSlot: accountSlot,
    chatId: chatId,
    title: title,
    localeTag: 'zh-Hans',
    dark: true,
    enterToSend: enterToSend,
    palette: DesktopChatWindowPalette.fromColors(
      AppColors.dark,
      brand: const Color(0xFF7C4DFF),
    ),
  );

  test('chat window arguments round-trip without session material', () {
    final original = arguments(title: 'Group\nname');
    final encoded = original.encode();
    final parsed = DesktopChatWindowArguments.tryParse(encoded);

    expect(parsed?.accountSlot, 2);
    expect(parsed?.chatId, -10042);
    expect(parsed?.title, 'Group name');
    expect(parsed?.localeTag, 'zh-Hans');
    expect(parsed?.enterToSend, isFalse);
    expect(parsed?.palette.brandColor, const Color(0xFF7C4DFF));
    expect(encoded, isNot(contains('session')));
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('phone')));
    expect(encoded, isNot(contains('database')));
  });

  test('main-window and malformed arguments are ignored', () {
    expect(
      DesktopChatWindowArguments.tryParseLaunchArguments(const []),
      isNull,
    );
    expect(DesktopChatWindowArguments.tryParse('not json'), isNull);
    expect(
      DesktopChatWindowArguments.tryParse('{"type":"mithka.video"}'),
      isNull,
    );
  });

  test('registry reuses one active window per account and chat', () {
    final registry = DesktopChatWindowRegistry();
    const first = DesktopChatWindowKey(accountSlot: 0, chatId: 99);
    const otherAccount = DesktopChatWindowKey(accountSlot: 1, chatId: 99);

    registry.register(first, 10);
    expect(registry.activeWindowFor(first, const [10]), 10);

    registry.register(first, 11);
    expect(registry.activeWindowFor(first, const [10, 11]), 11);
    expect(registry.keyForWindow(10), isNull);

    registry.register(otherAccount, 12);
    expect(registry.activeWindowFor(otherAccount, const [11, 12]), 12);
    expect(registry.activeWindowFor(first, const [11, 12]), 11);

    expect(registry.activeWindowFor(first, const [12]), isNull);
    expect(registry.keyForWindow(11), isNull);
  });

  test('IPC authorization fails closed for unknown or mismatched windows', () {
    final registry = DesktopChatWindowRegistry();
    const registered = DesktopChatWindowKey(accountSlot: 0, chatId: 99);
    const otherChat = DesktopChatWindowKey(accountSlot: 0, chatId: 100);
    registry.register(registered, 10);

    expect(
      desktopChatWindowRequestIsRegistered(
        registry: registry,
        windowId: 10,
        requestedKey: registered,
      ),
      isTrue,
    );
    expect(
      desktopChatWindowRequestIsRegistered(
        registry: registry,
        windowId: 11,
        requestedKey: registered,
      ),
      isFalse,
    );
    expect(
      desktopChatWindowRequestIsRegistered(
        registry: registry,
        windowId: 10,
        requestedKey: otherChat,
      ),
      isFalse,
    );

    registry.clear();
    expect(
      desktopChatWindowRequestIsRegistered(
        registry: registry,
        windowId: 10,
        requestedKey: registered,
      ),
      isFalse,
    );
  });

  test('child bootstrap is an IPC view and never owns Telegram lifecycle', () {
    final child = File('lib/app/desktop_chat_window.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final io = File('lib/app/desktop_chat_window_io.dart').readAsStringSync();

    expect(child, isNot(contains('TdClient')));
    expect(child, isNot(contains('AuthManager')));
    expect(child, isNot(contains('ChatViewModel')));
    expect(child, isNot(contains("import '../tdlib/")));
    expect(
      main,
      contains('DesktopChatWindowArguments.tryParseLaunchArguments'),
    );
    expect(main, contains('runApp(DesktopChatWindowApp'));
    expect(io, contains('invokeMethodToWindow(0, _snapshotMethod'));
    expect(io, contains('TdClient.shared.queryTo'));
    expect(io, isNot(contains('TdClient.shared.start')));
    expect(io, contains('registered == null'));
    expect(io, isNot(contains('if (registered == null) _registerWindow')));
  });

  test('desktop child uses platform-appropriate custom title bar controls', () {
    final child = File('lib/app/desktop_chat_window.dart').readAsStringSync();
    final io = File('lib/app/desktop_chat_window_io.dart').readAsStringSync();
    final titleBar = File(
      'lib/app/macos_desktop_title_bar.dart',
    ).readAsStringSync();

    expect(io, contains('TitleBarStyle.hidden'));
    expect(io, contains('windowButtonVisibility: Platform.isMacOS'));
    expect(child, contains('MacosDesktopTitleBar'));
    expect(child, contains('DesktopWindowControls'));
    expect(titleBar, contains('trafficLightLeadingClearance = 78'));
  });

  test('separate-window label is localized in all supported locales', () {
    final expected = <Locale, String>{
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'):
          '打开独立聊天窗口',
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'):
          '開啟獨立聊天視窗',
      const Locale('ja'): '別のチャットウインドウで開く',
      const Locale('ko'): '별도 채팅 창에서 열기',
      const Locale('en'): 'Open in separate chat window',
      const Locale('fr'): 'Ouvrir dans une fenêtre de discussion séparée',
      const Locale('es'): 'Abrir en una ventana de chat separada',
      const Locale('de'): 'In separatem Chatfenster öffnen',
    };

    for (final entry in expected.entries) {
      expect(
        AppLocalizations(entry.key).t(AppStringKeys.desktopChatOpenSeparate),
        entry.value,
      );
    }
  });

  testWidgets('child renders transcript and follows Ctrl-Enter preference', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final controller = _FakeDesktopChatController(
        const DesktopChatWindowSnapshot(
          title: 'Desktop group',
          canSend: true,
          messages: [
            DesktopChatMessageSnapshot(
              id: 1,
              date: 1,
              outgoing: false,
              senderName: 'Alice',
              contentType: 'messageText',
              text: 'Incoming',
            ),
            DesktopChatMessageSnapshot(
              id: 2,
              date: 2,
              outgoing: true,
              senderName: '',
              contentType: 'messageText',
              text: 'Outgoing',
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.dark]),
          home: DesktopChatWindowPage(
            arguments: arguments(),
            controller: controller,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('desktop-chat-window-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-chat-window-transcript')),
        findsOneWidget,
      );
      expect(find.text('Incoming'), findsOneWidget);
      expect(find.text('Outgoing'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Ctrl+Enter'), findsOneWidget);

      final composer = find.byKey(
        const ValueKey('desktop-chat-window-composer'),
      );
      await tester.tap(composer);
      await tester.enterText(composer, 'hello');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(controller.sentTexts, ['hello']);
      expect(tester.widget<TextField>(composer).controller?.text, isEmpty);

      final enterController = _FakeDesktopChatController(controller.snapshot);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.dark]),
          home: DesktopChatWindowPage(
            arguments: arguments(enterToSend: true),
            controller: enterController,
          ),
        ),
      );
      expect(find.text('Enter'), findsOneWidget);
      final enterComposer = find.byKey(
        const ValueKey('desktop-chat-window-composer'),
      );
      await tester.tap(enterComposer);
      final enterField = tester.widget<TextField>(enterComposer);
      enterField.controller!.value = const TextEditingValue(
        text: 'に',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(enterController.sentTexts, isEmpty);

      await tester.enterText(enterComposer, 'second');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(enterController.sentTexts, ['second']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _FakeDesktopChatController extends DesktopChatWindowChildController {
  _FakeDesktopChatController(this._snapshot);

  final DesktopChatWindowSnapshot _snapshot;
  final List<String> sentTexts = [];

  @override
  bool get loading => false;

  @override
  bool get sendFailed => false;

  @override
  bool get sending => false;

  @override
  DesktopChatWindowSnapshot get snapshot => _snapshot;

  @override
  Future<bool> sendText(String text) async {
    sentTexts.add(text);
    return true;
  }
}
