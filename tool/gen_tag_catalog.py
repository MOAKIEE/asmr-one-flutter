"""由 tool/tags_raw.json 生成 lib/core/data/tag_catalog.dart。

用法：
    python tool/gen_tag_catalog.py
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'tool', 'tags_raw.json')
DST = os.path.join(ROOT, 'lib', 'core', 'data', 'tag_catalog.dart')

LIMIT = 260
BS = chr(92)
DOL = chr(36)


def esc(s):
    return (s.replace(BS + BS, BS + BS)
             .replace("'", BS + "'")
             .replace(DOL, BS + DOL))


HEADER = """import '../../core/models/common.dart';

/// 内置标签目录（自动生成，数据来源：asmr.one 热门作品标签统计）。
///
/// 未登录时接口不开放 `/api/tags`，这里内置一份热门标签用于筛选面板；
/// 登录后 `TagRepository` 会用服务端返回的完整目录覆盖它。
///
/// 重新生成：`python tool/gen_tag_catalog.py`。
class BundledTags {
  const BundledTags._();

  /// 数据版本，用于判断是否需要刷新内置目录。
  static const int version = 1;

  static const List<Tag> all = [
"""

FOOTER = """  ];

  /// 按 id 快速查找。
  static Tag? byId(int id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 关键字过滤（同时匹配中 / 日 / 英文名）。
  static List<Tag> search(String keyword) {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return all;
    return all
        .where((t) =>
            t.label(AppLang.zh).toLowerCase().contains(k) ||
            t.label(AppLang.ja).toLowerCase().contains(k) ||
            t.label(AppLang.en).toLowerCase().contains(k))
        .toList();
  }
}
"""


def main():
    with open(SRC, encoding='utf-8') as f:
        rows = json.load(f)
    rows = [r for r in rows if r.get('zh') and r.get('id')][:LIMIT]

    body = []
    for r in rows:
        body.append(
            "    Tag(id: %d, name: '%s', i18n: {"
            "'zh-cn': {'name': '%s'}, "
            "'ja-jp': {'name': '%s'}, "
            "'en-us': {'name': '%s'}}, count: %d),"
            % (r['id'], esc(r['zh']), esc(r['zh']), esc(r['ja']), esc(r['en']), r['n'])
        )

    with open(DST, 'w', encoding='utf-8') as f:
        f.write(HEADER + '\n'.join(body) + '\n' + FOOTER)
    print('generated', DST, 'tags =', len(rows))


if __name__ == '__main__':
    main()
