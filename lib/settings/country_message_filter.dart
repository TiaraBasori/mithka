import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/country_picker.dart';

/// Local-only filter for private chats from non-contacts in selected regions.
class CountryMessageFilter extends ChangeNotifier {
  CountryMessageFilter();

  static final CountryMessageFilter shared = CountryMessageFilter();

  static const _selectedCountriesKey = 'countryMessageFilter.selectedCountries';

  SharedPreferences? _prefs;
  Set<String> _selectedCountries = const <String>{};

  Set<String> get selectedCountries => Set.unmodifiable(_selectedCountries);
  bool get isEnabled => _selectedCountries.isNotEmpty;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _selectedCountries =
        (prefs.getStringList(_selectedCountriesKey) ?? const [])
            .map((iso) => iso.trim().toUpperCase())
            .where((iso) => Country.all.any((country) => country.iso == iso))
            .toSet();
  }

  void setCountrySelected(String iso, bool selected) {
    final normalized = iso.trim().toUpperCase();
    if (!Country.all.any((country) => country.iso == normalized)) return;
    final next = {..._selectedCountries};
    if (selected) {
      next.add(normalized);
    } else {
      next.remove(normalized);
    }
    if (setEquals(next, _selectedCountries)) return;
    _selectedCountries = next;
    _prefs?.setStringList(_selectedCountriesKey, next.toList()..sort());
    notifyListeners();
  }

  bool matchesUser({required bool isContact, String? phoneNumber}) {
    if (!isEnabled || isContact) return false;
    final digits = (phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final country = Country.match(digits);
    return country != null && _selectedCountries.contains(country.iso);
  }
}
