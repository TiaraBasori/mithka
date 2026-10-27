import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/chats/archived_chats_view.dart';
import 'package:mithka/chats/chat_folder_tag_controller.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_row_metrics.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + fontSize * fontSize / 40;
  @override
  double get textScaleFactor => 1.025;
}

ChatSummary _chat({String? sender = '发送者', int unread = 7}) => ChatSummary(
  id: 517,
  title: '中文 Conversation',
  lastMessage: '消息 Hello 👋',
  lastSender: sender,
  lastMessageId: 1,
  date: 1600000000,
  unreadCount: unread,
  order: 1,
  isMuted: false,
);

RenderParagraph _paragraph(WidgetTester tester, Finder parent) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: parent, matching: find.byType(RichText)).first,
    );

double _spanPixels(RenderParagraph paragraph, TextSpan span) => paragraph
    .textScaler
    .scale(span.style?.fontSize ?? paragraph.text.style!.fontSize!);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures = L10nFixtures.load();
  final updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);

  setUpAll(() {
    fixtures.install();
    AppStrings.setLocale(const Locale('en'));
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Synthetic'},
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  Future<ThemeController> controller() async {
    SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    return theme;
  }

  Widget host(
    ThemeController theme,
    Widget child, {
    double app = .9,
    TextScaler system = TextScaler.noScaling,
    double? lineHeight,
    Locale locale = const Locale('en'),
  }) => ChangeNotifierProvider<ThemeController>.value(
    value: theme,
    child: MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, route) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: system),
        child: ScaledAppView(textScale: app, interfaceScale: 1, child: route!),
      ),
      home: Scaffold(
        body: DefaultTextStyle(
          style: TextStyle(
            fontFamily: 'Ahem',
            fontSize: 15,
            height: lineHeight,
          ),
          child: child,
        ),
      ),
    ),
  );

  void platformTestWidgets(
    String description,
    TargetPlatform platform,
    WidgetTesterCallback callback,
  ) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await callback(tester);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 6));
        } finally {
          // Foundation invariants are checked before addTearDown callbacks.
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });
  }

  test(
    'OS Bold Text measurement matches Flutter without changing other style',
    () {
      const style = TextStyle(
        fontFamily: 'Synthetic',
        fontFamilyFallback: ['CJK fallback'],
        fontSize: 16,
        height: 1.7,
        letterSpacing: .3,
        color: Color(0xFF123456),
        fontWeight: FontWeight.w500,
      );
      expect(
        AppTextStyle.forSystemBoldTextMeasurement(style, boldText: false),
        same(style),
      );
      expect(
        AppTextStyle.forSystemBoldTextMeasurement(style, boldText: true),
        style.merge(const TextStyle(fontWeight: FontWeight.bold)),
      );
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    platformTestWidgets(
      '$platform row and archive keep the calibrated Small rhythm',
      platform,
      (tester) async {
        final theme = await controller();
        final chat = _chat();
        await tester.pumpWidget(
          host(
            theme,
            SizedBox(
              width: 390,
              child: Column(
                children: [
                  ChatRowView(key: const ValueKey('ordinary'), chat: chat),
                  ArchivedChatsRow(archived: [chat]),
                ],
              ),
            ),
          ),
        );
        final ordinary = find.byKey(const ValueKey('ordinary'));
        final archive = find.byType(ArchivedChatsRow);
        for (final row in [ordinary, archive]) {
          final rect = tester.getRect(row);
          final avatar = row == ordinary
              ? find.descendant(of: row, matching: find.byType(PhotoAvatar))
              : find.byKey(const ValueKey('archived-chats-avatar'));
          final art = tester.getRect(avatar);
          expect(rect.height, 68);
          expect(art.size, const Size.square(49));
          expect(art.left - rect.left, 16);
          expect(art.center.dy, rect.center.dy);
          final preview = find.descendant(
            of: row,
            matching: find.byType(ChatPreviewText),
          );
          expect(tester.getTopLeft(preview).dx - rect.left, 77);
          final textColumn = find.descendant(
            of: row,
            matching: find.byType(ChatRowTextColumn),
          );
          expect(tester.getRect(textColumn).right, rect.right - 16);
          final renderedRow = row == ordinary
              ? tester.widget<ChatRowView>(row)
              : tester.widget<ChatRowView>(
                  find.descendant(of: row, matching: find.byType(ChatRowView)),
                );
          final title = find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.data == renderedRow.chat.title &&
                  widget.style?.fontSize == 17,
            ),
          );
          expect(title, findsOneWidget);
          expect(
            tester.getTopLeft(preview).dy - tester.getBottomLeft(title).dy,
            2,
          );
          final badge = find.descendant(
            of: row,
            matching: find.byType(UnreadBadge),
          );
          final badgeRect = tester.getRect(badge);
          expect(badgeRect.size, const Size.square(17));
          expect(badgeRect.topRight, art.topRight);
          final count = _paragraph(tester, badge);
          expect(
            count.textScaler.scale(count.text.style!.fontSize!),
            closeTo(10.8, 1e-9),
          );
        }
        final title = _paragraph(tester, find.text(chat.title));
        final timestamp = _paragraph(
          tester,
          find.descendant(
            of: ordinary,
            matching: find.byWidgetPredicate(
              (widget) => widget is Text && widget.style?.fontSize == 13,
            ),
          ),
        );
        // The production layout must retain the name/time alphabetic baseline.
        final titleTop = title.localToGlobal(Offset.zero).dy;
        final timeTop = timestamp.localToGlobal(Offset.zero).dy;
        final titleBaseline = title.getDryBaseline(
          title.constraints,
          TextBaseline.alphabetic,
        )!;
        final timeBaseline = timestamp.getDryBaseline(
          timestamp.constraints,
          TextBaseline.alphabetic,
        )!;
        expect(titleTop + titleBaseline, closeTo(timeTop + timeBaseline, .001));
        expect(tester.takeException(), isNull);
      },
    );
  }

  platformTestWidgets(
    'chat badge keeps full count, 5pt padding and drag-clear hit area',
    TargetPlatform.iOS,
    (tester) async {
      final theme = await controller();
      var clears = 0;
      await tester.pumpWidget(
        host(
          theme,
          ChatRowView(chat: _chat(unread: 105), onClearUnread: () => clears++),
        ),
      );
      final badge = find.byType(UnreadBadge);
      final hit = find.descendant(of: badge, matching: find.byType(Listener));
      expect(tester.getSize(hit).width, greaterThanOrEqualTo(36));
      expect(tester.getSize(hit).height, greaterThanOrEqualTo(36));
      final body = tester.widget<Container>(
        find.descendant(
          of: badge,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.constraints?.minHeight == 17,
          ),
        ),
      );
      expect(body.padding, const EdgeInsets.symmetric(horizontal: 5));
      expect(
        find.descendant(of: badge, matching: find.text('99+')),
        findsOneWidget,
      );
      final semantics = tester.widget<Semantics>(
        find.descendant(
          of: badge,
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == '105',
          ),
        ),
      );
      expect(semantics.properties.label, '105');
      await tester.dragFrom(
        tester.getTopLeft(hit) + const Offset(2, 25),
        const Offset(60, 0),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(clears, 1);
      expect(tester.takeException(), isNull);
    },
  );

  platformTestWidgets(
    'actual spans grow once and the tallest sender determines row extent',
    TargetPlatform.iOS,
    (tester) async {
      final theme = await controller();
      for (final sender in <String?>['发送者', null]) {
        for (final app in [.9, .94, 1.0, 1.47, 1.6]) {
          for (final system in <TextScaler>[
            const TextScaler.linear(.823),
            TextScaler.noScaling,
            const TextScaler.linear(2),
            const _NonlinearScaler(),
          ]) {
            final chat = _chat(sender: sender, unread: 0);
            late ChatRowMetrics metrics;
            await tester.pumpWidget(
              host(
                theme,
                SingleChildScrollView(
                  child: SizedBox(
                    width: 1000,
                    child: Builder(
                      builder: (context) {
                        metrics = chatRowMetricsFor(context, chat, width: 1000);
                        return ChatRowView(chat: chat);
                      },
                    ),
                  ),
                ),
                app: app,
                system: system,
                lineHeight: 3,
              ),
            );
            final preview = _paragraph(tester, find.byType(ChatPreviewText));
            final spans = (preview.text as TextSpan).children!.cast<TextSpan>();
            double os(double font) => math.max(font, system.scale(font));
            expect(
              _spanPixels(preview, spans.last),
              closeTo(os(math.max(12.5, 13 * app)), 1e-9),
            );
            if (sender != null) {
              expect(
                _spanPixels(preview, spans.first),
                closeTo(os(13 * math.max(app, 1)), 1e-9),
              );
            }
            final title = _paragraph(tester, find.text(chat.title));
            expect(
              title.textScaler.scale(title.text.style!.fontSize!),
              closeTo(os(17 * app), 1e-9),
            );
            expect(
              metrics.extent,
              closeTo(title.size.height + 2 + preview.size.height + 16, .001),
            );
            expect(
              tester.getSize(find.byType(ChatRowView)).height,
              metrics.extent,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  platformTestWidgets(
    'production search grows with OS 2/3 for CJK and Latin without clipping',
    TargetPlatform.iOS,
    (tester) async {
      final theme = await controller();
      for (final locale in [
        const Locale('en'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ]) {
        for (final os in [2.0, 3.0]) {
          await tester.pumpWidget(
            host(
              theme,
              const ChatListView(),
              system: TextScaler.linear(os),
              locale: locale,
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final visual = find.byKey(const ValueKey('chat-list-search-visual'));
          final hit = find.byKey(const ValueKey('chat-list-search-hit'));
          final label = _paragraph(
            tester,
            find.descendant(of: visual, matching: find.byType(Text)),
          );
          final labelRect = label.localToGlobal(Offset.zero) & label.size;
          final visualRect = tester.getRect(visual);
          expect(label.textScaler.scale(label.text.style!.fontSize!), 16 * os);
          expect(visualRect.height, greaterThan(33));
          expect(visualRect.top, lessThanOrEqualTo(labelRect.top));
          expect(visualRect.bottom, greaterThanOrEqualTo(labelRect.bottom));
          expect(
            tester.getSize(hit).height,
            closeTo(visualRect.height + 17, .001),
          );
          expect(tester.getCenter(hit), visualRect.center);
          expect(
            tester
                .getSize(find.byKey(const ValueKey('chat-list-inline-search')))
                .height,
            tester.getSize(hit).height,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 6));
        }
      }
    },
  );

  platformTestWidgets(
    'touch header art, 44pt hits, full 50pt search slot and typed text',
    TargetPlatform.iOS,
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final theme = await controller();
      final drawer = dc.DrawerController();
      addTearDown(drawer.dispose);
      await tester.pumpWidget(
        host(
          theme,
          ChangeNotifierProvider<dc.DrawerController>.value(
            value: drawer,
            child: const ChatListView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final avatarHit = find.byKey(
        const ValueKey('chat-list-header-avatar-hit'),
      );
      final addHit = find.byKey(const ValueKey('chat-list-header-add-hit'));
      expect(tester.getSize(avatarHit), const Size.square(44));
      expect(tester.getSize(addHit), const Size.square(44));
      final avatar = find.descendant(
        of: avatarHit,
        matching: find.byType(PhotoAvatar),
      );
      expect(tester.widget<PhotoAvatar>(avatar).size, 38);
      expect(tester.getTopLeft(avatar).dx, 16);
      expect(tester.getTopLeft(find.text('Synthetic')).dx, 66);
      expect(
        tester
            .widget<AppIcon>(
              find.descendant(of: addHit, matching: find.byType(AppIcon)),
            )
            .size,
        29,
      );
      final searchHit = find.byKey(const ValueKey('chat-list-search-hit'));
      final visual = find.byKey(const ValueKey('chat-list-search-visual'));
      expect(tester.getSize(searchHit), const Size(358, 50));
      expect(tester.getSize(visual), const Size(358, 33));
      expect(tester.getTopLeft(visual).dx, 16);
      expect(tester.getCenter(searchHit), tester.getCenter(visual));
      final container = tester.widget<Container>(visual);
      expect(
        (container.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(12),
      );
      expect(
        tester
            .widget<AppIcon>(
              find.descendant(of: visual, matching: find.byType(AppIcon)),
            )
            .size,
        18,
      );
      final placeholder = _paragraph(
        tester,
        find.descendant(of: visual, matching: find.byType(Text)),
      );
      expect(
        placeholder.textScaler.scale(placeholder.text.style!.fontSize!),
        16,
      );
      // Both targets work outside their smaller visual artwork.
      await tester.tapAt(tester.getTopRight(avatarHit) + const Offset(-1, 1));
      expect(drawer.isOpen, isTrue);
      await tester.tapAt(tester.getTopLeft(searchHit) + const Offset(2, 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SearchView), findsOneWidget);
      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(field.style!.fontSize, 16);
      expect(field.placeholderStyle!.fontSize, 16);
      await tester.enterText(find.byType(CupertinoTextField), '中文 Search');
      await tester.pump();
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(editable.textScaler.scale(editable.text!.style!.fontSize!), 16);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    },
  );
}
