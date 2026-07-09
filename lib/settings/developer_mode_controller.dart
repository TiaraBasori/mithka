//
//  developer_mode_controller.dart
//
//  Hidden diagnostics toggles for local device debugging. The entry point is
//  unlocked by tapping the About version label repeatedly.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeveloperModeController extends ChangeNotifier {
  DeveloperModeController(this._prefs)
    : _unlocked = _prefs.getBool(_unlockedKey) ?? false,
      _showPiPBounds = _prefs.getBool(_showPiPBoundsKey) ?? false;

  static const _unlockedKey = 'developer_mode.unlocked';
  static const _showPiPBoundsKey = 'developer_mode.show_pip_bounds';

  final SharedPreferences _prefs;
  bool _unlocked;
  bool _showPiPBounds;

  bool get unlocked => _unlocked;
  bool get showPiPBounds => _showPiPBounds;

  Future<void> unlock() async {
    if (_unlocked) return;
    _unlocked = true;
    await _prefs.setBool(_unlockedKey, true);
    notifyListeners();
  }

  set showPiPBounds(bool value) {
    if (_showPiPBounds == value) return;
    _showPiPBounds = value;
    unawaited(_prefs.setBool(_showPiPBoundsKey, value));
    notifyListeners();
  }
}
