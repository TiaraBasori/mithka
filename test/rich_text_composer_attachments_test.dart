import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/chat/rich_text_composer_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  testWidgets('rich composer renders ordered file and music attachments', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RichTextComposerView(
          initialText: 'Album caption',
          initialAttachments: [
            OutgoingAttachment(
              path: '/tmp/document.pdf',
              kind: OutgoingAttachmentKind.document,
            ),
            OutgoingAttachment(
              path: '/tmp/song.flac',
              kind: OutgoingAttachmentKind.audio,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2/10'), findsOneWidget);
    expect(find.text('document.pdf'), findsOneWidget);
    expect(find.text('song.flac'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
