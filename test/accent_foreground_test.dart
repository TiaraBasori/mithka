//
//  accent_foreground_test.dart
//
//  What sits on top of an accent fill. readableForeground maximises the raw
//  contrast ratio, which flips to near-black on any saturated mid-tone — a
//  green accent came out black-on-green where every app using that green
//  draws white. Accents are picked to be carried by white; only a genuinely
//  light one needs dark on top.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_theme.dart';

const white = Color(0xFFFFFFFF);
const dark = Color(0xFF171717);

void main() {
  group('foregroundOnAccent', () {
    test('carries white on saturated accents', () {
      for (final accent in const [
        Color(0xFF07C160), // WeChat green
        Color(0xFF3390EC), // Telegram blue
        Color(0xFF0A84E0), // Mithka default
        Color(0xFFFF4D4F), // destructive red
        Color(0xFF9B7BE8), // member violet
      ]) {
        expect(foregroundOnAccent(accent), white, reason: '$accent');
      }
    });

    test('switches to dark only on a genuinely light accent', () {
      for (final accent in const [
        Color(0xFFF9F7F4), // near-white
        Color(0xFFFFD700), // gold
        Color(0xFFF3B4BD), // pastel pink cloud accent
        Color(0xFFFFFFFF),
      ]) {
        expect(foregroundOnAccent(accent), dark, reason: '$accent');
      }
    });

    test('differs from raw-contrast pick where that was the bug', () {
      const green = Color(0xFF07C160);
      expect(
        readableForeground(green),
        dark,
        reason:
            'raw contrast still prefers dark here — that is why the '
            'accent rule exists rather than reusing it',
      );
      expect(foregroundOnAccent(green), white);
    });

    test('agrees with raw contrast on a light accent', () {
      const light = Color(0xFFF9F7F4);
      expect(readableForeground(light), foregroundOnAccent(light));
    });
  });

  group('the shipped palettes', () {
    test('default accents carry white', () {
      expect(AppColors.light.onAccent, white);
      expect(AppColors.dark.onAccent, white);
    });
  });
}
