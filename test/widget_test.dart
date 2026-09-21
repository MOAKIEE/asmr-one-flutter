import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_one/core/models/common.dart';
import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/utils/formatters.dart';

/// 这些用例锁定住与 asmr.one 接口之间的数据契约：
/// 接口偶发地用 int / double / String 混用同一字段，
/// 一旦解析逻辑被改坏，测试会立刻发现。
void main() {
  group('Work.fromJson', () {
    test('解析列表接口返回的作品，并兼容 int 形式的评分', () {
      final work = Work.fromJson({
        'id': 1653004,
        'title': '测试作品',
        'circle_id': 51931,
        'name': '青春×フェティシズム',
        'nsfw': true,
        'release': '2026-06-27',
        'dl_count': 350,
        'price': 1980,
        'review_count': 4,
        'rate_count': 7,
        // 服务端对满分作品返回的是 int 5 而不是 double
        'rate_average_2dp': 5,
        'has_subtitle': true,
        'create_date': '2026-08-07',
        'duration': 13636,
        'source_id': 'RJ01653004',
        'vas': [
          {'id': 'va-1', 'name': '浅木式'},
        ],
        'tags': [
          {
            'id': 497,
            'name': 'ASMR',
            'i18n': {
              'zh-cn': {'name': 'ASMR'},
            },
          },
        ],
        'mainCoverUrl': 'https://api.asmr.one/api/cover/1653004.jpg?type=main',
      });

      expect(work.id, 1653004);
      expect(work.rateAverage, 5.0);
      expect(work.price, 1980);
      expect(work.isFree, isFalse);
      expect(work.workNo, 'RJ01653004');
      expect(work.duration, 13636);
      expect(work.vas.single.name, '浅木式');
      expect(work.tags.single.label(AppLang.zh), 'ASMR');
      expect(work.nsfw, isTrue);
    });

    test('缺失字段时使用安全默认值而不是抛异常', () {
      final work = Work.fromJson({'id': 1});
      expect(work.title, '');
      expect(work.rateAverage, 0);
      expect(work.tags, isEmpty);
      expect(work.isFree, isTrue);
    });
  });

  group('WorkQuery', () {
    test('只输出非空的查询参数', () {
      const query = WorkQuery(
        page: 2,
        pageSize: 24,
        order: WorkOrder.dlCount,
        nsfw: false,
        subtitle: true,
        tags: [497, 496],
      );
      final params = query.toQueryParameters();

      expect(params['page'], 2);
      expect(params['order'], 'dl_count');
      expect(params['tags'], '497,496');
      expect(params['nsfw'], 'false');
      expect(params['subtitle'], 1);
      // 未设置的筛选项不应出现在 query 中
      expect(params.containsKey('keyword'), isFalse);
      expect(params.containsKey('rate'), isFalse);
      expect(params.containsKey('circle'), isFalse);
    });

    test('clearWith 能真正清空可空筛选条件', () {
      const query = WorkQuery(rate: 4.5, duration: 600, nsfw: true);
      final cleared = query.copyWith(
        clearRate: true,
        clearDuration: true,
        clearNsfw: true,
      );
      expect(cleared.rate, isNull);
      expect(cleared.duration, isNull);
      expect(cleared.nsfw, isNull);
      expect(cleared.hasFilters, isFalse);
    });

    test('filterCount 统计生效的筛选维度', () {
      const query = WorkQuery(tags: [1], rate: 4, subtitle: true);
      expect(query.filterCount, 3);
    });
  });

  group('曲目树', () {
    test('flatten 按深度优先展开并保留目录路径', () {
      final nodes = [
        TrackNode.fromJson({
          'type': 'folder',
          'title': '01_本篇',
          'children': [
            {
              'type': 'audio',
              'title': '01_开场.mp3',
              'hash': '1653004/111',
              'duration': 61.5,
            },
            {
              'type': 'folder',
              'title': '01_mp3',
              'children': [
                {
                  'type': 'audio',
                  'title': '02_第二个.wav',
                  'hash': '1653004/222',
                },
              ],
            },
          ],
        }),
      ];

      final flat = nodes.expand((n) => n.flatten()).toList();
      expect(flat, hasLength(2));
      expect(flat[0].title, '01_开场.mp3');
      expect(flat[0].folderPath, ['01_本篇']);
      expect(flat[1].folderPath, ['01_本篇', '01_mp3']);
      expect(flat[1].folderLabel, '01_本篇 / 01_mp3');
      expect(flat[0].hasDuration, isTrue);
    });
  });

  group('格式化', () {
    test('时长', () {
      expect(Fmt.duration(59), '0:59');
      expect(Fmt.duration(3725), '1:02:05');
      expect(Fmt.duration(null), '--:--');
    });

    test('大数字', () {
      expect(Fmt.count(999), '999');
      expect(Fmt.count(1200), '1.2k');
      expect(Fmt.count(148637), '14.9万');
    });

    test('价格', () {
      expect(Fmt.price(0, '免费'), '免费');
      expect(Fmt.price(1980, '免费'), '¥1,980');
    });

    test('去掉音频扩展名', () {
      expect(Fmt.stripExt('01_开场.mp3'), '01_开场');
      expect(Fmt.stripExt('cover.jpg'), 'cover.jpg');
    });
  });
}
