import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chats/archived_chats_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/contacts/contacts_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_view.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('rapid main-tab switching preserves the nested tab state', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(800, 1200));
    await _pumpMainShell(tester);

    // The test shell has two main tabs, Messages and Contacts.
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ContactsView), findsOneWidget);

    await tester.tap(find.text('Group chat'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<Text>(find.text('Group chat')).style?.fontWeight,
      FontWeight.w600,
    );

    // Interrupt each transition with another selection. The already-built
    // Contacts navigator must stay mounted throughout the rapid changes.
    await tester.tapAt(const Offset(200, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(200, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ContactsView), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Group chat')).style?.fontWeight,
      FontWeight.w600,
    );
    await _disposeShell(tester);
  });

  testWidgets('reduced motion opens and closes the profile drawer instantly', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(390, 844));
    final harness = await _pumpMainShell(tester, reducedMotion: true);

    var drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, closeTo(-343.2, 0.001));

    harness.drawer.open();
    await tester.pump();
    drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, 0);

    harness.drawer.close();
    await tester.pump();
    drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, closeTo(-343.2, 0.001));
    await _disposeShell(tester);
  });

  testWidgets('reduced motion reveals a tablet detail without an entrance', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(1024, 800));
    await _pumpMainShell(tester, reducedMotion: true, showChannelsTab: true);

    // Move from Messages to Channels. On a tablet this replaces the detail
    // pane as well as the sidebar root.
    await tester.tapAt(const Offset(164, 770));
    await tester.pump();

    final detail = find.byKey(const ValueKey('tablet-channel-empty'));
    expect(detail, findsOneWidget);

    final opacity = _closestAncestor<Opacity>(tester, detail);
    final transform = _closestAncestor<Transform>(tester, detail);
    expect(opacity.opacity, 1);
    expect(transform.transform.getTranslation().x, 0);
    await _disposeShell(tester);
  });

  testWidgets('tablet archive replaces only the sidebar pane', (tester) async {
    await _setSurfaceSize(tester, const Size(1024, 800));
    await _pumpMainShell(tester, reducedMotion: true);

    final emptyDetail = find.byKey(const ValueKey('tablet-message-empty'));
    final detailElement = tester.element(emptyDetail);
    final updates = ChangeNotifier();
    addTearDown(updates.dispose);
    final archived = [
      ChatSummary(
        id: 77,
        title: 'Archived conversation',
        lastMessage: 'Still in the list pane',
        lastMessageId: 2,
        date: 1,
        unreadCount: 0,
        order: 1,
        isMuted: false,
      ),
    ];

    final chatList = tester.widget<ChatListView>(find.byType(ChatListView));
    chatList.onOpenArchived!(
      ArchivedChatListSelection(
        chatsProvider: () => archived,
        updates: updates,
        onClearUnread: (_) {},
      ),
    );
    await tester.pump();

    expect(find.byType(ArchivedChatsView), findsOneWidget);
    expect(find.text('Archived conversation'), findsOneWidget);
    expect(identical(tester.element(emptyDetail), detailElement), isTrue);

    tester.widget<ArchivedChatsView>(find.byType(ArchivedChatsView)).onBack!();
    await tester.pump();

    expect(find.byType(ArchivedChatsView), findsNothing);
    expect(find.byType(ChatListView), findsOneWidget);
    expect(identical(tester.element(emptyDetail), detailElement), isTrue);
    await _disposeShell(tester);
  });

  testWidgets('macOS uses an icon rail and embedded list-pane chrome', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(1100, 720));
      await _pumpMainShell(tester, reducedMotion: true);

      final rail = find.byKey(const ValueKey('desktop-navigation-rail'));
      final listPane = find.byKey(const ValueKey('desktop-list-pane'));
      expect(rail, findsOneWidget);
      expect(tester.getSize(rail).width, 68);
      expect(tester.getSize(listPane).width, inInclusiveRange(320, 420));
      expect(
        tester.widget<ChatListView>(find.byType(ChatListView)).desktopSidebar,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('chat-list-desktop-toolbar')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('desktop-navigation-item-1')));
      await tester.pump();
      final contacts = tester.widget<ContactsView>(find.byType(ContactsView));
      expect(contacts.desktopSidebar, isTrue);
      expect(find.byKey(const ValueKey('contacts-root-header')), findsNothing);
      expect(
        find.byKey(const ValueKey('contacts-desktop-toolbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('narrow macOS keeps the rail and collapses the list column', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(780, 620));
      await _pumpMainShell(tester, reducedMotion: true);

      expect(
        find.byKey(const ValueKey('desktop-navigation-rail')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('desktop-list-pane')), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('desktop-conversation-pane')))
            .width,
        780 - desktopNavigationRailWidth,
      );
      expect(
        tester.widget<ChatListView>(find.byType(ChatListView)).desktopSidebar,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _MainShellHarness {
  const _MainShellHarness({required this.drawer});

  final dc.DrawerController drawer;
}

Future<_MainShellHarness> _pumpMainShell(
  WidgetTester tester, {
  bool reducedMotion = false,
  bool showChannelsTab = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': showChannelsTab,
    'showMomentsTab': false,
    'communitiesEnabled': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = AccountStore(prefs);
  final auth = AuthManager();
  final translation = TranslationController(prefs);
  final drawer = dc.DrawerController();
  final deepLinks = ChatDeepLinkController.shared;
  deepLinks.consumePending();

  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);
  addTearDown(auth.dispose);
  addTearDown(translation.dispose);
  addTearDown(drawer.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
        ChangeNotifierProvider<TranslationController>.value(value: translation),
        ChangeNotifierProvider<ChatDeepLinkController>.value(value: deepLinks),
        ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
        home: const MainSplitRootView(),
      ),
    ),
  );
  await tester.pump();
  return _MainShellHarness(drawer: drawer);
}

Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Chat-list cache warming uses delayed no-op guards after disposal.
  await tester.pump(const Duration(seconds: 6));
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

T _closestAncestor<T extends Widget>(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  T? result;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is! T) return true;
    result = widget;
    return false;
  });
  return result!;
}
