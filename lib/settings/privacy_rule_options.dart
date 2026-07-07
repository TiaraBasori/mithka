import 'package:mithka/l10n/app_localizations.dart';

import '../tdlib/json_helpers.dart';

enum PrivacyVisibilityOption {
  everyone,
  contacts,
  nobody;

  String get labelKey => switch (this) {
    PrivacyVisibilityOption.everyone => AppStringKeys.privacyVisibilityEveryone,
    PrivacyVisibilityOption.contacts => AppStringKeys.privacyVisibilityContacts,
    PrivacyVisibilityOption.nobody => AppStringKeys.privacyVisibilityNobody,
  };

  String get ruleType => switch (this) {
    PrivacyVisibilityOption.everyone => 'userPrivacySettingRuleAllowAll',
    PrivacyVisibilityOption.contacts => 'userPrivacySettingRuleAllowContacts',
    PrivacyVisibilityOption.nobody => 'userPrivacySettingRuleRestrictAll',
  };
}

PrivacyVisibilityOption privacyVisibilityFromRules(
  List<Map<String, dynamic>> rules,
) {
  var value = PrivacyVisibilityOption.everyone;
  for (final rule in rules) {
    final broadRule = switch (rule.type) {
      'userPrivacySettingRuleAllowAll' => PrivacyVisibilityOption.everyone,
      'userPrivacySettingRuleAllowContacts' => PrivacyVisibilityOption.contacts,
      'userPrivacySettingRuleRestrictAll' => PrivacyVisibilityOption.nobody,
      _ => null,
    };
    if (broadRule != null) value = broadRule;
  }
  return value;
}
