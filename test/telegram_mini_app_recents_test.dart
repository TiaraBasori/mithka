import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_mini_app_recents.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('uses bot identity while preserving the recent launch title', () {
    const recent = TelegramMiniAppRecent(
      title: '小程序购买',
      url: 'menu://https://example.com/app',
      botUserId: 10,
      chatId: 20,
      updatedAt: 30,
    );
    final discovered = TelegramMiniAppRecent(
      title: 'Open',
      botTitle: 'USDT eSIM',
      url: 'menu://https://example.com/app',
      botUserId: 10,
      chatId: 20,
      updatedAt: 0,
      photo: TdFileRef(id: 42),
    );

    final merged = mergeTelegramMiniAppRecents([recent], [discovered]);

    expect(merged, hasLength(1));
    expect(merged.single.title, '小程序购买');
    expect(merged.single.displayTitle, 'USDT eSIM');
    expect(merged.single.photo?.id, 42);
  });

  test('keeps only the most recently stored app for each bot', () {
    TelegramMiniAppRecent recent(String title, String url) =>
        TelegramMiniAppRecent(
          title: title,
          url: url,
          botUserId: 10,
          chatId: 20,
          updatedAt: 30,
        );

    final merged = mergeTelegramMiniAppRecents([
      recent('Open', 'menu://https://example.com/new'),
      recent('小程序购买', 'https://example.com/old'),
    ], const []);

    expect(merged, hasLength(1));
    expect(merged.single.title, 'Open');
  });
}
