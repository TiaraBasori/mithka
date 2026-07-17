import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  test('gallery and TGS actions have native Simplified Chinese wording', () {
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.gallerySendHdTitle),
      '高清画质',
    );
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.gallerySendMotionSubtitle),
      '将动态部分作为视频发送',
    );
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.stickerStudioFormatTgs),
      '矢量动画 · 最大 64 KB',
    );
  });

  test('gallery and TGS actions have native Traditional Chinese wording', () {
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.gallerySendHdTitle),
      '高畫質',
    );
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.gallerySendMotionSubtitle),
      '將動態部分作為影片傳送',
    );
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.stickerStudioValidationTgs),
      '所選檔案不是有效的 gzip 壓縮 TGS 動畫。',
    );
  });
}
