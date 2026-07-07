import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/privacy_rule_options.dart';

void main() {
  test('decodes nobody as the effective broad privacy rule', () {
    expect(
      privacyVisibilityFromRules([
        {'@type': 'userPrivacySettingRuleAllowAll'},
        {'@type': 'userPrivacySettingRuleRestrictAll'},
      ]),
      PrivacyVisibilityOption.nobody,
    );
  });

  test('ignores exception rules and keeps the broad rule', () {
    expect(
      privacyVisibilityFromRules([
        {
          '@type': 'userPrivacySettingRuleAllowUsers',
          'user_ids': ['1'],
        },
        {'@type': 'userPrivacySettingRuleRestrictAll'},
      ]),
      PrivacyVisibilityOption.nobody,
    );
  });

  test('uses contacts as the broad privacy rule', () {
    expect(
      privacyVisibilityFromRules([
        {
          '@type': 'userPrivacySettingRuleRestrictUsers',
          'user_ids': ['2'],
        },
        {'@type': 'userPrivacySettingRuleAllowContacts'},
      ]),
      PrivacyVisibilityOption.contacts,
    );
  });
}
