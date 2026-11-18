import 'dart:async';

import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/state/work_feed.dart';
import 'package:flutter_test/flutter_test.dart';

WorksPage _page(int page, List<int> ids, {required int total}) => WorksPage(
  works: [
    for (final id in ids) Work.fromJson({'id': id}),
  ],
  page: page,
  pageSize: 1,
  totalCount: total,
);

void main() {
  test('a duplicate on the last page ends pagination', () async {
    final requested = <int>[];
    final feed = WorkFeed((page, _) async {
      requested.add(page);
      return _page(page, [1], total: 2);
    }, pageSize: 1);
    addTearDown(feed.dispose);

    await feed.load();
    expect(feed.hasMore, isTrue);
    await feed.loadMore();
    await feed.loadMore();

    expect(requested, [1, 2]);
    expect(feed.items.map((work) => work.id), [1]);
    expect(feed.page, 2);
    expect(feed.totalCount, 2);
    expect(feed.hasMore, isFalse);
  });

  test(
    'an empty page ends pagination before reaching the reported total',
    () async {
      final requested = <int>[];
      final feed = WorkFeed((page, _) async {
        requested.add(page);
        return _page(page, page == 3 ? [] : [1], total: 10);
      }, pageSize: 1);
      addTearDown(feed.dispose);

      await feed.load();
      await feed.loadMore();
      expect(feed.hasMore, isTrue);
      await feed.loadMore();
      await feed.loadMore();

      expect(requested, [1, 2, 3]);
      expect(feed.items.map((work) => work.id), [1]);
      expect(feed.hasMore, isFalse);

      await feed.refresh();
      expect(feed.hasMore, isTrue);
      expect(feed.page, 1);
    },
  );

  test('a previous page response cannot end a refreshed feed', () async {
    final previousPage = Completer<WorksPage>();
    final feed = WorkFeed(
      (page, _) async =>
          page == 1 ? _page(page, [1], total: 3) : previousPage.future,
      pageSize: 1,
    );
    addTearDown(feed.dispose);

    await feed.load();
    final pending = feed.loadMore();
    await feed.refresh();
    previousPage.complete(_page(2, [], total: 3));
    await pending;

    expect(feed.page, 1);
    expect(feed.hasMore, isTrue);
  });

  test(
    'server page size and requested page size support short final pages',
    () {
      final result = WorksPage.fromJson({
        'works': [
          {'id': 25},
        ],
        'pagination': {'currentPage': 2, 'pageSize': 24, 'totalCount': 25},
      }, requestedPageSize: 50);
      expect(result.page, 2);
      expect(result.maxPage, 2);

      final fallback = WorksPage.fromJson({
        'works': [
          {'id': 25},
        ],
        'page': 2,
        'totalCount': 25,
      }, requestedPageSize: 24);
      expect(fallback.maxPage, 2);
    },
  );
}
