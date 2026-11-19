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

  testWidgets('ActiveFilterBar deletes subtitle, translation and nsfw chips independently', (
    tester,
  ) async {
    var clearedAll = false;
    var clearedNsfw = false;
    var clearedSubtitle = false;
    var clearedTranslation = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveFilterBar(
            query: const WorkQuery(
              nsfw: true,
              subtitle: true,
              includeTranslationWorks: true,
              tags: [1],
            ),
            tagLabels: const {1: 'Ear Cleaning'},
            onRemoveTag: (_) {},
            onClear: () => clearedAll = true,
            onAdjustRate: () {},
            onClearDuration: () {},
            onClearNsfw: () => clearedNsfw = true,
            onClearSubtitle: () => clearedSubtitle = true,
            onClearTranslation: () => clearedTranslation = true,
          ),
        ),
      ),
    );

    final deleteIcons = find.byIcon(Icons.close_rounded);
    expect(deleteIcons, findsNWidgets(4));

    await tester.tap(deleteIcons.at(0));
    await tester.pump();
    expect(clearedNsfw, isTrue);
    expect(clearedAll, isFalse);

    await tester.tap(deleteIcons.at(1));
    await tester.pump();
    expect(clearedSubtitle, isTrue);
    expect(clearedAll, isFalse);

    await tester.tap(deleteIcons.at(2));
    await tester.pump();
    expect(clearedTranslation, isTrue);
    expect(clearedAll, isFalse);
  });

  testWidgets('filter chips support overlapping removals and insertions', (
    tester,
  ) async {
    final query = ValueNotifier(const WorkQuery(tags: [1, 2, 3]));
    addTearDown(query.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: query,
            builder: (_, value, _) => ActiveFilterBar(
              query: value,
              tagLabels: const {},
              onRemoveTag: (_) {},
              onClear: () {},
              onAdjustRate: () {},
              onClearDuration: () {},
            ),
          ),
        ),
      ),
    );
    query.value = const WorkQuery(tags: [3, 1, 4]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    query.value = const WorkQuery(tags: []);
    await tester.pump();
    query.value = const WorkQuery(tags: [2, 4]);
    await tester.pumpAndSettle();
    expect(find.text('# 1'), findsNothing);
    expect(find.text('# 2'), findsOneWidget);
    expect(find.text('# 3'), findsNothing);
    expect(find.text('# 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
