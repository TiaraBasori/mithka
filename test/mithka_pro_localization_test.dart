import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/messages/de.dart';
import 'package:mithka/l10n/messages/en.dart';
import 'package:mithka/l10n/messages/es.dart';
import 'package:mithka/l10n/messages/fr.dart';
import 'package:mithka/l10n/messages/ja.dart';
import 'package:mithka/l10n/messages/ko.dart';
import 'package:mithka/l10n/messages/zh_hans.dart';
import 'package:mithka/l10n/messages/zh_hant.dart';

void main() {
  test('all supported locale maps own the Pro and backup consent copy', () {
    const keys = {
      'accountBackupLoginAndroid',
      'accountBackupLoginDescription',
      'accountBackupLoginICloud',
      'accountBackupNoticeAndroid',
      'accountBackupNoticeICloud',
      'accountBackupUnavailable',
      'mithkaProActive',
      'mithkaProActiveUntil',
      'mithkaProBackupLimitReached',
      'mithkaProBestValue',
      'mithkaProBillingNotice',
      'mithkaProCloudBackup',
      'mithkaProCloudBackupDescription',
      'mithkaProContinue',
      'mithkaProFreePlan',
      'mithkaProLimitExempt',
      'mithkaProManagePlan',
      'mithkaProMonthly',
      'mithkaProNothingToRestore',
      'mithkaProPerMonth',
      'mithkaProPerYear',
      'mithkaProPurchaseFailed',
      'mithkaProPrivacy',
      'mithkaProRestore',
      'mithkaProRestoreFailed',
      'mithkaProStoreUnavailable',
      'mithkaProTerms',
      'mithkaProTitle',
      'mithkaProUnlimitedAccounts',
      'mithkaProUnlimitedAccountsDescription',
      'mithkaProYearly',
    };
    const locales = <String, Map<String, String>>{
      'en': enMessages,
      'zhHans': zhHansMessages,
      'zhHant': zhHantMessages,
      'ja': jaMessages,
      'ko': koMessages,
      'fr': frMessages,
      'es': esMessages,
      'de': deMessages,
    };

    for (final entry in locales.entries) {
      expect(
        entry.value.keys,
        containsAll(keys),
        reason: '${entry.key} must not fall back to raw English',
      );
      if (entry.key != 'en') {
        expect(
          entry.value['mithkaProFreePlan'],
          isNot(enMessages['mithkaProFreePlan']),
          reason: '${entry.key} needs native plan copy',
        );
      }
    }
  });
}
