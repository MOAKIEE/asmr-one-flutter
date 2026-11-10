import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/screens/filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reset in [false, true]) {
    testWidgets(
      'subtitle and translation filters can be cleared by ${reset ? "reset" : "switches"}',
      (tester) async {
        WorkQuery? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await showWorkFilterSheet(
                      context,
                      query: const WorkQuery(
                        subtitle: true,
                        includeTranslationWorks: true,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        if (reset) {
          await tester.tap(find.byType(TextButton).first);
        } else {
          for (final label in ['仅带字幕', '包含翻译版本']) {
            final tile = find.widgetWithText(SwitchListTile, label);
            await tester.scrollUntilVisible(
              tile,
              150,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.tap(tile);
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(result!.subtitle, isFalse);
        expect(result!.includeTranslationWorks, isFalse);
        expect(result!.toQueryParameters().containsKey('subtitle'), isFalse);
        expect(
          result!.toQueryParameters().containsKey('includeTranslationWorks'),
          isFalse,
        );
      },
    );
  }
}
