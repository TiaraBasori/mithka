import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/chat/desktop_chat_context_pane.dart';
import 'package:mithka/chat/group_remark_controller.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'group pane keeps local remark, announcement, count, search, and members in order',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final remarks = GroupRemarkController(
        preferences,
        initialAccountUserId: 9,
      );
      await remarks.setRemark(42, 'Local project name');
      addTearDown(remarks.dispose);

      final model = ChatInfoViewModel(chatId: 42, title: 'Server group')
        ..isGroup = true
        ..description = 'Authoritative server announcement'
        ..memberCount = 27
        ..members = [ChatMember(1, 'Ada', null), ChatMember(2, 'Grace', null)];
      addTearDown(model.dispose);
      var closeTaps = 0;
      var searchTaps = 0;
      var memberListTaps = 0;
      var openedMember = 0;
      var fullInfoTaps = 0;

      await _pumpPane(
        tester,
        model: model,
        remarks: remarks,
        onClose: () => closeTaps++,
        onSearch: () => searchTaps++,
        onOpenMembers: () => memberListTaps++,
        onOpenMember: (member) => openedMember = member.id,
        onOpenFullInfo: () => fullInfoTaps++,
      );

      final remark = find.byKey(const ValueKey('desktopChatContextRemark'));
      final announcement = find.byKey(
        const ValueKey('desktopChatContextAnnouncement'),
      );
      final members = find.byKey(const ValueKey('desktopChatContextMembers'));
      expect(remark, findsOneWidget);
      expect(announcement, findsOneWidget);
      expect(members, findsOneWidget);
      expect(
        tester.getTopLeft(remark).dy,
        lessThan(tester.getTopLeft(announcement).dy),
      );
      expect(
        tester.getTopLeft(announcement).dy,
        lessThan(tester.getTopLeft(members).dy),
      );
      expect(find.text('Local project name'), findsWidgets);
      expect(find.text('Saved only on this device.'), findsOneWidget);
      expect(find.text('Authoritative server announcement'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
      expect(
        find.descendant(
          of: remark,
          matching: find.byType(AppInteractiveSurface),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('desktopChatContextClose')));
      await tester.tap(find.byKey(const ValueKey('desktopChatContextSearch')));
      await tester.tap(
        find.byKey(const ValueKey('desktopChatContextMembersHeader')),
      );
      await tester.tap(
        find.byKey(const ValueKey('desktopChatContextMember-1')),
      );
      await tester.tap(
        find.byKey(const ValueKey('desktopChatContextOpenFullInfo')),
      );
      expect(closeTaps, 1);
      expect(searchTaps, 1);
      expect(memberListTaps, 1);
      expect(openedMember, 1);
      expect(fullInfoTaps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('channel omits local remark and keeps server announcement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final model = ChatInfoViewModel(chatId: 80, title: 'News channel')
      ..isGroup = true
      ..isChannel = true
      ..description = 'Channel description'
      ..memberCount = 400;
    addTearDown(model.dispose);

    await _pumpPane(tester, model: model);

    expect(
      find.byKey(const ValueKey('desktopChatContextRemark')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktopChatContextAnnouncement')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktopChatContextMembers')),
      findsOneWidget,
    );
    expect(find.text('Channel description'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private chat degrades to generic search and full info actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final model = ChatInfoViewModel(chatId: 7, title: 'Private chat');
    addTearDown(model.dispose);
    var searchTaps = 0;
    var fullInfoTaps = 0;

    await _pumpPane(
      tester,
      model: model,
      onSearch: () => searchTaps++,
      onOpenFullInfo: () => fullInfoTaps++,
    );

    expect(
      find.byKey(const ValueKey('desktopChatContextRemark')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktopChatContextAnnouncement')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktopChatContextMembers')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktopChatContextPrivateActions')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('desktopChatContextSearch')));
    await tester.tap(
      find.byKey(const ValueKey('desktopChatContextOpenFullInfo')),
    );
    expect(searchTaps, 1);
    expect(fullInfoTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pane reacts to local remark and server model updates', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final remarks = GroupRemarkController(preferences, initialAccountUserId: 1);
    addTearDown(remarks.dispose);
    final model = ChatInfoViewModel(chatId: 55, title: 'Server group')
      ..isGroup = true
      ..description = 'Original announcement';
    addTearDown(model.dispose);

    await _pumpPane(tester, model: model, remarks: remarks);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('Original announcement'), findsOneWidget);

    await remarks.setRemark(55, 'Local label');
    model.description = 'Updated announcement';
    model.notifyListeners();
    await tester.pump();

    expect(find.text('Local label'), findsWidgets);
    expect(find.text('Updated announcement'), findsOneWidget);
    expect(find.text('Original announcement'), findsNothing);
  });
}

Future<void> _pumpPane(
  WidgetTester tester, {
  required ChatInfoViewModel model,
  GroupRemarkController? remarks,
  VoidCallback? onClose,
  VoidCallback? onSearch,
  VoidCallback? onOpenMembers,
  ValueChanged<ChatMember>? onOpenMember,
  VoidCallback? onOpenFullInfo,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 760);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 260,
              height: 700,
              child: DesktopChatContextPane(
                chatId: model.chatId,
                title: model.title,
                viewModel: model,
                groupRemarks: remarks,
                onClose: onClose ?? () {},
                onSearch: onSearch ?? () {},
                onOpenMembers: onOpenMembers,
                onOpenMember: onOpenMember,
                onOpenFullInfo: onOpenFullInfo ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
