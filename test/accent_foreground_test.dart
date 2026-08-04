//
//  accent_foreground_test.dart
//
//  What sits on top of an accent fill. This is a stored token, never derived
//  from the accent — the same shape every Telegram client uses. Android keeps
//  key_chats_actionIcon / key_featuredStickers_buttonText / key_checkboxCheck,
//  each defaulting to 0xffffffff, and its theme engine contains no luminance
//  or contrast maths at all. Deriving it instead is what once produced
//  black-on-green for the WeChat accent.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';

const white = Color(0xFFFFFFFF);

TelegramCloudTheme themeWith(Map<String, int> palette, {int? accent}) =>
    TelegramCloudTheme(
      slug: 'Probe',
      rawTitle: 'Probe',
      baseTheme: 'builtInThemeDay',
      accentColorValue: accent ?? 0xFF07C160,
      outgoingColors: const [],
      palette: palette,
    );

void main() {
  group('the shipped palettes', () {
    test('default accents carry white', () {
      expect(AppColors.light.onAccent, white);
      expect(AppColors.dark.onAccent, white);
    });
  });

  group('cloud themes', () {
    test('fall back to the stored token, not to a contrast calculation', () {
      // A saturated green accent with no on-accent key. The old luminance
      // branch is gone, so this is white because the base palette says white.
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
      }, accent: 0xFF07C160).uiColors;
      expect(colors.onAccent, white);
    });

    test('a light accent alone does not flip the foreground', () {
      // Nothing about the accent itself moves this — only an explicit key can.
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
      }, accent: 0xFFF3B4BD).uiColors;
      expect(colors.onAccent, white);
    });

    test('an explicit Android key wins', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'chats_actionIcon': 0xFF171717,
      }).uiColors;
      expect(colors.onAccent, const Color(0xFF171717));
    });

    test('reads each client key it advertises', () {
      for (final key in const [
        'chats_actionIcon',
        'featuredStickers_buttonText',
        'checkboxCheck',
        'list.itemCheckColors.foregroundColor',
        'underSelectedColor',
        'activeButtonFg',
      ]) {
        final colors = themeWith({
          'list.plainBg': 0xFFFFFFFF,
          key: 0xFF102030,
        }).uiColors;
        expect(colors.onAccent, const Color(0xFF102030), reason: key);
      }
    });

    test('prefers the Android key over lower-fidelity ones', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'chats_actionIcon': 0xFF111111,
        'activeButtonFg': 0xFF222222,
      }).uiColors;
      expect(colors.onAccent, const Color(0xFF111111));
    });
  });

  group('readableForeground', () {
    test('still maximises raw contrast for non-accent surfaces', () {
      expect(readableForeground(const Color(0xFFFFFFFF)), isNot(white));
      expect(readableForeground(const Color(0xFF000000)), white);
    });
  });
}
