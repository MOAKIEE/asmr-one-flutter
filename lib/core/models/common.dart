/// 通用 JSON 解析辅助 + 小型共享模型。
///
/// asmr.one 的接口在不同字段上会出现 int / double / String 混用的情况
/// （例如 `rate_average_2dp` 可能是 `5` 也可能是 `4.69`），
/// 因此这里统一做宽松解析，避免运行时类型异常。
library;

double asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

double? asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

int? asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  return v.toString();
}

String? asStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? v.map((k, value) => MapEntry(k.toString(), value)) : const {};

List<Map<String, dynamic>> asMapList(dynamic v) =>
    v is List ? v.map(asMap).where((e) => e.isNotEmpty).toList() : const [];

/// 支持的界面语言。
enum AppLang { zh, ja, en }

extension AppLangX on AppLang {
  String get apiKey => switch (this) {
    AppLang.zh => 'zh-cn',
    AppLang.ja => 'ja-jp',
    AppLang.en => 'en-us',
  };

  /// 作品详情里语言版本用的三位代号。
  String get code => switch (this) {
    AppLang.zh => 'CHI',
    AppLang.ja => 'JPN',
    AppLang.en => 'ENG',
  };
}

/// 标签，例如 `ASMR` / `双声道立体声/人头麦`。
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.i18n = const {},
    this.count = 0,
    this.voteRank,
    this.voteStatus,
    this.upvote,
    this.downvote,
  });

  final int id;
  final String name;

  /// 形如 `{'ja-jp': {'name': 'バイノーラル/ダミヘ'}, ...}`。
  final Map<String, Map<String, dynamic>> i18n;
  final int count;
  final int? voteRank;
  final int? voteStatus;
  final int? upvote;
  final int? downvote;

  /// 取指定语言下的显示名，缺失时回退到原始 `name`。
  String label(AppLang lang) {
    final entry = i18n[lang.apiKey];
    final v = entry == null ? null : entry['name'];
    final s = v?.toString();
    if (s != null && s.isNotEmpty) return s;
    // 中文环境优先回退到日文原名之外的可读项
    for (final fallback in const ['zh-cn', 'ja-jp', 'en-us']) {
      final f = i18n[fallback]?['name']?.toString();
      if (f != null && f.isNotEmpty) return f;
    }
    return name;
  }

  factory Tag.fromJson(Map<String, dynamic> json) {
    final rawI18n = asMap(json['i18n']);
    final i18n = <String, Map<String, dynamic>>{};
    rawI18n.forEach((k, v) => i18n[k] = asMap(v));
    return Tag(
      id: asInt(json['id']),
      name: asString(json['name']),
      i18n: i18n,
      count: asInt(json['count']),
      voteRank: asIntOrNull(json['voteRank']),
      voteStatus: asIntOrNull(json['voteStatus']),
      upvote: asIntOrNull(json['upvote']),
      downvote: asIntOrNull(json['downvote']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'i18n': i18n,
    'count': count,
  };
}

/// 声优 / 演绎者。
class Va {
  const Va({required this.id, required this.name});

  final String id;
  final String name;

  factory Va.fromJson(Map<String, dynamic> json) =>
      Va(id: asString(json['id']), name: asString(json['name']));

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// 社团（Circle / サークル）。
class Circle {
  const Circle({
    required this.id,
    required this.name,
    this.sourceId,
    this.sourceType,
  });

  final int id;
  final String name;
  final String? sourceId;
  final String? sourceType;

  factory Circle.fromJson(Map<String, dynamic> json) => Circle(
    id: asInt(json['id']),
    name: asString(json['name']),
    sourceId: asStringOrNull(json['source_id']),
    sourceType: asStringOrNull(json['source_type']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source_id': sourceId,
    'source_type': sourceType,
  };
}

/// 榜单条目（日榜 / 周榜 / 月榜）。
class RankEntry {
  const RankEntry({
    required this.term,
    required this.category,
    required this.rank,
    this.rankDate,
  });

  final String term;
  final String category;
  final int rank;
  final String? rankDate;

  factory RankEntry.fromJson(Map<String, dynamic> json) => RankEntry(
    term: asString(json['term']),
    category: asString(json['category']),
    rank: asInt(json['rank']),
    rankDate: asStringOrNull(json['rank_date']),
  );
}

/// 评分分布中的单档（1~5 星）。
class RateCountDetail {
  const RateCountDetail({
    required this.reviewPoint,
    required this.count,
    required this.ratio,
  });

  final int reviewPoint;
  final int count;
  final double ratio;

  factory RateCountDetail.fromJson(Map<String, dynamic> json) =>
      RateCountDetail(
        reviewPoint: asInt(json['review_point']),
        count: asInt(json['count']),
        ratio: asDouble(json['ratio']),
      );
}

/// 作品的其它语言版本。
class LanguageEdition {
  const LanguageEdition({
    required this.lang,
    required this.label,
    required this.workno,
    this.editionId,
    this.editionType,
    this.displayOrder,
  });

  final String lang;
  final String label;
  final String workno;
  final int? editionId;
  final String? editionType;
  final int? displayOrder;

  factory LanguageEdition.fromJson(Map<String, dynamic> json) =>
      LanguageEdition(
        lang: asString(json['lang']),
        label: asString(json['label']),
        workno: asString(json['workno']),
        editionId: asIntOrNull(json['edition_id']),
        editionType: asStringOrNull(json['edition_type']),
        displayOrder: asIntOrNull(json['display_order']),
      );
}

/// 分页元信息，供列表页做「是否还有下一页」判断。
class Paged<T> {
  const Paged({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int totalCount;

  bool get hasMore => items.length >= pageSize && page * pageSize < totalCount;

  static Paged<T> empty<T>() =>
      Paged<T>(items: const [], page: 1, pageSize: 20, totalCount: 0);
}
